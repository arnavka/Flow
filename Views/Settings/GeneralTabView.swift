import SwiftUI

struct GeneralTabView: View {
    @AppStorage("startAtLogin")
    private var startAtLogin = false

    @AppStorage("closeToMenubar")
    private var closeToMenubar = true
    
    @AppStorage("hideDuplicateTracks")
    private var hideDuplicateTracks: Bool = true

    @AppStorage("autoScanInterval")
    private var autoScanInterval: AutoScanInterval = .every60Minutes

    @AppStorage("colorMode")
    private var colorMode: ColorMode = .auto

    @AppStorage("showFoldersTab")
    private var showFoldersTab = false

    @AppStorage("fullScreenPlayerBackground")
    private var fullScreenPlayerBackground: FullScreenBackgroundMode = .artworkBlur

    enum ColorMode: String, CaseIterable, TabbedItem {
        case light = "Light"
        case dark = "Dark"
        case auto = "Auto"

        var displayName: String {
            self.rawValue
        }

        var icon: String {
            switch self {
            case .light:
                return "sun.max.fill"
            case .dark:
                return "moon.fill"
            case .auto:
                return "circle.lefthalf.filled"
            }
        }

        var title: String { self.displayName }
    }

    enum FullScreenBackgroundMode: String, CaseIterable, TabbedItem {
        case artworkBlur = "Artwork with Blur"
        case solidBlack = "Solid Black"

        var displayName: String {
            self.rawValue
        }

        var icon: String {
            switch self {
            case .artworkBlur:
                return "photo.fill"
            case .solidBlack:
                return "rectangle.fill"
            }
        }

        var title: String { self.displayName }
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .help("Starts app on login")
                Toggle("Keep running in menubar on close", isOn: $closeToMenubar)
                    .help("Keeps the app running in the menubar even after closing")
                Toggle("Hide duplicate songs (requires app relaunch)", isOn: $hideDuplicateTracks)
                    .help("Shows only the highest quality version when multiple copies exist")
                    .onChange(of: hideDuplicateTracks) {
                        // Force UserDefaults to write immediately to prevent out of sync
                        Logger.info("Hide duplicate songs setting changed to \(hideDuplicateTracks), synchronizing UserDefaults, this will require a relaunch")
                        UserDefaults.standard.synchronize()
                    }
            }

            Section("Appearance") {
                HStack {
                    Text("Color mode")
                    Spacer()
                    TabbedButtons(
                        items: ColorMode.allCases,
                        selection: $colorMode,
                        style: .flexible
                    )
                    .frame(width: 200)
                }

                HStack {
                    Text("Full-screen player background")
                    Spacer()
                    TabbedButtons(
                        items: FullScreenBackgroundMode.allCases,
                        selection: $fullScreenPlayerBackground,
                        style: .flexible
                    )
                    .frame(width: 250)
                }
                .help("Choose the background style for the full-screen player view")

                Toggle("Show folders tab in main window", isOn: $showFoldersTab)
                    .help("Shows Folders tab within the main window to browse music directly from added folders")
            }

            Section("Library Scanning") {
                HStack {
                    Picker("Auto-scan library every", selection: $autoScanInterval) {
                        ForEach(AutoScanInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .help("Automatically scan for new music in the library on selected interval")
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding()
        .onChange(of: colorMode) { _, newValue in
            updateAppearance(newValue)
        }
        .onAppear {
            // Apply the saved color mode when the view appears
            updateAppearance(colorMode)
        }
    }

    private func updateAppearance(_ mode: ColorMode) {
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .auto:
            NSApp.appearance = nil
        }
    }
}

#Preview {
    GeneralTabView()
        .frame(width: 600, height: 500)
}
