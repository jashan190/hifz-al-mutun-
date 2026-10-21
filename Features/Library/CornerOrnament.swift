// Features/Library/CornerOrnament.swift
import SwiftUI

/// The four arabesque corner ornaments of a cover, tinted to the subject colour.
/// One corner motif (top-left) is mirrored into the other three corners. The
/// motif's own border lines run along the edges and lead into a scroll at each
/// corner; a continuous double rule (in MatnCover) completes the edges.
struct CornerOrnament: View {
    let color: Color
    var inset: CGFloat = 6
    var size: CGFloat = 62

    var body: some View {
        ZStack {
            // The PDF asset imports horizontally mirrored, so the top-left
            // motif needs flipX to land its cluster in the actual corner.
            corner(.topLeading,     flipX: true,  flipY: false)
            corner(.topTrailing,    flipX: false, flipY: false)
            corner(.bottomLeading,  flipX: true,  flipY: true)
            corner(.bottomTrailing, flipX: false, flipY: true)
        }
        .allowsHitTesting(false)
    }

    private func corner(_ alignment: Alignment, flipX: Bool, flipY: Bool) -> some View {
        Image("FloralCorner")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .scaleEffect(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

#Preview {
    CornerOrnament(color: Color(hex: 0x15803D))
        .background(Color(hex: 0xF4EBD3))
        .frame(width: 220, height: 280)
}
