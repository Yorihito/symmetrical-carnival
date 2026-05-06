import SwiftUI

struct VolumeControlView: View {
    let volumeDB: Double        // 実際の dB 値（-80 〜 +18）
    let isMuted: Bool
    let dbString: String        // 表示用（Denon 単位: "30" など）
    let dbLabel: String         // 補足 dB ラベル（"-50 dB" など）
    let onVolumeChange: (Double) -> Void   // dB 値を渡す
    let onMuteToggle: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    @Environment(\.localizedBundle) private var bundle
    @State private var isDragging = false
    @State private var isPending = false   // ドラッグ終了〜AVR確認応答まで
    @State private var dragValue: Double = -30

    private var displayDB: Double { (isDragging || isPending) ? dragValue : volumeDB }

    private var displayDBString: String {
        String(format: "%.1f", displayDB + 80.0)
    }

    private var displayDBLabel: String {
        String(format: "%.1f dB", displayDB)
    }

    var body: some View {
        VStack(spacing: 12) {
            // 音量表示（dB 主表示 ＋ Denon 単位 副表示）
            Group {
                if isMuted {
                    Label {
                        Text("ミュート中", bundle: bundle)
                    } icon: {
                        Image(systemName: "speaker.slash.fill")
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                } else {
                    VStack(alignment: .center, spacing: 1) {
                        Text(displayDBLabel)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: displayDBLabel)
                        Text("Vol \(displayDBString)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: displayDBString)
                    }
                }
            }
            .frame(height: 52)

            // スライダー行
            HStack(spacing: 12) {
                Button(action: onVolumeDown) {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.downArrow, modifiers: .command)

                Slider(
                    value: Binding(
                        get: { displayDB },
                        set: { newVal in
                            dragValue = newVal
                            isDragging = true
                        }
                    ),
                    in: -80...18,
                    step: 0.5,
                    onEditingChanged: { editing in
                        if !editing {
                            isDragging = false
                            isPending = true   // AVR確認応答まで現在値を保持
                            onVolumeChange(dragValue)
                        }
                    }
                )
                .tint(isMuted ? .orange : .accentColor)
                .onAppear { dragValue = volumeDB }
                .onChange(of: volumeDB) { _, val in
                    if !isDragging {
                        dragValue = val
                        isPending = false   // AVR確認応答で確定
                    }
                }

                Button(action: onVolumeUp) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.upArrow, modifiers: .command)
            }

            // ミュートボタン
            Button(action: onMuteToggle) {
                Label {
                    Text(isMuted ? "ミュート解除" : "ミュート", bundle: bundle)
                } icon: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    isMuted ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(isMuted ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: .command)
        }
    }
}
