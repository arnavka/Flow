import SwiftUI
import AppKit

struct LyricsNotFoundView: View {
    let message: String
    let onAddLyricsManually: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: onAddLyricsManually) {
                Text("Add Lyrics Manually")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}