import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @State private var showingConnectionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            volumeSection
            Divider()
            quickInputSection
            Divider()
            footerSection
        }
        .frame(width: 300)
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionView()
                .environment(vm)
        }
        .onAppear {
            // menuBarOnly モードでは ContentView が自動接続をスキップするため、ここで行う
            guard UserDefaults.standard.bool(forKey: "menuBarOnly") else { return }
            let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
            let auto = UserDefaults.standard.bool(forKey: "autoConnect")
            if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
                Task { await vm.connect(host: host) }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "hifispeaker.fill")
                .font(.title2)
                .foregroundStyle(vm.connectionStatus.isConnected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(vm.avr.deviceInfo.displayTitle.isEmpty
                     ? "AV RECEIVER"
                     : vm.avr.deviceInfo.displayTitle)
                    .font(.callout.weight(.semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(vm.connectionStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Power
            Button {
                vm.togglePower()
            } label: {
                Image(systemName: vm.avr.isPoweredOn ? "power.circle.fill" : "power.circle")
                    .font(.title2)
                    .foregroundStyle(vm.avr.isPoweredOn ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!vm.connectionStatus.isConnected)
        }
        .padding(12)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("音量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    if vm.avr.isMuted {
                        Text("ミュート中")
                    } else {
                        Text(vm.avr.volumeDBString)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(vm.avr.isMuted ? Color.orange : Color.primary)
            }

            HStack(spacing: 10) {
                Button { vm.volumeDown() } label: {
                    Image(systemName: "speaker.minus.fill")
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { vm.avr.volumeDB },
                        set: { vm.setVolume($0) }
                    ),
                    in: -80...18, step: 0.5
                )
                .tint(vm.avr.isMuted ? .orange : .accentColor)

                Button { vm.volumeUp() } label: {
                    Image(systemName: "speaker.plus.fill")
                }
                .buttonStyle(.plain)
            }

            Button {
                vm.toggleMute()
            } label: {
                Label(vm.avr.isMuted ? LocalizedStringKey("ミュート解除") : LocalizedStringKey("ミュート"),
                      systemImage: vm.avr.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(vm.avr.isMuted ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(vm.avr.isMuted ? .orange : .primary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .disabled(!vm.connectionStatus.isConnected || !vm.avr.isPoweredOn)
        .opacity(vm.connectionStatus.isConnected && vm.avr.isPoweredOn ? 1 : 0.4)
    }

    // MARK: - Quick Input (top 6)

    private var quickInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力切替")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 表示設定済みの入力のうち最大 6 件をメニューバーに表示
            let quickInputs = Array(vm.inputNames.visibleSources.prefix(6))
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(quickInputs) { source in
                    Button {
                        vm.setInput(source)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: source.systemImage)
                                .font(.callout)
                            Text(source.name(using: vm.inputNames))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            vm.avr.input == source
                                ? Color.accentColor.opacity(0.2)
                                : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .foregroundStyle(vm.avr.input == source ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .disabled(!vm.connectionStatus.isConnected || !vm.avr.isPoweredOn)
        .opacity(vm.connectionStatus.isConnected && vm.avr.isPoweredOn ? 1 : 0.4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                showingConnectionSheet = true
            } label: {
                Label(
                    vm.connectionStatus.isConnected ? LocalizedStringKey("接続済み") : LocalizedStringKey("接続"),
                    systemImage: "network"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    existing.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("詳細を開く", systemImage: "arrow.up.forward.app")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:    .green
        case .connecting:   .orange
        case .disconnected, .error: .red
        }
    }
}
