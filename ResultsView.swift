//
//  ResultsView.swift
//  neu
//
//  Created by its on 01.05.25.
//


import SwiftUI
import Foundation

struct ResultsView: View {
    let results: [MeasurementResult]
    let onDeleteAll: () -> Void
    @State private var showChart = false

    var sortedResults: [MeasurementResult] {
        results.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationView {
            List(sortedResults) { result in
                NavigationLink(destination: ResultDetailView(result: result)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zeit: \(result.timestamp, style: .time)")
                            .font(.headline)
                        Text("oxyHb: \(result.deltaOxy, specifier: "%.2f"), deoxyHb: \(result.deltaDeoxy, specifier: "%.2f")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Ergebnisse")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Diagramm") { showChart = true }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Alle löschen") { onDeleteAll() }
                }
            }
            .sheet(isPresented: $showChart) {
                ChartView(results: sortedResults)
            }
        }
    }
}
