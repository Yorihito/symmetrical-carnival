import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @State private var showingConnectionSheet = false
    @State private var isDraggingVolume = false
    @State private var isPendingVolume = false   // ドラッグ終了〜AVR確認応答まで
    @State private var dragVolumeValue: Double = -60.0

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            volumeSection
            Divider()
            quickInputSection
            if vm.avr.input == .tuner && vm.avr.isConnected && vm.avr.isPoweredOn {
                Divider()
                tunerQuickSection
            }
            Divider()
            footerSection
        }
        .frame(width: 300)
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionView()
                .environment(vm)
                .environment(\.locale, locale)
        }
        .onAppear {
            // menuBarOnly モードでは ContentView が自動接続をスキップするため、ここで行う
            guard UserDefaults.standard.bool(forKey: "menuBarOnly") else { return }
            guard UserDefaults.standard.bool(forKey: "autoConnect") else { return }
            guard !vm.connectionStatus.isConnected else { return }
            // 保存ホストで接続を試み、失敗時は MDNS フォールバック
            Task { await vm.connectAutomatic() }
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
                        Text((isDraggingVolume || isPendingVolume) ? menuBarVolumeString(dragVolumeValue) : vm.avr.volumeDBString)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(vm.avr.isMuted ? Color.orange : Color.primary)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.15), value: isDraggingVolume ? dragVolumeValue : vm.avr.volumeDB)
            }

            HStack(spacing: 10) {
                Button { vm.volumeDown() } label: {
                    Image(systemName: "speaker.minus.fill")
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { (isDraggingVolume || isPendingVolume) ? dragVolumeValue : vm.avr.volumeDB },
                        set: { newVal in
                            dragVolumeValue = newVal
                            isDraggingVolume = true
                        }
                    ),
                    in: -80...18, step: 0.5,
                    onEditingChanged: { editing in
                        if !editing {
                            isDraggingVolume = false
                            isPendingVolume = true   // AVR確認応答まで現在値を保持
                            vm.setVolume(dragVolumeValue)
                        }
                    }
                )
                .tint(vm.avr.isMuted ? .orange : .accentColor)
                .onAppear { dragVolumeValue = vm.avr.volumeDB }
                .onChange(of: vm.avr.volumeDB) { _, val in
                    if !isDraggingVolume {
                        dragVolumeValue = val
                        isPendingVolume = false   // AVR確認応答で確定
                    }
                }

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
                let delegate = AppDelegate.shared
                delegate?.didSuppressInitialWindow = true
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                if let win = delegate?.mainWindow {
                    win.alphaValue = 1
                    win.ignoresMouseEvents = false
                    win.collectionBehavior = [.moveToActiveSpace]
                    win.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            } label: {
                Label("詳細を開く", systemImage: "arrow.up.forward.app")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - Tuner Quick Section

    private var tunerQuickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー: ラベル + 現在の周波数/局名
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("チューナー")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if !vm.avr.tunerStationName.isEmpty {
                        Text(vm.avr.tunerStationName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    } else if !vm.avr.tunerFrequency.isEmpty {
                        Text("\(vm.avr.tunerFrequency) \(vm.avr.tunerBand.freqUnit)")
                            .font(.caption.weight(.medium))
                    }
                }
            }

            // プリセット切替ボタン
            HStack(spacing: 6) {
                Button { vm.tunerPresetDown() } label: {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // 中央: プリセット番号 + 周波数（局名がない場合）
                VStack(spacing: 1) {
                    Text(vm.avr.tunerPreset > 0
                         ? String(format: "P%02d", vm.avr.tunerPreset)
                         : "--")
                        .font(.callout.weight(.semibold).monospacedDigit())
                    if vm.avr.tunerStationName.isEmpty && !vm.avr.tunerFrequency.isEmpty {
                        Text("\(vm.avr.tunerFrequency) \(vm.avr.tunerBand.freqUnit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !vm.avr.tunerStationName.isEmpty {
                        Text(vm.avr.tunerStationName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)

                Button { vm.tunerPresetUp() } label: {
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func menuBarVolumeString(_ db: Double) -> String {
        String(format: "%.1f", db + 80.0)
    }

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:    .green
        case .connecting:   .orange
        case .disconnected, .error: .red
        }
    }
}
