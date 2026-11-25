import SwiftUI
import AVFoundation

struct HomeView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var capture: CaptureViewModel?
    @State private var showSettings = false
    @State private var renaming: Project?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        Button { startNew() } label: { Label("Create HDRI", systemImage: "camera.aperture") }.buttonStyle(PrimaryButtonStyle())
                        storageCard
                        Text("Recent projects").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary).textCase(.uppercase)
                        if store.projects.isEmpty {
                            Text("No projects yet. Tap Create HDRI to capture your first panorama.").font(.callout).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(store.projects) { p in row(p) }
                    }.padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $capture, onDismiss: { store.reload() }) { vm in CaptureView(vm: vm) }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let p = renaming { store.rename(p, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HDRI Creator").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
            Text("28-position spherical capture").font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var storageCard: some View {
        HStack {
            Image(systemName: "internaldrive").foregroundStyle(Theme.accent)
            VStack(alignment: .leading) {
                Text("Storage used").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(ByteCountFormatter.string(fromByteCount: store.storageBytes, countStyle: .file)).font(.headline).foregroundStyle(.white)
            }
            Spacer()
            Text("\(store.projects.count) project\(store.projects.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.textSecondary)
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
         .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline))
    }

    private func row(_ p: Project) -> some View {
        HStack(spacing: 14) {
            thumb(p).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text("\(p.status.label) · \(p.capturedIDs.count)/28 · \(p.resolutionLabel)").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(p.created.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if p.status == .capturing { Button("Resume") { capture = CaptureViewModel(project: p, store: store) }.buttonStyle(GlassButtonStyle()) }
        }
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Rename") { newName = p.name; renaming = p }
            Button("Delete", role: .destructive) { store.delete(p) }
        }
    }

    @ViewBuilder private func thumb(_ p: Project) -> some View {
        if let img = UIImage(contentsOfFile: store.thumbURL(p).path) { Image(uiImage: img).resizable().scaledToFill() }
        else { Rectangle().fill(Theme.surfaceHigh).overlay(Image(systemName: "photo").foregroundStyle(Theme.textSecondary)) }
    }

    private func startNew() {
        do { let p = try store.create(fov: 67.4); store.reload(); capture = CaptureViewModel(project: p, store: store) }
        catch { print("create failed", error) }
    }
}

struct SettingsView: View {
    @AppStorage("autoCapture") private var autoCapture = true
    @AppStorage("aimTolerance") private var tolerance = 6.0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Toggle("Automatic capture when stable", isOn: $autoCapture)
                    VStack(alignment: .leading) {
                        Text("Aim tolerance: \(Int(tolerance))°")
                        Slider(value: $tolerance, in: 3...12, step: 1)
                    }
                }
                Section { Text("Bracket count, RAW and export resolution are added with the bracketing and export stages.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Capture settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
