import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("runInMenuBar") private var runInMenuBar = false
    @AppStorage("periodicRescanEnabled") private var periodicRescan = false
    @AppStorage("periodicRescanIntervalHours") private var intervalHours = 6

    var body: some View {
        Form {
            Section {
                Toggle("Show TreeSpace in the menu bar", isOn: $runInMenuBar)
                Text("Keeps TreeSpace running with a menu bar icon even after you close the main window. Click the icon to rescan, see the latest size, or reopen the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Menu bar")
            }

            Section {
                Toggle("Periodically rescan in the background", isOn: $periodicRescan)
                Picker("Rescan every", selection: $intervalHours) {
                    Text("1 hour").tag(1)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                .disabled(!periodicRescan)
                Text("Background rescans use a low-priority schedule. macOS will defer them on battery, low power mode, or when the system is busy — the exact run time is up to the OS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Background tracking")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .onChange(of: periodicRescan) { _ in state.reconcileBackgroundScheduler() }
        .onChange(of: intervalHours) { _ in state.reconcileBackgroundScheduler() }
    }
}
