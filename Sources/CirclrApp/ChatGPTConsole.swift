import SwiftUI

/// Selecting a mode only changes presentation. Authentication begins with an explicit action.
enum ChatGPTConsoleMode: String { case command, chat }

struct ChatGPTConsole: View {
    @ObservedObject var session: ChatGPTMusicSession
    let logHeight: Double
    @FocusState private var draftFocused: Bool
    @FocusState private var transcriptFocused: Bool
    @State private var followsLatest = true
    @AppStorage("circlr.chatGPTPlanUseAcknowledged") private var planUseAcknowledged = false
    @State private var showPlanWelcome = false
    @State private var scrollScheduler = ConsoleScrollScheduler()

    private var canSubmit: Bool {
        session.isSignedIn && !session.isSigningIn && !session.isRunning &&
        !session.isLoadingModels && !session.selectedModel.isEmpty &&
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountControls
            if let error = session.errorMessage, !error.isEmpty {
                ScrollView {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(StudioTheme.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("AI 오류 · " + error)
                }.frame(maxHeight: 52)
                    .help(error)
            }
            if !session.turnScopeLabel.isEmpty {
                Text(session.turnScopeLabel).font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                    .lineLimit(1).truncationMode(.middle).help(session.turnScopeLabel)
                    .accessibilityLabel("AI 작업 범위 · " + session.turnScopeLabel)
            }
            transcript
            if !session.status.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if session.isRunning { ProgressView().controlSize(.small) }
                    Text(session.status).font(.system(size: 11))
                        .foregroundStyle(StudioTheme.secondary)
                        .lineLimit(2).help(session.status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("AI 진행 상태 · " + session.status)
                    Spacer(minLength: 0)
                    if session.isRunning { stopButton }
                }
            } else if session.isRunning {
                HStack { Spacer(); stopButton }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("음악 작업을 요청하세요", text: $session.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain)
                    .font(.system(size: 13)).focused($draftFocused)
                    .padding(8).background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("AI 메시지")
                    .accessibilityHint("입력한 뒤 보내기 버튼을 누르세요")
                Button("보내기") { submit() }
                    .disabled(!canSubmit)
                    .help("현재 곡에 AI 작업 요청 · 명령 Return")
                    .accessibilityLabel("AI 메시지 보내기")
            }
            .onKeyPress(.return, phases: .down) { press in
                guard draftFocused, press.modifiers.contains(.command),
                      (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return .ignored }
                if canSubmit { submit() }
                return .handled
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
        .onDisappear { scrollScheduler.didDisappear() }
        .onAppear { showPlanWelcome = session.isSignedIn && !planUseAcknowledged }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn && !planUseAcknowledged { showPlanWelcome = true }
        }
        .alert("ChatGPT 플랜을 사용합니다", isPresented: $showPlanWelcome) {
            Button("확인") { planUseAcknowledged = true }
        } message: {
            Text("써클러의 AI 요청에는 연결한 ChatGPT 플랜이나 크레딧이 사용됩니다. 사용량과 한도는 ChatGPT 설정에서 관리할 수 있습니다.")
        }
    }

