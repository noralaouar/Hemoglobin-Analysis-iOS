import Foundation
import UIKit

struct MeasurementResult: Identifiable, Codable {

    // MARK: - Identifiable
    var id: UUID

    // MARK: - Data
    let timestamp: Date
    let deltaOxy: Double
    let deltaDeoxy: Double

    // MARK: - Images (nicht Codable)
    var liveImage: UIImage?
    var oxyHbImage: UIImage?
    var deoxyHbImage: UIImage?

    // MARK: - Scale + Colormap
    let minOxy: Double
    let maxOxy: Double
    let minDeoxy: Double
    let maxDeoxy: Double
    let oxyMap: ColormapType
    let deoxyMap: ColormapType

    // MARK: - Init
    init(
        id: UUID = UUID(),
        timestamp: Date,
        deltaOxy: Double,
        deltaDeoxy: Double,
        liveImage: UIImage?,
        oxyHbImage: UIImage?,
        deoxyHbImage: UIImage?,
        minOxy: Double,
        maxOxy: Double,
        minDeoxy: Double,
        maxDeoxy: Double,
        oxyMap: ColormapType,
        deoxyMap: ColormapType
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deltaOxy = deltaOxy
        self.deltaDeoxy = deltaDeoxy
        self.liveImage = liveImage
        self.oxyHbImage = oxyHbImage
        self.deoxyHbImage = deoxyHbImage
        self.minOxy = minOxy
        self.maxOxy = maxOxy
        self.minDeoxy = minDeoxy
        self.maxDeoxy = maxDeoxy
        self.oxyMap = oxyMap
        self.deoxyMap = deoxyMap
    }

    // MARK: - Codable (ohne UIImage)
    enum CodingKeys: String, CodingKey {
        case id, timestamp, deltaOxy, deltaDeoxy
        case minOxy, maxOxy, minDeoxy, maxDeoxy
        case oxyMap, deoxyMap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.deltaOxy = try c.decode(Double.self, forKey: .deltaOxy)
        self.deltaDeoxy = try c.decode(Double.self, forKey: .deltaDeoxy)

        self.minOxy = try c.decode(Double.self, forKey: .minOxy)
        self.maxOxy = try c.decode(Double.self, forKey: .maxOxy)
        self.minDeoxy = try c.decode(Double.self, forKey: .minDeoxy)
        self.maxDeoxy = try c.decode(Double.self, forKey: .maxDeoxy)

        self.oxyMap = try c.decodeIfPresent(ColormapType.self, forKey: .oxyMap) ?? .hot
        self.deoxyMap = try c.decodeIfPresent(ColormapType.self, forKey: .deoxyMap) ?? .blue

        // Bilder werden nicht decodiert
        self.liveImage = nil
        self.oxyHbImage = nil
        self.deoxyHbImage = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(deltaOxy, forKey: .deltaOxy)
        try c.encode(deltaDeoxy, forKey: .deltaDeoxy)

        try c.encode(minOxy, forKey: .minOxy)
        try c.encode(maxOxy, forKey: .maxOxy)
        try c.encode(minDeoxy, forKey: .minDeoxy)
        try c.encode(maxDeoxy, forKey: .maxDeoxy)

        try c.encode(oxyMap, forKey: .oxyMap)
        try c.encode(deoxyMap, forKey: .deoxyMap)
    }
}
