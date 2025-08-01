import Foundation
import GRDB

public class Track: Identifiable, ObservableObject, Equatable, FetchableRecord, PersistableRecord, Hashable {
    public let id = UUID()
    var trackId: Int64?
    let url: URL
    
    // Core metadata for display
    var title: String
    var album: String
    var artist: String
    var duration: Double
    
    // File properties
    let format: String
    var folderId: Int64?
    
    // Navigation fields (for "Go to" functionality)
    var albumArtist: String?
    var composer: String
    var genre: String
    var year: String
    
    // User interaction state
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date?
    
    // Sorting fields
    var trackNumber: Int?
    var discNumber: Int?
    
    // State tracking
    var isMetadataLoaded: Bool = false
    var isDuplicate: Bool = false
    var dateAdded: Date?
    
    // Album reference (for artwork lookup)
    var albumId: Int64?
    
    // Transient property for album artwork (populated separately)
    var albumArtworkData: Data?
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        
        // Default values - these will be overridden by metadata
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.composer = "Unknown Composer"
        self.genre = "Unknown Genre"
        self.year = "Unknown Year"
        self.duration = 0
        self.format = url.pathExtension
    }
    
    // MARK: - DB Configuration
    public static let databaseTableName = "tracks"

    public enum Columns {
        static let trackId = Column("id")
        static let folderId = Column("folder_id")
        static let path = Column("path")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let dateAdded = Column("date_added")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let discNumber = Column("disc_number")
        static let albumId = Column("album_id")
        static let isDuplicate = Column("is_duplicate")
    }

    static let columnMap: [String: Column] = [
        "artist": Columns.artist,
        "album": Columns.album,
        "album_artist": Columns.albumArtist,
        "composer": Columns.composer,
        "genre": Columns.genre,
        "year": Columns.year
    ]
    
    // MARK: - FetchableRecord

    required public init(row: Row) throws {
        // Extract path and create URL
        let path: String = row[Columns.path]
        self.url = URL(fileURLWithPath: path)
        self.format = row[Columns.format]
        
        // Core properties
        self.trackId = row[Columns.trackId]
        self.folderId = row[Columns.folderId]
        self.title = row[Columns.title]
        self.artist = row[Columns.artist]
        self.album = row[Columns.album]
        self.composer = row[Columns.composer]
        self.genre = row[Columns.genre]
        self.year = row[Columns.year]
        self.duration = row[Columns.duration]
        self.dateAdded = row[Columns.dateAdded]
        self.isFavorite = row[Columns.isFavorite]
        self.playCount = row[Columns.playCount]
        self.lastPlayedDate = row[Columns.lastPlayedDate]
        
        // Navigation fields
        self.albumArtist = row[Columns.albumArtist]
        
        // Sorting fields
        self.trackNumber = row[Columns.trackNumber]
        self.discNumber = row[Columns.discNumber]
        
        // State
        self.isDuplicate = row[Columns.isDuplicate] ?? false
        
        // Album reference
        self.albumId = row[Columns.albumId]
        
        self.isMetadataLoaded = true
    }
    
    // MARK: - PersistableRecord

    public func encode(to container: inout PersistenceContainer) throws {
        // Only encode the lightweight fields when saving
        container[Columns.trackId] = trackId
        container[Columns.folderId] = folderId
        container[Columns.path] = url.path
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.composer] = composer
        container[Columns.genre] = genre
        container[Columns.year] = year
        container[Columns.duration] = duration
        container[Columns.format] = format
        container[Columns.dateAdded] = dateAdded ?? Date()
        container[Columns.isFavorite] = isFavorite
        container[Columns.playCount] = playCount
        container[Columns.lastPlayedDate] = lastPlayedDate
        container[Columns.albumArtist] = albumArtist
        container[Columns.trackNumber] = trackNumber
        container[Columns.discNumber] = discNumber
        container[Columns.albumId] = albumId
    }

    // Update if exists based on path
    public func didInsert(_ inserted: InsertionSuccess) {
        trackId = inserted.rowID
    }

    // MARK: - Relationships

    public static let folder = belongsTo(Folder.self)
    
    public var folder: QueryInterfaceRequest<Folder> {
        request(for: Track.folder)
    }
    
    // MARK: - Equatable

    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Helper Methods

extension Track {
    /// Get a display-friendly artist name
    var displayArtist: String {
        albumArtist ?? artist
    }
    
    /// Get formatted duration string
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Computed property for artwork
    var artworkData: Data? {
        // Only return album artwork since track artwork is not stored in lightweight model
        albumArtworkData
    }
    
    /// Check if this track has album artwork
    var hasArtwork: Bool {
        albumArtworkData != nil
    }
}

// MARK: - Update Helpers

extension Track {
    /// Create a copy with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> Track {
        var copy = self
        copy.isFavorite = isFavorite
        return copy
    }
    
    /// Create a copy with updated play stats
    func withPlayStats(playCount: Int, lastPlayedDate: Date?) -> Track {
        var copy = self
        copy.playCount = playCount
        copy.lastPlayedDate = lastPlayedDate
        return copy
    }
}

// MARK: - Database Query Helpers

extension Track {
    /// Fetch only the columns needed for lightweight Track
    static var lightweightSelection: [Column] {
        [
            Columns.trackId,
            Columns.folderId,
            Columns.path,
            Columns.title,
            Columns.artist,
            Columns.album,
            Columns.composer,
            Columns.genre,
            Columns.year,
            Columns.duration,
            Columns.format,
            Columns.dateAdded,
            Columns.isFavorite,
            Columns.playCount,
            Columns.lastPlayedDate,
            Columns.albumArtist,
            Columns.trackNumber,
            Columns.discNumber,
            Columns.albumId,
            Columns.isDuplicate
        ]
    }
    
    /// Request for fetching lightweight tracks
    static func lightweightRequest() -> QueryInterfaceRequest<Track> {
        Track
            .select(lightweightSelection)
            .filter(Columns.isDuplicate == false)
    }
}

// MARK: - Duplicate Detection

extension Track {
    /// Generate a key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
}
// MARK: - Full Track Loading

extension Track {
    /// Fetch the complete FullTrack record from database
    /// - Parameter db: Database connection
    /// - Returns: FullTrack with all metadata, or nil if not found
    func fullTrack(db: Database) throws -> FullTrack? {
        guard let trackId = trackId else { return nil }
        
        return try FullTrack
            .filter(FullTrack.Columns.trackId == trackId)
            .fetchOne(db)
    }
    
    /// Async version for fetching FullTrack
    /// - Parameter dbQueue: Database queue
    /// - Returns: FullTrack with all metadata, or nil if not found
    func fullTrack(using dbQueue: DatabaseQueue) async throws -> FullTrack? {
        guard let trackId = trackId else { return nil }
        
        return try await dbQueue.read { db in
            try FullTrack
                .filter(FullTrack.Columns.trackId == trackId)
                .fetchOne(db)
        }
    }
}
