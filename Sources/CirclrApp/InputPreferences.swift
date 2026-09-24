import Foundation
import Combine
import CirclrAudio

/// Recording input is an app preference. It never writes the macOS default device.
@MainActor final class InputPreferences:ObservableObject {
    private static let key="circlr.recording.inputDeviceUID"
    private let defaults:UserDefaults
    private let query:@Sendable () async throws -> [InputDeviceDescriptor]
    private var task:Task<Void,Never>?
    private var generation=0
    @Published private(set) var selection:InputDeviceSelection
    @Published private(set) var devices:[InputDeviceDescriptor]=[]
    @Published private(set) var loading=false
    @Published private(set) var queried=false
    @Published private(set) var message:String?

    init(defaults:UserDefaults = .standard,
         query:@escaping @Sendable () async throws -> [InputDeviceDescriptor] = {
             try await IsolatedInputDeviceCatalog.available()
         }) {
        self.defaults=defaults;self.query=query
        if let uid=defaults.string(forKey:Self.key),
           (try? InputDeviceSelection.deviceUID(uid).validate()) != nil {
            selection = .deviceUID(uid)
        }else{selection = .systemDefault}
    }
    var selectedUID:String? {if case .deviceUID(let uid)=selection{return uid};return nil}
    var selectedName:String {
        guard let uid=selectedUID else{return "시스템 기본 입력"}
        return devices.first(where:{$0.uid==uid})?.name ?? "저장된 입력 장치"
    }
    var missing:Bool {
        guard queried,let uid=selectedUID else{return false}
        return !devices.contains(where:{$0.uid==uid})
    }
    func choose(_ uid:String?) {
        if let uid {
            guard devices.contains(where:{$0.uid==uid}) else{return}
            selection = .deviceUID(uid);defaults.set(uid,forKey:Self.key)
        }else{selection = .systemDefault;defaults.removeObject(forKey:Self.key)}
    }
    func refresh() {
        cancel();generation+=1;let ticket=generation;loading=true;message=nil
        let query=query
        task=Task{[weak self] in
            do {
                let result=try await query();try Task.checkCancellation()
                guard let self,self.generation==ticket else{return}
                self.devices=result;self.queried=true;self.loading=false;self.task=nil
            }catch{
                guard let self,self.generation==ticket else{return}
                self.loading=false;self.task=nil
                if !(error is CancellationError) {
                    self.message="입력 장치 목록을 확인하지 못했습니다. 다시 조회하세요."
                }
            }
        }
    }
    func cancel(){generation+=1;task?.cancel();task=nil;loading=false}
}
