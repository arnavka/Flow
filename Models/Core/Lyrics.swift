import Foundation

public struct Lyrics: Identifiable {
    public let id = UUID()
    public var lines: [LyricsLine]
    public var metadata: [String: String]
    public var source: String?
    
    public init(lines: [LyricsLine] = [], metadata: [String: String] = [:], source: String? = nil) {
        self.lines = lines
        self.metadata = metadata
        self.source = source
    }
    
    public var isEmpty: Bool {
        return lines.isEmpty
    }
    
    public var count: Int {
        return lines.count
    }
    
    public func currentLineIndex(at time: TimeInterval) -> Int? {
        return lines.firstIndex { $0.isCurrentLine(at: time) }
    }
    
    public func currentLine(at time: TimeInterval) -> LyricsLine? {
        guard let index = currentLineIndex(at: time) else { return nil }
        return lines[index]
    }
    
    public func previousLine(at time: TimeInterval) -> LyricsLine? {
        guard let currentIndex = currentLineIndex(at: time), currentIndex > 0 else { return nil }
        return lines[currentIndex - 1]
    }
    
    public func nextLine(at time: TimeInterval) -> LyricsLine? {
        guard let currentIndex = currentLineIndex(at: time), currentIndex < lines.count - 1 else { return nil }
        return lines[currentIndex + 1]
    }
    
    public func linesAroundCurrent(at time: TimeInterval, count: Int = 3) -> [LyricsLine] {
        guard let currentIndex = currentLineIndex(at: time) else { return [] }
        
        let startIndex = max(0, currentIndex - count / 2)
        let endIndex = min(lines.count, startIndex + count)
        
        return Array(lines[startIndex..<endIndex])
    }
}

extension Lyrics: CustomStringConvertible {
    public var description: String {
        let metadataStr = metadata.map { "[\($0.key): \($0.value)]" }.joined(separator: "\n")
        let linesStr = lines.map { $0.description }.joined(separator: "\n")
        return metadataStr + "\n" + linesStr
    }
} 