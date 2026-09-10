import Foundation
import CoreAudio
import Darwin

/// Called only by the dedicated helper executable; never changes the system output device.
public enum OutputDeviceCatalogService {
    public static func run(arguments:[String])->Never {
        guard arguments == ["--list"] else{exit(64)}
        signal(SIGPIPE,SIG_IGN)
        DispatchQueue(label:"circlr.catalog-parent").async {
            var byte:UInt8=0
            while true {
                let count=Darwin.read(STDIN_FILENO,&byte,1)
                if count<0 && errno==EINTR{continue}
                exit(count==0 ? 0:66)
            }
        }
        do {
            let catalog=try enumerate();try catalog.validate()
            let bytes=try JSONEncoder().encode(catalog)
            guard bytes.count<=OutputDeviceCatalog.maximumBytes else{exit(70)}
            try FileHandle.standardOutput.write(contentsOf:bytes);exit(0)
        } catch {exit(70)}
    }
    private static func address(_ selector:AudioObjectPropertySelector,_ scope:AudioObjectPropertyScope=kAudioObjectPropertyScopeGlobal)->AudioObjectPropertyAddress {
        .init(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    private static func integer(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)throws->UInt32 {
        var property=address(selector),value:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object,&property,0,nil,&size,&value)==noErr,size==4 else{throw OutputDeviceCatalogError.invalidResponse};return value
    }
    private static func string(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)throws->String {
        var property=address(selector),value:Unmanaged<CFString>?=nil,size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object,&property,0,nil,&size,&value)==noErr,size==UInt32(MemoryLayout<Unmanaged<CFString>?>.size),let value else{throw OutputDeviceCatalogError.invalidResponse}
        // CoreAudio transfers ownership for DeviceUID and Name (AudioHardwareBase.h).
        return value.takeRetainedValue() as String
    }
    private static func enumerate()throws->OutputDeviceCatalog {
        let system=AudioObjectID(kAudioObjectSystemObject)
        var property=address(kAudioHardwarePropertyDevices),size:UInt32=0
        guard AudioObjectGetPropertyDataSize(system,&property,0,nil,&size)==noErr,size<=4096,size%4==0 else{throw OutputDeviceCatalogError.invalidResponse}
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/4)
        if size>0 {
            let status=ids.withUnsafeMutableBytes{AudioObjectGetPropertyData(system,&property,0,nil,&size,$0.baseAddress!)}
            guard status==noErr,Int(size)<=ids.count*4,size%4==0 else{throw OutputDeviceCatalogError.invalidResponse}
            ids=Array(ids.prefix(Int(size)/4))
        }
        let defaultID=try integer(system,kAudioHardwarePropertyDefaultOutputDevice)
        var devices=[OutputDeviceDescriptor](),defaultUID:String?
        for id in ids {
            guard (try? integer(id,kAudioDevicePropertyDeviceIsAlive))==1 else{continue}
            var streams=address(kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput),bytes:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&bytes)==noErr,bytes>0 else{continue}
            let uid=try string(id,kAudioDevicePropertyDeviceUID),name=try string(id,kAudioObjectPropertyName)
            devices.append(.init(uid:uid,name:name));if id==defaultID{defaultUID=uid}
        }
        return .init(devices:devices,defaultUID:defaultUID)
    }
}
