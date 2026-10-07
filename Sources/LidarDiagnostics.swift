import Foundation
import ARKit
import UIKit

/// Resultado de una lectura del diagnóstico del sensor.
struct LidarReport {
    enum Status {
        case ok
        case warning
        case failure
    }

    var status: Status = .ok
    var issues: [String] = []
    var depthSize = "—"
    var depthRate: Double = 0
    var validPercent: Double = 0
    var highPercent: Double = 0
    var mediumPercent: Double = 0
    var lowPercent: Double = 0
    var centerDistance: Float?
    var nearDistance: Float?
    var farDistance: Float?
    var tracking = "—"
    var light: Double?
    var thermal = "—"
    /// Mapa de profundidad en colores (rojo cerca, azul lejos), ya girado a vertical.
    var image: UIImage?

    static func unsupported() -> LidarReport {
        var report = LidarReport()
        report.status = .failure
        report.issues = ["Este dispositivo no entrega datos del sensor LiDAR a las apps. "
                         + "Debe ser un iPhone Pro con LiDAR y iOS 17 o superior."]
        return report
    }
}

/// Mide lo que entrega el LiDAR: lecturas por segundo, confianza, distancias y temperatura.
final class LidarDiagnostics {

    private var timestamps: [TimeInterval] = []
    private var framesSeen = 0

    func reset() {
        timestamps.removeAll()
        framesSeen = 0
    }

    func count(_ frame: ARFrame) {
        framesSeen += 1
        guard frame.sceneDepth != nil else { return }
        timestamps.append(frame.timestamp)
        let cutoff = frame.timestamp - 2
        timestamps.removeAll { $0 < cutoff }
    }

    private var depthRate: Double {
        guard timestamps.count > 1,
              let first = timestamps.first,
              let last = timestamps.last,
              last > first else { return 0 }
        return Double(timestamps.count - 1) / (last - first)
    }

    /// Devuelve nil si todavía no hay datos suficientes para opinar.
    func analyze(_ frame: ARFrame) -> LidarReport? {
        var report = LidarReport()
        report.depthRate = depthRate
        report.tracking = frame.camera.trackingState.texto
        if let estimate = frame.lightEstimate {
            report.light = Double(estimate.ambientIntensity)
        }
        let thermalState = ProcessInfo.processInfo.thermalState
        report.thermal = LidarDiagnostics.text(for: thermalState)

        var failures: [String] = []
        var warnings: [String] = []

        let hasDepth = frame.sceneDepth != nil
        if let sceneDepth = frame.sceneDepth {
            measure(sceneDepth, into: &report)
        } else if framesSeen > 90 && depthRate == 0 {
            failures.append("El sensor no está entregando profundidad. Reinicia el iPhone y vuelve a probar.")
        } else {
            return nil
        }

        if report.depthRate > 0 && report.depthRate < 15 {
            warnings.append(String(format: "Pocas lecturas por segundo (%.0f/s). "
                                   + "Cierra otras apps o deja enfriar el iPhone.", report.depthRate))
        }
        if hasDepth {
            if report.validPercent < 10 || (report.highPercent < 5 && report.lowPercent > 80) {
                failures.append("Casi no hay lecturas confiables. Revisa que nada tape el sensor "
                                + "(funda, dedo, protector, suciedad) y apunta a una pared a 1 m. "
                                + "Si sigue igual, el sensor puede tener una falla.")
            } else {
                if report.validPercent < 60 {
                    warnings.append("Muchos puntos sin lectura: apunta a una superficie entre 0,3 y 4 m.")
                }
                if report.highPercent < 30 {
                    warnings.append("Poca confianza alta: superficie difícil (vidrio, negro, brillante), "
                                    + "algo muy lejos o el sensor sucio. Limpia el círculo negro "
                                    + "junto a las cámaras.")
                }
            }
            if report.centerDistance == nil {
                warnings.append("Sin lectura en el centro (+): apunta a una superficie mate entre 0,3 y 4 m.")
            }
        }
        if case .normal = frame.camera.trackingState {
            // Todo bien.
        } else {
            warnings.append("Seguimiento: \(report.tracking). Muévete más lento y busca detalles "
                            + "y buena luz (esto afecta la malla, no al sensor).")
        }
        if let light = report.light, light < 250 {
            warnings.append("Poca luz: el seguimiento de posición necesita ver bien "
                            + "(el LiDAR sí mide a oscuras).")
        }
        if thermalState == .serious || thermalState == .critical {
            warnings.append("El iPhone está caliente: iOS reduce el rendimiento del sensor. Déjalo enfriar.")
        }

        report.issues = failures + warnings
        if !failures.isEmpty {
            report.status = .failure
        } else if !warnings.isEmpty {
            report.status = .warning
        }
        return report
    }

