import SwiftUI

struct TunerView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle
    @AppStorage("debugMode") private var debugMode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                currentStateBanner
                controlsCard
                presetScanCard
                if !vm.tunerPresets.isEmpty {
                    presetListCard
                }
                if debugMode {
                    diagCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        
        .navigationTitle(localizedNavTitle("チューナー", locale: locale))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Current State Banner

    private var currentStateBanner: some View {
        CardView {
            HStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(vm.avr.tunerBand.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())

                        if vm.avr.tunerPreset > 0 {
                            Text(String(format: "P%02d", vm.avr.tunerPreset))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(vm.avr.tunerFrequency.isEmpty
                         ? "--"
                         : "\(vm.avr.tunerFrequency) \(vm.avr.tunerBand.freqUnit)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()

                    if !vm.avr.tunerStationName.isEmpty {
                        Text(vm.avr.tunerStationName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if vm.avr.isConnected && vm.avr.isPoweredOn && vm.avr.input != .tuner {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("入力: TUNER\nを選択", bundle: bundle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 64)
                }
            }
        }
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        CardView {
            VStack(spacing: 20) {
                // バンド切替
                VStack(alignment: .leading, spacing: 10) {
                    Text("バンド", bundle: bundle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach([TunerBand.fm, TunerBand.am], id: \.self) { band in
                            TunerBandButton(
                                band: band,
                                isSelected: vm.avr.tunerBand == band,
                                isEnabled: isEnabled
                            ) {
                                vm.setTunerBand(band)
                            }
                        }
                        Spacer()
                    }
                }

                Divider()

                // プリセット操作
                VStack(alignment: .leading, spacing: 10) {
                    Text("プリセット", bundle: bundle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        // 前へ
                        Button {
                            vm.tunerPresetDown()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)

                        // 現在プリセット番号
                        Text(vm.avr.tunerPreset > 0
                             ? String(format: "P%02d", vm.avr.tunerPreset)
                             : "--")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .frame(minWidth: 80, minHeight: 52)
                            .multilineTextAlignment(.center)

                        // 次へ
                        Button {
                            vm.tunerPresetUp()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                    }
                }

                Divider()

                // 周波数ステップ
                VStack(alignment: .leading, spacing: 10) {
                    Text("周波数ステップ", bundle: bundle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            vm.tunerFreqDown()
                        } label: {
                            Label("Down", systemImage: "minus")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)

                        Button {
                            vm.tunerFreqUp()
                        } label: {
                            Label("Up", systemImage: "plus")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                    }
                }
            }
        }
    }

    // MARK: - Preset Scan Card

    @State private var skipFreqText: String = ""

    private var presetScanCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("プリセット取得", bundle: bundle)
                            .font(.headline)
                        Text("AVR に登録されたプリセットを一括取得します。", bundle: bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.isScanningTuner {
                        Button { vm.cancelTunerScan() } label: {
                            Text("キャンセル", bundle: bundle)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button { vm.startTunerScan() } label: {
                            Text("取得", bundle: bundle)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isEnabled)
                    }
                }

                // 除外周波数
                HStack(spacing: 8) {
                    Text("除外周波数:", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(LS("例: 90.0, 85.0", bundle), text: $skipFreqText)
                        .font(.caption.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .onSubmit { vm.setTunerSkipFrequencies(skipFreqText) }
                        .onChange(of: skipFreqText) { vm.setTunerSkipFrequencies(skipFreqText) }
                    Text("MHz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear { skipFreqText = vm.tunerSkipFrequencies }

                if vm.isScanningTuner {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(vm.tunerScanProgress), total: 56)
                        Text("スロット \(vm.tunerScanProgress) / 56 を確認中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !vm.tunerAllPresets.isEmpty {
                    let total = vm.tunerAllPresets.count
                    let shown = vm.tunerPresets.count
                    Text(total == shown
                         ? "\(shown) 件のプリセットを取得しました。"
                         : "\(shown) 件を表示中（\(total - shown) 件除外）")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Preset List Card

    private var presetListCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("プリセット一覧", bundle: bundle)
                    .font(.headline)

                ForEach(vm.tunerPresets) { preset in
                    Button {
                        vm.selectTunerPreset(preset.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "P%02d", preset.id))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(vm.avr.tunerPreset == preset.id
                                                 ? Color.accentColor : .secondary)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text("\(preset.band.displayName)  \(preset.displayFrequency)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.avr.tunerPreset == preset.id {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            vm.avr.tunerPreset == preset.id
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.4)

                    if preset.id != vm.tunerPresets.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics Card

    @State private var showDiag = false

    private var diagCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("生データ確認", bundle: bundle)
                            .font(.headline)
                        Text("チューナー XML のレスポンスを表示します", bundle: bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showDiag = true
                        vm.fetchTunerDiagnostics()
                    } label: {
                        Text(vm.isFetchingTunerDiag ? LS("取得中...", bundle) : LS("取得", bundle))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!vm.avr.isConnected || vm.isFetchingTunerDiag)
                }

                if showDiag && !vm.tunerDiagLog.isEmpty {
                    ScrollView(.vertical) {
                        Text(vm.tunerDiagLog)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 280)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Helper

    private var isEnabled: Bool {
        vm.avr.isConnected && vm.avr.isPoweredOn
    }
}

// MARK: - TunerBandButton

private struct TunerBandButton: View {
    let band: TunerBand
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(band.displayName)
                .font(.callout.weight(.semibold))
                .frame(minWidth: 64, minHeight: 40)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(isSelected ? .white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.spring(duration: 0.2), value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
