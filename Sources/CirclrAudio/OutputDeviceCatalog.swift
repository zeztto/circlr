import Foundation

public struct OutputDeviceDescriptor:Codable,Equatable,Sendable {
    public var uid:String
    public var name:String
    public init(uid:String,name:String){self.uid=uid;self.name=name}
}
public struct OutputDeviceCatalog:Codable,Equatable,Sendable {
    public var version:Int=1
    public var devices:[OutputDeviceDescriptor]
    public var defaultUID:String?
    public init(devices:[OutputDeviceDescriptor],defaultUID:String?=nil){self.devices=devices;self.defaultUID=defaultUID}
    public static let maximumBytes=65_536
    public func validate()throws {
        guard version==1,devices.count<=256 else{throw OutputDeviceCatalogError.invalidResponse}
        var ids=Set<String>()
        for device in devices {
            guard !device.uid.isEmpty,device.uid.utf8.count<=1024,!device.uid.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
                  !device.name.isEmpty,device.name.utf8.count<=1024,!device.name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),ids.insert(device.uid).inserted else{throw OutputDeviceCatalogError.invalidResponse}
        }
        if let defaultUID, !ids.contains(defaultUID){throw OutputDeviceCatalogError.invalidResponse}
    }
    static func decode(_ data:Data)throws->Self {
        guard data.count<=maximumBytes else{throw OutputDeviceCatalogError.invalidResponse}
        let value=try JSONDecoder().decode(Self.self,from:data);try value.validate();return value
    }
}
public enum OutputDeviceCatalogError:Error,LocalizedError {
    case unavailable,timedOut,invalidResponse,failed(Int32)
    public var errorDescription:String? {
        switch self {
        case .unavailable:return "출력 장치 조회 helper를 찾을 수 없습니다"
        case .timedOut:return "출력 장치 조회 시간이 초과되었습니다"
        case .invalidResponse:return "출력 장치 목록을 확인할 수 없습니다"
        case .failed:return "출력 장치를 조회하지 못했습니다"
        }
    }
}
