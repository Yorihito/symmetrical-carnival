import SwiftUI

struct ConnectionView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localizedBundle) private var bundle

    @AppStorage("defaultHost") private var defaultHost = ""
    @AppStorage("debugMode") private var debugMode = false
    @State private var ipAddress = ""
    @State private var isConnecting = false
    @State private var showDiscovery = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVR に接続", bundle: bundle)
                        .font(.title2.weight(.bold))
                    Text("Denon / Marantz AVR", bundle: bundle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(LS("閉じる", bundle)) { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {

                // ── 手動接続（メイン） ──────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Label(LS("IP アドレスで接続", bundle), systemImage: "network")
                        .font(.headline)

                    HStack {
                        TextField(LS("例: 192.168.1.100", bundle), text: $ipAddress)
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
                                Text("接続", bundle: bundle)
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
                        Label(LS("接続中...", bundle), systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .error(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    default:
                        EmptyView()
                    }

                    // 接続ログ表示（デバッグモード時のみ）
                    if debugMode && !vm.connectionLog.isEmpty {
                        TextEditor(text: .constant(vm.connectionLog.joined(separator: "\n")))
                            .font(.system(size: 10, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(height: 100)
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
                        Label(LS("自動検出 (Bonjour)", bundle), systemImage: "antenna.radiowaves.left.and.right")
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
            vm.discovery.start() // 自動的に開始
        }
        .onDisappear {
            vm.discovery.stop()
        }
    }

    // MARK: - Bonjour content

    @ViewBuilder
    private var discoveryContent: some View {
        if vm.discovery.devices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if vm.discovery.isSearching {
                        ProgressView().scaleEffect(0.7)
                        Text("検索中...", bundle: bundle)
                    } else {
                        Image(systemName: "questionmark.circle")
                        Text("デバイスが見つかりません", bundle: bundle)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                // 診断ログ（選択・コピー可能）
                if !vm.discovery.isSearching && !vm.discovery.scanLog.isEmpty {
                    TextEditor(text: .constant(vm.discovery.scanLog.joined(separator: "\n")))
                        .font(.system(size: 10, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(height: 130)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(vm.discovery.devices) { device in
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                            if device.host.isEmpty {
                                Text("解決中...", bundle: bundle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(device.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(LS("接続", bundle)) {
                            Task {
                                isConnecting = true
                                defer { isConnecting = false }
                                await vm.connect(host: device.host, port: device.port)
                                if vm.connectionStatus.isConnected { dismiss() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(device.host.isEmpty)
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
