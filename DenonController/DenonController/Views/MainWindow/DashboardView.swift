import SwiftUI

struct DashboardView: View {
    @Environment(MainViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.avr.isConnected {
                    deviceInfoBanner
                }
                powerCard
                volumeCard
                inputCard
                surroundCard
            }
            .padding()
        }
        .navigationTitle("ダッシュボード")
    }

    // MARK: - Device Info Banner

    private var deviceInfoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hifispeaker.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                if !vm.avr.deviceInfo.modelName.isEmpty {
                    Text(vm.avr.deviceInfo.modelName)
                        .font(.callout.weight(.semibold))
                    Text(vm.avr.deviceInfo.brandName + " " + vm.avr.deviceInfo.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("AV RECEIVER")
                        .font(.callout.weight(.semibold))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Power Card

    private var powerCard: some View {
        CardView {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("電源")
                        .font(.headline)
                    Text(vm.avr.isPoweredOn ? "オン" : "スタンバイ")
                        .font(.subheadline)
                        .foregroundStyle(vm.avr.isPoweredOn ? .green : .secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.avr.isPoweredOn },
                    set: { vm.setPower($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!vm.avr.isConnected)
            }
        }
    }

    // MARK: - Volume Card

    private var volumeCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("入力ソース")
                        .font(.headline)
                    Spacer()
                    Label(vm.avr.input.name(using: vm.inputNames), systemImage: vm.avr.input.systemImage)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }

                let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
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

    // MARK: - Surround Card

    private var surroundCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("サラウンドモード")
                        .font(.headline)
                    Spacer()
                    Text(vm.avr.surroundMode.displayName)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }

                let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(SurroundMode.allCases) { mode in
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
            VStack(spacing: 6) {
                Image(systemName: source.systemImage)
                    .font(.title3)
                Text(name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
            HStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.callout)
                Text(mode.displayName)
                    .font(.caption.weight(.medium))
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

// MARK: - CardView

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}
