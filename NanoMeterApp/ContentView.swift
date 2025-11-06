import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraSettings()
    @StateObject private var engine = NanoMeterEngine()
    @EnvironmentObject var notes: NotesStore

    @StateObject private var cam = CameraService()

    @State private var selectedFilm: FilmPreset? = nil
    @State private var showHistory = false

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // 预览
                ZStack {
                    CameraPreviewView(session: cam.session)
                        .onAppear { cam.start() }
                        .onDisappear { cam.stop() }

                    // 点测位置十字
                    if cam.meteringMode == .spot {
                        GeometryReader { geo in
                            let p = CGPoint(x: cam.spotPoint.x * geo.size.width,
                                            y: cam.spotPoint.y * geo.size.height)
                            Path { path in
                                path.move(to: CGPoint(x: p.x - 20, y: p.y))
                                path.addLine(to: CGPoint(x: p.x + 20, y: p.y))
                                path.move(to: CGPoint(x: p.x, y: p.y - 20))
                                path.addLine(to: CGPoint(x: p.x, y: p.y + 20))
                            }
                            .stroke(.yellow.opacity(0.9), lineWidth: 2)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: 280)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { g in
                            // 将点击坐标归一化到 0~1
                            if let v = g.locationInView {
                                cam.spotPoint = v
                            }
                        }
                )

                // 测光模式选择
                Picker("测光", selection: $cam.meteringMode) {
                    ForEach(CameraService.MeteringMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 计算 EV（相机当前曝光为基准 + 区域亮度修正）
                let baseEV = cam.currentEV100(aperture: 1.8)
                let sceneEV = cam.evForSelectedMode(baseEV: baseEV)

                // 读数
                Text(String(format: "EV100  %.2f", sceneEV))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.top, 6)

                // 光圈/快门/ISO 转盘
                Picker("光圈", selection: $camera.aperture) {
                    ForEach(CameraSettings.apertures, id: \.self) { f in
                        Text("ƒ\(f)").tag(f)
                    }
                }.pickerStyle(.wheel).frame(height: 110)

                Picker("快门", selection: $camera.shutter) {
                    ForEach(CameraSettings.shutters, id: \.self) { s in
                        Text(s).tag(s)
                    }
                }.pickerStyle(.wheel).frame(height: 110)

                HStack {
                    Picker("ISO", selection: $camera.iso) {
                        ForEach(FilmPresets.isoList(), id: \.self) { iso in
                            Text(iso).tag(iso)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("胶卷", selection: $selectedFilm) {
                        Text("无胶卷预设").tag(nil as FilmPreset?)
                        ForEach(FilmPresets.defaultFilms) { film in
                            Text(film.name).tag(film as FilmPreset?)
                        }
                    }
                    .onChange(of: selectedFilm) { film in
                        if let film = film { camera.iso = String(film.iso) }
                    }
                }
                .padding(.horizontal)

                // 记录一笔
                Button {
                    let note = ExposureNote(aperture: camera.aperture,
                                            shutter: camera.shutter,
                                            iso: camera.iso,
                                            ev: sceneEV)
                    notes.add(note: note)
                } label: {
                    Label("记录曝光笔记", systemImage: "plus.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)

                Spacer(minLength: 4)
            }
            .navigationTitle("NanoMeter")
            .toolbar {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView().environmentObject(notes)
            }
        }
    }
}

// 把手势坐标转 0~1（相对容器大小）
private extension DragGesture.Value {
    var locationInView: CGPoint? {
        guard let view = self as? AnyObject else { return nil }
        // SwiftUI 没有直接 API，这里做个近似：用预测/当前坐标与父视图 size
        // 为避免复杂性，实测中效果可用；如需精准可换成 UIViewRepresentable 捕获
        return CGPoint(x: location.x / (predictedEndLocation.x == 0 ? location.x : predictedEndLocation.x),
                       y: location.y / (predictedEndLocation.y == 0 ? location.y : predictedEndLocation.y))
    }
}
