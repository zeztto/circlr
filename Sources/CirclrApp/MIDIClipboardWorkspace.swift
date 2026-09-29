import AppKit
import CirclrCore

extension AppStore {
    static let midiClipboardType = NSPasteboard.PasteboardType("com.circlr.midi-phrase.v1")
    var midiClipboardEditingAvailable: Bool {
        currentLane != nil && !trackBounceRecoveryLocked && midiImportDraft == nil && !midiRecording && !audioRecordingBusy
    }
    @discardableResult func copyMIDIPhrase(cut: Bool = false, pasteboard: NSPasteboard = .general) -> Bool {
        guard let lane = currentLane, !selectedMIDIIDs.isEmpty, !cut || midiClipboardEditingAvailable else { return false }
        do {
            let ids = selectedMIDIIDs
            let data = try MIDIClipboard(notes: lane.notes.filter { ids.contains($0.id) }).encoded()
            let next = cut ? try MIDIEditing.apply(.delete, to: lane, ids: ids, beats: editorBeats) : lane
            // Preflight the same target before publishing a cut. No asynchronous work
            // occurs between this check, the clipboard write and the single Undo edit.
            if cut { try validateClipboardLane(next) }
            pasteboard.clearContents()
            guard pasteboard.setData(data, forType: Self.midiClipboardType) else { throw CirclrError("MIDI 구절을 클립보드에 쓰지 못했습니다. 원본은 유지됩니다") }
            if cut {
                setLane(next)
                guard currentLane?.notes == next.notes else { return false }
                selectMIDINotes([])
            }
            status = cut ? "MIDI 구절 잘라내기 · \(ids.count)개 노트" : "MIDI 구절 복사 · \(ids.count)개 노트"
            return true
        } catch { fail(error); return false }
    }
    @discardableResult func pasteMIDIPhrase(atOriginalBeat: Bool = false, pasteboard: NSPasteboard = .general) -> Bool {
        guard midiClipboardEditingAvailable, let lane = currentLane else { return false }
        // Never inspect strings, URLs, images, or any other clipboard representation.
        guard pasteboard.availableType(from: [Self.midiClipboardType]) != nil,
              let data = pasteboard.data(forType: Self.midiClipboardType) else { return false }
        do {
            let phrase = try MIDIClipboard.decode(data)
            let next = try phrase.pasting(into: lane, at: atOriginalBeat ? phrase.sourceStartBeat : selectedBeat, beats: editorBeats)
            try validateClipboardLane(next)
            let ids = Set(next.notes.map(\.id)).subtracting(lane.notes.map(\.id))
            setLane(next)
            guard currentLane?.notes == next.notes else { return false }
            selectMIDINotes(ids)
            status = "MIDI 구절 붙여넣기 · \(ids.count)개 노트"
            return true
        } catch { fail(error); return false }
    }
    private func validateClipboardLane(_ lane: Lane) throws {
        var candidate = project
        if let patternID = editPatternID {
            guard let index = candidate.patterns.firstIndex(where: { $0.id == patternID }) else { throw CirclrError("편집할 공유 리듬을 찾을 수 없습니다") }
            candidate.patterns[index].notes = lane.notes
        } else {
            guard let useID = selectedUse?.id else { throw CirclrError("붙여넣을 섹션을 선택하세요") }
            try ProjectEditing.setLane(lane, for: useID, original: editOriginal, in: &candidate)
        }
        try UseTempoOverrideEditing.validateChanges(from: project, to: candidate)
        try ProjectStore.validateStructure(candidate)
    }
}

// Standard responder actions keep the Edit menu and native keyboard dispatch in
// the focused MIDI editor. NSTextView retains its own copy/cut/paste and IME.
extension OrbitMIDIView {
    @objc func copy(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase() } }
    @objc func cut(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase(cut: true) } }
    @objc func paste(_ sender: Any?) { if allowsEditing { store.pasteMIDIPhrase() } }
}
extension PianoRollView {
    @objc func copy(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase() } }
    @objc func cut(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase(cut: true) } }
    @objc func paste(_ sender: Any?) { if allowsEditing { store.pasteMIDIPhrase() } }
}
extension StepGridView {
    @objc func copy(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase() } }
    @objc func cut(_ sender: Any?) { if allowsEditing { store.copyMIDIPhrase(cut: true) } }
    @objc func paste(_ sender: Any?) { if allowsEditing { store.pasteMIDIPhrase() } }
}
