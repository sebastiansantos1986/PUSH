// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

/// Finite layout values keep popup content from expanding an enclosing window.
struct PreviewSizing {
    let cardWidth: Double
    let scale: Double
    let scaledWidth: Double
    let scaledHeight: Double
    init(cardWidth requested: Double, viewportWidth: Double, contentHeight: Double) {
        cardWidth = requested.isFinite ? min(900, max(300, requested)) : 540
        let viewport = viewportWidth.isFinite ? max(1, viewportWidth) : 540
        scale = min(1, max(0.001, (viewport - 40) / cardWidth))
        scaledWidth = cardWidth * scale
        let height = contentHeight.isFinite ? min(100_000, max(1, contentHeight)) : 720
        scaledHeight = height * scale
    }
}
