import SwiftUI

struct ConnectionView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultHost") private var defaultHost = ""

    @State private var ipAddress = ""
    @State private var isConnecting = false
    @State private var showDiscovery = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVR に接続")
                        .font(.title2.weight(.bold))
                    Text("AVR-X3800H  —  HTTP API (ポート 8080)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {

                // ── 手動接続（メイン） ──────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Label("IP アドレスで接続", systemImage: "network")
                        .font(.headline)

                    HStack {
                        TextField("例: 192.168.1.100", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { connectManual() }
                            .onChange(of: ipAddress) { _, val in
                                defaultHost = val
                            }

                        Button(action: connectManual) {
                            if isConnecting {
                                ProgressView().scaleEffect(0.75)
                                    .frame(width: 60)
                            } else {
                                Text("接続")
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ipAddress.isEmpty || isConnecting)
                        .keyboardShortcut(.return)
                    }

                    // ステータス表示
                    switch vm.connectionStatus {
                    case .connecting:
                        Label("接続中...", systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .error(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    default:
                        EmptyView()
                    }
                }

                Divider()

                // ── Bonjour（折りたたみ） ───────────────────────────────
                DisclosureGroup(
                    isExpanded: $showDiscovery,
                    content: {
                        discoveryContent
                            .padding(.top, 8)
                    },
                    label: {
                        Label("自動検出 (Bonjour)", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                )
                .onChange(of: showDiscovery) { _, expanded in
                    if expanded { vm.discovery.start() } else { vm.discovery.stop() }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 420, height: 340)
        .background(.windowBackground)
        .onAppear {
            if ipAddress.isEmpty { ipAddress = defaultHost }
        }
        .onDisappear {
            vm.discovery.stop()
        }
    }

    // MARK: - Bonjour content

    @ViewBuilder
    private var discoveryContent: some View {
        if vm.discovery.devices.isEmpty {
            HStack(spacing: 8) {
                if vm.discovery.isSearching {
                    ProgressView().scaleEffect(0.7)
                    Text("検索中...")
                } else {
                    Image(systemName: "questionmark.circle")
                    Text("デバイスが見つかりません")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(vm.discovery.devices) { device in
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(device.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button("接続") {
                            Task {
                                isConnecting = true
                                if case .service(let name, _, _, _) = device.endpoint {
                                    await vm.connect(host: name)
                                }
                                isConnecting = false
                                if vm.connectionStatus.isConnected { dismiss() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Connect

    private func connectManual() {
        guard !ipAddress.isEmpty, !isConnecting else { return }
        Task {
            isConnecting = true
            await vm.connect(host: ipAddress)
            isConnecting = false
            if vm.connectionStatus.isConnected { dismiss() }
        }
    }
}
