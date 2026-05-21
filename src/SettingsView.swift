import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var downloader: ModelDownloader
    @State private var hasAccessibilityAccess: Bool = false
    
    // Timer to poll for Accessibility permissions while window is active
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with Gradient
            VStack(spacing: 8) {
                Text("Izi Input")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Голосовой ввод и перевод на английский с помощью Fn")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            
            Divider()
            
            // Section 1: Model Status
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.title3)
                        .foregroundColor(.blue)
                    Text("ИИ Модель (Whisper)")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Размер модели:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $downloader.selectedModel) {
                            ForEach(WhisperModel.allCases) { model in
                                Text(model.rawValue).tag(model)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 180)
                        .disabled(downloader.isDownloading)
                    }
                    
                    Divider()
                    
                    Text(downloader.status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if downloader.isDownloading {
                        ProgressView(value: downloader.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .accentColor(.purple)
                            .padding(.vertical, 4)
                        
                        Button(action: {
                            downloader.cancelDownload()
                        }) {
                            Text("Отменить скачивание")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else if !downloader.isModelDownloaded {
                        Button(action: {
                            downloader.startDownload()
                        }) {
                            Text("Скачать выбранную модель")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack {
                            Label("Готова к использованию", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Button(action: {
                                downloader.startDownload()
                            }) {
                                Text("Перекачать")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            
            // Section 2: Accessibility Access
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.title3)
                        .foregroundColor(.purple)
                    Text("Права универсального доступа")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if hasAccessibilityAccess {
                        HStack {
                            Label("Доступ разрешен", systemImage: "lock.open.fill")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        Text("Приложение может автоматически вставлять переведенный текст в любое поле ввода.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Label("Доступ ограничен", systemImage: "lock.fill")
                                .foregroundColor(.red)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text("Для автоматической печати (эмуляции вставки Cmd+V) требуются системные разрешения.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            openAccessibilitySettings()
                        }) {
                            Text("Выдать права в настройках macOS")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            
            // Section 3: Usage Instructions
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text("Как использовать")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Поставьте курсор в любое текстовое поле.")
                    Text("2. **Зажмите и удерживайте** клавишу **Fn** (или клавишу с Глобусом).")
                    Text("3. Диктуйте текст на **русском языке**.")
                    Text("4. **Отпустите** клавишу **Fn**.")
                    Text("5. Приложение обработает аудио и вставит перевод на **английском**.")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .padding()
        .frame(width: 480, height: 580)
        .onAppear {
            checkAccessibilityAccess()
        }
        .onReceive(timer) { _ in
            checkAccessibilityAccess()
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
}
