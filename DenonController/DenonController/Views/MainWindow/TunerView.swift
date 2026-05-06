import SwiftUI

struct TunerView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle

    @AppStorage("debugMode") private var debugMode = false
    @State private var showDiag = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
            .padding()
        }
        .navigationTitle(localizedNavTitle("チューナー", locale: locale))
    }

    // MARK: - Current State Banner

    private var currentStateBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(vm.avr.tunerBand.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())

                    if vm.avr.tunerPreset > 0 {
                        Text(String(format: "P%02d", vm.avr.tunerPreset))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if vm.avr.tunerFrequency.isEmpty {
                    Text("--")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(vm.avr.tunerFrequency) \(vm.avr.tunerBand.freqUnit)")
                        .font(.title2.weight(.semibold))
                }

                if !vm.avr.tunerStationName.isEmpty {
                    Text(vm.avr.tunerStationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            // チューナー以外の入力が選択されているときの案内
            if vm.avr.isConnected && vm.avr.isPoweredOn && vm.avr.input != .tuner {
                Text("入力: TUNER\nを選択", bundle: bundle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                Text("操作", bundle: bundle)
                    .font(.headline)

                // バンド切替
                HStack(spacing: 12) {
                    Text("バンド", bundle: bundle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    ForEach([TunerBand.fm, TunerBand.am], id: \.self) { band in
                        BandButton(
                            band: band,
                            isSelected: vm.avr.tunerBand == band,
                            isEnabled: isEnabled
                        ) {
                            vm.setTunerBand(band)
                        }
                    }
                    Spacer()
                }

                Divider()

                // プリセット操作
                HStack(spacing: 12) {
                    Text("プリセット", bundle: bundle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    StepButton(
                        systemImage: "chevron.backward",
                        label: LS("前", bundle),
                        isEnabled: isEnabled
                    ) { vm.tunerPresetDown() }

                    if vm.avr.tunerPreset > 0 {
                        Text("P\(String(format: "%02d", vm.avr.tunerPreset))")
                            .font(.headline.monospacedDigit())
                            .frame(minWidth: 44)
                    } else {
                        Text("--")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44)
                    }

                    StepButton(
                        systemImage: "chevron.forward",
                        label: LS("次", bundle),
                        isEnabled: isEnabled
                    ) { vm.tunerPresetUp() }

                    Spacer()
                }

                Divider()

                // 周波数ステップ
                HStack(spacing: 12) {
                    Text("周波数ステップ", bundle: bundle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    StepButton(
                        systemImage: "minus",
                        label: "Down",
                        isEnabled: isEnabled
                    ) { vm.tunerFreqDown() }

                    StepButton(
                        systemImage: "plus",
                        label: "Up",
                        isEnabled: isEnabled
                    ) { vm.tunerFreqUp() }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Preset Scan Card

    @State private var skipFreqText: String = ""

    private var presetScanCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
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
                        .controlSize(.small)
                    } else {
                        Button { vm.startTunerScan() } label: {
                            Text("取得", bundle: bundle)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!vm.avr.isConnected || !vm.avr.isPoweredOn)
                    }
                }

                // 除外周波数設定
                HStack(spacing: 8) {
                    Text("除外周波数:", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(LS("例: 90.0, 85.0", bundle), text: $skipFreqText)
                        .font(.caption.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
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
                        Text("スロット \(vm.tunerScanProgress) / 56 を確認中...", bundle: bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !vm.tunerAllPresets.isEmpty {
                    let total = vm.tunerAllPresets.count
                    let shown = vm.tunerPresets.count
                    Group {
                        if total == shown {
                            Text("\(shown) 件のプリセットを取得しました。", bundle: bundle)
                        } else {
                            Text("\(shown) 件を表示中（\(total - shown) 件除外）", bundle: bundle)
                        }
                    }
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

                let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.tunerPresets) { preset in
                        TunerPresetButton(
                            preset: preset,
                            isSelected: vm.avr.tunerPreset == preset.id,
                            isEnabled: isEnabled
                        ) {
                            vm.selectTunerPreset(preset.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Diag Card

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
                    .controlSize(.small)
                    .disabled(!vm.avr.isConnected || vm.isFetchingTunerDiag)
                }

                if showDiag && !vm.tunerDiagLog.isEmpty {
                    ScrollView(.vertical) {
                        Text(vm.tunerDiagLog)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 320)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Helper

    private var isEnabled: Bool {
        vm.avr.isConnected && vm.avr.isPoweredOn
    }
}

// MARK: - BandButton

private struct BandButton: View {
    let band: TunerBand
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(band.displayName)
                .font(.callout.weight(.semibold))
                .frame(width: 48)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(isSelected ? .white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - StepButton

private struct StepButton: View {
    let systemImage: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .frame(width: 36, height: 32)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(label)
    }
}

// MARK: - TunerPresetButton

private struct TunerPresetButton: View {
    let preset: TunerPreset
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(String(format: "P%02d", preset.id))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !preset.stationName.isEmpty {
                        Text(preset.displayFrequency)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(preset.band.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}
