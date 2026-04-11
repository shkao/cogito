import SwiftUI

struct VideoGenerationBannerView: View {
    @EnvironmentObject var vm: PDFViewModel

    private var status: VideoStatus? { vm.videoStatus }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading icon
            ZStack {
                if status?.isDone == true {
                    Circle().fill(Color.green).frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else if status?.isAuthRequired == true || status?.isError == true {
                    Circle().fill(status?.isAuthRequired == true ? Color.orange : Color.red).frame(width: 28, height: 28)
                    Image(systemName: status?.isAuthRequired == true ? "person.crop.circle.badge.exclamationmark" : "exclamationmark")
                        .font(.system(size: status?.isAuthRequired == true ? 9 : 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 28, height: 28)
                    ProgressView().scaleEffect(0.6).tint(Color.accentColor)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                if let title = vm.videoChapterTitle {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(vm.videoStatus?.statusText ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Actions
            if case .authRequired = vm.videoStatus {
                Button {
                    vm.loginToNotebookLM()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle").font(.system(size: 10))
                        Text("Login").font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if case .done(let url) = vm.videoStatus {
                Button {
                    vm.playingVideoURL = url
                    vm.dismissVideo()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Watch")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Button {
                if vm.isGeneratingVideo {
                    vm.cancelVideoGeneration()
                } else {
                    vm.dismissVideo()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help(vm.isGeneratingVideo ? "Cancel" : "Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .frame(maxWidth: 380)
    }
}
