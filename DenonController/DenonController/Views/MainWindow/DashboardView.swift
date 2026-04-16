import SwiftUI

struct DashboardView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusBar
                volumeCard
                inputCard
                surroundCard
            }
            .padding()
        }
        .navigationTitle(localizedNavTitle("ダッシュボード", locale: locale))
    }

    // MARK: - Status Bar（電源トグル込みの1行ヘッダー）

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "hifispeaker.fill")
                .font(.callout)
                .foregroundStyle(Color.accentColor)

            Text(vm.avr.deviceInfo.modelName.isEmpty ? "AV RECEIVER" : vm.avr.deviceInfo.modelName)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            if vm.avr.isConnected && vm.avr.isPoweredOn {
                separatorDot
                Label(vm.avr.input.name(using: vm.inputNames), systemImage: vm.avr.input.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                separatorDot
                Text(vm.avr.isMuted ? "ミュート" : vm.avr.volumedBLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(vm.avr.isMuted ? .orange : .secondary)
                    .lineLimit(1)
            } else if vm.avr.isConnected {
                separatorDot
                Text("スタンバイ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { vm.avr.isPoweredOn },
                set: { vm.setPower($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(!vm.avr.isConnected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var separatorDot: some View {
        Text("•")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Volume Card

    private var volumeCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("音量")
                    .font(.headline)

                VolumeControlView(
                    volumeDB: vm.avr.volumeDB,
                    isMuted: vm.avr.isMuted,
                    dbString: vm.avr.volumeDBString,
                    dbLabel: vm.avr.volumedBLabel,
                    onVolumeChange: { vm.setVolume($0) },
                    onMuteToggle: { vm.toggleMute() },
                    onVolumeUp: { vm.volumeUp() },
                    onVolumeDown: { vm.volumeDown() }
                )
                .disabled(!vm.avr.isConnected || !vm.avr.isPoweredOn)
            }
        }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("入力ソース")
                        .font(.headline)
                    Spacer()
                    Label(vm.avr.input.name(using: vm.inputNames), systemImage: vm.avr.input.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                let columns = [GridItem(.adaptive(minimum: 75), spacing: 6)]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(vm.inputNames.visibleSources) { source in
                        InputButton(
                            source: source,
                            name: source.name(using: vm.inputNames),
                            isSelected: vm.avr.input == source,
                            isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                        ) {
                            vm.setInput(source)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Surround Card（カテゴリ別グループ）

    private var surroundCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("サラウンドモード")
                        .font(.headline)
                    Spacer()
                    Text(vm.avr.surroundMode.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                surroundGroup(label: "スマート",   modes: [.auto, .stereo])
                surroundGroup(label: "ダイレクト", modes: [.direct])
                surroundGroup(label: "コンテンツ", modes: [.movie, .music, .game])
                surroundGroup(label: "イマーシブ", modes: [.auro3D])
            }
        }
    }

    @ViewBuilder
    private func surroundGroup(label: String, modes: [SurroundMode]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)

            let columns = [GridItem(.adaptive(minimum: 96), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(modes) { mode in
                    SurroundButton(
                        mode: mode,
                        isSelected: vm.avr.surroundMode == mode,
                        isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                    ) {
                        vm.setSurroundMode(mode)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct InputButton: View {
    let source: InputSource
    let name: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: source.systemImage)
                    .font(.callout)
                Text(name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct SurroundButton: View {
    let mode: SurroundMode
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: mode.systemImage)
                    .font(.caption)
                Text(mode.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - CardView

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}
