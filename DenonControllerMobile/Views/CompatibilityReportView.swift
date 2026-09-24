import SwiftUI

/// 「この機種での動作を報告する」画面。機能ごとに動いたかどうかを選んで送る。
/// 送信経路は「ご意見・ご要望」と同じ Worker で、GitHub の公開 issue になる。
/// 設計: docs/compatibility-reports-design.md 3.2
struct CompatibilityReportView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.localizedBundle) private var bundle
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case editing
        case submitting
        case posted(URL)
        case failed(String)
    }

    /// 機能ごとの答え。nil は「使っていない」（送らない）
    @State private var answers: [CompatibilityFeature: CompatibilityFeatureResult] = [:]
    @State private var overall: CompatibilityOverall = .works
    @State private var comment = ""
    @State private var phase: Phase = .editing
    @State private var didPrefill = false

    private var brand: ReceiverBrand { vm.capabilities.brand }
    private var model: String { vm.avr.deviceInfo.modelName }
    private var features: [CompatibilityFeature] { CompatibilityFeature.applicable(to: vm.capabilities) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("この内容は GitHub 上で公開されます。個人情報（メールアドレスなど）は書かないでください。", bundle: bundle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if model.isEmpty {
                    Section {
                        Text("AVR に接続すると、その機種での動作を報告できます。", bundle: bundle)
                            .foregroundStyle(.secondary)
                    }
                } else if case .posted(let url) = phase {
                    postedSections(url)
                } else {
                    editingSections
                }
            }
            .navigationTitle(Text("動作を報告", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LS("キャンセル", bundle)) { dismiss() }
                }
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Editing

    @ViewBuilder
    private var editingSections: some View {
        Section {
            LabeledContent {
                Text("\(brand.displayName) \(model)")
            } label: {
                Text("機種", bundle: bundle)
            }
            LabeledContent {
                Text(Bundle.main.appVersionString)
            } label: {
                Text("アプリ", bundle: bundle)
            }
        } footer: {
            Text("機種名は AVR から自動で取得しています。", bundle: bundle)
        }

        Section {
            Picker(selection: $overall) {
                ForEach(CompatibilityOverall.allCases) { value in
                    Text(LS(value.titleKey, bundle)).tag(value)
                }
            } label: {
                Text("全体として", bundle: bundle)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("全体として", bundle: bundle)
        } footer: {
            if overall != .works {
                Text("詳しい様子は「ご意見・ご要望を送る」からバグ報告として送ることもできます。", bundle: bundle)
            }
        }

        Section {
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LS(feature.titleKey, bundle))
                        .font(.subheadline)
                    Picker(LS(feature.titleKey, bundle), selection: answerBinding(feature)) {
                        Text("動いた", bundle: bundle).tag(Optional(CompatibilityFeatureResult.ok))
                        Text("動かない", bundle: bundle).tag(Optional(CompatibilityFeatureResult.ng))
                        Text("使っていない", bundle: bundle).tag(CompatibilityFeatureResult?.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("機能ごと", bundle: bundle)
        } footer: {
            Text("使った機能だけで大丈夫です。この接続で操作できた機能は、最初から「動いた」を選んでいます。", bundle: bundle)
        }

        Section {
            TextEditor(text: $comment)
                .frame(minHeight: 90)
        } header: {
            Text("コメント（任意）", bundle: bundle)
        }

        if case .failed(let message) = phase {
            Section {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                if let url = ProblemReporter.prefilledCompatibilityIssueURL(currentReport, comment: comment) {
                    Button {
                        openURL(url)
                        CompatibilityReportLog.markReported(brand: brand, model: model)
                        dismiss()
                    } label: {
                        Label {
                            Text("ブラウザで報告（プレフィル）", bundle: bundle)
                        } icon: {
                            Image(systemName: "safari")
                        }
                    }
                }
            } header: {
                Text("送信に失敗しました", bundle: bundle)
            }
        }

        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if phase == .submitting {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text(phase == .submitting ? LS("送信中…", bundle) : LS("送信", bundle))
                }
            }
            .disabled(phase == .submitting)
        }
    }

    // MARK: - Posted

    @ViewBuilder
    private func postedSections(_ url: URL) -> some View {
        Section {
            Label {
                Text("ご報告ありがとうございます。", bundle: bundle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)

            Link(destination: HelpSiteLinks.compatibility(locale: locale)) {
                Label {
                    Text("対応機種の一覧を見る", bundle: bundle)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            Link(destination: url) {
                Label {
                    Text("Issue を開く", bundle: bundle)
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        } footer: {
            Text("報告は 1 日 1 回ほど集計して、一覧に反映します。", bundle: bundle)
        }

        // 満足している人には、評価もお願いする（本人が押したときだけ開く。お願いの回数には数えない）
        if overall == .works {
            Section {
                Button {
                    ReviewRequestManager.markRequested()
                    openURL(AppStoreLinks.writeReview)
                } label: {
                    Label {
                        Text("App Store で評価する", bundle: bundle)
                    } icon: {
                        Image(systemName: "star.bubble")
                    }
                }
            } footer: {
                Text("よろしければ、App Store での評価もお願いします。", bundle: bundle)
            }
        }

        Section {
            Button(LS("閉じる", bundle)) { dismiss() }
        }
    }

    // MARK: - Helpers

    private func answerBinding(_ feature: CompatibilityFeature) -> Binding<CompatibilityFeatureResult?> {
        Binding(get: { answers[feature] }, set: { answers[feature] = $0 })
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        for feature in features where vm.sessionSucceededFeatures.contains(feature) {
            answers[feature] = .ok
        }
    }

    private var currentReport: CompatibilityReport {
        let info = vm.avr.deviceInfo
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return CompatibilityReport(
            brand: brand.rawValue,
            model: model,
            region: info.region.isEmpty ? nil : info.region,
            firmware: info.firmwareVersion.isEmpty ? nil : info.firmwareVersion,
            apiVersion: info.apiVersion.isEmpty ? nil : info.apiVersion,
            app: "\(version) (\(build))",
            platform: "\(device.systemName) \(device.systemVersion) / \(device.model)",
            overall: overall,
            features: Dictionary(uniqueKeysWithValues: answers.compactMap { key, value in
                features.contains(key) ? (key.rawValue, value) : nil
            })
        )
    }

    private func submit() async {
        phase = .submitting
        do {
            let url = try await ProblemReporter.submitCompatibility(currentReport, comment: comment)
            CompatibilityReportLog.markReported(brand: brand, model: model)
            DiagnosticsLog.shared.record("compat report: sent (\(overall.rawValue))")
            phase = .posted(url)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }
}
