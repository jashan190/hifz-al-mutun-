// Features/Library/HatchBackground.swift
import SwiftUI

/// A faint diamond cross-hatch (two sets of diagonal lines) for the cover
/// "paper", echoing the printed matn title pages. Very low opacity so it only
/// adds texture. Tint defaults to a warm brown; it never competes with content.
struct HatchBackground: View {
    var spacing: CGFloat = 7
    var tint: Color = Color(hex: 0x715A3A).opacity(0.16)

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))   // "/"
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))             // "\"
                x += spacing
            }
            ctx.stroke(path, with: .color(tint), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    HatchBackground()
        .background(Color(hex: 0xF4EBD3))
        .frame(width: 220, height: 280)
}
