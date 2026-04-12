import SwiftUI

struct FeynmanCardView: View {
    @EnvironmentObject var vm: PDFViewModel
    let pageIndex: Int

    @State private var localText: String = ""
    @FocusState private var isFocused: Bool

    private var cue: ConceptCue? { vm.conceptCues[pageIndex] }

    var body: some View {
        if let cue {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    stepIndicator(step: cue.step)

                    Text(cue.concept)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(cue.promptQuestion)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $localText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.2))
                        .focused($isFocused)
                        .onChange(of: isFocused) { _, focused in vm.isEditingText = focused }
                        .onChange(of: localText) { _, newValue in
                            vm.updateConceptCueExplanation(pageIndex: pageIndex, text: newValue)
                        }
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(4)
                        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 4))

                    if !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if vm.isAnalyzingGaps {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("Checking...").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                vm.analyzeGaps(for: pageIndex)
                            } label: {
                                Label("Check My Understanding", systemImage: "brain.head.profile")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                    }

                    if let gaps = cue.gapFeedback, !gaps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Think about:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)

                            ForEach(gaps, id: \.self) { gap in
                                Text(gap)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.3))
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }

                    if cue.step >= .reviewed {
                        if let model = cue.modelExplanation {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Model Answer")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text(model)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.35))
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 4))
                            }
                        } else if vm.isGeneratingModelAnswer {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("Generating...").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                vm.revealModelExplanation(for: pageIndex)
                            } label: {
                                Label("Show Model Answer", systemImage: "lightbulb")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color.white)
            .onAppear { localText = cue.userExplanation }
        }
    }

    @ViewBuilder
    private func stepIndicator(step: FeynmanStep) -> some View {
        HStack(spacing: 4) {
            ForEach(2...4, id: \.self) { s in
                Circle()
                    .fill(s <= step.rawValue ? Color.accentColor : Color(white: 0.85))
                    .frame(width: 6, height: 6)
            }
            Spacer()
            Text("Feynman")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}
