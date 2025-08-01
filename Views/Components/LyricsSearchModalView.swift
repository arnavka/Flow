import SwiftUI

struct LyricsSearchModalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var playbackManager: PlaybackManager
    
    @State private var searchTitle: String
    @State private var searchArtist: String = "" // Change to optional or empty string default
    @State private var searchAlbum: String
    
    @State private var searchResults: [Lyrics] = []
    @State private var isLoadingSearch: Bool = false
    @State private var searchError: String?
    
    @State private var showingLyricsPreview: Bool = false
    @State private var selectedLyrics: Lyrics?
    
    init(currentTitle: String, currentArtist: String, currentAlbum: String?) {
        _searchTitle = State(initialValue: currentTitle)
        _searchArtist = State(initialValue: currentArtist)
        _searchAlbum = State(initialValue: currentAlbum ?? "")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Search Lyrics")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $searchTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Artist (Optional)", text: $searchArtist) // Update label
                    .textFieldStyle(.roundedBorder)
                
                TextField("Album (Optional)", text: $searchAlbum)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    performSearch()
                } label: {
                    Text("Search")
                        .font(.headline)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoadingSearch || searchTitle.isEmpty) // Artist is now optional
            }
            
            if isLoadingSearch {
                ProgressView()
            } else if let error = searchError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else if searchResults.isEmpty {
                Text("No lyrics found for your search. Try different keywords or add manually.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                LyricsNotFoundView(
                    message: "Still no luck? Try adding them manually.",
                    onAddLyricsManually: {
                        handleAddLyricsManually()
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(searchResults) { lyrics in
                            LyricsSearchResultRow(lyrics: lyrics) {
                                selectedLyrics = lyrics
                                showingLyricsPreview = true
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, maxWidth: 600, minHeight: 400, maxHeight: 800)
        .sheet(isPresented: $showingLyricsPreview) {
            if let lyrics = selectedLyrics {
                LyricsPreviewView(lyrics: lyrics) {
                    saveAndUseLyrics(lyrics)
                    dismiss()
                }
            }
        }
    }
    
    private func performSearch() {
        isLoadingSearch = true
        searchError = nil
        searchResults = []
        
        let request = LyricsSearchRequest(
            title: searchTitle,
            artist: searchArtist.isEmpty ? nil : searchArtist, // Pass optional artist
            album: searchAlbum.isEmpty ? nil : searchAlbum,
            duration: playbackManager.currentTrack?.duration
        )
        
        lyricsManager.searchLyrics(request: request)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoadingSearch = false
                if case .failure(let error) = completion {
                    self.searchError = error.localizedDescription
                }
            } receiveValue: { lyricsArray in
                self.searchResults = lyricsArray
            }
            .store(in: &lyricsManager.cancellables) // Store in LyricsManager's cancellables
    }
    
    private func saveAndUseLyrics(_ lyrics: Lyrics) {
        guard let currentTrack = playbackManager.currentTrack else { return }
        
        do {
            let fileName = lyricsManager.cacheFileName(for: currentTrack) // Use LyricsManager's naming convention
            let destinationURL = lyricsManager.cacheDirectory.appendingPathComponent(fileName)
            
            // Convert lyrics to LRC format for saving
            let lrcContent = lyricsManager.convertLyricsToLRC(lyrics)
            try lrcContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            
            print("Selected lyrics saved to: \(destinationURL.path)")
            
            // Reload lyrics in the main player view
            lyricsManager.loadLyrics(for: currentTrack) // This will now correctly load from cache because it exists
        } catch {
            print("Failed to save selected lyrics: \(error.localizedDescription)")
            // Optionally, show an alert to the user
        }
    }
    
    private func handleAddLyricsManually() {
        guard let currentTrack = playbackManager.currentTrack else { return }
        
        LyricsFilePicker.present { url in
            guard let sourceURL = url else { return }
            
            do {
                let fileName = lyricsManager.cacheFileName(for: currentTrack) // Use LyricsManager's naming convention
                let destinationURL = lyricsManager.cacheDirectory.appendingPathComponent(fileName)
                
                // Ensure the destination directory exists
                try FileManager.default.createDirectory(at: lyricsManager.cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                
                // Copy the file
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                
                print("Manual lyrics saved to: \(destinationURL.path)")
                
                // Reload lyrics
                if let loadedLyrics = lyricsManager.getCachedLyrics(for: currentTrack) {
                    lyricsManager.currentLyrics = loadedLyrics
                    print("Manual lyrics loaded successfully from cache.")
                } else {
                    print("Failed to load manual lyrics from cache after saving. Attempting full reload.")
                    lyricsManager.loadLyrics(for: currentTrack) // Fallback to full load logic
                }
                dismiss() // Dismiss the modal after adding lyrics
            } catch {
                print("Failed to save or load manual lyrics: \(error.localizedDescription)")
                // Optionally, show an alert to the user
            }
        }
    }
}

struct LyricsSearchResultRow: View {
    let lyrics: Lyrics
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(lyrics.metadata["ti"] ?? "Unknown Title")
                    .font(.headline)
                Text(lyrics.metadata["ar"] ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Preview") {
                onSelect()
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct LyricsPreviewView: View {
    let lyrics: Lyrics
    let onUseLyrics: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            HStack {
                Text("Lyrics Preview")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text)
                            .padding(.vertical, 2)
                    }
                }
            }
            
            Button {
                onUseLyrics()
            } label: {
                Text("Use These Lyrics")
                    .font(.headline)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .frame(minWidth: 400, maxWidth: 600, minHeight: 400, maxHeight: 800)
    }
}