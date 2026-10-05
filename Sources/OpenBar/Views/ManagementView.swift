import SwiftUI

struct ManagementView: View {
    @Bindable var store: MenuBarStore
    let onHide: () -> Void
    let onShowAll: () -> Void
    let onOpenTray: () -> Void
    let onRefresh: () -> Void
    let onAccessibility: () -> Void
    let onScreenCapture: () -> Void
    @State private var search = ""

    private var filteredApps: [ManagedMenuApp] {
        store.apps.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "tray.full.fill").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A calmer menu bar").font(.title2.weight(.semibold))
                    Text("Choose apps to keep visible or put in your tray.").foregroundStyle(.secondary)
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
                if store.isHidden { Button("Open Tray", action: onOpenTray).disabled(store.isBusy) }
                Button(store.isHidden ? "Show All" : "Hide Selected", action: store.isHidden ? onShowAll : onHide)
                    .buttonStyle(.borderedProminent).disabled(store.isBusy || (!store.isHidden && store.hiddenCount == 0))
            }.padding(22)
            if let error = store.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.callout)
                    Spacer()
                    Button("Dismiss") { store.errorMessage = nil }.buttonStyle(.borderless)
                }.padding(.horizontal, 22).padding(.bottom, 12)
            }
            HStack {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.help("Refresh apps and menu bar items")
            }.padding(.horizontal, 22).padding(.bottom, 14)
            Divider()
            List(filteredApps) { app in
                HStack(spacing: 12) {
                    if let icon = app.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 28, height: 28) }
                    else { Image(systemName: "app.dashed").frame(width: 28, height: 28).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).fontWeight(.medium)
                        Text(app.isRunning ? app.itemCount.map { $0 == 0 ? "No menu bar item found" : "\($0) menu bar item\($0 == 1 ? "" : "s")" } ?? "Running app" : "Not running")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Visibility for \(app.name)", selection: Binding(get: { store.zone(for: app.id) }, set: { store.setZone($0, for: app.id) })) {
                        ForEach(MenuBarZone.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 128)
                }.padding(.vertical, 5)
            }.listStyle(.inset)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(store.accessibilityGranted ? "Tray controls ready" : "Open icons from the tray", systemImage: store.accessibilityGranted ? "checkmark.circle.fill" : "hand.tap")
                    Spacer()
                    Button(store.accessibilityGranted ? "Accessibility Settings" : "Enable Accessibility", action: onAccessibility)
                }
                HStack {
                    Label(store.screenCaptureGranted ? "Current icon captures enabled" : "App icons work without screen access", systemImage: store.screenCaptureGranted ? "checkmark.circle.fill" : "app.badge")
                    Spacer()
                    Button(store.screenCaptureGranted ? "Screen Capture Settings" : "Enable Live Icons", action: onScreenCapture)
                }
                Text("Hiding works without these permissions. On macOS 27, all menu bar icons from an app move together. Hidden Only apps stay out of the tray. Move the pointer into the menu bar to temporarily show everything.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.callout).padding(22)
        }.frame(minWidth: 600, minHeight: 560)
    }
}
