import Foundation

/// Each bus carries an independent stereo pair; channel 1/2 are not bus 1/2.
public struct AudioBusRoute: Codable, Equatable {
    public var input: String
    public var output: String
    public var gain: Double
    public init(input: String, output: String, gain: Double = 1) {
        self.input = input; self.output = output; self.gain = gain
    }
}

public struct AudioRouter: Codable, Equatable {
    public static let input1 = "in.audio.bus1", input2 = "in.audio.bus2"
    public static let output1 = "out.audio.bus1", output2 = "out.audio.bus2"
    public static let inputs = [input1, input2], outputs = [output1, output2]
    public var routes: [AudioBusRoute]
    public init(routes: [AudioBusRoute] = [
        .init(input: input1, output: output1), .init(input: input2, output: output2)
    ]) { self.routes = routes }

    public func validate() throws {
        guard routes.count <= 4,
              routes.allSatisfy({ Self.inputs.contains($0.input) && Self.outputs.contains($0.output) &&
                  $0.gain.isFinite && (0...4).contains($0.gain) }),
              Set(routes.map { [$0.input, $0.output] }).count == routes.count
        else { throw CirclrError("라우터의 입력·출력 bus와 중복 경로·gain을 확인하세요") }
    }
}

/// Renderer keys must include the bus, even when a node has only one output.
public struct MusicBusEndpoint: Hashable, Sendable {
    public var nodeID: ID
    public var portID: String
    public init(nodeID: ID, portID: String) { self.nodeID = nodeID; self.portID = portID }
}

public struct MusicBusConnection: Equatable, Sendable {
    public var id: ID
    public var from: MusicBusEndpoint
    public var to: MusicBusEndpoint
    public var signal: MusicSignal
    public var gain: Double
    public var sidechain: Bool { to.portID == CirclePort.sidechainInput }
    public init(_ edge: MusicConnection) {
        id = edge.id; from = .init(nodeID: edge.from, portID: edge.resolvedFromPortID)
        to = .init(nodeID: edge.to, portID: edge.resolvedToPortID)
        signal = edge.signal; gain = edge.gain
    }
}
