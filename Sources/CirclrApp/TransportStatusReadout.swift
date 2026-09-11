import SwiftUI

/// The same compact readout can be inspected without constructing an audio backend.
struct TransportStatusReadout:View {
    let time:String
    let label:String?
    let detail:String
    let footer:String?
    let textColor:Color
    let secondaryColor:Color
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            Text(time).font(.system(size:13,design:.monospaced)).foregroundStyle(textColor)
            if let label {
                Text(label).font(.system(size:12,weight:.medium)).lineLimit(1)
                    .foregroundStyle(textColor).help(detail).accessibilityLabel(detail)
            }
            if let footer {
                Text(footer).font(.system(size:10)).lineLimit(1).monospacedDigit()
                    .foregroundStyle(secondaryColor)
            }
        }.frame(width:108,alignment:.leading)
    }
}
