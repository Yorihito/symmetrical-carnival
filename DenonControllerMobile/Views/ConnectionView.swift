import SwiftUI

struct ConnectionView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @AppStorage("defaultHost") private var defaultHost = ""
    @State private var ipAddress = ""

    var body: some View {
        NavigationStack {
            List {
                // 手動入力セクション
                Section {
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)
                        TextField("例: 192.168.1.100", text: $ipAddress)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { connectManual() }
                            .onChange(of: ipAddress) { _, val in defaultHost = val }
                    }

                    Button {
                        connectManual()
                    } label: {
                        HStack {
                            Spacer()
                            if vm.connectionStatus == .connecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 6)
                            }
                            Text(vm.connectionStatus.isConnected
                                 ? LocalizedStringKey("再接続")
                                 : LocalizedStringKey("接続"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                        }
                    }
                    .disabled(ipAddress.isEmpty || vm.connectionStatus == .connecting)

                    if case .error(let msg) = vm.connectionStatus {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("手動入力")
                } footer: {
                    Text("Denon / Marantz AVR の IP アドレスを入力してください。")
                }

                // mDNS 自動検索セクション
                Section {
                    if vm.discovery.isSearching {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("デバイスを検索中...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            vm.discovery.start()
                        } label: {
                            Label("ネットワークを再検索", systemImage: "magnifyingglass")
                        }
                    }

                    ForEach(vm.discovery.devices) { device in
                        Button {
                            Task {
                                defaultHost = device.host
                                ipAddress   = device.host
                                await vm.connect(host: device.host)
                                if vm.connectionStatus.isConnected {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hifispeaker.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(Color.accentColor.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(device.host.isEmpty ? "解決中..." : device.host)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(device.host.isEmpty)
                    }

                    if !vm.discovery.isSearching && vm.discovery.devices.isEmpty {
                        if !vm.discovery.scanLog.isEmpty {
                            DisclosureGroup("診断ログ") {
                                Text(vm.discovery.scanLog.joined(separator: "\n"))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } header: {
                    Text("自動検索 (Bonjour)")
                } footer: {
                    if !vm.discovery.devices.isEmpty {
                        Text("\(vm.discovery.devices.count) 台見つかりました。タップして接続します。")
                    }
                }

                // 接続状態
                if vm.connectionStatus.isConnected {
                    Section {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("接続済み")
                                    .font(.callout.weight(.semibold))
                                if !vm.avr.deviceInfo.modelName.isEmpty {
                                    Text(vm.avr.deviceInfo.modelName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("切断") { vm.disconnect() }
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("現在の接続")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(localizedNavTitle("接続設定", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                if ipAddress.isEmpty { ipAddress = defaultHost }
                vm.discovery.start()
            }
            .onDisappear {
                vm.discovery.stop()
            }
        }
    }

    private func connectManual() {
        let host = ipAddress.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        defaultHost = host
        Task {
            await vm.connect(host: host)
            if vm.connectionStatus.isConnected { dismiss() }
        }
    }
}
