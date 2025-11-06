import Foundation

struct FilmPreset: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let iso: Int
}

enum FilmPresets {
    static let defaultFilms: [FilmPreset] = [
        .init(name: "Kodak Portra 400", iso: 400),
        .init(name: "Kodak Gold 200", iso: 200),
        .init(name: "ILFORD HP5+", iso: 400),
        .init(name: "ILFORD Delta 100", iso: 100),
        .init(name: "Manual ISO", iso: 100)
    ]

    static func isoList() -> [String] { ["25","50","100","200","400","800","1600","3200"] }

    static func match(iso: String) -> FilmPreset? {
        guard let v = Int(iso) else { return nil }
        return defaultFilms.first { $0.iso == v }
    }
}

