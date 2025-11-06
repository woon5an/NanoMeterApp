import Foundation

final class NanoMeterEngine: ObservableObject {
    struct ExposureSuggestion: Identifiable {
        let id = UUID()
        let apertureLabel: String
        let shutterLabel: String
        let isoLabel: String
        let deltaEV: Double
        let apertureValue: Double
    }

    func ev100(aperture: Double, shutter: Double, iso: Double) -> Double {
        guard aperture > 0, shutter > 0, iso > 0 else { return 0 }
        return log2((aperture * aperture) / shutter) - log2(iso / 100.0)
    }

    func equivalentExposures(ev100: Double, isoString: String) -> [ExposureSuggestion] {
        guard ev100.isFinite, let iso = Double(isoString), iso > 0 else { return [] }

        let shutterOptions = NanoMeterEngine.shutterOptions
        guard !shutterOptions.isEmpty else { return [] }

        let powFactor = pow(2.0, ev100) * (iso / 100.0)

        let suggestions: [ExposureSuggestion] = CameraSettings.apertures.compactMap { apertureString in
            guard let aperture = Double(apertureString) else { return nil }

            let targetShutterSeconds = (aperture * aperture) / powFactor
            guard let closest = NanoMeterEngine.closestShutter(to: targetShutterSeconds, from: shutterOptions) else {
                return nil
            }

            let comboEV = ev100(aperture: aperture, shutter: closest.seconds, iso: iso)
            let delta = comboEV - ev100

            return ExposureSuggestion(apertureLabel: "ƒ\(apertureString)",
                                      shutterLabel: closest.label,
                                      isoLabel: "ISO \(isoString)",
                                      deltaEV: delta,
                                      apertureValue: aperture)
        }

        return suggestions
            .filter { abs($0.deltaEV) <= 1.0 }
            .sorted { lhs, rhs in
                if lhs.apertureValue == rhs.apertureValue {
                    return abs(lhs.deltaEV) < abs(rhs.deltaEV)
                }
                return lhs.apertureValue < rhs.apertureValue
            }
    }

    private static func seconds(from shutterString: String) -> Double? {
        if shutterString.contains("/") {
            let parts = shutterString.split(separator: "/")
            if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
                return numerator / denominator
            }
        } else if let value = Double(shutterString) {
            return value
        }
        return nil
    }

    private static func closestShutter(to seconds: Double, from options: [(label: String, seconds: Double)]) -> (label: String, seconds: Double)? {
        options.min { lhs, rhs in
            abs(lhs.seconds - seconds) < abs(rhs.seconds - seconds)
        }
    }

    private static let shutterOptions: [(label: String, seconds: Double)] = CameraSettings.shutters.compactMap { value in
        guard let secs = NanoMeterEngine.seconds(from: value) else { return nil }
        return (label: value, seconds: secs)
    }
}
