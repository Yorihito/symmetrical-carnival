import SwiftUI

struct DashboardView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.localizedBundle) private var bundle
    @Binding var showConnection: Bool

    @State private var isDraggingVolume = false
    @State private var isPendingVolume  = false
    @State private var dragVolumeValue: Double = -30

    private var displayDB: Double { (isDraggingVolume || isPendingVolume) ? dragVolumeValue : vm.avr.volumeDB }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 接続状態ピル（ナビバー非表示のため直接配置）
                connectionPill
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
                Divider()
                deviceHeader
                Divider()
                volumeSection
                Divider()
                inputSection
                Divider()
                surroundSection
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - ナビゲーションバー: 接続状態ピル

    private var connectionPill: some View {
        Button { showConnection = true } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(pillLabel)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - デバイスヘッダー（電源トグル）

    private var deviceHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                if vm.avr.isConnected && vm.avr.isPoweredOn {
                    Label(vm.avr.input.name(using: vm.inputNames),
                          systemImage: vm.avr.input.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(vm.avr.surroundMode.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(vm.avr.isConnected ? "スタンバイ" : "未接続")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // 電源ボタン（大きく）
            Button {
                vm.togglePower()
            } label: {
                Image(systemName: vm.avr.isPoweredOn ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(vm.avr.isPoweredOn ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!vm.avr.isConnected)
            #if !targetEnvironment(simulator)
            .sensoryFeedback(.impact, trigger: vm.avr.isPoweredOn)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 音量セクション

    private var volumeSection: some View {
        let isOn = vm.avr.isConnected && vm.avr.isPoweredOn

        return VStack(spacing: 0) {
            // 音量数値
            ZStack {
                if vm.avr.isMuted {
                    VStack(spacing: 4) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("ミュート中")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                } else {
                    VStack(spacing: 2) {
                        VolumeDisplay(vm: vm, displayDB: displayDB)
                    }
                }
            }
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // スライダー
            VolumeSlider(
                vm: vm,
                isDragging: $isDraggingVolume,
                isPending: $isPendingVolume,
                dragValue: $dragVolumeValue
            )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .disabled(!isOn)

            // ボタン行: [−] [Mute] [+]
            HStack(spacing: 0) {
                // −
                VolumeStepButton(systemImage: "minus", label: "音量 −") {
                    vm.volumeDown()
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44)

                // Mute
                Button {
                    vm.toggleMute()
                } label: {
                    Image(systemName: vm.avr.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(vm.avr.isMuted ? .orange : .primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                #if !targetEnvironment(simulator)
                .sensoryFeedback(.impact, trigger: vm.avr.isMuted)
                #endif

                Divider().frame(height: 44)

                // +
                VolumeStepButton(systemImage: "plus", label: "音量 +") {
                    vm.volumeUp()
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.35)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 入力ソースセクション

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("入力ソース", bundle: bundle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Spacer(minLength: 10)
                    ForEach(vm.inputNames.visibleSources) { source in
                        InputChip(
                            source: source,
                            name: source.name(using: vm.inputNames),
                            isSelected: vm.avr.input == source,
                            isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                        ) {
                            vm.setInput(source)
                        }
                    }
                    Spacer(minLength: 10)
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - サラウンドモードセクション

    private var surroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("サラウンドモード", bundle: bundle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Spacer(minLength: 10)
                    ForEach(SurroundMode.selectableModes) { mode in
                        SurroundChip(
                            mode: mode,
                            isSelected: vm.avr.surroundMode == mode,
                            isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                        ) {
                            vm.setSurroundMode(mode)
                        }
                    }
                    Spacer(minLength: 10)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helper

    private var pillLabel: String {
        if vm.avr.isConnected {
            return vm.avr.deviceInfo.modelName.isEmpty ? LS("接続済み", bundle) : vm.avr.deviceInfo.modelName
        }
        switch vm.connectionStatus {
        case .disconnected: return LS("未接続", bundle)
        case .connecting:   return LS("接続中...", bundle)
        case .connected:    return LS("接続済み", bundle)
        case .error:        return LS("エラー", bundle)
        }
    }

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:            .green
        case .connecting:           .orange
        case .disconnected, .error: .red
        }
    }
}

// MARK: - Volume Display (数値表示)

private struct VolumeDisplay: View {
    let vm: MainViewModel
    let displayDB: Double
    
    var body: some View {
        Text(String(format: "%.1f", displayDB) + " dB")
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.15), value: displayDB)
        Text("Vol  \(String(format: "%.1f", displayDB + 80.0))")
            .font(.callout.weight(.medium))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
    }
}

// MARK: - Volume Slider (スライダー)

private struct VolumeSlider: View {
    let vm: MainViewModel
    @Binding var isDragging: Bool
    @Binding var isPending: Bool
    @Binding var dragValue: Double

    private var displayDB: Double { (isDragging || isPending) ? dragValue : vm.avr.volumeDB }

    var body: some View {
        Slider(
            value: Binding(
                get: { displayDB },
                set: { v in dragValue = v; isDragging = true }
            ),
            in: -80...18,
            step: 0.5,
            onEditingChanged: { editing in
                if !editing {
                    isDragging = false
                    isPending  = true
                    vm.setVolume(dragValue)
                }
            }
        )
        .tint(vm.avr.isMuted ? .orange : .accentColor)
        .onAppear { dragValue = vm.avr.volumeDB }
        .onChange(of: vm.avr.volumeDB) { _, v in
            if !isDragging { dragValue = v; isPending = false }
        }
    }
}

// MARK: - Volume Step Button

private struct VolumeStepButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Input Chip

private struct InputChip: View {
    let source: InputSource
    let name: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: 68, height: 64)
            .background(
                isSelected ? Color.accentColor : Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        #if !targetEnvironment(simulator)
        .sensoryFeedback(.selection, trigger: isSelected)
        #endif
    }
}

// MARK: - Surround Chip

private struct SurroundChip: View {
    let mode: SurroundMode
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(mode.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.accentColor : Color(.tertiarySystemBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        #if !targetEnvironment(simulator)
        .sensoryFeedback(.selection, trigger: isSelected)
        #endif
    }
}
