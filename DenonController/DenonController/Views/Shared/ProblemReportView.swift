import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// バグ報告・機能リクエストを GitHub Issue として送信するための画面（macOS/iOS 共通）。
///
/// 送信は `ProblemReporter` 経由でレポートプロキシ（`server/`）に POST する。プロキシが
/// 未設定・到達不能な場合は、GitHub の「Issue を作成」画面を事前入力状態で開くか、
/// クリップボードにコピーするフォールバックへ切り替える。
struct ProblemReportView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.localizedBundle) private var bundle
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case editing
        case submitting
        case posted(URL)
        case failed(String)
    }

    @State private var category: ProblemReportCategory = .bug
    @State private var title: String = ""
    @State private var reportBody: String = ""
    @State private var includeDiagnostics = true
    @State private var phase: Phase = .editing
    @State private var copied = false

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

                switch phase {
                case .posted(let url):
                    postedSection(url)
                default:
                    editingSections
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
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 620)
        #endif
        .onAppear {
            if title.isEmpty && reportBody.isEmpty { buildReport() }
        }
        .onChange(of: category) { _, _ in buildReport() }
        .onChange(of: includeDiagnostics) { _, _ in buildReport() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var editingSections: some View {
        Section {
            Picker(selection: $category) {
                Text("バグ報告", bundle: bundle).tag(ProblemReportCategory.bug)
                Text("機能リクエスト", bundle: bundle).tag(ProblemReportCategory.feature)
                Text("その他", bundle: bundle).tag(ProblemReportCategory.other)
            } label: {
                Text("種類", bundle: bundle)
            }
        } header: {
            Text("種類", bundle: bundle)
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

        if case .failed(let message) = phase {
            Section {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                fallbackButtons
            } header: {
                Text("送信に失敗しました", bundle: bundle)
            } footer: {
                Text("送信先に接続できない場合は、ブラウザで報告するかコピーしてください。", bundle: bundle)
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
                    Text(phase == .submitting ? LS("送信中…", bundle) : LS("GitHub で送信", bundle))
                }
            }
            .disabled(phase == .submitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func postedSection(_ url: URL) -> some View {
        Section {
            Label {
                Text("送信しました", bundle: bundle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)

            Link(destination: url) {
                Label {
                    Text("Issue を開く", bundle: bundle)
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        } footer: {
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Button(LS("閉じる", bundle)) { dismiss() }
        }
    }

    @ViewBuilder
    private var fallbackButtons: some View {
        if let prefilled = ProblemReporter.prefilledIssueURL(currentReport) {
            Button {
                openURL(prefilled)
                dismiss()
            } label: {
                Label {
                    Text("ブラウザで報告（プレフィル）", bundle: bundle)
                } icon: {
                    Image(systemName: "safari")
                }
            }
        }
        Button {
            copyToClipboard()
        } label: {
            Label {
                Text(copied ? "コピーしました" : "クリップボードにコピー", bundle: bundle)
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
    }

    // MARK: - Report building

    private var currentReport: ProblemReporter.Report {
        ProblemReporter.Report(category: category, title: title, body: reportBody)
    }

    private func buildReport() {
        let context = ProblemReporter.currentContext(
            connectedModel: vm.avr.deviceInfo.modelName,
            lastError: vm.errorMessage,
            includeLogs: includeDiagnostics
        )
        let report = ProblemReporter.makeReport(category: category, context: context)
        title = report.title
        reportBody = report.body
    }

    // MARK: - Actions

    private func submit() async {
        phase = .submitting
        do {
            let url = try await ProblemReporter.submit(currentReport)
            phase = .posted(url)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }

    private func copyToClipboard() {
        let text = "\(title)\n\n\(reportBody)"
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
    }
}
