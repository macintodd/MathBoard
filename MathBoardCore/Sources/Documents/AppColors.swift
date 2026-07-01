//
//  AppColors.swift
//  MathBoard
//
//  Warm, playful, FigJam-inspired color tokens.
//  Kept intentionally small for v1 — let Liquid Glass / standard SwiftUI
//  materials handle most chrome; only define explicit colors where the
//  design language calls for warmth (canvas, folder accents, primary CTA).
//

import SwiftUI

enum AppColors {
    static let canvasBackground = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let folderTint = Color(red: 0.96, green: 0.78, blue: 0.45)
    static let accent = Color(red: 0.91, green: 0.45, blue: 0.32)
}
