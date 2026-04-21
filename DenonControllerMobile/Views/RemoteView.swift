import SwiftUI

struct RemoteView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var lBundle

    @State private var hapticTrigger = false

    private var isEnabled: Bool { vm.avr.isConnected && vm.avr.isPoweredOn }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                functionButtons
                directionPad
                backButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(localizedNavTitle("リモコン", locale: locale))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Function Buttons（情報 / オプション / 設定メニュー）

    private var functionButtons: some View {
        CardView {
            HStack(spacing: 12) {
                RemoteActionButton(
                    label: LS("情報", lBundle),
                    systemImage: "info.circle",
                    isEnabled: isEnabled
                ) { fire { vm.infoButton() } }

                RemoteActionButton(
                    label: LS("オプション", lBundle),
                    systemImage: "ellipsis.circle",
                    isEnabled: isEnabled
                ) { fire { vm.optionButton() } }

                RemoteActionButton(
                    label: LS("設定メニュー", lBundle),
                    systemImage: "gearshape",
                    isEnabled: isEnabled
                ) { fire { vm.setupMenu() } }
            }
        }
    }

    // MARK: - Direction Pad（↑↓←→ + 決定）

    private var directionPad: some View {
        CardView {
            VStack(spacing: 10) {
                // ↑
                RemoteActionButton(systemImage: "chevron.up", isEnabled: isEnabled) {
                    fire { vm.cursorUp() }
                }

                // ← 決定 →
                HStack(spacing: 10) {
                    RemoteActionButton(systemImage: "chevron.left", isEnabled: isEnabled) {
                        fire { vm.cursorLeft() }
                    }

                    RemoteActionButton(
                        label: LS("決定", lBundle),
                        systemImage: "return",
                        isEnabled: isEnabled
                    ) { fire { vm.cursorEnter() } }

                    RemoteActionButton(systemImage: "chevron.right", isEnabled: isEnabled) {
                        fire { vm.cursorRight() }
                    }
                }

                // ↓
                RemoteActionButton(systemImage: "chevron.down", isEnabled: isEnabled) {
                    fire { vm.cursorDown() }
                }
            }
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        CardView {
            RemoteActionButton(
                label: LS("戻る", lBundle),
                systemImage: "arrow.uturn.left",
                isEnabled: isEnabled
            ) { fire { vm.navBack() } }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helper

    private func fire(_ action: () -> Void) {
        action()
        hapticTrigger.toggle()
    }
}

// MARK: - RemoteActionButton

private struct RemoteActionButton: View {
    var label: String? = nil
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var hapticTrigger = false

    var body: some View {
        Button {
            action()
            hapticTrigger.toggle()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                if let label {
                    Text(label)
                        .font(.caption.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
