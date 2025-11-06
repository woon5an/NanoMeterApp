import SwiftUI
@main struct NanoMeterApp: App { @StateObject private var notes = NotesStore(); var body: some Scene { WindowGroup { ContentView().environmentObject(notes) } } }