    private var accountControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.isSignedIn && !session.isSigningIn {
                modelControls
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { accountState; Spacer(minLength: 8); accountActions }
                    VStack(alignment: .leading, spacing: 6) { accountState; accountActions }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.planUsageText ?? (session.isSignedIn ? "ChatGPT 플랜 사용 중" : "로그인하면 ChatGPT 플랜을 사용할 수 있습니다"))
                    .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                    .lineLimit(1).help(session.accountStatus)
                    .accessibilityValue(session.accountStatus)
                Spacer(minLength: 0)
                Link("사용량 확인", destination: Self.usageURL)
                    .font(.system(size: 11)).fixedSize()
                    .help("브라우저에서 ChatGPT 사용량 설정 열기")
            }
        }
    }

    private var accountState: some View {
        Text(session.accountStatus).font(.system(size: 12))
            .foregroundStyle(StudioTheme.text)
            .lineLimit(2).help(session.accountStatus)
            .accessibilityLabel("ChatGPT 계정 · " + session.accountStatus)
    }

    @ViewBuilder private var accountActions: some View {
        if session.isSigningIn {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("로그인 취소") { session.cancelLogin() }
            }
        } else if session.isSignedIn {
            HStack(spacing: 8) {
                Button("다른 계정") { session.login(newAccount: true) }
                    .help("현재 AI 작업을 중단하고 다른 계정으로 로그인합니다. 연결이 완료되면 이 앱에 저장된 계정이 교체됩니다")
                Button("로그아웃") { session.logout() }
                    .help("AI 작업을 중단하고 이 앱의 계정 연결을 해제합니다")
            }
        } else {
            HStack(spacing: 8) {
                Button("저장된 계정 연결") { session.connect() }
                    .help("이 앱이 Keychain에 저장한 계정으로 연결합니다")
                Button { session.login() } label: {
                    HStack(spacing: 12) {
                        if let logo = ChatGPTConsoleBranding.logo {
                            Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 21, height: 21).accessibilityHidden(true)
                        }
                        Text("Sign in with ChatGPT").font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white).frame(width: 242, height: 45)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                    .disabled(ChatGPTConsoleBranding.logo == nil)
                    .help(ChatGPTConsoleBranding.logo == nil ? "로그인 리소스를 찾을 수 없습니다. 앱을 다시 설치해 주세요" : "시스템 브라우저에서 ChatGPT 계정으로 로그인합니다")
                    .accessibilityLabel("ChatGPT로 로그인")
            }
        }
    }

    private var modelControls: some View {
        HStack(spacing: 8) {
            if session.models.isEmpty {
                Text(session.isLoadingModels ? "모델 목록 불러오는 중" : "사용 가능한 모델이 없습니다")
                    .font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
            } else {
                Menu {
                    ForEach(session.models, id: \.slug) { model in
                        Button { session.selectedModel = model.slug } label: {
                            if model.slug == session.selectedModel {
                                Label(model.displayName, systemImage: "checkmark")
                            } else { Text(model.displayName) }
                        }
                    }
                } label: {
                    Text(selectedModelName).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 0, maxWidth: .infinity)
                .help(selectedModelName).accessibilityLabel("AI 모델 선택")
                .accessibilityValue(selectedModelName)
                .disabled(session.isRunning || session.isLoadingModels || session.isSigningIn)
            }
            Spacer(minLength: 0)
            Menu("계정") {
                Text(session.accountStatus)
                Button("다른 계정") { session.login(newAccount: true) }
                Button("로그아웃") { session.logout() }
            }.fixedSize().accessibilityLabel("ChatGPT 계정 관리")
            Button("새 대화") { session.clearConversation() }
                .help("AI 작업을 중단하고 대화 기록을 비웁니다. 작성 중인 요청은 유지합니다")
            Button { session.refreshModels() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(session.isLoadingModels || session.isRunning || session.isSigningIn)
                .help("사용 가능한 모델 새로 고침").accessibilityLabel("AI 모델 목록 새로 고침")
        }
    }

    private var selectedModelName: String {
        session.models.first(where: { $0.slug == session.selectedModel })?.displayName ?? session.selectedModel
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty {
                        Text("요청과 응답은 여기에 표시됩니다. AI가 작업하는 동안에도 곡을 직접 편집할 수 있습니다.")
                            .font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(session.messages) { message in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(roleLabel(message.role)).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(StudioTheme.secondary)
                            Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                    }
                    Color.clear.frame(height: 1).id("chatgpt-console-bottom")
                }.padding(.vertical, 8)
            }
            .frame(height: session.messages.isEmpty ? 40 : ConsolePreferences.boundedHeight(logHeight))
            .focusable().focused($transcriptFocused)
            .background(AgentConsoleInputObserver(onWheel: { followsLatest = false },
                onScrollKey: { followsLatest = false }, logFocused: transcriptFocused && !draftFocused))
            .overlay(alignment: .bottomTrailing) {
                if !followsLatest {
                    Button("최신 대화") { followsLatest = true; scroll(proxy) }
                        .controlSize(.small).buttonStyle(.bordered)
                        .accessibilityLabel("최신 AI 대화로 이동")
                }
            }
            .onAppear { scrollScheduler.didAppear(); scroll(proxy) }
            .onChange(of: session.messages.last?.text) { _, _ in scroll(proxy) }
            .onChange(of: session.messages.count) { _, _ in scroll(proxy) }
        }
    }

    private var stopButton: some View {
        Button("AI 중단") { session.stop() }
            .fixedSize()
            .help("AI 요청과 편집 권한을 중단합니다. 음악 재생은 유지합니다")
            .accessibilityLabel("AI 작업 중단")
    }

    private func submit() {
        guard canSubmit else { return }
        followsLatest = true
        session.submit()
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard followsLatest, let generation = scrollScheduler.schedule() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30.0) {
            guard scrollScheduler.consume(generation), followsLatest else { return }
            proxy.scrollTo("chatgpt-console-bottom", anchor: .bottom)
        }
    }

    private func roleLabel(_ role: ChatGPTMusicMessage.Role) -> String {
        switch role {
        case .user: return "나"
        case .assistant: return "AI"
        case .system: return "작업"
        }
    }

    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!
}

/// Keep an AI stop action reachable even when the transcript is folded or commands are selected.
struct ChatGPTConsoleRunControl: View {
    @ObservedObject var session: ChatGPTMusicSession
    var body: some View {
        if session.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(session.status).font(.system(size: 11)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).help(session.status)
                Button("AI 중단") { session.stop() }
                    .accessibilityLabel("AI 작업 중단")
                    .help("AI 요청과 편집 권한을 중단합니다. 음악 재생은 유지합니다")
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

@MainActor
enum ChatGPTConsoleBranding {
    static let logo: NSImage? = Bundle.main.resourceURL.flatMap(loadLogo)
    static func loadLogo(from resources: URL) -> NSImage? {
        NSImage(contentsOf: resources.appendingPathComponent("ChatGPTSignIn/chatgpt-logo-white.svg"))
    }
}
