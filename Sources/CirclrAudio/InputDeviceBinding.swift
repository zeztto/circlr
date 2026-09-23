import Foundation
import CoreAudio
import AudioToolbox

public enum InputDeviceBindingError:Error,LocalizedError,Equatable {
    case invalidSelection,missingDevice,unavailableDevice,noInput,changedDevice,notBound,selectedCaptureUnavailable
    case systemCall(operation:String,status:OSStatus)
    public var errorDescription:String? {
        switch self {
        case .invalidSelection:return "입력 장치 선택값이 올바르지 않습니다"
        case .missingDevice:return "선택한 입력 장치를 찾을 수 없습니다"
        case .unavailableDevice:return "선택한 입력 장치를 사용할 수 없습니다"
        case .noInput:return "선택한 장치에는 오디오 입력이 없습니다"
        case .changedDevice:return "입력 장치가 변경되어 녹음을 시작하지 않았습니다. 장치 선택을 확인하세요"
        case .notBound:return "입력 장치가 아직 확인되지 않았습니다"
        case .selectedCaptureUnavailable:return "선택한 입력 장치의 녹음 경로를 이 빌드에서 사용할 수 없습니다"
        case .systemCall(let operation,let status):return "입력 장치 \(operation)에 실패했습니다 (OSStatus \(status))"
        }
    }
}

/// No method here changes the system's default input device.
protocol InputDeviceAccess:AnyObject {
    func defaultInputID() throws -> AudioDeviceID
    func resolveUID(_ uid:String) throws -> AudioDeviceID
    func descriptor(_ id:AudioDeviceID) throws -> InputDeviceDescriptor
    func isAlive(_ id:AudioDeviceID) throws -> Bool
    func hasInput(_ id:AudioDeviceID) throws -> Bool
    func currentDevice() throws -> AudioDeviceID
    func setCurrentDevice(_ id:AudioDeviceID) throws
}

/// Bind only after AUHAL input IO has been enabled.
public final class InputDeviceBinding {
    public let selection:InputDeviceSelection
    public private(set) var deviceID:AudioDeviceID?
    private let access:any InputDeviceAccess
    private var boundUID:String?

    public convenience init(selection:InputDeviceSelection,audioUnit:AudioUnit) throws {
        try self.init(selection:selection,access:CoreAudioInputDeviceAccess(audioUnit:audioUnit))
    }
    init(selection:InputDeviceSelection,access:any InputDeviceAccess) throws {
        try selection.validate();self.selection=selection;self.access=access
    }
    private func selectedID() throws -> AudioDeviceID {
        let id:AudioDeviceID
        switch selection {
        case .systemDefault:id=try access.defaultInputID()
        case .deviceUID(let uid):id=try access.resolveUID(uid)
        }
        guard id != kAudioObjectUnknown else{throw InputDeviceBindingError.missingDevice}
        return id
    }
    private func checked(_ id:AudioDeviceID) throws -> InputDeviceDescriptor {
        guard try access.isAlive(id) else{throw InputDeviceBindingError.unavailableDevice}
        guard try access.hasInput(id) else{throw InputDeviceBindingError.noInput}
        let descriptor=try access.descriptor(id)
        try InputDeviceSelection.deviceUID(descriptor.uid).validate()
        if case .deviceUID(let uid)=selection,descriptor.uid != uid {throw InputDeviceBindingError.changedDevice}
        return descriptor
    }
    @discardableResult public func bind() throws -> InputDeviceDescriptor {
        deviceID=nil;boundUID=nil
        let id=try selectedID(),descriptor=try checked(id)
        try access.setCurrentDevice(id)
        guard try access.currentDevice()==id,try selectedID()==id else{throw InputDeviceBindingError.changedDevice}
        let confirmed=try checked(id)
        guard confirmed.uid==descriptor.uid else{throw InputDeviceBindingError.changedDevice}
        deviceID=id;boundUID=confirmed.uid
        return confirmed
    }
    @discardableResult public func revalidate() throws -> InputDeviceDescriptor {
        guard let id=deviceID,let uid=boundUID else{throw InputDeviceBindingError.notBound}
        guard try selectedID()==id,try access.currentDevice()==id else{throw InputDeviceBindingError.changedDevice}
        let descriptor=try checked(id)
        guard descriptor.uid==uid else{throw InputDeviceBindingError.changedDevice}
        return descriptor
    }
}

