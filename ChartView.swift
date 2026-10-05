//
//  ChartView.swift
//  neu
//
//  Created by its on 01.05.25.
//


import SwiftUI
import Charts

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let series: String
}

struct ChartView: View {
    let results: [MeasurementResult]

    var chartData: [ChartDataPoint] {
        var data = [ChartDataPoint]()
        for result in results {
            data.append(ChartDataPoint(timestamp: result.timestamp, value: result.deltaOxy, series: "oxyHb"))
            data.append(ChartDataPoint(timestamp: result.timestamp, value: result.deltaDeoxy, series: "deoxyHb"))
        }
        return data
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Verlauf der Chromophoren")
                .font(.headline)
                .padding(.leading)

            Chart(chartData) { point in
                LineMark(
                    x: .value("Zeit", point.timestamp),
                    y: .value("Wert", point.value * 100) // Skalierung für bessere Sichtbarkeit
                )
                .foregroundStyle(by: .value("Serie", point.series))
                .symbol(by: .value("Serie", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3)) // dickere Linien
            }
        
            .chartForegroundStyleScale(domain: ["oxyHb", "deoxyHb"], range: [Color.red, Color.blue])
            .frame(height: 300)
            .padding()
        }
    }
}
