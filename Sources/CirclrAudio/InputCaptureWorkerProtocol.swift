import Foundation
import CirclrCore

/// The capture helper receives only an app-created, private staging directory.
/// The destination take path never crosses the process boundary.
public struct InputCaptureWorkerMessage:Codable,Sendable {
    public enum Kind:String,Codable,Sendable {case start,stop,started,progress,finished,failed,catalog,catalogDevice,catalogFinished}
    public let version:Int
    public let session:UUID
    public let kind:Kind
    public let directory:String?
    public let maximumSeconds:Double?
    /// Present only for app-selected input. A nil value keeps the system-default route.
    public let deviceUID:String?
    public let device:InputDeviceDescriptor?
    public let sampleRate:Double?
    public let channels:UInt32?
    public let frames:Int64?
    public let peak:Float?
    public let reachedLimit:Bool?
    public let interrupted:Bool?
    public let error:String?
    public init(session:UUID,kind:Kind,directory:String?=nil,maximumSeconds:Double?=nil,deviceUID:String?=nil,
                device:InputDeviceDescriptor?=nil,
                sampleRate:Double?=nil,channels:UInt32?=nil,frames:Int64?=nil,peak:Float?=nil,
                reachedLimit:Bool?=nil,interrupted:Bool?=nil,error:String?=nil) {
        self.version=1;self.session=session;self.kind=kind;self.directory=directory
        self.maximumSeconds=maximumSeconds;self.deviceUID=deviceUID;self.device=device;self.sampleRate=sampleRate;self.channels=channels
        self.frames=frames;self.peak=peak;self.reachedLimit=reachedLimit;self.interrupted=interrupted;self.error=error
    }
}

public enum InputCaptureWorkerWire {
    public static let maximumLineBytes=4096
    public static func encode(_ message:InputCaptureWorkerMessage)throws->Data {
        var data=try JSONEncoder().encode(message)
        guard data.count<maximumLineBytes else{throw CirclrError("입력 worker 메시지가 너무 큽니다")}
        data.append(10);return data
    }
    public static func decode(_ line:Data)throws->InputCaptureWorkerMessage {
        guard !line.isEmpty,line.count<=maximumLineBytes,
              let value=try? JSONDecoder().decode(InputCaptureWorkerMessage.self,from:line),value.version==1 else {
            throw CirclrError("입력 worker 응답이 올바르지 않습니다")
        }
        return value
    }
    public static func checkedFormat(_ message:InputCaptureWorkerMessage)throws->CaptureFormat {
        guard let rate=message.sampleRate,rate.isFinite,(8000...384000).contains(rate),
              let channels=message.channels,(1...2).contains(channels) else {
            throw CirclrError("입력 worker 오디오 형식이 올바르지 않습니다")
        }
        return CaptureFormat(sampleRate:rate,channels:channels)
    }
    public static func checkedSelection(_ message:InputCaptureWorkerMessage)throws->InputDeviceSelection {
        let selection=message.deviceUID.map(InputDeviceSelection.deviceUID) ?? .systemDefault
        try selection.validate()
        return selection
    }
}
