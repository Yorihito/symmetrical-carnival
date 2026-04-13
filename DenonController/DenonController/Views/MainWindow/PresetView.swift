import SwiftUI

struct PresetView: View {
    @Environment(MainViewModel.self) private var vm
    @State private var showingAddSheet = false
    @State private var editingPreset: Preset?

    var body: some View {
        VStack(spacing: 0) {
            if vm.presetStore.presets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        .navigationTitle("プリセット")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPresetSheet()
        }
        .sheet(item: $editingPreset) { preset in
            EditPresetSheet(preset: preset)
        }
    }

    private var presetList: some View {
        List {
            ForEach(vm.presetStore.presets) { preset in
                PresetRow(preset: preset) {
                    if vm.avr.isConnected && vm.avr.isPoweredOn {
                        vm.applyPreset(preset)
                    }
                } onEdit: {
                    editingPreset = preset
                } onDelete: {
                    vm.presetStore.delete(preset)
                }
            }
            .onMove(perform: vm.presetStore.move)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("プリセットがありません")
                .font(.title3.weight(.medium))
            Text("現在の設定（入力・音量・サラウンド）を\nプリセットとして保存できます")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("プリセットを追加") { showingAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: Preset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(preset.emoji)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.body.weight(.semibold))
                HStack(spacing: 8) {
                    Label(preset.input.displayName, systemImage: preset.input.systemImage)
                    Text("·")
                    Label(preset.surroundMode.displayName, systemImage: preset.surroundMode.systemImage)
                    Text("·")
                    Label(String(format: "%.0f dB", preset.volumeDB),
                          systemImage: "speaker.wave.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("適用") { onApply() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("編集", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button("適用", action: onApply)
            Button("編集", action: onEdit)
            Divider()
            Button("削除", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Add Preset Sheet

private struct AddPresetSheet: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "⭐"

    var body: some View {
        VStack(spacing: 20) {
            Text("プリセットを保存")
                .font(.title2.weight(.bold))

            HStack(spacing: 12) {
                TextField("絵文字", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)

                TextField("プリセット名", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("現在の設定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Label(vm.avr.input.displayName, systemImage: vm.avr.input.systemImage)
                    Label(vm.avr.surroundMode.displayName, systemImage: vm.avr.surroundMode.systemImage)
                    Label(vm.avr.volumeDBString, systemImage: "speaker.wave.2")
                }
                .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("キャンセル") { dismiss() }
                Spacer()
                Button("保存") {
                    vm.saveCurrentAsPreset(name: name, emoji: emoji)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Edit Preset Sheet

private struct EditPresetSheet: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State var preset: Preset

    var body: some View {
        VStack(spacing: 20) {
            Text("プリセットを編集")
                .font(.title2.weight(.bold))

            HStack(spacing: 12) {
                TextField("絵文字", text: $preset.emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)

                TextField("プリセット名", text: $preset.name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("キャンセル") { dismiss() }
                Spacer()
                Button("保存") {
                    vm.presetStore.save(preset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(preset.name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
