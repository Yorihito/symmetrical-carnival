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
    let allowsDial: Bool

    @Environment(\.localizedBundle) private var bundle
    @AppStorage("volumeControlStyle") private var volumeControlStyle = "slider"
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

            // ボリューム操作
            HStack(spacing: 12) {
                Button(action: onVolumeDown) {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.downArrow, modifiers: .command)
                .accessibilityLabel(Text("音量を下げる", bundle: bundle))

                if allowsDial && volumeControlStyle == "dial" {
                    VolumeDialControl(
                        value: displayDB,
                        isMuted: isMuted,
                        diameter: 168
                    ) { newValue, editing in
                        dragValue = newValue
                        isDragging = editing
                        if !editing {
                            isPending = true
                            onVolumeChange(newValue)
                        }
                    }
                } else {
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
                }

                Button(action: onVolumeUp) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .accessibilityLabel(Text("音量を上げる", bundle: bundle))
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
        .onAppear { dragValue = volumeDB }
        .onChange(of: volumeDB) { _, val in
            if !isDragging {
                dragValue = val
                isPending = false   // AVR確認応答で確定
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: dragValue)
        .sensoryFeedback(.impact(weight: .light), trigger: volumeDB)
        #endif
    }
}

/// アプリアイコンのノブをモチーフにした回転式ボリュームコントロール。
/// ドラッグ中はローカル表示だけを0.5 dB刻みで更新し、終了時に確定値を1回送る。
struct VolumeDialControl: View {
    let value: Double
    let isMuted: Bool
    var diameter: CGFloat = 176
    let onEditingChanged: (Double, Bool) -> Void

    @Environment(\.localizedBundle) private var bundle
    @State private var workingValue: Double = -30
    @State private var lastTouchAngle: Double?
    @State private var angleRemainder: Double = 0
    @State private var hapticTrigger = 0

    private let minimum = -80.0
    private let maximum = 18.0
    private let step = 0.5
    private let sweep = 280.0
    private let startAngle = -140.0
    private let tickCount = 41

    private var normalizedValue: Double {
        (workingValue - minimum) / (maximum - minimum)
    }

    private var indicatorAngle: Angle {
        .degrees(startAngle + normalizedValue * sweep)
    }

    private var activeTick: Int {
        Int((normalizedValue * Double(tickCount - 1)).rounded())
    }

    private var tint: Color { isMuted ? .orange : .accentColor }

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                Capsule()
                    .fill(index <= activeTick ? tint.opacity(0.9) : Color.secondary.opacity(0.18))
                    .frame(width: 2, height: index.isMultiple(of: 5) ? 10 : 6)
                    .offset(y: -diameter * 0.47)
                    .rotationEffect(.degrees(startAngle + Double(index) * sweep / Double(tickCount - 1)))
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.gray.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.72), lineWidth: 2)
                        .padding(3)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
                .padding(diameter * 0.105)

            Circle()
                .fill(tint)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                .shadow(color: tint.opacity(0.45), radius: 4)
                .offset(y: -diameter * 0.31)
                .rotationEffect(indicatorAngle)
                .animation(.interactiveSpring(duration: 0.16), value: indicatorAngle)

            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: diameter * 0.18, weight: .medium))
                .foregroundStyle(isMuted ? Color.orange : Color.secondary.opacity(0.72))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(rotationGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("音量ダイアル", bundle: bundle))
        .accessibilityValue(Text(String(format: "%.1f dB", workingValue)))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            let adjusted = clamped(workingValue + delta)
            workingValue = adjusted
            onEditingChanged(adjusted, false)
            hapticTrigger += 1
        }
        .onAppear { workingValue = clamped(value) }
        .onChange(of: value) { _, newValue in
            if lastTouchAngle == nil {
                workingValue = clamped(newValue)
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        #endif
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let currentAngle = angle(at: gesture.location)
                guard let previousAngle = lastTouchAngle else {
                    workingValue = clamped(value)
                    lastTouchAngle = currentAngle
                    angleRemainder = 0
                    onEditingChanged(workingValue, true)
                    return
                }

                var delta = currentAngle - previousAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                lastTouchAngle = currentAngle
                angleRemainder += delta

                // 約5度の回転を0.5 dBとして扱い、細かく確かなクリック感を作る。
                let radiansPerStep = Double.pi / 36
                while abs(angleRemainder) >= radiansPerStep {
                    let direction = angleRemainder > 0 ? 1.0 : -1.0
                    let adjusted = clamped(workingValue + direction * step)
                    angleRemainder -= direction * radiansPerStep
                    guard adjusted != workingValue else { continue }
                    workingValue = adjusted
                    onEditingChanged(adjusted, true)
                    hapticTrigger += 1
                }
            }
            .onEnded { _ in
                lastTouchAngle = nil
                angleRemainder = 0
                onEditingChanged(workingValue, false)
            }
    }

    private func angle(at location: CGPoint) -> Double {
        atan2(Double(location.y - diameter / 2), Double(location.x - diameter / 2))
    }

    private func clamped(_ rawValue: Double) -> Double {
        let rounded = (rawValue / step).rounded() * step
        return min(maximum, max(minimum, rounded))
    }
}
