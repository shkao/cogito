import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            Divider()

            LLMSection()

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Word Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Language")
                        .font(.callout)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $vm.translationLang) {
                        ForEach(SupportedLanguage.all, id: \.code) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Text("Select a word in the PDF to see its translation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Video Generation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Format")
                        .font(.callout)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $vm.videoFormat) {
                        ForEach(VideoFormat.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Style")
                        .font(.callout)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $vm.videoStyle) {
                        ForEach(VideoStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Divider()

            NotebookLMAuthSection()
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct LLMSection: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On-Device LLM")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("Model")
                    .font(.callout)
                    .frame(width: 60, alignment: .leading)
                Text(LLMService.configuration.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("Status")
                    .font(.callout)
                    .frame(width: 60, alignment: .leading)

                switch vm.llmState {
                case .ready:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text("Loaded")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case .downloading(let progress):
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .frame(width: 80)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                case .idle:
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        Text("Not loaded")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case .error(let msg):
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Text("Used for TOC detection, Ask Question, and mind maps.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { vm.refreshLLMState() }
    }
}

private struct NotebookLMAuthSection: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var isLoggingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NotebookLM")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                    Text("Browser opening for Google login...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if vm.notebooklmAuthError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Not authenticated")
                        .font(.callout)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready")
                        .font(.callout)
                }
            }

            Button("Login with Google") {
                vm.loginToNotebookLM()
            }
            .controlSize(.small)

            Text("Opens Terminal. A browser will launch for Google login.\nPress Enter in Terminal when done.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
