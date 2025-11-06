//
//  HistoryView.swift
//  NanoMeterApp
//
//  Created by Woonsan on 2025/11/5.
//

import SwiftUI
import Photos

struct HistoryView: View {
    @EnvironmentObject var notes: NotesStore
    @Environment(\.dismiss) var dismiss
    @State private var exporting = false
    @State private var exportResult: String?

    var body: some View {
        NavigationView {
            List {
                ForEach(notes.notes) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(n.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("ƒ\(n.aperture) · \(n.shutter)s · ISO \(n.iso)")
                            .font(.headline)
                        Text(String(format: "EV100 %.2f", n.ev))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            export(note: n)
                        } label: {
                            Label("导出到相册", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .navigationTitle("曝光笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("导出结果", isPresented: .constant(exportResult != nil), actions: {
                Button("好的") { exportResult = nil }
            }, message: {
                Text(exportResult ?? "")
            })
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
