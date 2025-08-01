import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @AppStorage("globalViewType")
    private var globalViewType: LibraryViewType = .table
    
    @AppStorage("entityViewType")
    private var entityViewType: LibraryViewType = .grid
    
    @AppStorage("rightSidebarSplitPosition")
    private var splitPosition: Double = 200
    
    @AppStorage("showFoldersTab")
    private var showFoldersTab = false
    
    @State private var selectedTab: Sections = .home
    @State private var showingSettings = false
    @State private var settingsInitialTab: SettingsView.SettingsTab = .general
    @State private var showingQueue = false
    @State private var showingTrackDetail = false
    @State private var detailTrack: Track?
    @State private var showingFullScreenPlayer = false
    @State private var pendingLibraryFilter: LibraryFilterRequest?
    @State private var windowDelegate = WindowDelegate()
    @State private var isSettingsHovered = false
    @State private var homeShowingEntities: Bool = false

    var body: some View {
        mainView
            .frame(minWidth: 1000, minHeight: 600)
            .onAppear(perform: handleOnAppear)
            .contentViewNotificationHandlers(
                showingSettings: $showingSettings,
                selectedTab: $selectedTab,
                libraryManager: libraryManager,
                pendingLibraryFilter: $pendingLibraryFilter,
                showTrackDetail: { track in
                    detailTrack = track
                    showingTrackDetail = true
                    showingQueue = false
                }
            )
            .onChange(of: playbackManager.currentTrack?.id) { oldId, _ in
                if showingTrackDetail,
                   let detailTrack = detailTrack,
                   detailTrack.id == oldId,
                   let newTrack = playbackManager.currentTrack {
                    self.detailTrack = newTrack
                }
            }
            .onChange(of: libraryManager.globalSearchText) { _, newValue in
                if !newValue.isEmpty && selectedTab != .library {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = .library
                    }
                }
            }
            .onChange(of: showFoldersTab) { _, newValue in
                if !newValue && selectedTab == .folders {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = .home
                    }
                }
            }
            .background(WindowAccessor(windowDelegate: windowDelegate))
            .navigationTitle("")
            // Only show toolbar and settings when not in full-screen player
            .toolbar { if !showingFullScreenPlayer { toolbarContent } }
            .onChange(of: showingFullScreenPlayer) { _, isFullScreen in
                            if let window = NSApplication.shared.windows.first {
                                if isFullScreen {
                                    // Configure window for full-screen player with black bar and visible traffic lights
                                    window.titlebarAppearsTransparent = false // Make it opaque
                                    window.titleVisibility = .hidden
                                    window.backgroundColor = NSColor.black // Set background to black
                                    window.styleMask.insert(.fullSizeContentView) // Allow content to extend under title bar
                                    
                                    // Ensure window buttons are visible
                                    window.standardWindowButton(.closeButton)?.isHidden = false
                                    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                                    window.standardWindowButton(.zoomButton)?.isHidden = false
                                    
                                    // Bring traffic light buttons to front (if they exist)
                                    window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = false
                                } else {
                                    // Restore normal window appearance
                                    window.titlebarAppearsTransparent = false
                                    window.titleVisibility = .visible
                                    window.backgroundColor = NSColor.windowBackgroundColor // Restore default background
                                    window.styleMask.remove(.fullSizeContentView) // Remove full size content view
                                    
                                    // Ensure window buttons are visible
                                    window.standardWindowButton(.closeButton)?.isHidden = false
                                    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                                    window.standardWindowButton(.zoomButton)?.isHidden = false
                                }
                            }
                        }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(libraryManager)
            }
            .animation(.easeInOut(duration: 0.3), value: showingFullScreenPlayer)
                        }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(libraryManager)
            }
            .animation(.easeInOut(duration: 0.3), value: showingFullScreenPlayer)
    }

    @ViewBuilder
    @ViewBuilder
    private var mainView: some View {
        if showingFullScreenPlayer {
            FullScreenPlayerView(
                isPresented: $showingFullScreenPlayer,
                showingQueue: $showingQueue
            )
            .environmentObject(playbackManager)
            .environmentObject(playlistManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale))
        } else {
            VStack(spacing: 0) {
                // Persistent Contextual Toolbar - always present when we have music
                if !libraryManager.folders.isEmpty {
                    ContextualToolbar(
                        viewType: Binding(
                            get: {
                                if selectedTab == .home && homeShowingEntities {
                                    return entityViewType
                                }
                                return globalViewType
                            },
                            set: { newValue in
                                if selectedTab == .home && homeShowingEntities {
                                    entityViewType = newValue
                                } else {
                                    globalViewType = newValue
                                }
                            }
                        ),
                        disableTableView: selectedTab == .home && homeShowingEntities
                    )
                    .frame(height: 40)
                    Divider()
                }

                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Main content
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Side panel (queue or track detail)
                        if showingQueue {
                            PlayQueueView(showingQueue: $showingQueue)
                                .frame(width: max(geometry.size.width * 0.28, 320))
                                .frame(maxHeight: .infinity)
                                .background(Color(NSColor.controlBackgroundColor))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else if showingTrackDetail, let track = detailTrack {
                            TrackDetailView(track: track, onClose: hideTrackDetail)
                                .frame(width: max(geometry.size.width * 0.28, 320))
                                .frame(maxHeight: .infinity)
                                .background(Color(NSColor.controlBackgroundColor))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                playerControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .home:
            HomeView(isShowingEntities: $homeShowingEntities)
        case .library:
            LibraryView(
                viewType: globalViewType,
                pendingFilter: $pendingLibraryFilter
            )
        case .playlists:
            PlaylistsView(viewType: globalViewType)
        case .folders:
            FoldersView(viewType: globalViewType)
        }
    }
        }
    }

    @ViewBuilder
    private var playerControls: some View {
<<<<<<< HEAD
        if !libraryManager.folders.isEmpty && !libraryManager.tracks.isEmpty {
            PlayerView(
                showingQueue: Binding(
                    get: { showingQueue },
                    set: { newValue in
                        if newValue {
                            showingTrackDetail = false
                            detailTrack = nil
                        }
                        showingQueue = newValue
                        if let coordinator = AppCoordinator.shared {
                            coordinator.isQueueVisible = newValue
                        }
                    }
                ),
                showingFullScreenPlayer: $showingFullScreenPlayer
            )
            .frame(height: 90)
            .background(Color(NSColor.windowBackgroundColor))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: libraryManager.folders.isEmpty)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TabbedButtons(
                items: Sections.allCases.filter { $0 != .folders || showFoldersTab },
                selection: $selectedTab,
                animation: .transform,
                isDisabled: libraryManager.folders.isEmpty
            )
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(alignment: .center, spacing: 8) {
                NotificationTray()
                    .frame(width: 24, height: 24)

                settingsButton
            }
        }
    }

    private var settingsButton: some View {
        Button(action: {
            showingSettings = true
        }) {
            Image(systemName: "gear")
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .foregroundColor(isSettingsHovered ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .background(
            Circle()
                .fill(Color.gray.opacity(isSettingsHovered ? 0.1 : 0))
                .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: isSettingsHovered)
        )
        .onHover { hovering in
            isSettingsHovered = hovering
        }
        .help("Settings")
    }

    // MARK: - Event Handlers

    private func handleOnAppear() {
        if let coordinator = AppCoordinator.shared {
            showingQueue = coordinator.isQueueVisible
        }
    }

    private func handleLibraryFilter(_ notification: Notification) {
        if let filterType = notification.userInfo?["filterType"] as? LibraryFilterType,
           let filterValue = notification.userInfo?["filterValue"] as? String {
            selectedTab = .library
            pendingLibraryFilter = LibraryFilterRequest(filterType: filterType, value: filterValue)
        }
    }

    private func hideTrackDetail() {
        showingTrackDetail = false
        detailTrack = nil
    }
}

