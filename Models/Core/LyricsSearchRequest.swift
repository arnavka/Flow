import Foundation

public struct LyricsSearchRequest: Equatable {
    public var title: String
    public var artist: String
    public var duration: TimeInterval?
    public var limit: Int
    
    public init(title: String, artist: String, duration: TimeInterval? = nil, limit: Int = 5) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.limit = limit
    }
    
    public var searchQuery: String {
        return "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var normalizedTitle: String {
        return title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var normalizedArtist: String {
        return artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension LyricsSearchRequest: CustomStringConvertible {
    public var description: String {
        return "LyricsSearchRequest(title: \(title), artist: \(artist), duration: \(duration?.description ?? "nil"))"
    }
} 