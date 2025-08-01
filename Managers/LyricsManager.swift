import Foundation
import Combine

public class LyricsManager: ObservableObject {
    @Published public var currentLyrics: Lyrics?
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    
    private var cancellables = Set<AnyCancellable>()
    public let cacheDirectory: URL
    
    public init() {
        // Create lyrics cache directory in app support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "org.Petrichor.debug"
        let appDirectory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        self.cacheDirectory = appDirectory.appendingPathComponent("LyricsCache", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        print("🎵 LyricsManager: Cache directory: \(cacheDirectory.path)")
    }
    
    func loadLyrics(for track: Track) {
        print("🎵 LyricsManager: Loading lyrics for '\(track.title)' by '\(track.artist)'")
        guard !track.title.isEmpty && !track.artist.isEmpty else {
            print("🎵 LyricsManager: Track has empty title or artist, skipping")
            self.currentLyrics = nil
            return
        }
        
        isLoading = true
        error = nil
        
        // First, try to load from cache
        if let cachedLyrics = loadCachedLyrics(for: track) {
            print("🎵 LyricsManager: Found cached lyrics")
            self.currentLyrics = cachedLyrics
            self.isLoading = false
            return
        }
        
        // If not cached, fetch from network
        let request = LyricsSearchRequest(title: track.title, artist: track.artist, duration: track.duration)
        print("🎵 LyricsManager: No cached lyrics found, fetching from network")
        
        searchLyrics(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        print("🎵 LyricsManager: Search failed with error: \(error)")
                        self?.error = error.localizedDescription
                    } else {
                        print("🎵 LyricsManager: Search completed successfully")
                    }
                },
                receiveValue: { [weak self] lyrics in
                    print("🎵 LyricsManager: Received lyrics with \(lyrics.count) lines")
                    self?.currentLyrics = lyrics
                    
                    // Cache the lyrics if we got some
                    if !lyrics.isEmpty {
                        self?.cacheLyrics(lyrics, for: track)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Cache Management
    
    private func cacheFileName(for track: Track) -> String {
        // Create a safe filename from track info
        let safeTitle = track.title.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        let safeArtist = track.artist.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        return "\(safeArtist) - \(safeTitle).lrc"
    }
    
    private func cacheLyrics(_ lyrics: Lyrics, for track: Track) {
        let fileName = cacheFileName(for: track)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        // Convert lyrics back to LRC format for storage
        let lrcContent = convertLyricsToLRC(lyrics)
        
        do {
            try lrcContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("🎵 LyricsManager: Cached lyrics to \(fileURL.path)")
        } catch {
            print("🎵 LyricsManager: Failed to cache lyrics: \(error)")
        }
    }
    
    public func loadCachedLyrics(for track: Track) -> Lyrics? {
        let fileName = cacheFileName(for: track)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let lrcContent = try String(contentsOf: fileURL, encoding: .utf8)
            let lyrics = LRCParser.parseFromString(lrcContent)
            print("🎵 LyricsManager: Loaded cached lyrics from \(fileURL.path)")
            return lyrics
        } catch {
            print("🎵 LyricsManager: Failed to load cached lyrics: \(error)")
            return nil
        }
    }
    
    private func convertLyricsToLRC(_ lyrics: Lyrics) -> String {
        var lrcContent = ""
        
        // Add metadata if available
        for (key, value) in lyrics.metadata {
            lrcContent += "[\(key):\(value)]\n"
        }
        
        // Add lyrics lines with timestamps
        for line in lyrics.lines {
            lrcContent += "[\(line.timeTag)]\(line.text)\n"
        }
        
        return lrcContent
    }
    
    // MARK: - Network Fetching
    
    private func searchLyrics(request: LyricsSearchRequest) -> AnyPublisher<Lyrics, Error> {
        print("🎵 LyricsManager: Starting LRCLIB search for '\(request.searchQuery)'")
        let lrclibSource = LRCLibSource()
        return lrclibSource.searchLyrics(request: request)
            .mapError { error in
                print("🎵 LyricsManager: LRCLIB search failed: \(error)")
                return error
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Bulk Operations
    
    func fetchAllLyricsForTracks(_ tracks: [Track]) async {
        print("🎵 LyricsManager: Starting bulk lyrics fetch for \(tracks.count) tracks")
        
        for (index, track) in tracks.enumerated() {
            // Skip if already cached
            if loadCachedLyrics(for: track) != nil {
                continue
            }
            
            print("🎵 LyricsManager: Fetching lyrics for track \(index + 1)/\(tracks.count): '\(track.title)'")
            
            let request = LyricsSearchRequest(title: track.title, artist: track.artist, duration: track.duration)
            
            do {
                let lyrics = try await searchLyrics(request: request).async()
                if !lyrics.isEmpty {
                    cacheLyrics(lyrics, for: track)
                    print("🎵 LyricsManager: Successfully cached lyrics for '\(track.title)'")
                }
                
                // Small delay to be respectful to the API
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
            } catch {
                print("🎵 LyricsManager: Failed to fetch lyrics for '\(track.title)': \(error)")
            }
        }
        
        print("🎵 LyricsManager: Bulk lyrics fetch completed")
    }
    
    func clearCache() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
            print("🎵 LyricsManager: Cache cleared")
        } catch {
            print("🎵 LyricsManager: Failed to clear cache: \(error)")
        }
    }
    
    func getCacheSize() -> Int64 {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            return try fileURLs.reduce(0) { total, fileURL in
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            print("🎵 LyricsManager: Failed to get cache size: \(error)")
            return 0
        }
    }
}

// MARK: - Extensions for async/await support

extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = first()
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
        }
    }
}

// MARK: - Errors