extension View {
    func contentViewNotificationHandlers(
        showingSettings: Binding<Bool>,
        selectedTab: Binding<Sections>,
        libraryManager: LibraryManager,
        pendingLibraryFilter: Binding<LibraryFilterRequest?>,
        showTrackDetail: @escaping (Track) -> Void
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .goToLibraryFilter)) { notification in
                if let filterType = notification.userInfo?["filterType"] as? LibraryFilterType,
                   let filterValue = notification.userInfo?["filterValue"] as? String {
                    withAnimation(.easeInOut(duration: AnimationDuration.standardDuration)) {
                        selectedTab.wrappedValue = .library
                        pendingLibraryFilter.wrappedValue = LibraryFilterRequest(filterType: filterType, value: filterValue)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTrackInfo"))) { notification in
                if let track = notification.userInfo?["track"] as? Track {
                    showTrackDetail(track)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
                showingSettings.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettingsAboutTab"))) { _ in
                showingSettings.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SettingsSelectTab"),
                        object: SettingsView.SettingsTab.about
                    )
                }
            }
    }
}
// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let windowDelegate: WindowDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = windowDelegate
                window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
                window.setFrameAutosaveName("MainWindow")
                WindowManager.shared.mainWindow = window
                window.title = ""
                window.isExcludedFromWindowsMenu = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Window Manager

class WindowManager {
    static let shared = WindowManager()
    weak var mainWindow: NSWindow?

    private init() {}
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            NotificationManager.shared.isActivityInProgress = true
            coordinator.libraryManager.folders = [Folder(url: URL(fileURLWithPath: "/Music"))]
            return coordinator.libraryManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playlistManager
        }())
}
