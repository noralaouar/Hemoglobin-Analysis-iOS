//
//  CSVExporter.swift
//  neu Kopie1
//
//  Created by its on 28.10.25.
//

// CSVExporter.swift
import Foundation

struct CSVExporter {

    /// Exportiert die Messwerte als CSV in den Temp-Ordner und gibt die Datei-URL zurück.
    static func export(results: [MeasurementResult],
                       filename: String = "Messwerte.csv") throws -> URL {

        var rows: [String] = []
        rows.append("timestamp,deltaOxy,deltaDeoxy,minOxy,maxOxy,minDeoxy,maxDeoxy")

        // Zeitstempel sauber im ISO-8601 Format
        let df = ISO8601DateFormatter()
        df.timeZone = TimeZone(secondsFromGMT: 0)

        // Zahlenformat (Punkt als Dezimaltrenner, keine Gruppierung)
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "en_US_POSIX")
        nf.maximumFractionDigits = 6
        nf.minimumFractionDigits = 0
        nf.usesGroupingSeparator = false

        @inline(__always)
        func fmt(_ x: Double?) -> String {
            guard let v = x, v.isFinite else { return "" }
            return nf.string(from: NSNumber(value: v)) ?? "\(v)"
        }

        for r in results {
            let t = df.string(from: r.timestamp)
            let line = [
                t,
                fmt(r.deltaOxy),
                fmt(r.deltaDeoxy),
                fmt(r.minOxy),
                fmt(r.maxOxy),
                fmt(r.minDeoxy),
                fmt(r.maxDeoxy)
            ].joined(separator: ",")
            rows.append(line)
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(filename)

        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }
}
