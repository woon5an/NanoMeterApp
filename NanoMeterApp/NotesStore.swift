import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct NotesCSVDocument: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            document.data
        }
        .suggestedFileName { document in
            document.filename
        }
    }
}

final class NotesStore: ObservableObject {
    @Published var notes: [ExposureNote] {
        didSet { save() }
    }

    private let storageKey = "nano.notes"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ExposureNote].self, from: data) {
            notes = decoded
        } else {
            notes = []
        }
    }

    func add(note: ExposureNote) {
        notes.append(note)
    }

    func remove(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
    }

    func delete(_ note: ExposureNote) {
        notes.removeAll { $0.id == note.id }
    }

    func update(note: ExposureNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
    }

    func exportCSVDocument() -> NotesCSVDocument? {
        guard !notes.isEmpty else { return nil }
        var rows = ["Date,Aperture,Shutter,ISO,EV100,Latitude,Longitude"]
        let formatter = ISO8601DateFormatter()
        for note in notes {
            let cols: [String] = [
                formatter.string(from: note.date),
                note.aperture,
                note.shutter,
                note.iso,
                String(format: "%.2f", note.ev),
                note.latitude.map { String($0) } ?? "",
                note.longitude.map { String($0) } ?? ""
            ]
            rows.append(cols.joined(separator: ","))
        }
        let content = rows.joined(separator: "\n")
        guard let data = content.data(using: .utf8) else { return nil }
        return NotesCSVDocument(data: data, filename: "NanoMeterNotes.csv")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
