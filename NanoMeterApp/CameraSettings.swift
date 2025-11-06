import Foundation

final class CameraSettings: ObservableObject {
    static let apertures: [String] = ["1.4","2","2.8","4","5.6","8","11","16","22"]
    static let shutters: [String] = [
        "1/8000","1/4000","1/2000","1/1000","1/500","1/250","1/125","1/60","1/30",
        "1/15","1/8","1/4","1/2","1","2","4","8","15","30"
    ]

    @Published var aperture: String = "8"       // 显示给 UI 的字符串
    @Published var shutter: String = "1/125"
    @Published var iso: String = "400"

    /// 便捷：把 "8" / "2.8" 转成 Double
    var apertureValue: Double {
        Double(aperture) ?? 8.0
    }

    /// 便捷：把 "1/125" 或 "2" 转成秒
    var shutterSeconds: Double {
        if shutter.contains("/") {
            let parts = shutter.split(separator: "/")
            if parts.count == 2, let denom = Double(parts[1]) { return 1.0 / denom }
        }
        return Double(shutter) ?? 1.0
    }
}

