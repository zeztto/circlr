import Foundation

/// Source-time presentation state only; fitting never changes or follows a trim.
public struct AudioSourceViewport:Equatable {
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
