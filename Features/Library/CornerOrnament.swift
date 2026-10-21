// Features/Library/CornerOrnament.swift
import SwiftUI

/// The four floral corner ornaments of a cover, tinted to the subject colour.
/// One CC0 corner motif (top-left) is mirrored into the other three corners.
/// Edges-only: it hugs each corner and trails lightly along the edges.
struct CornerOrnament: View {
    let color: Color
    var inset: CGFloat = 6
    var size: CGFloat = 62

    var body: some View {
        ZStack {
            corner(.topLeading,     flipX: false, flipY: false)
            corner(.topTrailing,    flipX: true,  flipY: false)
            corner(.bottomLeading,  flipX: false, flipY: true)
            corner(.bottomTrailing, flipX: true,  flipY: true)
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
