import SwiftUI
import Combine
import ARKit
import RealityKit

/// Controla la sesión de ARKit: vista previa, escaneo, parada y exportación.
@MainActor
final class ScanManager: ObservableObject {

    enum Phase {
        case idle
        case scanning
        case finished
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

    private let cloud = PointCloud()
    private var meshAnchors: [ARMeshAnchor] = []

    init() {
        arView = ARView(frame: .zero)
        lidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        arView.automaticallyConfigureSession = false
    }

    /// Solo cámara, sin reconstrucción: lo que se ve antes de empezar.
    func startPreview() {
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

        cloud.reset()
        meshAnchors = []
        exportedFiles = []
        meshVertices = 0
        cloudPoints = 0

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

        cloud.add(frame: frame)
        cloudPoints = cloud.count

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
            hint = cloud.isFull
                ? "Nube de puntos llena. Detén y exporta."
                : "Muévete despacio y recorre todas las caras."
        case .limited:
            hint = "Seguimiento limitado: muévete más lento y busca mejor luz."
        case .notAvailable:
            hint = "Seguimiento no disponible."
        }
        if hint != message {
            message = hint
        }
    }

    func stopScan() {
        guard phase == .scanning else { return }
        if let frame = arView.session.currentFrame {
            meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        }
        arView.session.pause()
        phase = .finished
        message = "Escaneo detenido. Pulsa Exportar para guardar OBJ + PLY."
    }

    func newScan() {
        cloud.reset()
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

        Task {
            // Pequeña pausa para que la interfaz alcance a mostrar "Exportando…".
            try? await Task.sleep(nanoseconds: 150_000_000)
            do {
                let urls = try Exporter.export(meshAnchors: meshAnchors, cloud: cloud)
                exportedFiles = urls
                message = "Guardado en Archivos › En mi iPhone › Escáner LiDAR."
                showShare = true
            } catch {
                message = "Error al exportar: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}
