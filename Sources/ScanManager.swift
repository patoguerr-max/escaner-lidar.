import SwiftUI
import Combine
import ARKit
import RealityKit

/// Controla la sesión de ARKit: vista previa, escaneo, parada, exportación y diagnóstico.
@MainActor
final class ScanManager: ObservableObject {

    enum Phase {
        case idle
        case scanning
        case finished
        case diagnosing
    }

    let arView: ARView
    let lidarAvailable: Bool

    @Published var phase: Phase = .idle
    @Published var meshVertices: Int = 0
    @Published var cloudPoints: Int = 0
    @Published var message: String = ""
    @Published var isExporting: Bool = false
    @Published var exportedFiles: [URL] = []
    @Published var showShare: Bool = false
    @Published var report: LidarReport?
    /// Exportar con Z vertical (Vulcan, CloudCompare, Civil 3D). Se recuerda entre usos.
    @Published var zUp: Bool {
        didSet { UserDefaults.standard.set(zUp, forKey: "zUp") }
    }

    private let processor = FrameProcessor()
    private var meshAnchors: [ARMeshAnchor] = []

    init() {
        arView = ARView(frame: .zero)
        lidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        zUp = UserDefaults.standard.object(forKey: "zUp") as? Bool ?? true
        arView.automaticallyConfigureSession = false

        // Los cuadros de la cámara se procesan en una cola propia, no en la pantalla.
        arView.session.delegate = processor
        arView.session.delegateQueue = processor.queue
        processor.onPointCount = { [weak self] count in
            self?.cloudPoints = count
        }
        processor.onReport = { [weak self] report in
            self?.report = report
        }
    }

    /// Solo cámara, sin reconstrucción: lo que se ve antes de empezar.
    func startPreview() {
        processor.setMode(.idle)
        guard ARWorldTrackingConfiguration.isSupported else {
            message = "Este dispositivo no es compatible con ARKit."
            return
        }
        arView.debugOptions.remove(.showSceneUnderstanding)
        arView.session.run(ARWorldTrackingConfiguration(),
                           options: [.resetTracking, .removeExistingAnchors])
        if lidarAvailable {
            message = "Apunta a lo que quieras escanear y pulsa Iniciar."
        } else {
            message = "Este dispositivo no tiene sensor LiDAR."
        }
    }

    func startScan() {
        guard lidarAvailable else { return }

        meshAnchors = []
        exportedFiles = []
        meshVertices = 0
        cloudPoints = 0
        processor.setMode(.scanning, resetCloud: true)

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.environmentTexturing = .none
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.session.run(config, options: [.resetTracking,
                                             .removeExistingAnchors,
                                             .resetSceneReconstruction])
        message = "Muévete despacio y recorre todas las caras."
        phase = .scanning
    }

    /// Se llama unas 2-3 veces por segundo desde la vista.
    func tick() {
        guard phase == .scanning, let frame = arView.session.currentFrame else { return }

        var total = 0
        for anchor in frame.anchors {
            if let mesh = anchor as? ARMeshAnchor {
                total += mesh.geometry.vertices.count
            }
        }
        meshVertices = total

        let hint: String
        switch frame.camera.trackingState {
        case .normal:
            hint = cloudPoints >= PointCloud.maxPoints
                ? "Nube de puntos llena. Detén y exporta."
                : "Muévete despacio y recorre todas las caras."
        case .limited:
            hint = "Seguimiento limitado (\(frame.camera.trackingState.texto)): "
                + "muévete más lento y busca mejor luz."
        case .notAvailable:
            hint = "Seguimiento no disponible."
        }
        if hint != message {
            message = hint
        }
    }

    func stopScan() {
        guard phase == .scanning else { return }
        processor.setMode(.idle)
        if let frame = arView.session.currentFrame {
            meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        }
        arView.session.pause()
        phase = .finished
        message = "Escaneo detenido. Pulsa Exportar para guardar OBJ + PLY."
    }

    func newScan() {
        processor.setMode(.idle, resetCloud: true)
        meshAnchors = []
        exportedFiles = []
        meshVertices = 0
        cloudPoints = 0
        phase = .idle
        startPreview()
    }

    func export() {
        guard !isExporting else { return }
        isExporting = true
        message = "Exportando…"

        processor.export(meshAnchors: meshAnchors, zUp: zUp) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let urls):
                self.exportedFiles = urls
                self.message = "Guardado en Archivos › En mi iPhone › Escáner LiDAR."
                self.showShare = true
            case .failure(let error):
                self.message = "Error al exportar: \(error.localizedDescription)"
            }
            self.isExporting = false
        }
    }

    // MARK: - Diagnóstico del sensor

    func startDiagnostics() {
        report = nil
        phase = .diagnosing
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            report = LidarReport.unsupported()
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)
        arView.debugOptions.remove(.showSceneUnderstanding)
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        processor.setMode(.diagnosing)
    }

    func stopDiagnostics() {
        processor.setMode(.idle)
        report = nil
        phase = .idle
        startPreview()
    }
}
