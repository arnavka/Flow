import Foundation

public struct LyricsLine: Identifiable, Equatable {
    public let id = UUID()
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    
    public init(text: String, startTime: TimeInterval, endTime: TimeInterval? = nil) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
    
    public var duration: TimeInterval {
        return endTime ?? startTime + 3.0 // Default 3 seconds if no end time
    }
    
    public var timeTag: String {
        let min = Int(startTime / 60)
        let sec = startTime - TimeInterval(min * 60)
        return String(format: "%02d:%06.3f", min, sec)
    }
    
    public func isCurrentLine(at time: TimeInterval) -> Bool {
        let end = endTime ?? (startTime + 3.0)
        return time >= startTime && time < end
    }
}

extension LyricsLine: CustomStringConvertible {
    public var description: String {
        return "[\(timeTag)]\(text)"
    }
} 