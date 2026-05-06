import SwiftUI

struct RemoteView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle

    private var isEnabled: Bool { vm.avr.isConnected && vm.avr.isPoweredOn }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                functionButtons
                directionPad
                backButton
            }
            .padding()
        }
        .navigationTitle(localizedNavTitle("リモコン", locale: locale))
    }

    // MARK: - Function Buttons（情報 / オプション / 設定メニュー）

    private var functionButtons: some View {
        CardView {
            HStack(spacing: 12) {
                RemoteButton(label: "情報",     systemImage: "info.circle", bundle: bundle)   { vm.infoButton() }
                RemoteButton(label: "オプション", systemImage: "ellipsis.circle", bundle: bundle) { vm.optionButton() }
                RemoteButton(label: "設定メニュー", systemImage: "gearshape", bundle: bundle)    { vm.setupMenu() }
            }
            .frame(maxWidth: .infinity)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
        }
    }

    // MARK: - Direction Pad（↑↓←→ + 決定）

    private var directionPad: some View {
        CardView {
            VStack(spacing: 8) {
                RemoteButton(systemImage: "chevron.up") { vm.cursorUp() }

                HStack(spacing: 8) {
                    RemoteButton(systemImage: "chevron.left")  { vm.cursorLeft() }
                    RemoteButton(label: "決定", systemImage: "return", bundle: bundle) { vm.cursorEnter() }
                    RemoteButton(systemImage: "chevron.right") { vm.cursorRight() }
                }

                RemoteButton(systemImage: "chevron.down") { vm.cursorDown() }
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        CardView {
            RemoteButton(label: "戻る", systemImage: "arrow.uturn.left", bundle: bundle) { vm.navBack() }
                .frame(maxWidth: .infinity)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

// MARK: - RemoteButton

private struct RemoteButton: View {
    let label: String?
    let systemImage: String
    let bundle: Bundle
    let action: () -> Void

    init(label: String? = nil, systemImage: String, bundle: Bundle = .main, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.bundle = bundle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                if let label {
                    Text(LocalizedStringKey(label), bundle: bundle)
                        .font(.caption2.weight(.medium))
                }
            }
            .frame(minWidth: 64, minHeight: 48)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
