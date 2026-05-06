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
            }
            .padding()
        }
        .navigationTitle(LS("ゾーン制御", bundle))
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
                }

                if vm.avr.zone2Power {
                    Divider()
                    VolumeControlView(
                        volumeDB: vm.avr.zone2VolumeDB,
                        isMuted: vm.avr.zone2Mute,
                        dbString: vm.avr.zone2VolumeDBString,
                        dbLabel: vm.avr.zone2VolumeDB.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f dB", vm.avr.zone2VolumeDB)
                            : String(format: "%.1f dB", vm.avr.zone2VolumeDB),
                        onVolumeChange: { _ in },   // Zone 2 はステップ制御のみ
                        onMuteToggle: { vm.setZone2Mute(!vm.avr.zone2Mute) },
                        onVolumeUp: { vm.zone2VolumeUp() },
                        onVolumeDown: { vm.zone2VolumeDown() }
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
                }

                if vm.avr.zone3Power {
                    Divider()
                    HStack(spacing: 16) {
                        Button { vm.zone3VolumeDown() } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 2) {
                            Text("音量", bundle: bundle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(vm.avr.zone2VolumeDBString)
                                .font(.title3.weight(.semibold))
                        }
                        .frame(minWidth: 80)

                        Button { vm.zone3VolumeUp() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Zone 3 はオフです", bundle: bundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
