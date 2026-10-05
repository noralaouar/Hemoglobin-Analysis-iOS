//
//  Colormap.swift
//  neu Kopie1
//
//  Created by its on 26.10.25.
//

import Foundation
import CoreGraphics

// Welcher Farbstil soll verwendet werden?
public enum ColormapType: String, CaseIterable, Identifiable, Codable {
    case hot  = "Hot"   // Schwarz → Rot → Gelb → Weiß
    case blue = "Blue"  // Schwarz/Dunkelblau → Cyan → Weiß

    public var id: String { rawValue }

    /// Schönere Labels für den Picker
    public var label: String {
        switch self {
        case .hot:  return "Hot (rot-betont)"
        case .blue: return "Blue (blau-betont)"
        }
    }
}

/// Sammlung von Colormaps
public enum Colormap {
    /// Heiß-Farbskala
    public struct hot {
        /// Input: 0…1 → Output: (r,g,b) ebenfalls 0…1
        public static func color01(for xIn: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let x = max(0, min(1, xIn))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            if x < 1/3 {
                r = 3 * x; g = 0; b = 0
            } else if x < 2/3 {
                r = 1; g = 3 * (x - 1/3); b = 0
            } else {
                r = 1; g = 1; b = 3 * (x - 2/3)
            }
            return (r, g, b)
        }
    }

    /// Blau-Farbskala
    public struct blue {
        /// Input: 0…1 → Output: (r,g,b) ebenfalls 0…1
        public static func color01(for xIn: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let x = max(0, min(1, xIn))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            if x < 0.45 {
                r = 0
                g = 0
                b = (x / 0.45) * 0.5                  // 0 → 0.5
            } else if x < 0.80 {
                r = 0
                g = (x - 0.45) / 0.35                 // 0 → 1
                b = 0.5 + ((x - 0.45) / 0.35) * 0.5   // 0.5 → 1
            } else {
                r = (x - 0.80) / 0.20                 // 0 → 1
                g = 1
                b = 1
            }
            return (r, g, b)
        }
    }

    /// Dispatcher: wählt die richtige Map und liefert UInt8-RGB
    public static func rgb255(forNormalized x: CGFloat, using map: ColormapType) -> (UInt8, UInt8, UInt8) {
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch map {
        case .hot:
            (r, g, b) = hot.color01(for: x)
        case .blue:
            (r, g, b) = blue.color01(for: x)
        }
        return (to255(r), to255(g), to255(b))
    }

    @inline(__always) private static func to255(_ v: CGFloat) -> UInt8 {
        let clamped = max(0, min(1, v))
        return UInt8((clamped * 255).rounded())
    }
}
