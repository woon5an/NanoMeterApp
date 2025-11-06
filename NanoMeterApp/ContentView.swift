import SwiftUI

private enum ExposureMode: String, CaseIterable, Identifiable {
    case table
    case manual

    var id: ExposureMode { self }

    var title: String {
        switch self {
        case .table:
            return "参考组合"
        case .manual:
            return "手动调节"
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraSettings()
    @StateObject private var engine = NanoMeterEngine()
    @EnvironmentObject var notes: NotesStore

    @StateObject private var cameraService = CameraService()

    @State private var selectedFilm: FilmPreset? = nil
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var previewSize: CGSize = .zero
    @State private var exposureMode: ExposureMode = .table

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [.black, .gray.opacity(0.25), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        previewCard

                        meteringControls

                        exposureReadout

                        controlsCard

                        recordButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("NanoMeter")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }

                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView().environmentObject(notes)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(cameraService: cameraService)
            }
        }
    }

    private var previewCard: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                CameraPreviewView(session: cameraService.session)
                    .onAppear { cameraService.start() }
                    .onDisappear { cameraService.stop() }
                    .overlay(heatmapOverlay)
                    .overlay(spotOverlay)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: PreviewSizeKey.self, value: proxy.size)
                    })
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let point = value.location
                        guard previewSize.width > 0, previewSize.height > 0 else { return }
                        let norm = CGPoint(x: min(max(point.x / previewSize.width, 0), 1),
                                           y: min(max(point.y / previewSize.height, 0), 1))
                        cameraService.spotPoint = norm
                    }
            )

            VStack(alignment: .leading, spacing: 6) {
                Label("ƒ\(String(format: "%.2f", cameraService.effectiveAperture))", systemImage: "camera.aperture")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())

                if cameraService.calibrationConstant != nil {
                    Label("灰卡校准已启用", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                }
            }
            .padding(14)
        }
        .onPreferenceChange(PreviewSizeKey.self) { newSize in
            previewSize = newSize
        }
    }

    private var meteringControls: some View {
        GroupBox {
            VStack(spacing: 12) {
                Picker("测光模式", selection: $cameraService.meteringMode) {
                    ForEach(CameraService.MeteringMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Text("当前模式：\(cameraService.meteringMode.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        } label: {
            Label("测光", systemImage: "light.min")
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }

    private var exposureReadout: some View {
        let baseEV = cameraService.currentEV100()
        let sceneEV = cameraService.evForSelectedMode(baseEV: baseEV)
        let shutterValue = camera.shutterSeconds
        let evForSettings = engine.ev100(aperture: camera.apertureValue,
                                         shutter: shutterValue,
                                         iso: Double(camera.iso) ?? 100)

        return GroupBox {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("实测 EV100")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(String(format: "%.2f", sceneEV))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(String(format: "基准 %.2f", baseEV), systemImage: "camera.metering.center")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(String(format: "设置 EV %.2f", evForSettings), systemImage: "dial.max")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: min(max(sceneEV / 15.0, 0), 1)) {
                    Text("EV100 范围预估")
                }
                .tint(.orange)
                .progressViewStyle(.linear)
            }
            .padding(.top, 6)
        } label: {
            Label("曝光读数", systemImage: "sun.max")
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }

    private var controlsCard: some View {
        let baseEV = cameraService.currentEV100()
        let sceneEV = cameraService.evForSelectedMode(baseEV: baseEV)
        let suggestions = engine.equivalentExposures(sceneEV: sceneEV, isoString: camera.iso)

        return GroupBox {
            VStack(spacing: 16) {
                Picker("模式", selection: $exposureMode) {
                    ForEach(ExposureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch exposureMode {
                case .manual:
                    manualControls
                case .table:
                    ExposureSuggestionTable(sceneEV: sceneEV, suggestions: suggestions)
                }

                isoSelection
            }
            .padding(.top, 6)
        } label: {
            Label("参数设定", systemImage: "dial.low")
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }

    private var manualControls: some View {
        VStack(spacing: 16) {
            Picker("光圈", selection: $camera.aperture) {
                ForEach(CameraSettings.apertures, id: \.self) { f in
                    Text("ƒ\(f)").tag(f)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)

            Picker("快门", selection: $camera.shutter) {
                ForEach(CameraSettings.shutters, id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
        }
    }

    private var isoSelection: some View {
        VStack(spacing: 12) {
            Picker("ISO", selection: $camera.iso) {
                ForEach(FilmPresets.isoList(), id: \.self) { iso in
                    Text(iso).tag(iso)
                }
            }
            .pickerStyle(.segmented)

            Picker("胶卷预设", selection: $selectedFilm) {
                Text("手动").tag(nil as FilmPreset?)
                ForEach(FilmPresets.defaultFilms) { film in
                    Text(film.name).tag(film as FilmPreset?)
                }
            }
            .onChange(of: selectedFilm) { film in
                if let film = film { camera.iso = String(film.iso) }
            }
        }
    }

    private var recordButton: some View {
        let baseEV = cameraService.currentEV100()
        let sceneEV = cameraService.evForSelectedMode(baseEV: baseEV)
        return Button {
            let note = ExposureNote(aperture: camera.aperture,
                                    shutter: camera.shutter,
                                    iso: camera.iso,
                                    ev: sceneEV)
            notes.add(note: note)
        } label: {
            Label("记录曝光笔记", systemImage: "plus.viewfinder")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
    }

    private var heatmapOverlay: some View {
        Group {
            if cameraService.isHeatmapEnabled {
                GeometryReader { geo in
                    let rows = cameraService.heatmapCells.count
                    let cols = cameraService.heatmapCells.first?.count ?? 0
                    if rows > 0, cols > 0 {
                        ForEach(0..<rows, id: \.self) { r in
                            ForEach(0..<cols, id: \.self) { c in
                                let cellWidth = geo.size.width / CGFloat(cols)
                                let cellHeight = geo.size.height / CGFloat(rows)
                                Rectangle()
                                    .fill(heatColor(for: cameraService.heatmapCells[r][c]).opacity(0.35))
                                    .frame(width: cellWidth, height: cellHeight)
                                    .position(x: (CGFloat(c) + 0.5) * cellWidth,
                                              y: (CGFloat(r) + 0.5) * cellHeight)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var spotOverlay: some View {
        Group {
            if cameraService.meteringMode == .spot {
                GeometryReader { geo in
                    let p = CGPoint(x: cameraService.spotPoint.x * geo.size.width,
                                    y: cameraService.spotPoint.y * geo.size.height)
                    Path { path in
                        path.move(to: CGPoint(x: p.x - 24, y: p.y))
                        path.addLine(to: CGPoint(x: p.x + 24, y: p.y))
                        path.move(to: CGPoint(x: p.x, y: p.y - 24))
                        path.addLine(to: CGPoint(x: p.x, y: p.y + 24))
                    }
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func heatColor(for value: CGFloat) -> Color {
        let clamped = min(max(Double(value), 0.0), 1.0)
        let hue = (1.0 - clamped) * 0.6 // 蓝 -> 黄 -> 红
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }
}

private struct ExposureSuggestionTable: View {
    let sceneEV: Double
    let suggestions: [NanoMeterEngine.ExposureSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基于当前实测 EV100 \(String(format: "%.2f", sceneEV)) 计算")
                .font(.caption)
                .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                Text("暂无可用的标准组合，请调整 ISO 或重新测光。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        HStack(spacing: 12) {
                            Text(suggestion.apertureLabel)
                                .font(.system(.body, design: .rounded))
                                .monospacedDigit()

                            Spacer(minLength: 12)

                            Text(suggestion.shutterLabel)
                                .font(.system(.body, design: .rounded))
                                .monospacedDigit()

                            Spacer(minLength: 12)

                            Text(suggestion.isoLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            Text(String(format: "%+.2f EV", suggestion.deltaEV))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(deltaColor(for: suggestion.deltaEV))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: suggestions.count)
    }

    private func deltaColor(for delta: Double) -> Color {
        let absDelta = abs(delta)
        switch absDelta {
        case 0..<0.15:
            return .green
        case 0.15..<0.35:
            return .yellow
        default:
            return .orange
        }
    }
}

private struct PreviewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.subheadline)
                .foregroundStyle(.secondary)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
