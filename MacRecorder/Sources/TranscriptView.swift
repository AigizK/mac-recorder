import SwiftUI

struct TranscriptView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack(spacing: 8) {
                    if appState.isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if appState.isTranscribing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Circle()
                            .fill(.gray)
                            .frame(width: 8, height: 8)
                        Text("Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Button("Clear") {
                    appState.segments = []
                    appState.fullText = ""
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Transcript
            if filteredSegments.isEmpty {
                ContentUnavailableView {
                    Label("No Transcript", systemImage: "text.bubble")
                } description: {
                    if appState.isRecording {
                        Text("Recording in progress. Transcript will appear after you stop.")
                    } else if appState.isTranscribing {
                        Text("Transcribing audio...")
                    } else {
                        Text("Start recording to capture audio, then transcribe.")
                    }
                }
            } else {
                List(filteredSegments) { segment in
                    SegmentRow(segment: segment)
                        .id(segment.id)
                }
                .listStyle(.plain)
            }

            // Status bar
            HStack {
                Text("\(appState.segments.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .navigationTitle("Transcript")
    }

    private var filteredSegments: [TranscriptSegment] {
        if searchText.isEmpty {
            return appState.segments
        }
        return appState.segments.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing) {
                Text(segment.formattedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(segment.language.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(languageColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(languageColor)

                if let source = segment.source {
                    Text(source)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120)

            Text(segment.text)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var languageColor: Color {
        switch segment.language {
        case "ru": return .blue
        case "en": return .green
        default: return .gray
        }
    }
}
