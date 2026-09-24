//
//  InvertingFillView.swift
//  RISE_RoutineTimer
//
//  The signature screen: a page that fills with colour from the bottom as the
//  step burns down, with the type inverting across the fill line.
//
//  Ported from the FLIP timer's version rather than the blend-mode one this
//  app used to have. Two real layers — white page with dark type, and a
//  coloured page with white type masked to the fill — beat
//  `.blendMode(.difference)` on every count that matters here:
//
//  * Type stays clean *at* the fill line instead of going muddy mid-glyph.
//  * Emoji render normally. The old version needed `.blendMode(.normal)` to
//    escape the difference blend, which knocked the icon out of the inversion.
//  * The fill can be any colour. Difference blending only ever gave black.
//
//  The cost is that `content` is built twice, which has two consequences the
//  call site has to respect:
//
//  1. The masked copy is hidden from VoiceOver here, so the screen is read
//     once rather than twice (audit item A8).
//  2. **Put no interactive controls inside `content`** — there would be two of
//     every button, stacked. Controls belong in an overlay above this view.
//

import SwiftUI

struct InvertingFillView<Content: View>: View {
    /// The colour that rises from the bottom.
    let fillColor: Color
    /// 0 = empty page, 1 = fully filled.
    let fillFraction: Double
    /// The page outside the fill and the type on it. White with dark type
    /// by day; the night routine turns the page black with white type, and
    /// the coloured fill then rises over black instead of white.
    var pageColor: Color = .white
    var pageTextColor: Color = .black
    /// Built twice: once with the colour to use on the page, once with the
    /// colour to use on the fill. The Bool says which layer is being built
    /// — on a black page both layers set white type, so the colour alone
    /// no longer tells the two apart.
    @ViewBuilder let content: (_ textColor: Color, _ onFill: Bool) -> Content

    var body: some View {
        ZStack {
            // Outside the fill: the page and its type.
            ZStack {
                pageColor
                content(pageTextColor, false)
            }

            // Inside the fill: coloured page, white type. Drawn at exactly the
            // same position as the layer above so glyphs stay continuous as
            // the mask grows past them.
            ZStack {
                fillColor
                content(.white, true)
            }
            .mask(alignment: .bottom) {
                GeometryReader { geo in
                    Color.black
                        .frame(height: geo.size.height * max(0, min(1, fillFraction)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .accessibilityHidden(true)
        }
        // Suppressed here rather than only on an ancestor. A transaction
        // modifier governs updates that flow down through it, but the
        // per-second tick invalidates this view directly (it is where the
        // engine is read), so an ancestor's modifier misses it and the digits
        // crossfade. Same lesson the FLIP timer learned.
        .transaction { $0.animation = nil }
    }
}
