import AVFAudio
import AudioToolbox
import Foundation
import CirclrCore

struct RecoverableSelectedInputError:Error {
    let audio:CapturedAudio
    let reason:String
}

/// AUHAL is required for a non-default input. This object is constructed only
/// inside circlr-input-worker, so a driver that blocks in CoreAudio cannot
/// block the app's MainActor or change the macOS default input.
final class SelectedInputCaptureBackend:AudioCaptureBackend {
    private let selection:InputDeviceSelection
    private var unit:AudioUnit?,binding:InputDeviceBinding?,buffer:AVAudioPCMBuffer?
    private var writer:TakeWriter?,control:CaptureControl?,started=false,initialized=false,reportedStarted=false
    private var outputFormat:AVAudioFormat?

    init(selection:InputDeviceSelection) {self.selection=selection}

    private func check(_ status:OSStatus,_ operation:String)throws {
        guard status==noErr else{throw InputDeviceBindingError.systemCall(operation:operation,status:status)}
    }

    func start(to url:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat {
        guard case .deviceUID=selection else{throw InputDeviceBindingError.invalidSelection}
        try selection.validate()
        self.control=control
        func active()throws {if !control.enabled{throw CancellationError()}}
        try active()
        var description=AudioComponentDescription(componentType:kAudioUnitType_Output,
            componentSubType:kAudioUnitSubType_HALOutput,componentManufacturer:kAudioUnitManufacturer_Apple,
            componentFlags:0,componentFlagsMask:0)
        guard let component=AudioComponentFindNext(nil,&description) else{
            throw CirclrError("입력 AUHAL 컴포넌트를 찾을 수 없습니다")
        }
        var created:AudioUnit?
        try check(AudioComponentInstanceNew(component,&created),"AUHAL 생성")
        guard let created else{throw CirclrError("입력 AUHAL을 만들 수 없습니다")}
        unit=created
        do {
            var enabled:UInt32=1,disabled:UInt32=0
            try check(AudioUnitSetProperty(created,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,
                &enabled,UInt32(MemoryLayout<UInt32>.size)),"입력 활성화")
            try check(AudioUnitSetProperty(created,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Output,0,
                &disabled,UInt32(MemoryLayout<UInt32>.size)),"출력 비활성화")
            try active()
            let bound=try InputDeviceBinding(selection:selection,audioUnit:created)
            try bound.bind();binding=bound
            var native=AudioStreamBasicDescription(),size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(created,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,1,
                &native,&size),"입력 형식 조회")
            guard size==MemoryLayout<AudioStreamBasicDescription>.size,
                  native.mSampleRate.isFinite,(8000...384000).contains(native.mSampleRate),
                  (1...32).contains(native.mChannelsPerFrame) else {
                throw CirclrError("선택한 장치의 오디오 입력 형식이 올바르지 않습니다")
            }
            let channels=min(2,native.mChannelsPerFrame)
            guard let format=AVAudioFormat(standardFormatWithSampleRate:native.mSampleRate,channels:channels) else {
                throw CirclrError("선택한 장치의 녹음 형식을 만들 수 없습니다")
            }
            var stream=format.streamDescription.pointee
            try check(AudioUnitSetProperty(created,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,1,
                &stream,UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),"녹음 형식 적용")
            var callback=AURenderCallbackStruct(inputProc:selectedInputCallback,
                inputProcRefCon:Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(created,kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Global,0,
                &callback,UInt32(MemoryLayout<AURenderCallbackStruct>.size)),"입력 callback 연결")
            try active();try bound.revalidate()
            try check(AudioUnitInitialize(created),"AUHAL 초기화");initialized=true
            var maximumFrames:UInt32=0;size=UInt32(MemoryLayout<UInt32>.size)
            try check(AudioUnitGetProperty(created,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,
                &maximumFrames,&size),"입력 buffer 크기 조회")
            guard size==MemoryLayout<UInt32>.size,(1...65536).contains(maximumFrames),
                  let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:maximumFrames) else {
                throw CirclrError("선택한 장치의 입력 buffer가 올바르지 않습니다")
            }
            self.buffer=buffer;outputFormat=format
            control.limit(frames:UInt64((maximumSeconds*format.sampleRate).rounded(.down)))
            writer=try TakeWriter(url:url,format:format)
            try active();try bound.revalidate()
            try check(AudioOutputUnitStart(created),"입력 시작");started=true
            try active();try bound.revalidate()
            reportedStarted=true
            return CaptureFormat(sampleRate:format.sampleRate,channels:channels)
        }catch {
            control.disable();_ = try? stop()
            throw error
        }
    }

    fileprivate func render(_ flags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ timestamp:UnsafePointer<AudioTimeStamp>,_ frames:UInt32)->OSStatus {
        guard let control,control.enabled,let unit,let buffer,let writer,let outputFormat else{return noErr}
        guard frames<=buffer.frameCapacity else{control.interrupt();return noErr}
        buffer.frameLength=frames
        let status=AudioUnitRender(unit,flags,timestamp,1,frames,buffer.mutableAudioBufferList)
        if status==noErr {control.append(buffer,to:writer,channels:outputFormat.channelCount)}
        else{control.interrupt()}
        return noErr
    }

    func stop()throws->CapturedAudio? {
        control?.disable()
        var error:Error?
        if let unit {
            if started {
                let status=AudioOutputUnitStop(unit)
                if status != noErr {error=InputDeviceBindingError.systemCall(operation:"입력 정지",status:status)}
                started=false
            }
            control?.waitForCallbacks()
            if binding != nil {
                do {try binding?.revalidate()}
                catch let validationError {
                    // Identity mismatch must never become a recoverable take.
                    if validationError as? InputDeviceBindingError == .changedDevice || error==nil {
                        error=validationError
                    }
                }
            }
            if initialized {_ = AudioUnitUninitialize(unit);initialized=false}
            _ = AudioComponentInstanceDispose(unit)
        }
        unit=nil;binding=nil;buffer=nil;outputFormat=nil;control=nil
        let current=writer;writer=nil
        guard let current else{if let error{throw error};return nil}
        // Finalize the private CAF even if the selected device disappeared.
        // The parent does not publish it when validation failed.
        do {try current.finish()}catch let finishError {if error==nil{error=finishError}}
        let file=try AVAudioFile(forReading:current.url)
        guard file.length>0 else{if let error{throw error};return nil}
        let audio=CapturedAudio(url:current.url,
            format:CaptureFormat(sampleRate:file.processingFormat.sampleRate,channels:file.processingFormat.channelCount),
            frames:file.length)
        if let error {
            guard reportedStarted,Self.canRecover(error) else{throw error}
            throw RecoverableSelectedInputError(audio:audio,reason:error.localizedDescription)
        }
        return audio
    }

    static func canRecover(_ error:Error)->Bool {
        guard !(error is CancellationError) else{return false}
        if let binding=error as? InputDeviceBindingError {
            switch binding {
            case .changedDevice,.invalidSelection,.notBound,.selectedCaptureUnavailable:return false
            case .missingDevice,.unavailableDevice,.noInput,.systemCall:return true
            }
        }
        return true
    }
}

private let selectedInputCallback:AURenderCallback = {refCon,flags,timestamp,_,frames,_ in
    return Unmanaged<SelectedInputCaptureBackend>.fromOpaque(refCon).takeUnretainedValue()
        .render(flags,timestamp,frames)
}
