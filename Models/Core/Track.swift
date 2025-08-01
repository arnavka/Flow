import Foundation
import GRDB

public class Track: Identifiable, ObservableObject, Equatable, FetchableRecord, PersistableRecord {
    public let id = UUID()
    var trackId: Int64?
    let url: URL

    @Published var title: String
    @Published var artist: String
    @Published var album: String
    @Published var composer: String
    @Published var genre: String
    @Published var year: String
    @Published var duration: Double
    @Published var trackArtworkData: Data?
    @Published var albumArtworkData: Data?
    @Published var isMetadataLoaded: Bool = false
    @Published var isFavorite: Bool = false
    @Published var playCount: Int = 0
    @Published var lastPlayedDate: Date?

    let format: String
    var folderId: Int64?
    var albumArtist: String?
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    var rating: Int?
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    var fileSize: Int64?
    var dateAdded: Date?
    var dateModified: Date?

    var isDuplicate: Bool = false
    var primaryTrackId: Int64?
    var duplicateGroupId: String?

    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?

    var extendedMetadata: ExtendedMetadata?

    var albumId: Int64?
    
    var artworkData: Data? {
        // Prefer album artwork if available
        if let albumArtwork = albumArtworkData {
            return albumArtwork
        }
        
        // Fall back to track's own artwork
        return trackArtworkData
    }

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
        self.extendedMetadata = ExtendedMetadata()
    }

    // MARK: - DB Configuration

    public static let databaseTableName = "tracks"

    static let columnMap: [String: Column] = [
        "artist": Columns.artist,
        "album": Columns.album,
        "album_artist": Columns.albumArtist,
        "composer": Columns.composer,
        "genre": Columns.genre,
        "year": Columns.year
    ]

    public enum Columns {
        static let trackId = Column("id")
        static let folderId = Column("folder_id")
        static let path = Column("path")
        static let filename = Column("filename")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let fileSize = Column("file_size")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
        static let isDuplicate = Column("is_duplicate")
        static let primaryTrackId = Column("primary_track_id")
        static let duplicateGroupId = Column("duplicate_group_id")
        static let trackArtworkData = Column("track_artwork_data")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let totalTracks = Column("total_tracks")
        static let discNumber = Column("disc_number")
        static let totalDiscs = Column("total_discs")
        static let rating = Column("rating")
        static let compilation = Column("compilation")
        static let releaseDate = Column("release_date")
        static let originalReleaseDate = Column("original_release_date")
        static let bpm = Column("bpm")
        static let mediaType = Column("media_type")
        static let bitrate = Column("bitrate")
        static let sampleRate = Column("sample_rate")
        static let channels = Column("channels")
        static let codec = Column("codec")
        static let bitDepth = Column("bit_depth")
        static let sortTitle = Column("sort_title")
        static let sortArtist = Column("sort_artist")
        static let sortAlbum = Column("sort_album")
        static let sortAlbumArtist = Column("sort_album_artist")
        static let extendedMetadata = Column("extended_metadata")
        static let albumId = Column("album_id")
    }

    // MARK: - FetchableRecord

    required public init(row: Row) throws {
        trackId = row[Columns.trackId]
        folderId = row[Columns.folderId]

        let path: String = row[Columns.path]
        url = URL(fileURLWithPath: path)

        title = row[Columns.title] ?? url.deletingPathExtension().lastPathComponent
        artist = row[Columns.artist] ?? "Unknown Artist"
        album = row[Columns.album] ?? "Unknown Album"
        genre = row[Columns.genre] ?? "Unknown Genre"

        // Normalize empty composer strings
        let composerValue = row[Columns.composer] ?? "Unknown Composer"
        composer = composerValue.isEmpty ? "Unknown Composer" : composerValue

        year = row[Columns.year] ?? ""
        duration = row[Columns.duration] ?? 0
        format = row[Columns.format] ?? url.pathExtension
        trackArtworkData = row[Columns.trackArtworkData]
        isFavorite = row[Columns.isFavorite] ?? false
        playCount = row[Columns.playCount] ?? 0
        lastPlayedDate = row[Columns.lastPlayedDate]
        albumArtist = row[Columns.albumArtist]
        trackNumber = row[Columns.trackNumber]
        totalTracks = row[Columns.totalTracks]
        discNumber = row[Columns.discNumber]
        totalDiscs = row[Columns.totalDiscs]
        rating = row[Columns.rating]
        compilation = row[Columns.compilation] ?? false
        releaseDate = row[Columns.releaseDate]
        originalReleaseDate = row[Columns.originalReleaseDate]
        bpm = row[Columns.bpm]
        mediaType = row[Columns.mediaType]
        bitrate = row[Columns.bitrate]
        sampleRate = row[Columns.sampleRate]
        channels = row[Columns.channels]
        codec = row[Columns.codec]
        bitDepth = row[Columns.bitDepth]
        fileSize = row[Columns.fileSize]
        dateAdded = row[Columns.dateAdded]
        dateModified = row[Columns.dateModified]
        isDuplicate = row[Columns.isDuplicate] ?? false
        primaryTrackId = row[Columns.primaryTrackId]
        duplicateGroupId = row[Columns.duplicateGroupId]
        sortTitle = row[Columns.sortTitle]
        sortArtist = row[Columns.sortArtist]
        sortAlbum = row[Columns.sortAlbum]
        sortAlbumArtist = row[Columns.sortAlbumArtist]
        isMetadataLoaded = true
        albumId = row[Columns.albumId]

        // Load extended metadata
        let extendedMetadataJSON: String? = row[Columns.extendedMetadata]
        extendedMetadata = ExtendedMetadata.fromJSON(extendedMetadataJSON)
    }

    // MARK: - PersistableRecord

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.trackId] = trackId
        container[Columns.folderId] = folderId
        container[Columns.path] = url.path
        container[Columns.filename] = url.lastPathComponent
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.composer] = composer
        container[Columns.genre] = genre
        container[Columns.year] = year
        container[Columns.duration] = duration
        container[Columns.format] = format
        container[Columns.dateAdded] = Date()
        container[Columns.trackArtworkData] = trackArtworkData
        container[Columns.isFavorite] = isFavorite
        container[Columns.playCount] = playCount
        container[Columns.lastPlayedDate] = lastPlayedDate
        container[Columns.albumArtist] = albumArtist
        container[Columns.trackNumber] = trackNumber
        container[Columns.totalTracks] = totalTracks
        container[Columns.discNumber] = discNumber
        container[Columns.totalDiscs] = totalDiscs
        container[Columns.rating] = rating
        container[Columns.compilation] = compilation
        container[Columns.releaseDate] = releaseDate
        container[Columns.originalReleaseDate] = originalReleaseDate
        container[Columns.bpm] = bpm
        container[Columns.mediaType] = mediaType
        container[Columns.bitrate] = bitrate
        container[Columns.sampleRate] = sampleRate
        container[Columns.channels] = channels
        container[Columns.codec] = codec
        container[Columns.bitDepth] = bitDepth
        container[Columns.fileSize] = fileSize
        container[Columns.dateModified] = dateModified
        container[Columns.isDuplicate] = isDuplicate
        container[Columns.primaryTrackId] = primaryTrackId
        container[Columns.duplicateGroupId] = duplicateGroupId
        container[Columns.sortTitle] = sortTitle
        container[Columns.sortArtist] = sortArtist
        container[Columns.sortAlbum] = sortAlbum
        container[Columns.sortAlbumArtist] = sortAlbumArtist
        container[Columns.albumId] = albumId

        // Save extended metadata as JSON
        container[Columns.extendedMetadata] = extendedMetadata?.toJSON()
    }

    // Update if exists based on path
    public func didInsert(_ inserted: InsertionSuccess) {
        trackId = inserted.rowID
    }

    // MARK: - Associations

    static let folder = belongsTo(Folder.self)
    static let album = belongsTo(Album.self, using: ForeignKey(["album_id"]))
    static let trackArtists = hasMany(TrackArtist.self)
    static let artists = hasMany(Artist.self, through: trackArtists, using: TrackArtist.artist)
    static let genres = hasMany(Genre.self, through: hasMany(TrackGenre.self), using: TrackGenre.genre)

    var folder: QueryInterfaceRequest<Folder> {
        request(for: Track.folder)
    }

    var artists: QueryInterfaceRequest<Artist> {
        request(for: Track.artists)
    }

    var genres: QueryInterfaceRequest<Genre> {
        request(for: Track.genres)
    }

    // MARK: - Equatable

    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Sorting support

    var albumArtistForSorting: String {
        albumArtist ?? ""
    }
}

