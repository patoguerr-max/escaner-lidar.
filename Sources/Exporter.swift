import Foundation
import ARKit
import Metal
import simd

enum ExportError: LocalizedError {
    case empty

    var errorDescription: String? {
        switch self {
        case .empty:
            return "No hay datos escaneados todavía."
        }
    }
}

enum Exporter {

    /// ARKit usa Y vertical. Con `zUp` (Vulcan, CloudCompare, Civil 3D) queda
    /// X igual, Y = -Z de ARKit, Z = Y de ARKit; sigue siendo un sistema de mano derecha.
    static func axes(_ p: SIMD3<Float>, zUp: Bool) -> SIMD3<Float> {
        zUp ? SIMD3<Float>(p.x, -p.z, p.y) : p
    }

    /// Escribe la malla (OBJ) y la nube de puntos (PLY) en la carpeta Documentos de la app.
    static func export(meshAnchors: [ARMeshAnchor], cloud: PointCloud, zUp: Bool) throws -> [URL] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())

        var urls: [URL] = []

        if !meshAnchors.isEmpty {
            let url = documents.appendingPathComponent("escaneo_\(stamp)_malla.obj")
            let text = objText(from: meshAnchors, zUp: zUp)
            try text.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }

        if cloud.count > 0 {
            let url = documents.appendingPathComponent("escaneo_\(stamp)_nube.ply")
            try cloud.plyData(zUp: zUp).write(to: url, options: .atomic)
            urls.append(url)
        }

        if urls.isEmpty {
            throw ExportError.empty
        }
        return urls
    }

    /// Une todos los trozos de malla de ARKit en un solo OBJ, en coordenadas de mundo (metros).
    static func objText(from anchors: [ARMeshAnchor], zUp: Bool) -> String {
        var out = "# Escaner LiDAR - metros - eje \(zUp ? "Z" : "Y") vertical\n"
        var vertexOffset = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform

            let vertices = geometry.vertices
            let vertexBase = vertices.buffer.contents().advanced(by: vertices.offset)
            for i in 0..<vertices.count {
                let p = vertexBase.advanced(by: i * vertices.stride)
                    .assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let world = transform * SIMD4<Float>(p.0, p.1, p.2, 1)
                let q = axes(SIMD3<Float>(world.x, world.y, world.z), zUp: zUp)
                out += String(format: "v %.4f %.4f %.4f\n", q.x, q.y, q.z)
            }

            let faces = geometry.faces
            let faceBase = faces.buffer.contents()
            let perFace = faces.indexCountPerPrimitive
            let bytesPerIndex = faces.bytesPerIndex
            if perFace == 3 {
                for f in 0..<faces.count {
                    let a = index(at: f * 3, base: faceBase, bytesPerIndex: bytesPerIndex)
                    let b = index(at: f * 3 + 1, base: faceBase, bytesPerIndex: bytesPerIndex)
                    let c = index(at: f * 3 + 2, base: faceBase, bytesPerIndex: bytesPerIndex)
                    // OBJ numera los vértices desde 1.
                    out += "f \(a + vertexOffset + 1) \(b + vertexOffset + 1) \(c + vertexOffset + 1)\n"
                }
            }

            vertexOffset += vertices.count
        }
        return out
    }

    private static func index(at position: Int, base: UnsafeMutableRawPointer, bytesPerIndex: Int) -> Int {
        let pointer = base.advanced(by: position * bytesPerIndex)
        if bytesPerIndex == 2 {
            return Int(pointer.assumingMemoryBound(to: UInt16.self).pointee)
        }
        return Int(pointer.assumingMemoryBound(to: UInt32.self).pointee)
    }
}
