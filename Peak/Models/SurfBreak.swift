import CoreLocation
import Foundation

/// One popular surf break from the bundled catalog, used to autocomplete the Add Spot flow.
struct SurfBreak: Decodable, Identifiable, Hashable {
    let name: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(name)|\(region)|\(country)" }

    /// Human label for the spot location field, e.g. "San Clemente, California, USA".
    var locationLabel: String {
        [region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension SurfBreak {
    // Kept computed (CLLocationCoordinate2D isn't Hashable), mirroring Spot+Location.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
