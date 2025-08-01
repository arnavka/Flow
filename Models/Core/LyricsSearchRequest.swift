import Foundation

public struct LyricsSearchRequest: Equatable {
    public var title: String
    public var artist: String? // Make artist optional
    public var album: String?
    public var duration: TimeInterval?
    public var limit: Int
    
    public init(title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil, limit: Int = 5) {
        self.title = title
        self.artist = artist // Initialize optional artist
        self.album = album
        self.duration = duration
        self.limit = limit
    }
    
    public var searchQuery: String {
        // Include artist only if it exists
        let artistPart = artist.map { " \($0)" } ?? ""
        return "\(title)\(artistPart)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var normalizedTitle: String {
        return title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var normalizedArtist: String? { // Make normalizedArtist optional
        return artist?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension LyricsSearchRequest: CustomStringConvertible {
    public var description: String {
        return "LyricsSearchRequest(title: \(title), artist: \(artist), duration: \(duration?.description ?? "nil"))"
    }
} 