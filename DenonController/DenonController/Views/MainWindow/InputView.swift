import SwiftUI

struct InputView: View {
    @Environment(MainViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentInputBanner

                let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vm.inputNames.visibleSources) { source in
                        LargeInputButton(
                            source: source,
                            name: source.name(using: vm.inputNames),
                            isSelected: vm.avr.input == source,
                            isEnabled: vm.avr.isConnected && vm.avr.isPoweredOn
                        ) {
                            vm.setInput(source)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("入力ソース")
    }

    private var currentInputBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: vm.avr.input.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("現在の入力")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(vm.avr.input.name(using: vm.inputNames))
                    .font(.title3.weight(.semibold))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LargeInputButton: View {
    let source: InputSource
    let name: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 26))
                    .frame(height: 32)
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
