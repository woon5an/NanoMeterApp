import Foundation
final class NotesStore:ObservableObject{ @Published var notes:[ExposureNote]=[]; func add(note:ExposureNote){ notes.append(note) } }