final class CoreAudioInputDeviceAccess:InputDeviceAccess {
    private let audioUnit:AudioUnit?
    init(audioUnit:AudioUnit?=nil){self.audioUnit=audioUnit}
    private func check(_ status:OSStatus,_ operation:String) throws {
        if status != noErr {throw InputDeviceBindingError.systemCall(operation:operation,status:status)}
    }
    private func uint(_ id:AudioObjectID,_ selector:AudioObjectPropertySelector) throws -> UInt32 {
        var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var value:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id,&address,0,nil,&size,&value),"조회")
        guard size==MemoryLayout<UInt32>.size else{throw InputDeviceBindingError.unavailableDevice}
        return value
    }
    func defaultInputID() throws -> AudioDeviceID {
        try uint(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultInputDevice)
    }
    func resolveUID(_ uid:String) throws -> AudioDeviceID {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyTranslateUIDToDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        let qualifier=uid as CFString
        var qualifierPointer=Unmanaged.passUnretained(qualifier).toOpaque()
        var result=AudioDeviceID(kAudioObjectUnknown),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        let status=withExtendedLifetime(qualifier) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,
                UInt32(MemoryLayout<UnsafeMutableRawPointer>.size),&qualifierPointer,&size,&result)
        }
        try check(status,"식별")
        guard size==MemoryLayout<AudioDeviceID>.size else{throw InputDeviceBindingError.unavailableDevice}
        return result
    }
    private func string(_ id:AudioDeviceID,_ selector:AudioObjectPropertySelector) throws -> String {
        var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var result:Unmanaged<CFString>?,size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(id,&address,0,nil,&size,&result),"정보 조회")
        guard let result,size==MemoryLayout<Unmanaged<CFString>?>.size else{throw InputDeviceBindingError.unavailableDevice}
        return result.takeRetainedValue() as String
    }
    func descriptor(_ id:AudioDeviceID) throws -> InputDeviceDescriptor {
        InputDeviceDescriptor(uid:try string(id,kAudioDevicePropertyDeviceUID),
                              name:try string(id,kAudioObjectPropertyName),isDefault:false)
    }
    func isAlive(_ id:AudioDeviceID) throws -> Bool {try uint(id,kAudioDevicePropertyDeviceIsAlive) != 0}
    func hasInput(_ id:AudioDeviceID) throws -> Bool {
        var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        try check(AudioObjectGetPropertyDataSize(id,&address,0,nil,&size),"입력 조회")
        return size>=MemoryLayout<AudioStreamID>.size
    }
    func currentDevice() throws -> AudioDeviceID {
        guard let audioUnit else{throw InputDeviceBindingError.notBound}
        var result=AudioDeviceID(kAudioObjectUnknown),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioUnitGetProperty(audioUnit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&result,&size),"적용 확인")
        guard size==MemoryLayout<AudioDeviceID>.size else{throw InputDeviceBindingError.unavailableDevice}
        return result
    }
    func setCurrentDevice(_ id:AudioDeviceID) throws {
        guard let audioUnit else{throw InputDeviceBindingError.notBound}
        var value=id
        try check(AudioUnitSetProperty(audioUnit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&value,UInt32(MemoryLayout<AudioDeviceID>.size)),"적용")
    }
}

public enum InputDeviceCatalog {
    /// Query off the MainActor; CoreAudio may synchronously contact a device driver.
    public static func available() throws -> [InputDeviceDescriptor] {
        let system=AudioObjectID(kAudioObjectSystemObject)
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        var status=AudioObjectGetPropertyDataSize(system,&address,0,nil,&size)
        guard status==noErr else{throw InputDeviceBindingError.systemCall(operation:"목록 조회",status:status)}
        let itemSize=MemoryLayout<AudioDeviceID>.size
        guard size<=UInt32(256*itemSize),Int(size)%itemSize==0 else{throw InputDeviceBindingError.unavailableDevice}
        let count=Int(size)/itemSize
        var ids=[AudioDeviceID](repeating:kAudioObjectUnknown,count:count)
        if size>0 {
            status=ids.withUnsafeMutableBytes {bytes in
                AudioObjectGetPropertyData(system,&address,0,nil,&size,bytes.baseAddress!)
            }
            guard status==noErr else{throw InputDeviceBindingError.systemCall(operation:"목록 조회",status:status)}
            guard Int(size)<=count*itemSize,Int(size)%itemSize==0 else{throw InputDeviceBindingError.unavailableDevice}
            ids=Array(ids.prefix(Int(size)/itemSize))
        }
        let access=CoreAudioInputDeviceAccess()
        let defaultID=try? access.defaultInputID()
        return try ids.compactMap { id in
            guard try access.isAlive(id),try access.hasInput(id) else{return nil}
            let descriptor=try access.descriptor(id)
            return InputDeviceDescriptor(uid:descriptor.uid,name:descriptor.name,isDefault:id==defaultID)
        }.sorted {$0.name.localizedStandardCompare($1.name)==(.orderedAscending)}
    }
}
