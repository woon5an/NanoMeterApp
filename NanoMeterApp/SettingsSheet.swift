import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var cameraService: CameraService
    @Environment(\.dismiss) private var dismiss

    @State private var customApertureText: String
    @State private var showCalibrationToast = false

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        _customApertureText = State(initialValue: cameraService.customApertureValue.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("主摄光圈") {
                    HStack {
                        Label("当前生效", systemImage: "camera.aperture")
                        Spacer()
                        Text(String(format: "ƒ%.2f", cameraService.effectiveAperture))
                            .font(.headline)
                    }

                    if let detected = cameraService.detectedApertureValue {
                        HStack {
                            Text("机型原生光圈")
                            Spacer()
                            Text(String(format: "ƒ%.2f", detected))
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("自定义光圈，例如 1.9", text: $customApertureText)
                        .keyboardType(.decimalPad)

                    HStack {
                        Button("应用自定义") {
                            applyCustomAperture()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("恢复默认") {
                            cameraService.setCustomAperture(nil)
                            customApertureText = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("矩阵热力图") {
                    Toggle("显示热力矩阵叠加", isOn: $cameraService.isHeatmapEnabled)
                    Text("默认关闭。开启后会在取景器上叠加 5x5 亮度热力可视化。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("亮度→EV 灰卡校准") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("将镜头对准 18% 灰卡，保持当前测光模式 \(cameraService.meteringMode.rawValue)，然后点击下方按钮。")
                            .font(.footnote)
                        Button {
                            cameraService.calibrateGreyCard(using: cameraService.meteringMode)
                            showCalibrationToast = true
                        } label: {
                            Label("立即校准", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)

                        if let constant = cameraService.calibrationConstant {
                            Text("当前 K 系数：\(String(format: "%.2f", constant))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("尚未校准，使用默认相对测光计算。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("清除校准") {
                            cameraService.clearCalibration()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("高级设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if showCalibrationToast {
                    ToastView(message: "灰卡校准完成")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showCalibrationToast = false }
                            }
                        }
                }
            }
        }
    }

    private func applyCustomAperture() {
        guard let value = Double(customApertureText), value > 0 else { return }
        cameraService.setCustomAperture(value)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 24)
            .shadow(radius: 6)
    }
}
