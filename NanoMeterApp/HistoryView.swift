//
//  HistoryView.swift
//  NanoMeterApp
//
//  Created by Woonsan on 2025/11/5.
//

import Photos
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var notes: NotesStore
    @Environment(\.dismiss) var dismiss
    @State private var exportResult: String?
    @State private var editingNote: ExposureNote?

    var body: some View {
        NavigationView {
            List {
                if notes.notes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("暂无笔记")
                            .font(.headline)
                        Text("回到主界面记录一条曝光笔记吧。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 48)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(notes.notes) { n in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("ƒ\(n.aperture) · \(n.shutter)s · ISO \(n.iso)")
                                .font(.headline)
                                .monospacedDigit()
                            Text(String(format: "EV100 %.2f", n.ev))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingNote = n
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingNote = n
                            } label: {
                                Label("编辑", systemImage: "square.and.pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                notes.delete(n)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                editingNote = n
                            } label: {
                                Label("编辑", systemImage: "square.and.pencil")
                            }

                            Button {
                                export(note: n)
                            } label: {
                                Label("导出到相册", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                    .onDelete(perform: notes.remove)
                }
            }
            .animation(.default, value: notes.notes)
            .navigationTitle("曝光笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let document = notes.exportCSVDocument() {
                        ShareLink(item: document, preview: SharePreview("NanoMeter 笔记", image: Image(systemName: "square.grid.3x3.fill"))) {
                            Label("分享 CSV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(notes.notes.isEmpty)
                    }
                }
            }
            .alert("导出结果", isPresented: .constant(exportResult != nil), actions: {
                Button("好的") { exportResult = nil }
            }, message: {
                Text(exportResult ?? "")
            })
            .sheet(item: $editingNote) { note in
                NoteEditSheet(note: note) { updated in
                    notes.update(note: updated)
                    editingNote = nil
                }
            }
        }
    }

    private func export(note: ExposureNote) {
        // 把笔记渲染成一张图片再保存相册
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1350))
        let img = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1350))
            let title = "Exposure Note"
            let attrs1: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            title.draw(at: CGPoint(x: 60, y: 80), withAttributes: attrs1)

            let body = """
            Date: \(note.date.formatted(date: .abbreviated, time: .standard))
            Aperture: ƒ\(note.aperture)
            Shutter: \(note.shutter)s
            ISO: \(note.iso)
            EV100: \(String(format: "%.2f", note.ev))
            """
            let attrs2: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 44, weight: .regular),
                .foregroundColor: UIColor.systemYellow
            ]
            body.draw(in: CGRect(x: 60, y: 220, width: 960, height: 1000), withAttributes: attrs2)
        }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { exportResult = "没有相册写入权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            }) { ok, err in
                DispatchQueue.main.async {
                    exportResult = ok ? "已保存到相册 ✅" : "保存失败：\(err?.localizedDescription ?? "")"
                }
            }
        }
    }
}

private struct NoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let note: ExposureNote
    let onSave: (ExposureNote) -> Void

    @State private var aperture: String
    @State private var shutter: String
    @State private var iso: String
    @State private var evText: String
    @State private var date: Date

    init(note: ExposureNote, onSave: @escaping (ExposureNote) -> Void) {
        self.note = note
        self.onSave = onSave
        _aperture = State(initialValue: note.aperture)
        _shutter = State(initialValue: note.shutter)
        _iso = State(initialValue: note.iso)
        _evText = State(initialValue: String(format: "%.2f", note.ev))
        _date = State(initialValue: note.date)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("拍摄时间") {
                    DatePicker("时间", selection: $date)
                        .datePickerStyle(.compact)
                }

                Section("曝光参数") {
                    TextField("光圈", text: $aperture)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                    TextField("快门", text: $shutter)
                        .textInputAutocapitalization(.never)
                    TextField("ISO", text: $iso)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                }

                Section("EV100") {
                    TextField("EV100", text: $evText)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                    Text("建议保留两位小数，方便与主界面读数对照。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(aperture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  shutter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  iso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = note
        let trimmedAperture = aperture.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShutter = shutter.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedISO = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.aperture = trimmedAperture.isEmpty ? note.aperture : trimmedAperture
        updated.shutter = trimmedShutter.isEmpty ? note.shutter : trimmedShutter
        updated.iso = trimmedISO.isEmpty ? note.iso : trimmedISO
        if let evValue = Double(evText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            updated.ev = evValue
        }
        updated.date = date
        onSave(updated)
        dismiss()
    }
}
