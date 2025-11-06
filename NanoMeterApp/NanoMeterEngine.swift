import Foundation

final class NanoMeterEngine: ObservableObject {
    func ev100(aperture: Double, shutter: Double, iso: Double) -> Double {
        guard aperture > 0, shutter > 0, iso > 0 else { return 0 }
        return log2((aperture * aperture) / shutter) - log2(iso / 100.0)
    }
}
