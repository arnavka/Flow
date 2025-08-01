import SwiftUI
import Foundation

enum FullScreenBackgroundMode: String, CaseIterable {
    case artworkBlur = "Artwork with Blur"
    case solidBlack = "Solid Black"
}

struct FullScreenPlayerView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isPresented: Bool
    @Binding var showingQueue: Bool
    
    @Environment(\.scenePhase)
    var scenePhase

    @State private var isDraggingProgress = false
    @State private var tempProgressValue: Double = 0
    @State private var hoveredOverProgress = false
    @State private var playButtonPressed = false
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.7
    
    // UI Timer state
    @State private var displayTime: Double = 0
    @State private var uiTimer: Timer?
    @State private var playbackStartTime: Date?
    @State private var playbackStartOffset: Double = 0
    
    // Lyrics state
    @StateObject private var lyricsManager = LyricsManager()
    @State private var currentLyricID: UUID?
    @State private var noLyricsFallbackMessage: String = ""
    @State private var showFullLyrics: Bool = false
    
    // Background setting
    @AppStorage("fullScreenPlayerBackground")
    private var backgroundMode: FullScreenBackgroundMode = .artworkBlur
    @State private var showingLyricsSearchModal: Bool = false
    
    var body: some View {
            ZStack(alignment: .topLeading) {
                // Main content
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Main player content
                        VStack(spacing: 0) {
                            // Top section with title and artist
                            topSection
                                .frame(maxHeight: 120)
                            
                            Spacer()
                            
                            // Artwork section
                            if !showFullLyrics {
                                artworkSection
                                    .frame(maxHeight: 300)
                                
                                Spacer()
                                
                                // Extra space to move lyrics down
                                Spacer()
                                    .frame(height: 40)
                            }
                            
                            // Lyrics section
                            lyricsSection
                                .frame(maxHeight: showFullLyrics ? .infinity : 120)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showFullLyrics.toggle()
                                    }
                                }
                            
                            // Controls section
                            controlsSection
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Queue side panel
                        if showingQueue {
                            PlayQueueView(showingQueue: $showingQueue)
                                .frame(width: max(geometry.size.width * 0.28, 320))
                                .frame(maxHeight: .infinity)
                                .background(Color(NSColor.controlBackgroundColor))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FullScreenBackgroundView(mode: backgroundMode, track: playbackManager.currentTrack))
            }
            .animation(.easeInOut(duration: 0.3), value: showingQueue)
        .onAppear {
            setupInitialState()
            syncDisplayTime()
            // Load lyrics for current track when view appears
            if let track = playbackManager.currentTrack {
                lyricsManager.loadLyrics(for: track)
                // Generate a new fallback message when a new track loads
                noLyricsFallbackMessage = Self.noLyricsMessages.randomElement() ?? "No lyrics available."
            }
        }
        .onChange(of: playbackManager.isPlaying) { _, isPlaying in
            if isPlaying && scenePhase == .active {
                startUITimer()
            } else {
                stopUITimer()
            }
        }
        .onChange(of: playbackManager.currentTrack) { _, _ in
            syncDisplayTime()
            if let track = playbackManager.currentTrack {
                lyricsManager.loadLyrics(for: track)
                // Generate a new fallback message when a new track loads
                noLyricsFallbackMessage = Self.noLyricsMessages.randomElement() ?? "No lyrics available."
            }
            if playbackManager.isPlaying && scenePhase == .active {
                startUITimer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayerDidSeek"))) { notification in
            if let time = notification.userInfo?["time"] as? Double {
                displayTime = time
                playbackStartTime = Date()
                playbackStartOffset = time
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if playbackManager.isPlaying {
                    syncDisplayTime()
                    startUITimer()
                }
            case .inactive, .background:
                stopUITimer()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        VStack(spacing: 8) {
            // Close button
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(scale: 1.1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            
            // Title and Artist (moved up much more)
            VStack(spacing: 4) {
                if let track = playbackManager.currentTrack {
                    Text(track.title.isEmpty ? "Unknown Title" : track.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !showFullLyrics {
                        Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            
            Spacer()
        }
    }
    
    // MARK: - Artwork Section
    
    private var artworkSection: some View {
        VStack {
            let trackArtworkInfo = playbackManager.currentTrack.map { track in
                TrackArtworkInfo(id: track.id, artworkData: track.artworkData)
            }
            
            FullScreenAlbumArtView(trackInfo: trackArtworkInfo)
                .contextMenu {
                    TrackContextMenuContent(items: currentTrackContextMenuItems)
                }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Lyrics Section
    
    private var lyricsSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if let lyrics = lyricsManager.currentLyrics, !lyrics.isEmpty {
                        ForEach(lyrics.lines) { line in
                            let isCurrentLine = line.isCurrentLine(at: displayTime)
                            Text(line.text)
                                .id(line.id) // Assign ID for ScrollViewReader
                                .font(.system(
                                    size: isCurrentLine ? 26 : 20,
                                    weight: isCurrentLine ? .bold : .medium
                                ))
                                .foregroundColor(isCurrentLine ? .white : .white.opacity(0.6))
                                .shadow(
                                    color: isCurrentLine ? .white.opacity(0.5) : .clear,
                                    radius: isCurrentLine ? 5 : 0
                                )
                                .multilineTextAlignment(.center)
                                .scaleEffect(isCurrentLine ? 1.1 : 0.9)
                                .opacity(isCurrentLine ? 1.0 : 0.7)
                                .padding(.vertical, 4)
                                .animation(.easeInOut(duration: 0.3), value: isCurrentLine)
                                .frame(maxWidth: .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if lyricsManager.isLoading {
                        Text("Loading lyrics...")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .frame(height: 32)
                    } else { // No lyrics available and not loading
                        VStack(spacing: 15) {
                            Text(noLyricsFallbackMessage)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            HStack(spacing: 15) {
                                Button(action: handleAddLyricsManually) {
                                    Text("Add Lyrics Manually")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 20)
                                        .background(Capsule().fill(Color.blue))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button {
                                    showingLyricsSearchModal = true
                                } label: {
                                    Text("Search Online")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 20)
                                        .background(Capsule().fill(Color.orange))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .sheet(isPresented: $showingLyricsSearchModal) {
                                    if let currentTrack = playbackManager.currentTrack {
                                        LyricsSearchModalView(
                                            currentTitle: currentTrack.title,
                                            currentArtist: currentTrack.artist,
                                            currentAlbum: currentTrack.album as String?
                                        )
                                        .environmentObject(lyricsManager)
                                        .environmentObject(playbackManager)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: displayTime) { _, newDisplayTime in
                if let lyrics = lyricsManager.currentLyrics {
                    let newCurrentLyricID = lyrics.currentLine(at: newDisplayTime)?.id
                    if newCurrentLyricID != currentLyricID {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(newCurrentLyricID, anchor: .center)
                        }
                        currentLyricID = newCurrentLyricID
                    }
                }
            }
            .onChange(of: showFullLyrics) { _, _ in
                // When showFullLyrics changes, re-scroll to center the current lyric
                if let lyrics = lyricsManager.currentLyrics, let id = lyrics.currentLine(at: displayTime)?.id {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Progress bar
            progressSection
                .padding(.top, 20) // Reduced top padding
            
            // All controls properly arranged
            HStack(spacing: 0) {
                // Volume controls (left side)
                HStack(spacing: 12) {
                    Button(action: toggleMute) {
                        Image(systemName: volumeIcon)
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    
                    Slider(
                        value: Binding(
                            get: { playbackManager.volume },
                            set: { newVolume in
                                playbackManager.setVolume(newVolume)
                                if isMuted && newVolume > 0 {
                                    isMuted = false
                                }
                            }
                        ),
                        in: 0...1
                    )
                    .frame(width: 120)
                    .controlSize(.small)
                    .disabled(isMuted)
                }
                .frame(width: 200)
                
                Spacer()
                
                // Playback controls (centered)
                HStack(spacing: 32) {
                    // Shuffle button
                    Button(action: {
                        playlistManager.toggleShuffle()
                    }) {
                        Image(systemName: Icons.shuffleFill)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(playlistManager.isShuffleEnabled ? Color.accentColor : Color.white.opacity(0.7))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    .disabled(playbackManager.currentTrack == nil)
                    
                    // Previous button
                    Button(action: {
                        playlistManager.playPreviousTrack()
                    }) {
                        Image(systemName: Icons.backwardFill)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    .disabled(playbackManager.currentTrack == nil)
                    
                    // Play/Pause button (centered)
                    Button(action: {
                        playbackManager.togglePlayPause()
                    }) {
                        PlayPauseIcon(isPlaying: playbackManager.isPlaying)
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    .scaleEffect(playButtonPressed ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: playButtonPressed)
                    .onLongPressGesture(
                        minimumDuration: 0,
                        maximumDistance: .infinity,
                        pressing: { pressing in
                            playButtonPressed = pressing
                        },
                        perform: {}
                    )
                    .disabled(playbackManager.currentTrack == nil)
                    
                    // Next button
                    Button(action: {
                        playlistManager.playNextTrack()
                    }) {
                        Image(systemName: Icons.forwardFill)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    .disabled(playbackManager.currentTrack == nil)
                    
                    // Repeat button
                    Button(action: {
                        playlistManager.toggleRepeatMode()
                    }) {
                        Image(systemName: Icons.repeatIcon(for: playlistManager.repeatMode))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(playlistManager.repeatMode != .off ? Color.accentColor : Color.white.opacity(0.7))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.1)
                    .disabled(playbackManager.currentTrack == nil)
                }
                
                Spacer()
                
                // Queue button (moved to the very end of the window)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingQueue.toggle()
                    }
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(showingQueue ? .white : .white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(showingQueue ? Color.accentColor : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(scale: 1.1)
                .help(showingQueue ? "Hide Queue" : "Show Queue")
                .frame(width: 80)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress slider
            progressSlider
            
            // Time labels
            HStack {
                Text(formatDuration(isDraggingProgress ? tempProgressValue : displayTime))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatDuration(playbackManager.currentTrack?.duration ?? 0))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
            }
        }
    }
    
    private var progressSlider: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    // Progress track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * progressPercentage,
                            height: 6
                        )
                    
                    // Drag handle
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .opacity(isDraggingProgress || hoveredOverProgress ? 1.0 : 0.0)
                        .offset(x: (geometry.size.width * progressPercentage) - 8)
                        .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.15), value: progressPercentage)
                        .animation(.easeInOut(duration: 0.15), value: hoveredOverProgress)
                }
                .contentShape(Rectangle())
                .gesture(progressDragGesture(in: geometry))
                .onTapGesture { value in
                    handleProgressTap(at: value.x, in: geometry.size.width)
                }
                .onHover { hovering in
                    hoveredOverProgress = hovering
                }
            }
        }
        .frame(height: 16)
    }
    
    private var bottomControlsSection: some View {
        HStack(spacing: 24) {
            // Volume controls
            HStack(spacing: 12) {
                Button(action: toggleMute) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(scale: 1.1)
                
                Slider(
                    value: Binding(
                        get: { playbackManager.volume },
                        set: { newVolume in
                            playbackManager.setVolume(newVolume)
                            if isMuted && newVolume > 0 {
                                isMuted = false
                            }
                        }
                    ),
                    in: 0...1
                )
                .frame(width: 120)
                .controlSize(.small)
                .disabled(isMuted)
            }
            
            Spacer()
            
            // Queue button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingQueue.toggle()
                }
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18))
                    .foregroundColor(showingQueue ? .white : .white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(showingQueue ? Color.accentColor : Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .hoverEffect(scale: 1.1)
        }
    }
    
    // MARK: - Helper Methods
    
    private var progressPercentage: Double {
        guard let track = playbackManager.currentTrack, track.duration > 0 else { return 0 }
        let currentTime = isDraggingProgress ? tempProgressValue : displayTime
        return min(max(currentTime / track.duration, 0), 1)
    }
    
    private var volumeIcon: String {
        if isMuted || playbackManager.volume < 0.01 {
            return "speaker.slash"
        } else if playbackManager.volume < 0.3 {
            return "speaker.wave.1"
        } else if playbackManager.volume < 0.7 {
            return "speaker.wave.2"
        } else {
            return "speaker.wave.3"
        }
    }
    
    private var currentTrackContextMenuItems: [ContextMenuItem] {
        guard let track = playbackManager.currentTrack else { return [] }
        
        return TrackContextMenu.createMenuItems(
            for: track,
            playbackManager: playbackManager,
            playlistManager: playlistManager,
            currentContext: .library
        )
    }
    
    private func setupInitialState() {
        syncDisplayTime()
        if playbackManager.isPlaying && scenePhase == .active {
            startUITimer()
        }
    }
    
    private func syncDisplayTime() {
        displayTime = playbackManager.actualCurrentTime
    }
    
    private func startUITimer() {
        guard scenePhase == .active else { return }

        stopUITimer()
        
        // Capture the current playback position
        playbackStartTime = Date()
        playbackStartOffset = playbackManager.actualCurrentTime
        displayTime = playbackStartOffset
        
        // Create a timer that updates the UI more frequently for smoother lyric sync
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateDisplayTime()
        }
        uiTimer?.tolerance = 0.05 // Small tolerance for consistent updates
    }
    
    private func stopUITimer() {
        uiTimer?.invalidate()
        uiTimer = nil
        syncDisplayTime() // Sync with actual player time when stopping
    }
    
    private func updateDisplayTime() {
        guard playbackManager.isPlaying, !isDraggingProgress else { return }
        
        // Directly use the actual current time from the playback manager
        displayTime = playbackManager.actualCurrentTime
    }
    
    // MARK: - Helper Functions
    
    private func toggleMute() {
        if isMuted {
            playbackManager.setVolume(previousVolume)
            isMuted = false
        } else {
            previousVolume = playbackManager.volume
            playbackManager.setVolume(0)
            isMuted = true
        }
    }
    
    private func progressDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDraggingProgress = true
                let percentage = value.location.x / geometry.size.width
                tempProgressValue = (playbackManager.currentTrack?.duration ?? 0) * percentage
            }
            .onEnded { value in
                isDraggingProgress = false
                let percentage = value.location.x / geometry.size.width
                let newTime = (playbackManager.currentTrack?.duration ?? 0) * percentage
                playbackManager.seekTo(time: newTime)
                displayTime = newTime
                playbackStartTime = Date()
                playbackStartOffset = newTime
            }
    }
    
    private func handleProgressTap(at x: CGFloat, in width: CGFloat) {
        let percentage = x / width
        let newTime = (playbackManager.currentTrack?.duration ?? 0) * percentage
        playbackManager.seekTo(time: newTime)
        displayTime = newTime
        playbackStartTime = Date()
        playbackStartOffset = newTime
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }
    
    private static let noLyricsMessages = [
        "Oops! The lyrics ghosted us just like your crush did.\nMaybe you can write them a love letter — or just add a .lrc file manually.",
        "We searched everywhere — even under the soundwaves.\nStill no luck. Feel free to drop in a lyrics file.",
        "Looks like the song is playing hide-and-seek with its lyrics.\nYou can win the game by adding them yourself.",
        "This track is vibing in silence.\nChange that by uploading a lyrics file.",
        "No lyrics today... even our AI couldn’t charm them out.\nMind giving it a nudge with a manual upload?",
        "The lyrics took a break. Union rules, probably.\nYou can help fill in the gap by adding them yourself.",
        "Well, this is awkward... the lyrics stood us up.\nCare to step in and upload them manually?",
        "It's like the song forgot its own words.\nMaybe you remember them? Add the file and save the day.",
        "The lyric search party came back empty-handed.\nHelp them out with a manual upload.",
        "This song's got beats, but no words to speak.\nWant to give it a voice? Add the lyrics file.",
        "Our lyric radar is officially broken.\nFeel free to go old-school and upload them yourself.",
        "No lyrics here. Even the backup singers are silent.\nWhy not be the lead and add the file manually?",
        "Nothing but echoes where lyrics should be.\nYou can fix that by uploading a lyrics file.",
        "Turns out the internet doesn’t know this song either.\nBut you do. Add the lyrics manually if you’ve got them.",
        "We tried everything short of summoning the lyrics.\nCare to save the effort and upload the file?",
        "This song is apparently a mystery track.\nWant to help solve it? Add a lyrics file.",
        "Lyrics not found. We even asked nicely.\nLooks like it’s manual upload time.",
        "The lyrics are on vacation.\nYou could fill in while they’re gone.",
        "We found the rhythm, but the words slipped through the cracks.\nPatch it up with a lyrics file.",
        "Even the search engines gave us a shrug.\nTime for the manual hero move — add the file."
    ]
    
    private func handleAddLyricsManually() {
        guard let currentTrack = playbackManager.currentTrack else { return }
        
        LyricsFilePicker.present { url in
            guard let sourceURL = url else { return }
            
            do {
                let trackFileName = currentTrack.url.deletingPathExtension().lastPathComponent
                let destinationURL = lyricsManager.cacheDirectory.appendingPathComponent("\(trackFileName).lrc")
                
                // Ensure the destination directory exists
                try FileManager.default.createDirectory(at: lyricsManager.cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                
                // Copy the file
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                
                print("Manual lyrics saved to: \(destinationURL.path)")
                
                // Load lyrics directly from the saved file
                if let loadedLyrics = lyricsManager.loadCachedLyrics(for: currentTrack) {
                    lyricsManager.currentLyrics = loadedLyrics
                    print("Manual lyrics loaded successfully.")
                } else {
                    print("Failed to load manual lyrics from cache after saving.")
                    // Fallback to trying to load from network if cache load fails (shouldn't happen)
                    lyricsManager.loadLyrics(for: currentTrack)
                }
            } catch {
                print("Failed to save or load manual lyrics: \(error.localizedDescription)")
                // Optionally, show an alert to the user
            }
        }
    }
}

// MARK: - Supporting Views

struct FullScreenAlbumArtView: View {
    let trackInfo: TrackArtworkInfo?
    
    var body: some View {
        if let artworkData = trackInfo?.artworkData,
           let nsImage = NSImage(data: artworkData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 320, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .frame(maxWidth: 320, maxHeight: 320)
                .overlay(
                    Image(systemName: Icons.musicNote)
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - Supporting Components

private struct PlayPauseIcon: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Image(systemName: Icons.playFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 0 : 1)
                .scaleEffect(isPlaying ? 0.8 : 1)
                .rotationEffect(.degrees(isPlaying ? -90 : 0))

            Image(systemName: Icons.pauseFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1 : 0.8)
                .rotationEffect(.degrees(isPlaying ? 0 : 90))
        }
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}

// MARK: - FullScreenBackgroundView

struct FullScreenBackgroundView: View {
    let mode: FullScreenBackgroundMode
    let track: Track?
    
    var body: some View {
        ZStack {
            switch mode {
            case .artworkBlur:
                artworkBlurBackground
            case .solidBlack:
                solidBlackBackground
            }
        }
    }
    
    private var artworkBlurBackground: some View {
        ZStack {
            // Artwork background
            if let track = track,
               let artworkData = track.artworkData,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                // Fallback gradient if no artwork
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            
            // Dark blur overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.8),
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 0)
            
            // Heavy blur effect
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .blur(radius: 40)
            
            // Additional blur layers for more depth
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .blur(radius: 60)
            
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .blur(radius: 80)
        }
    }
    
    private var solidBlackBackground: some View {
        Color.black
    }
}