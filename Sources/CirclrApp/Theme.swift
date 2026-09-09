import SwiftUI
import AppKit
import CirclrCore

/// A shared palette keeps AppKit drawing and SwiftUI controls in the same dark workspace.
enum StudioTheme {
    static let canvasNS = NSColor(white:0.065,alpha:1)
    static let surfaceNS = NSColor(white:0.105,alpha:1)
    static let raisedNS = NSColor(white:0.145,alpha:1)
    static let lineNS = NSColor(white:0.24,alpha:1)
    static let textNS = NSColor(white:0.94,alpha:1)
    static let secondaryNS = NSColor(white:0.63,alpha:1)
    static let accentNS = NSColor(srgbRed:0.52,green:0.88,blue:0.73,alpha:1)
    static let canvas = Color(nsColor:canvasNS)
    static let surface = Color(nsColor:surfaceNS)
    static let raised = Color(nsColor:raisedNS)
    static let line = Color(nsColor:lineNS)
    static let text = Color(nsColor:textNS)
    static let secondary = Color(nsColor:secondaryNS)
    static let accent = Color(nsColor:accentNS)
}

struct StudioFieldStyle:TextFieldStyle {
    func _body(configuration:TextField<Self._Label>)->some View {
        configuration.textFieldStyle(.plain).padding(.horizontal,10).padding(.vertical,8)
            .background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(StudioTheme.line))
    }
}

struct StudioChoice<Value:Hashable>:View {
    let title:String
    @Binding var selection:Value
    let options:[(Value,String)]
    init(_ title:String,selection:Binding<Value>,options:[(Value,String)]){self.title=title;_selection=selection;self.options=options}
    var body:some View {
        HStack(spacing:14) {
            if !title.isEmpty {Text(title);Spacer(minLength:8)}
            Menu {
                ForEach(options,id:\.0){value,name in Button((selection==value ? "✓ ":"")+name){selection=value}}
            } label: {
                HStack(spacing:16){Text(options.first{$0.0==selection}?.1 ?? "선택").lineLimit(1);Spacer(minLength:4);Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)).foregroundStyle(StudioTheme.secondary)}
                    .padding(.horizontal,11).padding(.vertical,9).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth:title.isEmpty ? .infinity:240).accessibilityLabel(title.isEmpty ? "선택":title).accessibilityValue(options.first{$0.0==selection}?.1 ?? "선택되지 않음")
        }
    }
}
struct StudioStepper:View {
    let title:String
    @Binding var value:Int
    let range:ClosedRange<Int>
    init(_ title:String,value:Binding<Int>,in range:ClosedRange<Int>){self.title=title;_value=value;self.range=range}
    var body:some View {
        HStack(spacing:14){Text(title);Spacer(minLength:8)
            HStack(spacing:4){
                Button {value=max(range.lowerBound,value-1)} label:{Image(systemName:"minus").font(.system(size:10))}.disabled(value<=range.lowerBound).accessibilityLabel(title+" 줄이기")
                Text("\(value)").monospacedDigit().frame(minWidth:24)
                Button {value=min(range.upperBound,value+1)} label:{Image(systemName:"plus").font(.system(size:10))}.disabled(value>=range.upperBound).accessibilityLabel(title+" 늘리기")
            }.background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
        }
    }
}

struct CountControl:View {
    let title:String
    @Binding var value:Int
    let range:ClosedRange<Int>
    var suffix=""
    var body:some View {
        HStack(spacing:6) {
            if !title.isEmpty {Text(title).foregroundStyle(StudioTheme.secondary)}
            HStack(spacing:0) {
                Button {value=max(range.lowerBound,value-1)} label:{Image(systemName:"minus").frame(width:28,height:32)}.disabled(value<=range.lowerBound).accessibilityLabel(title+" 줄이기")
                CommittedNumberField(title:title,value:Binding(get:{Double(value)},set:{if let next=Int(exactly:$0) {value=next}}),range:Double(range.lowerBound)...Double(range.upperBound),integerOnly:true,width:48,alignment:.center)
                Button {value=min(range.upperBound,value+1)} label:{Image(systemName:"plus").frame(width:28,height:32)}.disabled(value>=range.upperBound).accessibilityLabel(title+" 늘리기")
            }.buttonStyle(.plain).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
            if !suffix.isEmpty {Text(suffix).foregroundStyle(StudioTheme.secondary)}
        }.font(.system(size:13))
    }
}
struct ValueField:View {
    let title:String
    @Binding var value:Double
    var width:CGFloat=72
    var showsLabel=true
    var range:ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
    var integerOnly=false
    var presentation:NumberEditPresentation = .number
    var body:some View {
        HStack(spacing:7) {
            if showsLabel && !title.isEmpty {Text(title).foregroundStyle(StudioTheme.secondary)}
            CommittedNumberField(title:title,value:$value,range:range,integerOnly:integerOnly,width:width,presentation:presentation)
        }.font(.system(size:13))
    }
}
