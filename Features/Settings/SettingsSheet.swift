import SwiftUI

// Settings — our own layout (not a stock Form): appearance (the dark-mode
// control), the voice model and the flags. More settings can slot into this list later.
struct SettingsSheet: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var flagStore: FlagStore
    @State private var confirmClear = false
    @AppStorage(WhisperModel.defaultsKey) private var voiceModelRaw = WhisperModel.turbo.rawValue
    @AppStorage(MistakeSound.enabledKey) private var mistakeSound = true
    /// Bumped after removing a download, so the "Downloaded" labels refresh.
    @State private var storageVersion = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    appearanceCard
                    voiceCard
                    flagsCard
                }
                .padding(Theme.margin)
            }
        }
        .background(Theme.page.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("الإعدادات").font(.subheadline).foregroundStyle(Theme.brand)
                Text("Settings").serifDisplay(.title2).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ink.opacity(0.06)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.margin)
        .padding(.bottom, 10)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases) { mode in
                    option(mode)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // Which Whisper model listens. Each downloads once, the first time voice
    // review starts with it.
    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice model")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            ForEach(WhisperModel.allCases) { model in
                voiceOption(model)
            }
            .id(storageVersion)
            Divider().overlay(Theme.outline)
            Toggle(isOn: $mistakeSound) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound on mistakes").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text("A short tone when a word is judged wrong or skipped")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
            .tint(Theme.brand)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func voiceOption(_ model: WhisperModel) -> some View {
        let selected = voiceModelRaw == model.rawValue
        return Button {
            voiceModelRaw = model.rawValue
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.brand : Theme.ink.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(model.detail + (model.isDownloaded ? " · Downloaded" : ""))
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if model.isDownloaded {
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    model.remove()
                    storageVersion += 1
                }
            }
        }
        .accessibilityLabel("\(model.title), \(model.detail)\(model.isDownloaded ? ", downloaded" : "")\(selected ? ", selected" : "")")
    }

    // Flags gather from voice review; early testing can leave wrong ones.
    private var flagsCard: some View {
        let total = flagStore.flags.values.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Flags")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(total == 1 ? "1 word is flagged for review." : "\(total) words are flagged for review.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.7))
            Button(role: .destructive) { confirmClear = true } label: {
                Text("Clear all flags").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(total == 0)
            .confirmationDialog("Clear all \(total) flags?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear all flags", role: .destructive) { flagStore.clearAll() }
            } message: {
                Text("This removes every flag in every matn and can't be undone.")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func option(_ mode: AppearanceMode) -> some View {
        let selected = appearanceRaw == mode.rawValue
        return Button {
            appearanceRaw = mode.rawValue
        } label: {
            VStack(spacing: 7) {
                Image(systemName: mode.icon).font(.system(size: 18))
                Text(mode.label).font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(selected ? Theme.onChrome : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.brand : Theme.ink.opacity(0.05))
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(mode.label)\(selected ? ", selected" : "")")
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        SettingsSheet().environmentObject(FlagStore.inMemory())
    }
}
