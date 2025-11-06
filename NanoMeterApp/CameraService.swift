//
//  CameraService.swift
//  NanoMeterApp
//
//  Created by Woonsan on 2025/11/5.
//

import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

final class CameraService: NSObject, ObservableObject {
    enum MeteringMode: String, CaseIterable, Identifiable {
        case matrix = "矩阵测光"
        case centerWeighted = "中加权"
        case spot = "点测"
        var id: String { rawValue }
    }

    // 输出：给 UI 使用
    @Published var averageLuma: CGFloat = 0.5           // 全画面平均亮度 0~1
    @Published var matrixLuma: CGFloat = 0.5            // 矩阵中值亮度
    @Published var centerWeightedLuma: CGFloat = 0.5    // 中加权亮度
    @Published var spotLuma: CGFloat = 0.5              // 点测亮度（受 spotPoint 影响）
    @Published var exposureDuration: Double = 1/120.0   // 当前相机曝光时间（秒）
    @Published var exposureISO: Float = 100.0           // 当前相机 ISO
    @Published var meteringMode: MeteringMode = .matrix
    @Published var spotPoint: CGPoint = CGPoint(x: 0.5, y: 0.5) // 0~1 归一化坐标

    // 会话与输出
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?

    // 画面分区参数
    private let grid = (rows: 5, cols: 5) // 矩阵 5x5

    override init() {
        super.init()
    }

    func start() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { print("No camera"); return }
        self.device = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.sample.buffer"))
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            if let conn = videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }

            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()

            session.commitConfiguration()
            session.startRunning()
        } catch {
            print("Camera error:", error)
        }
    }

    func stop() {
        session.stopRunning()
    }

    // 计算 EV100：由相机当前曝光（固定光圈）估计场景 EV
    // iPhone 主摄光圈（示例）：f/1.78 ~ f/1.8，不同机型略有差异；可做成设置项
    func currentEV100(aperture: Double = 1.8) -> Double {
        let t = max(exposureDuration, 1e-6)
        let S = max(Double(exposureISO), 1.0)
        return log2((aperture * aperture) / t) - log2(S / 100.0)
    }

    // 基于亮度的相对 EV 修正（把不同测光模式的亮度与全画面平均的亮度对比）
    func evForSelectedMode(baseEV: Double) -> Double {
        let ref = max(Double(averageLuma), 1e-6)
        let luma: Double
        switch meteringMode {
        case .matrix:         luma = Double(matrixLuma)
        case .centerWeighted: luma = Double(centerWeightedLuma)
        case .spot:           luma = Double(spotLuma)
        }
        // 简单线性近似：EV += log2(luma / ref)
        return baseEV + log2(max(luma, 1e-6) / ref)
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 更新曝光参数
        if let d = device {
            let exposureTime = d.exposureDuration
            DispatchQueue.main.async {
                self.exposureDuration = Double(exposureTime.seconds)
                self.exposureISO = d.iso
            }
        }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        
        // 获取 Y 平面
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        let pixelRowStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0) // 修改名字为 pixelRowStride

        // 采样网格
        let stepX = max(1, width / 80)   // 采样网格
        let stepY = max(1, height / 80)

        var samples: [UInt8] = []
        samples.reserveCapacity((width / stepX) * (height / stepY))

        // 采样过程
        for y in stride(from: 0, to: height, by: stepY) {
            let row = base.advanced(by: y * pixelRowStride)  // 使用 pixelRowStride 代替 lineStride

            for x in stride(from: 0, to: width, by: stepX) {
                let v = row.load(fromByteOffset: x, as: UInt8.self)
                samples.append(v)
            }
        }

        if samples.isEmpty { return }
        let avg = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count) / 255.0


        // 矩阵中值（5x5）
        func gridLumaMedian(rows: Int, cols: Int) -> CGFloat {
            var cellMeans: [Double] = []
            cellMeans.reserveCapacity(rows*cols)
            let cellW = max(1, width / cols)
            let cellH = max(1, height / rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let xmin = c * cellW
                    let ymin = r * cellH
                    let xmax = min(width, xmin + cellW)
                    let ymax = min(height, ymin + cellH)
                    var sum = 0.0
                    var cnt = 0
                    var y = ymin
                    while y < ymax {
                        let row = base.advanced(by: y * pixelRowStride)
                        var x = xmin
                        while x < xmax {
                            let v = row.load(fromByteOffset: x, as: UInt8.self)
                            sum += Double(v)
                            cnt += 1
                            x += stepX
                        }
                        y += stepY
                    }
                    if cnt > 0 { cellMeans.append(sum / Double(cnt) / 255.0) }
                }
            }
            guard !cellMeans.isEmpty else { return CGFloat(avg) }
            cellMeans.sort()
            return CGFloat(cellMeans[cellMeans.count/2])
        }

        // 中加权（中心区域权重大）
        func centerWeighted() -> CGFloat {
            let cx = width/2, cy = height/2
            let radius = min(width, height) / 4
            var sumC = 0.0, cntC = 0
            var sumO = 0.0, cntO = 0
            for y in stride(from: 0, to: height, by: stepY) {
                let row = base.advanced(by: y * pixelRowStride)
                for x in stride(from: 0, to: width, by: stepX) {
                    let v = Double(row.load(fromByteOffset: x, as: UInt8.self)) / 255.0
                    let dx = x - cx, dy = y - cy
                    if (dx*dx + dy*dy) <= radius*radius {
                        sumC += v; cntC += 1
                    } else {
                        sumO += v; cntO += 1
                    }
                }
            }
            let c = cntC > 0 ? sumC / Double(cntC) : avg
            let o = cntO > 0 ? sumO / Double(cntO) : avg
            return CGFloat(0.7 * c + 0.3 * o)
        }

        // 点测（取 spotPoint 附近一个小方块）
        func spot(at p: CGPoint) -> CGFloat {
            let px = Int(p.x * CGFloat(width))
            let py = Int(p.y * CGFloat(height))
            let half = max(4, min(width, height) / 30)
            let xmin = max(0, px - half), xmax = min(width, px + half)
            let ymin = max(0, py - half), ymax = min(height, py + half)
            var sum = 0.0, cnt = 0
            var y = ymin
            while y < ymax {
                let row = base.advanced(by: y * pixelRowStride)
                var x = xmin
                while x < xmax {
                    let v = row.load(fromByteOffset: x, as: UInt8.self)
                    sum += Double(v); cnt += 1
                    x += max(1, half/6)
                }
                y += max(1, half/6)
            }
            return cnt > 0 ? CGFloat(sum / Double(cnt) / 255.0) : CGFloat(avg)
        }

        let matrix = gridLumaMedian(rows: grid.rows, cols: grid.cols)
        let centerW = centerWeighted()
        let spot = spot(at: spotPoint)

        DispatchQueue.main.async {
            self.averageLuma = CGFloat(avg)
            self.matrixLuma = matrix
            self.centerWeightedLuma = centerW
            self.spotLuma = spot
        }
    }
}
