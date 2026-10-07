import Foundation
import ARKit
import CoreVideo
import simd

/// Celda de 1 cm usada para no guardar el mismo punto muchas veces.
struct VoxelKey: Hashable {
    let x: Int32
    let y: Int32
    let z: Int32
}

/// Nube de puntos a color: profundidad del LiDAR + color de la cámara.
final class PointCloud {

    /// x, y, z consecutivos (metros, coordenadas de mundo de ARKit, eje Y vertical).
    private var xyz: [Float] = []
    /// r, g, b consecutivos.
    private var rgb: [UInt8] = []
    private var voxels = Set<VoxelKey>()

    private let voxelSize: Float = 0.01
    private let maxPoints = 2_000_000
    private let minDepth: Float = 0.15
    private let maxDepth: Float = 5.0
    /// Se usa 1 de cada `step` píxeles del mapa de profundidad en cada eje.
    private let step = 2

    var count: Int {
        rgb.count / 3
    }

    var isFull: Bool {
        count >= maxPoints
    }

    func reset() {
        xyz.removeAll()
        rgb.removeAll()
        voxels.removeAll()
    }

    func add(frame: ARFrame) {
        guard !isFull,
              let sceneDepth = frame.sceneDepth,
              let confidenceMap = sceneDepth.confidenceMap else { return }

        let depthMap = sceneDepth.depthMap
        let image = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(image) >= 2 else { return }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confBase = CVPixelBufferGetBaseAddress(confidenceMap),
              let lumaBase = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(image, 1) else { return }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap)
        let confStride = CVPixelBufferGetBytesPerRow(confidenceMap)

        let imageWidth = CVPixelBufferGetWidthOfPlane(image, 0)
        let imageHeight = CVPixelBufferGetHeightOfPlane(image, 0)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(image, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(image, 1)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(image, 1)

        guard depthWidth > 0, depthHeight > 0, imageWidth > 0, imageHeight > 0,
              chromaWidth > 0, chromaHeight > 0 else { return }

        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)

        // Los intrínsecos vienen para la resolución de la foto; se escalan al mapa de profundidad.
        let scaleX = Float(imageWidth) / Float(depthWidth)
        let scaleY = Float(imageHeight) / Float(depthHeight)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x / scaleX
        let fy = intrinsics.columns.1.y / scaleY
        let cx = intrinsics.columns.2.x / scaleX
        let cy = intrinsics.columns.2.y / scaleY
        guard fx > 0, fy > 0 else { return }

        let cameraToWorld = frame.camera.transform

        var v = 0
        while v < depthHeight {
            let depthRow = depthBase.advanced(by: v * depthStride)
                .assumingMemoryBound(to: Float32.self)
            let confRow = confBase.advanced(by: v * confStride)
                .assumingMemoryBound(to: UInt8.self)

            var u = 0
            while u < depthWidth {
                let d = depthRow[u]
                // Confianza: 0 baja, 1 media, 2 alta. Solo se guardan los puntos de confianza alta.
                if confRow[u] >= 2, d.isFinite, d > minDepth, d < maxDepth {
                    let xCam = (Float(u) - cx) * d / fx
                    let yCam = (Float(v) - cy) * d / fy
                    // Cámara de ARKit: +X derecha, +Y arriba, mira hacia -Z.
                    let world = cameraToWorld * SIMD4<Float>(xCam, -yCam, -d, 1)

                    if world.x.isFinite, world.y.isFinite, world.z.isFinite {
                        let key = VoxelKey(
                            x: Int32((world.x / voxelSize).rounded(.down)),
                            y: Int32((world.y / voxelSize).rounded(.down)),
                            z: Int32((world.z / voxelSize).rounded(.down))
                        )
                        if voxels.insert(key).inserted {
                            let px = min(imageWidth - 1, Int(Float(u) * scaleX))
                            let py = min(imageHeight - 1, Int(Float(v) * scaleY))
                            let cpx = min(chromaWidth - 1, px / 2)
                            let cpy = min(chromaHeight - 1, py / 2)

                            let yValue = Float(luma[py * lumaStride + px])
                            let cb = Float(chroma[cpy * chromaStride + cpx * 2]) - 128
                            let cr = Float(chroma[cpy * chromaStride + cpx * 2 + 1]) - 128

                            xyz.append(world.x)
                            xyz.append(world.y)
                            xyz.append(world.z)
                            rgb.append(PointCloud.clamp(yValue + 1.402 * cr))
                            rgb.append(PointCloud.clamp(yValue - 0.344136 * cb - 0.714136 * cr))
                            rgb.append(PointCloud.clamp(yValue + 1.772 * cb))
                        }
                    }
                }
                u += step
            }
            v += step
        }
    }

    private static func clamp(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, value)))
    }

    /// PLY binario (little endian): x y z como float32 y r g b como uchar.
    func plyData() -> Data {
        let n = count
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "comment Escaner LiDAR - metros - eje Y vertical\n"
        header += "element vertex \(n)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"
        header += "end_header\n"

        var body = [UInt8](repeating: 0, count: n * 15)
        var o = 0
        for i in 0..<n {
            for k in 0..<3 {
                let bits = xyz[i * 3 + k].bitPattern
                body[o] = UInt8(truncatingIfNeeded: bits)
                body[o + 1] = UInt8(truncatingIfNeeded: bits >> 8)
                body[o + 2] = UInt8(truncatingIfNeeded: bits >> 16)
                body[o + 3] = UInt8(truncatingIfNeeded: bits >> 24)
                o += 4
            }
            body[o] = rgb[i * 3]
            body[o + 1] = rgb[i * 3 + 1]
            body[o + 2] = rgb[i * 3 + 2]
            o += 3
        }

        var data = Data(header.utf8)
        data.append(contentsOf: body)
        return data
    }
}
