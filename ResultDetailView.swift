import SwiftUI
import UIKit

struct ResultDetailView: View {
    let result: MeasurementResult

    private let imageHeight: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                Text("Detailansicht des Messergebnisses")
                    .font(.title2)
                    .padding(.bottom, 6)

                Text("Zeit: \(result.timestamp, style: .date) \(result.timestamp, style: .time)")
                    .font(.headline)

                Text("oxyHb: \(result.deltaOxy, specifier: "%.2f"), deoxyHb: \(result.deltaDeoxy, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Live-Bild
                if let image = result.liveImage {
                    block(title: "Live-Bild") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: imageHeight)
                    }
                }

                
                if result.oxyHbImage != nil || result.deoxyHbImage != nil {
                    block(title: "Analysebilder") {

                        HStack(alignment: .top, spacing: 14) {

                            // oxyHb
                            if let oxy = result.oxyHbImage {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Δ[oxyHb]")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack(alignment: .center, spacing: 10) {
                                        Image(uiImage: oxy)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: imageHeight)

                                        ColormapLegend(
                                            map: result.oxyMap,
                                            minLabel: String(format: "%.2f", result.minOxy),
                                            maxLabel: String(format: "%.2f", result.maxOxy)
                                        )
                                        .frame(width: 30, height: imageHeight) // ✅ gleiche Höhe wie Bild
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // deoxyHb
                            if let deoxy = result.deoxyHbImage {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Δ[deoxyHb]")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack(alignment: .center, spacing: 10) {
                                        Image(uiImage: deoxy)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: imageHeight)

                                        ColormapLegend(
                                            map: result.deoxyMap,
                                            minLabel: String(format: "%.2f", result.minDeoxy),
                                            maxLabel: String(format: "%.2f", result.maxDeoxy)
                                        )
                                        .frame(width: 30, height: imageHeight) // ✅ gleiche Höhe wie Bild
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Messergebnis")
        .navigationBarTitleDisplayMode(.inline)
    }

    // ✅ MUSS hier stehen (auf Struct-Ebene), NICHT im body!
    @ViewBuilder
    private func block<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title + ":")
                .font(.headline)

            content()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
    }
}
