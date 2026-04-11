import SwiftUI

struct NotebookLMSettingsView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var isLoggingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NotebookLM")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Authentication")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if isLoggingIn {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Video Generation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Format")
                        .font(.callout)
                        .frame(width: 50, alignment: .leading)
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
                        .frame(width: 50, alignment: .leading)
                    Picker("", selection: $vm.videoStyle) {
                        ForEach(VideoStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Text("Applies to the next generated video.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
