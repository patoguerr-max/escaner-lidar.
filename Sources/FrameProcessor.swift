import Foundation
import ARKit

/// Recibe los cuadros de ARKit en una cola propia (fuera del hilo principal) y
/// alimenta la nube de puntos o el diagnóstico del sensor, según el modo.
final class FrameProcessor: NSObject, ARSessionDelegate {

    enum Mode {
        case idle
        case scanning
        case diagnosing
    }

    let queue = DispatchQueue(label: "cl.escaner.lidar.frames", qos: .userInitiated)

    /// Se llaman en el hilo principal.
    var onPointCount: ((Int) -> Void)?
    var onReport: ((LidarReport) -> Void)?

    // Solo se tocan dentro de `queue`.
    private let cloud = PointCloud()
    private let diagnostics = LidarDiagnostics()
    private var mode: Mode = .idle
    private var frameNumber = 0

    func setMode(_ newMode: Mode, resetCloud: Bool = false) {
        queue.async {
            if resetCloud {
                self.cloud.reset()
            }
            self.diagnostics.reset()
            self.frameNumber = 0
            self.mode = newMode
            let count = self.cloud.count
            DispatchQueue.main.async { self.onPointCount?(count) }
        }
    }

    /// Escribe los archivos en segundo plano para no congelar la pantalla.
    func export(meshAnchors: [ARMeshAnchor], zUp: Bool,
                completion: @escaping (Result<[URL], Error>) -> Void) {
        queue.async {
            let result = Result {
                try Exporter.export(meshAnchors: meshAnchors, cloud: self.cloud, zUp: zUp)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameNumber += 1
        switch mode {
        case .idle:
            break
        case .scanning:
            // 1 de cada 2 cuadros: unas 30 lecturas por segundo.
            guard frameNumber % 2 == 0, !cloud.isFull else { return }
            cloud.add(frame: frame)
            if frameNumber % 10 == 0 {
                let count = cloud.count
                DispatchQueue.main.async { self.onPointCount?(count) }
            }
        case .diagnosing:
            diagnostics.count(frame)
            if frameNumber % 15 == 0, let report = diagnostics.analyze(frame) {
                DispatchQueue.main.async { self.onReport?(report) }
            }
        }
    }
}
