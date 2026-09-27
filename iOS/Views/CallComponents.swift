import SwiftUI

/// "00:07" style call duration that updates every second.
struct CallDurationText: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(Self.format(context.date.timeIntervalSince(start)))
                .monospacedDigit()
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Places a view so that its center sits at a fraction of the container.
struct FractionalPosition: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    let size: CGSize

    func body(content: Content) -> some View {
        content.position(x: size.width * x, y: size.height * y)
    }
}

extension View {
    func at(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> some View {
        modifier(FractionalPosition(x: x, y: y, size: size))
    }
}

/// Dots that cycle like "..", "...", "." after a status line.
struct AnimatedDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let count = Int(context.date.timeIntervalSinceReferenceDate * 2) % 3 + 1
            Text(String(repeating: ".", count: count))
                .frame(width: 18, alignment: .leading)
        }
    }
}

/// Default grey avatar, like an account without a profile photo.
struct PlaceholderAvatar: View {
    var body: some View {
        ZStack {
            Color(white: 0.78)
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(14)
                .offset(y: 8)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
