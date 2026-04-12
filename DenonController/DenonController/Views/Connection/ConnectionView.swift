import SwiftUI

struct ConnectionView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var ipAddress = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVR に接続")
                        .font(.title2.weight(.bold))
                    Text("AVR-X3800H")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Auto discovery
                    discoverySection

                    Divider()

                    // Manual IP
                    manualSection
                }
                .padding()
            }
        }
        .frame(width: 440, height: 420)
        .background(.windowBackground)
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("自動検出 (Bonjour)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            if vm.discovery.devices.isEmpty {
                HStack {
                    if vm.discovery.isSearching {
                        ProgressView().scaleEffect(0.7)
                        Text("ネットワークを検索中...")
                    } else {
                        Image(systemName: "questionmark.circle")
                        Text("デバイスが見つかりません")
                    }
                }
                .foregroundStyle(.secondary)
                .font(.callout)
            } else {
                ForEach(vm.discovery.devices) { device in
                    deviceRow(device)
                }
            }

            HStack {
                Button(vm.discovery.isSearching ? "検索中..." : "再検索") {
                    vm.discovery.stop()
                    vm.discovery.start()
                }
                .disabled(vm.discovery.isSearching)
                Spacer()
            }
        }
        .onAppear { vm.discovery.start() }
        .onDisappear { vm.discovery.stop() }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        HStack {
            Image(systemName: "hifispeaker.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                Text("Bonjour で発見")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("接続") {
                Task {
                    isConnecting = true
                    // Resolve service name → connect via host extracted from endpoint
                    if case .service(let name, _, _, _) = device.endpoint {
                        await vm.connect(host: name)
                    }
                    isConnecting = false
                    if vm.connectionStatus.isConnected { dismiss() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Manual

    @ViewBuilder
    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("手動接続", systemImage: "network")
                .font(.headline)

            HStack {
                TextField("IPアドレス (例: 192.168.1.100)", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { connectManual() }

                Button("接続") { connectManual() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ipAddress.isEmpty || isConnecting)
            }

            if case .error(let msg) = vm.connectionStatus {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private func connectManual() {
        guard !ipAddress.isEmpty else { return }
        Task {
            isConnecting = true
            await vm.connect(host: ipAddress)
            isConnecting = false
            if vm.connectionStatus.isConnected { dismiss() }
        }
    }
}
