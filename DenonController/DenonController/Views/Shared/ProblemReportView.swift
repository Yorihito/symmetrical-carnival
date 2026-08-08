import SwiftUI

/// バグ報告・機能リクエストを GitHub Issue として送信するための画面（macOS/iOS 共通）。
/// 実際の送信はブラウザで GitHub の「Issue を作成」画面を事前入力状態で開く方式（§ProblemReporter）。
struct ProblemReportView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.localizedBundle) private var bundle
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var category: ProblemReportCategory = .bug
    @State private var title: String = ""
    @State private var reportBody: String = ""
    @State private var includeDiagnostics = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $category) {
                        Text("バグ報告", bundle: bundle).tag(ProblemReportCategory.bug)
                        Text("機能リクエスト", bundle: bundle).tag(ProblemReportCategory.feature)
                        Text("その他", bundle: bundle).tag(ProblemReportCategory.other)
                    } label: {
                        Text("種類", bundle: bundle)
                    }
                    .onChange(of: category) { _, newValue in
                        reportBody = template(for: newValue)
                    }
                } header: {
                    Text("問題を報告", bundle: bundle)
                } footer: {
                    Text("バグ報告や機能のリクエストを GitHub の Issue として送信します。", bundle: bundle)
                }

                Section {
                    TextField(LS("タイトル", bundle), text: $title)
                } header: {
                    Text("タイトル", bundle: bundle)
                }

                Section {
                    TextEditor(text: $reportBody)
                        .frame(minHeight: 160)
                } header: {
                    Text("内容", bundle: bundle)
                }

                Section {
                    Toggle(isOn: $includeDiagnostics) {
                        Text("診断情報を含める", bundle: bundle)
                    }
                } footer: {
                    Text("アプリのバージョンや OS など（IP アドレスなどのネットワーク情報は含まれません）", bundle: bundle)
                        .font(.caption)
                }

                Section {
                    Text("この内容は GitHub 上で公開されます。個人情報（メールアドレスなど）は書かないでください。送信前に内容を確認・編集できます。", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("問題を報告", bundle: bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LS("キャンセル", bundle)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 560)
        #endif
        .onAppear {
            if reportBody.isEmpty { reportBody = template(for: category) }
        }
    }

    private var submitButton: some View {
        Button(LS("GitHub で送信", bundle)) {
            submit()
        }
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() {
        guard let url = ProblemReporter.issueURL(
            category: category,
            title: title,
            body: reportBody,
            includeDiagnostics: includeDiagnostics,
            connectedModel: vm.avr.deviceInfo.modelName
        ) else { return }
        openURL(url)
        dismiss()
    }

    private func template(for category: ProblemReportCategory) -> String {
        switch category {
        case .bug:
            LS("起きたこと:\n\n再現手順:\n\n期待した動作:\n", bundle)
        case .feature:
            LS("実現したいこと:\n\n背景・理由:\n", bundle)
        case .other:
            ""
        }
    }
}
