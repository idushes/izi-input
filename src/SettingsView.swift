import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var downloader: ModelDownloader
    @ObservedObject var audioInputState: AudioInputState
    let onPlayPause: () -> Void

    @State private var hasAccessibilityAccess: Bool = false

    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    modelSection

                    if audioInputState.hasLastAudio {
                        lastRecordingSection
                    }

                    accessibilitySection
                    usageSection
                }
                .padding(14)
            }
        }
        .frame(width: 440, height: 560)
        .onAppear {
            checkAccessibilityAccess()
        }
        .onReceive(timer) { _ in
            checkAccessibilityAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Izi Input")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Голосовой ввод через Fn")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("", selection: $audioInputState.outputLanguage) {
                Text("RUS").tag(OutputLanguage.russian)
                Text("ENG").tag(OutputLanguage.english)
            }
            .pickerStyle(.segmented)
            .frame(width: 112)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modelSection: some View {
        section(title: "Whisper", icon: "cpu", color: .blue) {
            HStack(spacing: 10) {
                Text("Модель")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: $downloader.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 178)
                .disabled(downloader.isDownloading)
            }

            Text(downloader.status)
                .font(.caption)
                .foregroundColor(.secondary)

            if downloader.isDownloading {
                ProgressView(value: downloader.progress)
                    .progressViewStyle(.linear)
                    .accentColor(.purple)

                Button("Отменить скачивание") {
                    downloader.cancelDownload()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            } else if !downloader.isModelDownloaded {
                Button("Скачать модель") {
                    downloader.startDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                HStack {
                    Label("Готова", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)

                    Spacer()

                    Button("Перекачать") {
                        downloader.startDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var lastRecordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.pink)
                Text("Последняя запись")
                    .font(.headline)

                Spacer()

                Button(action: onPlayPause) {
                    Label(
                        audioInputState.isPlayingAudio ? "Пауза" : "Прослушать",
                        systemImage: audioInputState.isPlayingAudio ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(audioInputState.isPlayingAudio ? .red : .green)
            }

            transcriptBlock(
                title: "Русский",
                text: audioInputState.lastRussianText,
                emptyText: "Речь не распознана"
            )

            transcriptBlock(
                title: "English",
                text: audioInputState.lastEnglishText,
                emptyText: "Translation not available"
            )
        }
        .cardStyle()
    }

    private var accessibilitySection: some View {
        section(title: "Доступ", icon: "keyboard", color: .purple) {
            HStack {
                Label(
                    hasAccessibilityAccess ? "Разрешен" : "Нужен доступ",
                    systemImage: hasAccessibilityAccess ? "lock.open.fill" : "lock.fill"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(hasAccessibilityAccess ? .green : .red)

                Spacer()

                if !hasAccessibilityAccess {
                    Button("Открыть") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !hasAccessibilityAccess {
                Text("Нужно для автоматической вставки Cmd+V.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var usageSection: some View {
        section(title: "Как использовать", icon: "info.circle", color: .gray) {
            Text("Курсор в поле, удерживайте Fn, говорите по-русски, отпустите Fn. Вставится выбранный язык: RUS или ENG.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .cardStyle()
    }

    private func transcriptBlock(title: String, text: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    copyToClipboard(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Копировать")
            }

            ScrollView {
                Text(text.isEmpty ? emptyText : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 44)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    func checkAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let access = AXIsProcessTrustedWithOptions(options)
        if hasAccessibilityAccess != access {
            hasAccessibilityAccess = access
        }
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}