    private func measure(_ sceneDepth: ARDepthData, into report: inout LidarReport) {
        let depthMap = sceneDepth.depthMap
        let confidenceMap = sceneDepth.confidenceMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        report.depthSize = "\(width) × \(height)"

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard width > 0, height > 0,
              let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap)
        let confBase = confidenceMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var values: [Float] = []
        values.reserveCapacity(width * height)
        var centerValues: [Float] = []
        var high = 0
        var medium = 0
        var low = 0
        let cx = width / 2
        let cy = height / 2

        for v in 0..<height {
            let row = depthBase.advanced(by: v * depthStride).assumingMemoryBound(to: Float32.self)
            let confRow = confBase?.advanced(by: v * confStride).assumingMemoryBound(to: UInt8.self)
            for u in 0..<width {
                let o = (v * width + u) * 4
                rgba[o + 3] = 255
                // Confianza: 0 baja, 1 media, 2 alta.
                let confidence = confRow?[u] ?? 2
                switch confidence {
                case 0: low += 1
                case 1: medium += 1
                default: high += 1
                }

                let d = row[u]
                guard d.isFinite, d > 0 else { continue }
                values.append(d)
                if confidence >= 1, abs(u - cx) <= 2, abs(v - cy) <= 2 {
                    centerValues.append(d)
                }

                // Rojo cerca, azul lejos; más oscuro cuanto menor la confianza.
                let color = LidarDiagnostics.color(depth: d)
                let shade: Float = confidence >= 2 ? 1 : (confidence == 1 ? 0.55 : 0.2)
                rgba[o] = UInt8(color.0 * shade * 255)
                rgba[o + 1] = UInt8(color.1 * shade * 255)
                rgba[o + 2] = UInt8(color.2 * shade * 255)
            }
        }

        let total = Double(width * height)
        report.validPercent = Double(values.count) / total * 100
        report.highPercent = Double(high) / total * 100
        report.mediumPercent = Double(medium) / total * 100
        report.lowPercent = Double(low) / total * 100

        if !values.isEmpty {
            values.sort()
            report.nearDistance = values[values.count * 5 / 100]
            report.farDistance = values[min(values.count - 1, values.count * 95 / 100)]
        }
        if !centerValues.isEmpty {
            centerValues.sort()
            report.centerDistance = centerValues[centerValues.count / 2]
        }
        report.image = LidarDiagnostics.image(rgba: rgba, width: width, height: height)
    }

    /// 0,2 m rojo → 5 m azul.
    private static func color(depth: Float) -> (Float, Float, Float) {
        let t = max(0, min(1, (depth - 0.2) / 4.8))
        let hue = t * 240
        let x = 1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1)
        switch hue {
        case ..<60: return (1, x, 0)
        case ..<120: return (x, 1, 0)
        case ..<180: return (0, 1, x)
        default: return (0, x, 1)
        }
    }

    private static func image(rgba: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(width: width, height: height,
                                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        // El sensor entrega la imagen apaisada; .right la deja vertical.
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    private static func text(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Tibio"
        case .serious: return "Caliente"
        case .critical: return "Muy caliente"
        @unknown default: return "—"
        }
    }
}

extension ARCamera.TrackingState {
    var texto: String {
        switch self {
        case .normal:
            return "Normal"
        case .notAvailable:
            return "No disponible"
        case .limited(let reason):
            switch reason {
            case .initializing: return "Iniciando"
            case .excessiveMotion: return "Movimiento excesivo"
            case .insufficientFeatures: return "Pocos detalles visibles"
            case .relocalizing: return "Relocalizando"
            @unknown default: return "Limitado"
            }
        }
    }
}