// MARK: - Quality Scoring

extension Track {
    /// Calculate a quality score for duplicate detection
    /// Higher score = better quality
    var qualityScore: Int {
        var score = 0
        
        let formatLower = format.lowercased()
        let bitrateValue = bitrate ?? 0
        
        // Format scoring (base score by tier)
        switch formatLower {
        case "flac", "alac":
            score += 10000  // Tier 1: Lossless
        case "mp3":
            if bitrateValue >= 320 {
                score += 8000   // Tier 2: High quality lossy
            } else if bitrateValue >= 256 {
                score += 6000   // Tier 3: Good quality lossy
            } else {
                score += 1000   // Tier 4: Lower quality
            }
        case "m4a", "aac", "mp4":
            if bitrateValue >= 256 {
                score += 8000   // Tier 2: High quality lossy
            } else if bitrateValue >= 192 {
                score += 6000   // Tier 3: Good quality lossy
            } else {
                score += 1000   // Tier 4: Lower quality
            }
        default:
            score += 1000   // Tier 4: Everything else
        }
        
        // Add actual bitrate to score for differentiation within tiers
        score += bitrateValue
        
        // Use file size as final tiebreaker (larger usually means better quality)
        // Divide by 1MB to keep it in reasonable range
        if let fileSize = fileSize {
            score += Int(fileSize / 1_000_000)
        }
        
        return score
    }
    
    /// Generate a normalized key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
    
    /// Check if this track is a duplicate candidate of another track
    func isDuplicateOf(_ other: Track) -> Bool {
        // Must have valid durations
        guard duration > 0, other.duration > 0 else { return false }
        
        // Check if durations are within 2 seconds of each other
        let durationDiff = abs(duration - other.duration)
        guard durationDiff <= 2.0 else { return false }
        
        // Compare normalized metadata
        return duplicateKey == other.duplicateKey
    }
}

// MARK: - Hashable Conformance

extension Track: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Use the unique ID for hashing
        hasher.combine(id)
    }
}
