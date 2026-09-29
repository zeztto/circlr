import SwiftUI

/// Use the same cursor action in orbit, grid and step workspaces.
struct CursorPlaybackButton: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.playFromEditorCursor()
        } label: {
            Label("커서부터 듣기", systemImage: "play.circle")
        }
        .fixedSize()
        .disabled(!store.canPlayFromEditorCursor)
        .accessibilityLabel("편집 커서부터 선택 섹션 재생")
        .help(store.editorCursorPlaybackHelp + " · MIDI 편집에서 ⌥⌘Return")
    }
}
