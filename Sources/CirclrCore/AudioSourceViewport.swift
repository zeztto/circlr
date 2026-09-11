import Foundation

/// Source-time presentation state only; fitting never changes or follows a trim.
public struct AudioSourceViewport:Codable,Equatable {
    public private(set) var fitted:ClosedRange<Double>?
    public init(){}
    public func range(assetDuration:Double)->ClosedRange<Double> {
        let upper=max(0.001,assetDuration)
        guard let fitted else{return 0...upper}
        let start=max(0,min(upper-0.001,fitted.lowerBound))
        return start...min(upper,max(start+0.001,fitted.upperBound))
    }
    public mutating func fit(_ clip:AudioClip,assetDuration:Double) {
        let padding=max(0.05,clip.duration*0.08)
        fitted=max(0,clip.sourceStart-padding)...min(max(0.001,assetDuration),clip.sourceStart+clip.duration+padding)
    }
    public mutating func showAll(){fitted=nil}
    public mutating func clamp(to assetDuration:Double) {
        guard assetDuration.isFinite,assetDuration>0 else {showAll();return}
        if let fitted {
            guard fitted.lowerBound.isFinite,fitted.upperBound.isFinite else {showAll();return}
            self.fitted=range(assetDuration:assetDuration)
        }
    }
    /// Keep the time under the pointer fixed while changing the displayed duration.
    public mutating func zoom(by factor:Double,around source:Double,assetDuration:Double) {
        guard factor.isFinite,factor>0,source.isFinite,assetDuration.isFinite,assetDuration>0 else{return}
        let current=range(assetDuration:assetDuration),width=current.upperBound-current.lowerBound
        let anchor=min(current.upperBound,max(current.lowerBound,source))
        let next=min(assetDuration,max(min(0.01,assetDuration),width/factor))
        setRange(start:anchor-(anchor-current.lowerBound)/width*next,width:next,assetDuration:assetDuration)
    }
    public mutating func pan(by seconds:Double,assetDuration:Double) {
        guard seconds.isFinite,assetDuration.isFinite,assetDuration>0 else{return}
        let current=range(assetDuration:assetDuration)
        setRange(start:current.lowerBound+seconds,width:current.upperBound-current.lowerBound,assetDuration:assetDuration)
    }
    /// Finding a hidden cursor keeps the current zoom and does not follow later edits.
    public mutating func reveal(_ source:Double,assetDuration:Double) {
        guard source.isFinite,assetDuration.isFinite,assetDuration>0,source>=0,source<=assetDuration,
              !contains(source,assetDuration:assetDuration) else{return}
        let current=range(assetDuration:assetDuration),width=current.upperBound-current.lowerBound
        setRange(start:source-width/2,width:width,assetDuration:assetDuration)
    }
    private mutating func setRange(start:Double,width:Double,assetDuration:Double) {
        let width=min(assetDuration,width)
        if width>=assetDuration {fitted=nil;return}
        let lower=min(assetDuration-width,max(0,start))
        fitted=lower...(lower+width)
    }
    public func source(at phase:Double,assetDuration:Double)->Double {
        let r=range(assetDuration:assetDuration);return r.lowerBound+min(1,max(0,phase))*(r.upperBound-r.lowerBound)
    }
    public func phase(at source:Double,assetDuration:Double)->Double {
        let r=range(assetDuration:assetDuration);return (source-r.lowerBound)/(r.upperBound-r.lowerBound)
    }
    public func contains(_ source:Double,assetDuration:Double)->Bool {
        let r=range(assetDuration:assetDuration);return source>=r.lowerBound-1e-9 && source<=r.upperBound+1e-9
    }
}

/// Shared by numeric, pointer and keyboard trims, preserving the opposite edge.
public struct AudioTrimBounds {
    public let start:ClosedRange<Double>
    public let end:ClosedRange<Double>
    public init(clip:AudioClip,asset:Asset) {
        let lower=clip.renderWindow?.sourceStart ?? 0
        let upper=min(asset.duration,clip.renderWindow.map{$0.sourceStart+$0.duration} ?? asset.duration)
        let minimum=min(clip.duration,max(0.01,(clip.fadeIn ?? 0)+(clip.fadeOut ?? 0)))
        start=lower...max(lower,clip.sourceStart+clip.duration-minimum)
        end=min(upper,clip.sourceStart+minimum)...upper
    }
    public func trimming(_ clip:AudioClip,to value:Double,editingEnd:Bool)->AudioClip {
        var result=clip
        if editingEnd {result.duration=min(end.upperBound,max(end.lowerBound,value))-clip.sourceStart}
        else {result.sourceStart=min(start.upperBound,max(start.lowerBound,value));result.duration=clip.sourceStart+clip.duration-result.sourceStart}
        return result
    }
}
