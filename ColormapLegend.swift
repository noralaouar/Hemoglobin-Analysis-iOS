//
//  ColormapLegend.swift
//  neu
//
//  Created by its on 28.01.26.
//


import SwiftUI

struct ColormapLegend: View {
    let map: ColormapType
    let minLabel: String
    let maxLabel: String

    var body: some View {
        VStack(spacing: 4) {
            Text(maxLabel).font(.caption2)

            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: stops(for: map)),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 22, height: 200)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

            Text(minLabel).font(.caption2)
        }
    }

    private func stops(for map: ColormapType) -> [Gradient.Stop] {
        switch map {
        case .hot:
            return [
                .init(color: .white,  location: 0.0),
                .init(color: .yellow, location: 0.33),
                .init(color: .red,    location: 0.66),
                .init(color: .black,  location: 1.0)
            ]
        case .blue:
            return [
                .init(color: .black, location: 0.0),
                .init(color: .blue,  location: 0.35),
                .init(color: .cyan,  location: 0.70),
                .init(color: .white, location: 1.0)
            ]
        }
    }
}
