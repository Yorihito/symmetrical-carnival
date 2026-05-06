import SwiftUI

struct ZoneView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                zone2Card
                if vm.avr.deviceInfo.hasZone3 {
                    zone3Card
                }
                if !vm.avr.isConnected {
                    Text("AVR に接続するとゾーン情報が表示されます。", bundle: bundle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        
        .navigationTitle(localizedNavTitle("ゾーン制御", locale: locale))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Zone 2

    private var zone2Card: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Zone 2", systemImage: "2.square.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { vm.avr.zone2Power },
                        set: { vm.setZone2Power($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!vm.avr.isConnected)
                    #if !targetEnvironment(simulator)
                    .sensoryFeedback(.impact, trigger: vm.avr.zone2Power)
                    #endif
                }

                if vm.avr.zone2Power {
                    Divider()
                    ZoneStepControl(
                        label: vm.avr.zone2VolumeDBString,
                        isMuted: vm.avr.zone2Mute,
                        supportsMute: true,
                        isEnabled: vm.avr.isConnected,
                        onUp:        { vm.zone2VolumeUp() },
                        onDown:      { vm.zone2VolumeDown() },
                        onMute:      { vm.setZone2Mute(!vm.avr.zone2Mute) }
                    )
                } else {
                    Text("Zone 2 はオフです", bundle: bundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Zone 3

    private var zone3Card: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Zone 3", systemImage: "3.square.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { vm.avr.zone3Power },
                        set: { vm.setZone3Power($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!vm.avr.isConnected)
                    #if !targetEnvironment(simulator)
                    .sensoryFeedback(.impact, trigger: vm.avr.zone3Power)
                    #endif
                }

                if vm.avr.zone3Power {
                    Divider()
                    ZoneStepControl(
                        label: vm.avr.zone3VolumeDBString,
                        isMuted: false,
                        supportsMute: false,
                        isEnabled: vm.avr.isConnected,
                        onUp:   { vm.zone3VolumeUp() },
                        onDown: { vm.zone3VolumeDown() },
                        onMute: { }
                    )
                } else {
                    Text("Zone 3 はオフです", bundle: bundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Zone Step Control

private struct ZoneStepControl: View {
    let label: String
    let isMuted: Bool
    let supportsMute: Bool
    let isEnabled: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onMute: () -> Void

    @Environment(\.localizedBundle) private var bundle

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                Button(action: onDown) {
                    Image(systemName: "minus")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)

                VStack(spacing: 2) {
                    Text("Vol \(label)")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("音量", bundle: bundle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(minWidth: 100, minHeight: 56)
                .multilineTextAlignment(.center)

                Button(action: onUp) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }

            if supportsMute {
                Button(action: onMute) {
                    Label {
                        Text(isMuted ? "ミュート解除" : "ミュート", bundle: bundle)
                    } icon: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        isMuted ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(isMuted ? .orange : .primary)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                #if !targetEnvironment(simulator)
                .sensoryFeedback(.impact, trigger: isMuted)
                #endif
            }
        }
    }
}
