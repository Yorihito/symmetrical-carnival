import SwiftUI

struct PresetView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @State private var showingAddSheet = false
    @State private var editingPreset: Preset?

    var body: some View {
        Group {
            if vm.presetStore.presets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        
        .navigationTitle(localizedNavTitle("プリセット", locale: locale))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
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

    // MARK: - Preset List

    private var presetList: some View {
        List {
            ForEach(vm.presetStore.presets) { preset in
                PresetRow(preset: preset) {
                    guard vm.avr.isConnected && vm.avr.isPoweredOn else { return }
                    vm.applyPreset(preset)
                } onEdit: {
                    editingPreset = preset
                } onDelete: {
                    vm.presetStore.delete(preset)
                }
            }
            .onMove(perform: vm.presetStore.move)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "star.slash")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            VStack(spacing: 8) {
                Text("プリセットがありません")
                    .font(.title3.weight(.semibold))
                Text("現在の設定（入力・音量・サラウンド）を\nプリセットとして保存できます")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showingAddSheet = true
            } label: {
                Text("プリセットを追加")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: Preset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(preset.emoji)
                .font(.system(size: 30))
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.body.weight(.semibold))

                HStack(spacing: 6) {
                    Label(preset.input.displayName, systemImage: preset.input.systemImage)
                    Text("·")
                    Label(String(format: "%.0f dB", preset.volumeDB),
                          systemImage: "speaker.wave.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(preset.surroundMode.displayName, systemImage: preset.surroundMode.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("適用") { onApply() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(false)
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

    @State private var name  = ""
    @State private var emoji = "⭐"

    var body: some View {
        NavigationStack {
            Form {
                Section("プリセット名") {
                    HStack(spacing: 12) {
                        TextField("絵文字", text: $emoji)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                        TextField("名前", text: $name)
                    }
                }

                Section("保存する設定") {
                    LabeledContent("入力") {
                        Label(vm.avr.input.displayName, systemImage: vm.avr.input.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("音量") {
                        Text("\(vm.avr.volumeDBString)  (\(vm.avr.volumedBLabel))")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("サラウンド") {
                        Label(vm.avr.surroundMode.displayName,
                              systemImage: vm.avr.surroundMode.systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("プリセットを保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.saveCurrentAsPreset(name: name, emoji: emoji)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Preset Sheet

private struct EditPresetSheet: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State var preset: Preset

    var body: some View {
        NavigationStack {
            Form {
                Section("プリセット名") {
                    HStack(spacing: 12) {
                        TextField("絵文字", text: $preset.emoji)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                        TextField("名前", text: $preset.name)
                    }
                }

                Section("設定（変更不可）") {
                    LabeledContent("入力") {
                        Label(preset.input.displayName, systemImage: preset.input.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("音量") {
                        Text(String(format: "%.1f dB", preset.volumeDB))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("サラウンド") {
                        Label(preset.surroundMode.displayName,
                              systemImage: preset.surroundMode.systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("プリセットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.presetStore.save(preset)
                        dismiss()
                    }
                    .disabled(preset.name.isEmpty)
                }
            }
        }
    }
}
