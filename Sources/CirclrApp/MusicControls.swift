import SwiftUI
import CirclrCore

struct MeterEditor:View {
    @Binding var meter:Meter
    var body:some View {
        HStack(spacing:12){StudioStepper("박자",value:$meter.numerator,in:1...64);Text("/").foregroundStyle(StudioTheme.secondary)
            StudioChoice("",selection:$meter.denominator,options:[1,2,4,8,16,32,64].map{($0,String($0))}).frame(width:80)}
    }
}
struct ScaleEditor:View {
    @Binding var scale:Scale
    var body:some View {
        HStack(spacing:12){Text("스케일");Spacer()
            StudioChoice("",selection:$scale.root,options:(0..<12).map{($0,Scale.roots[$0])}).frame(width:80)
            StudioChoice("",selection:Binding(get:{scale.name},set:{n in scale.name=n;scale.intervals=Scale.modes.first{$0.0==n}?.1 ?? scale.intervals}),options:Scale.modes.map{($0.0,$0.0)}).frame(width:148)}
    }
}
struct BeatEditor:View {
    @Binding var grid:BeatGrid
    @State var accents=""
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            StudioStepper("박 분할",value:$grid.subdivisions,in:1...32)
            CompactNumber("Swing · 0–0.75",value:$grid.swing,range:0...0.75)
            HStack{Text("강세 묶음");Spacer();TextField("예: 2+2+3",text:$accents).frame(width:240)
                .onChange(of:accents){_,value in grid.accents=value.replacingOccurrences(of:"+",with:",").split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces))}.filter{$0>=1}}}
            Text("박 수를 더한 묶음 · 7/8의 예: 2+2+3").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
        }.onAppear{accents=grid.accents.map{String($0)}.joined(separator:"+")}
    }
}
struct PatternPicker:View {
    let project:Project
    @Binding var assignment:RhythmAssignment
    var body:some View {StudioChoice("리듬 패턴",selection:Binding(get:{assignment.patternID ?? ""},set:{assignment.patternID=$0.isEmpty ? nil:$0}),options:[("","재생 안 함")]+project.patterns.map{($0.id,$0.name)})}
}
