import Foundation

public class LRCParser {
    
    // Regex patterns for parsing LRC files
    private static let timeTagPattern = try! NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{2})\\.(\\d{1,3})\\]", options: [])
    private static let metadataPattern = try! NSRegularExpression(pattern: "\\[(ar|ti|al|by|offset|re|ve):([^\\]]+)\\]", options: [])
    private static let lyricsLinePattern = try! NSRegularExpression(pattern: "\\[\\d{1,2}:\\d{2}\\.\\d{1,3}\\](.+?)(?=\\[\\d{1,2}:\\d{2}\\.\\d{1,3}\\]|$)", options: [.dotMatchesLineSeparators])
    
    public static func parse(lrcContent: String) -> Lyrics {
        var metadata: [String: String] = [:]
        var lines: [LyricsLine] = []
        
        let contentLines = lrcContent.components(separatedBy: .newlines)
        print("🎵 LRCParser: Starting to parse content (length: \(lrcContent.count))")
        print("🎵 LRCParser: First 200 chars: \(String(lrcContent.prefix(200)))")
        print("🎵 LRCParser: Processing \(contentLines.count) lines")
        
        for (index, line) in contentLines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            print("🎵 LRCParser: Processing line \(index): '\(trimmedLine)'")
            
            // Check if this line contains time tags
            let timeTags = timeTagPattern.matches(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.count))
            
            if !timeTags.isEmpty {
                print("🎵 LRCParser: Found \(timeTags.count) time tags in line")
                
                // Extract the lyrics text (everything after the last timestamp)
                let lastTimeTag = timeTags.last!
                let textStartIndex = lastTimeTag.range.upperBound
                let lyricsText = String(trimmedLine[trimmedLine.index(trimmedLine.startIndex, offsetBy: textStartIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🎵 LRCParser: Extracted lyrics text: '\(lyricsText)'")
                
                if !lyricsText.isEmpty {
                    // Create a line for each timestamp
                    for (tagIndex, timeTag) in timeTags.enumerated() {
                        if let timeRange = Range(timeTag.range, in: trimmedLine) {
                            let timeString = String(trimmedLine[timeRange])
                            print("🎵 LRCParser: Processing time tag \(tagIndex): '\(timeString)'")
                            if let time = parseTimeTag(timeString) {
                                let lyricsLine = LyricsLine(text: lyricsText, startTime: time)
                                lines.append(lyricsLine)
                                print("🎵 LRCParser: Added line at time \(time): '\(lyricsText)'")
                            } else {
                                print("🎵 LRCParser: Failed to parse time tag: '\(timeString)'")
                            }
                        }
                    }
                }
            } else {
                // Only try to parse metadata if no time tags were found
                // Use a simpler approach for metadata parsing
                if trimmedLine.hasPrefix("[") && trimmedLine.contains(":") && trimmedLine.hasSuffix("]") {
                    let content = String(trimmedLine.dropFirst().dropLast()) // Remove [ and ]
                    let parts = content.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0])
                        let value = String(parts[1])
                        metadata[key] = value
                        print("🎵 LRCParser: Found metadata: \(key) = \(value)")
                    }
                } else {
                    print("🎵 LRCParser: No time tags or metadata found in line")
                }
            }
        }
        
        print("🎵 LRCParser: Total lines before sorting: \(lines.count)")
        
        // Sort lines by start time
        lines.sort { $0.startTime < $1.startTime }
        
        // Calculate end times for lines
        for i in 0..<lines.count {
            if i < lines.count - 1 {
                lines[i].endTime = lines[i + 1].startTime
            }
        }
        
        print("🎵 LRCParser: Final result: \(lines.count) lines")
        return Lyrics(lines: lines, metadata: metadata)
    }
    
    private static func parseTimeTag(_ timeTag: String) -> TimeInterval? {
        // Remove brackets
        let cleanTag = timeTag.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        
        let components = cleanTag.components(separatedBy: ":")
        guard components.count == 2 else { return nil }
        
        guard let minutes = Int(components[0]),
              let seconds = Double(components[1]) else { return nil }
        
        return TimeInterval(minutes * 60) + seconds
    }
    
    public static func parseFromFile(url: URL) -> Lyrics? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return parse(lrcContent: content)
        } catch {
            print("Error reading LRC file: \(error)")
            return nil
        }
    }
    
    public static func parseFromString(_ content: String) -> Lyrics {
        print("🎵 LRCParser: Starting to parse content (length: \(content.count))")
        print("🎵 LRCParser: First 200 chars: \(String(content.prefix(200)))")
        
        let result = parse(lrcContent: content)
        print("🎵 LRCParser: Parsed \(result.count) lines")
        return result
    }
} 