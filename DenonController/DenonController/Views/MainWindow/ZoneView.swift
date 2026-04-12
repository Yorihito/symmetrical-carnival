import SwiftUI

struct ZoneView: View {
    @Environment(MainViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                zone2Card
                zone3Card
            }
            .padding()
        }
        .navigationTitle("ゾーン制御")
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
                        volume: vm.avr.zone2Volume,
                        isMuted: vm.avr.zone2Mute,
                        dbString: vm.avr.zone2VolumeDBString,
                        onVolumeChange: { _ in },   // Zone 2 uses step only
                        onMuteToggle: { vm.setZone2Mute(!vm.avr.zone2Mute) },
                        onVolumeUp: { vm.zone2VolumeUp() },
                        onVolumeDown: { vm.zone2VolumeDown() }
                    )
                } else {
                    Text("Zone 2 はオフです")
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
                            Text("音量")
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
                    Text("Zone 3 はオフです")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