public enum LyricsError: LocalizedError {
    case noLyricsFound
    case networkError
    case parsingError
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .noLyricsFound:
            return "No lyrics found for this song"
        case .networkError:
            return "Network error while searching for lyrics"
        case .parsingError:
            return "Error parsing lyrics data"
        case .invalidResponse:
            return "Invalid response from lyrics service"
        }
    }
}

// MARK: - Lyrics Source Protocol

public protocol LyricsSource {
    func searchLyrics(request: LyricsSearchRequest) -> AnyPublisher<Lyrics, Error>
}

// MARK: - LRCLIB Source

public class LRCLibSource: LyricsSource {
    private let baseURL = "https://lrclib.net/api"
    
    public init() {}
    
    public func searchLyrics(request: LyricsSearchRequest) -> AnyPublisher<Lyrics, Error> {
        // Try search first as it's more reliable
        return searchLyricsByKeyword(request: request)
            .catch { error -> AnyPublisher<Lyrics, Error> in
                print("🎵 LRCLIB: Search failed, trying exact match with duration")
                // If search fails and we have duration, try exact match
                if let duration = request.duration {
                    return self.getLyricsWithDuration(request: request, duration: duration)
                } else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func getLyricsWithDuration(request: LyricsSearchRequest, duration: TimeInterval) -> AnyPublisher<Lyrics, Error> {
        let urlString = "\(baseURL)/get"
        let parameters = [
            "track_name": request.title,
            "artist_name": request.artist,
            "album_name": "Unknown Album", // We don't have album info, use placeholder
            "duration": String(Int(duration))
        ]
        
        return makeRequest(url: urlString, parameters: parameters)
            .map { data -> Lyrics in
                return self.parseLRCLibResponse(data: data)
            }
            .catch { error -> AnyPublisher<Lyrics, Error> in
                print("🎵 LRCLIB: Exact match failed, trying search: \(error)")
                // If exact match fails, try search
                return self.searchLyricsByKeyword(request: request)
            }
            .eraseToAnyPublisher()
    }
    
    private func searchLyricsByKeyword(request: LyricsSearchRequest) -> AnyPublisher<Lyrics, Error> {
        let urlString = "\(baseURL)/search"
        let parameters = [
            "q": "\(request.title) \(request.artist)" // Use the 'q' parameter for broader search
        ]
        
        print("🎵 LRCLIB: Searching with query: '\(parameters["q"] ?? "")'")
        
        return makeRequest(url: urlString, parameters: parameters)
            .map { data -> Lyrics in
                return self.parseLRCLibSearchResponse(data: data, request: request)
            }
            .eraseToAnyPublisher()
    }
    
    private func parseLRCLibResponse(data: Data) -> Lyrics {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("🎵 LRCLIB: Failed to parse JSON response")
            return Lyrics()
        }
        
        // Check if it's an error response
        if let code = json["code"] as? Int, code == 404 {
            print("🎵 LRCLIB: Track not found")
            return Lyrics()
        }
        
        // Parse successful response
        guard let syncedLyrics = json["syncedLyrics"] as? String else {
            print("🎵 LRCLIB: No synced lyrics in response")
            return Lyrics()
        }
        
        print("🎵 LRCLIB: Found synced lyrics, parsing LRC format")
        return LRCParser.parseFromString(syncedLyrics)
    }
    
    private func parseLRCLibSearchResponse(data: Data, request: LyricsSearchRequest) -> Lyrics {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🎵 LRCLIB: Failed to parse search response")
            return Lyrics()
        }
        
        print("🎵 LRCLIB: Found \(jsonArray.count) search results")
        
        // Find the best match
        for (index, result) in jsonArray.enumerated() {
            guard let trackName = result["trackName"] as? String,
                  let artistName = result["artistName"] as? String else {
                print("🎵 LRCLIB: Skipping result \(index) - missing trackName or artistName")
                continue
            }
            
            // Check if syncedLyrics exists and is not empty
            guard let syncedLyrics = result["syncedLyrics"] as? String, !syncedLyrics.isEmpty else {
                print("🎵 LRCLIB: Result \(index) has no syncedLyrics: '\(trackName)' by '\(artistName)'")
                continue
            }
            
            print("🎵 LRCLIB: Checking result \(index): '\(trackName)' by '\(artistName)' (lyrics length: \(syncedLyrics.count))")
            
            // More flexible matching logic
            let trackMatch = trackName.lowercased().contains(request.title.lowercased()) ||
                           request.title.lowercased().contains(trackName.lowercased())
            let artistMatch = artistName.lowercased().contains(request.artist.lowercased()) ||
                            request.artist.lowercased().contains(artistName.lowercased())
            
            if trackMatch && artistMatch {
                print("🎵 LRCLIB: Found good match: '\(trackName)' by '\(artistName)'")
                print("🎵 LRCLIB: Parsing syncedLyrics (first 100 chars): \(String(syncedLyrics.prefix(100)))")
                return LRCParser.parseFromString(syncedLyrics)
            }
        }
        
        print("🎵 LRCLIB: No good match found in search results")
        return Lyrics()
    }
}

// MARK: - Network Utilities

private extension LyricsSource {
    func makeRequest(url: String, parameters: [String: String]) -> AnyPublisher<Data, Error> {
        guard var components = URLComponents(string: url) else {
            return Fail(error: LyricsError.networkError).eraseToAnyPublisher()
        }
        
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let requestURL = components.url else {
            return Fail(error: LyricsError.networkError).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: requestURL)
        request.setValue("Petrichor/1.0 (https://github.com/arnavka/Petrichor)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        print("🎵 LRCLIB: Making request to \(requestURL)")
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .mapError { error in
                print("🎵 LRCLIB: Network error: \(error)")
                return LyricsError.networkError
            }
            .eraseToAnyPublisher()
    }
} 