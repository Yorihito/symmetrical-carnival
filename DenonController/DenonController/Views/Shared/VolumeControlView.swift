import SwiftUI

struct VolumeControlView: View {
    let volumeDB: Double        // 実際の dB 値（-80 〜 +18）
    let isMuted: Bool
    let dbString: String
    let onVolumeChange: (Double) -> Void   // dB 値を渡す
    let onMuteToggle: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = -30

    private var displayDB: Double { isDragging ? dragValue : volumeDB }

    var body: some View {
        VStack(spacing: 12) {
            // dB 表示
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if isMuted {
                    Label("ミュート", systemImage: "speaker.slash.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(dbString)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: dbString)
                }
            }
            .frame(height: 44)

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
                    step: 0.5
                )
                .tint(isMuted ? .orange : .accentColor)
                .onChange(of: dragValue) { _, val in
                    onVolumeChange(val)
                }
                .onAppear { dragValue = volumeDB }
                .onChange(of: volumeDB) { _, val in
                    if !isDragging { dragValue = val }
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
                Label(
                    isMuted ? "ミュート解除" : "ミュート",
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
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
