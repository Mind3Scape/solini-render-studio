import RealityKit
import Foundation

@MainActor func walk(_ e: Entity, _ depth: Int = 0) {
  if let m = e.components[ModelComponent.self] {
    for model in m.mesh.contents.models {
      for part in model.parts {
        let uv0 = part.textureCoordinates?.count ?? -1
        let uv1 = part.textureCoordinates1?.count ?? -1
        let ids = part.buffers.keys.map { $0.name }.sorted()
        for (id, b) in part.buffers where ["UV0","UV1","UV2","Lightmap","UVMap_001","st"].contains(id.name) {
          if let v = b.get(SIMD2<Float>.self) {
            let a = Array(v.elements.prefix(400))
            let mn = a.reduce(SIMD2<Float>(9,9)) { pointwiseMin($0,$1) }, mx = a.reduce(SIMD2<Float>(-9,-9)) { pointwiseMax($0,$1) }
            print(" ", id.name, "isCustom", id.isCustom, "n", v.count, "first", a.prefix(3).map{"(\($0.x),\($0.y))"}, "min", mn, "max", mx)
          } else { print(" ", id.name, "not SIMD2<Float>", b.elementType) }
        }
        print(e.name, "part", part.id, "verts", part.positions.count, "uv0", uv0, "uv1", uv1, "buffers", ids)
      }
    }
  }
  for c in e.children { walk(c, depth + 1) }
}
@main struct Probe {
  @MainActor static func main() async throws {
    let e = try await Entity(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    walk(e)
  }
}
