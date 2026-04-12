import SwiftUI

struct SurroundView: View {
    @Environment(MainViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentModeBanner

                let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SurroundMode.allCases) { mode in
                        SurroundModeCard(
                            mode: mode,
                            isSelected: vm.avr.surroundMode == mode,
                            isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                        ) {
                            vm.setSurroundMode(mode)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("サラウンドモード")
    }

    private var currentModeBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: vm.avr.surroundMode.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("現在のモード")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(vm.avr.surroundMode.displayName)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SurroundModeCard: View {
    let mode: SurroundMode
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(height: 28)
                Spacer()
                Text(mode.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .padding(14)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
