import SwiftUI

// MARK: - Model
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let date = Date()

    enum Role { case user, assistant }
}

// MARK: - Chat Sheet View
struct ChatSheetView: View {
    @ObservedObject var vm: RecordingDetailViewModel
    @State private var inputText = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Message list ─────────────────────────────────────────
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            // Intro hint
                            if vm.chatMessages.isEmpty {
                                VStack(spacing: 6) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.purple)
                                    Text("问问 OpenClaw")
                                        .font(.title3).fontWeight(.semibold)
                                    Text("可以就这段录音提问，例如：\n「帮我列一个行动计划」\n「用英文总结给我」")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }

                            ForEach(vm.chatMessages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id.uuidString)
                            }

                            if vm.isSendingChat {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.chatMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(vm.chatMessages.last?.id.uuidString ?? "typing",
                                           anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isSendingChat) { _, _ in
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }

                Divider()

                // ── Input bar ────────────────────────────────────────────
                HStack(spacing: 10) {
                    TextField("问点什么…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($focused)

                    Button {
                        let msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        inputText = ""
                        vm.sendChatMessage(msg)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSendingChat
                                             ? .gray : .purple)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSendingChat)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("AI 对话")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 44) }

            if !isUser {
                Image(systemName: "brain")
                    .font(.caption)
                    .padding(6)
                    .background(.purple.opacity(0.15))
                    .clipShape(Circle())
            }

            // Render Markdown for assistant, plain for user
            Group {
                if !isUser, let attr = try? AttributedString(
                    markdown: message.text,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attr)
                } else {
                    Text(message.text)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isUser ? Color.purple : Color(UIColor.secondarySystemBackground))
            .foregroundStyle(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .textSelection(.enabled)

            if !isUser { Spacer(minLength: 44) }
            if isUser {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.purple.opacity(0.6))
            }
        }
    }
}

// MARK: - Typing dots
struct TypingIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .scaleEffect(1 + 0.4 * sin(phase + Double(i) * 1.0))
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                               value: phase)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { phase = .pi }
    }
}
