import RealityKit
import Foundation

// Copy the importer's custom "Lightmap" buffer into the typed textureCoordinates1 semantic.
@MainActor func remap(_ e: Entity) throws {
  if var m = e.components[ModelComponent.self] {
    var contents = m.mesh.contents
    var models: [MeshResource.Model] = []
    for var model in contents.models {
      var parts: [MeshResource.Part] = []
      for var part in model.parts {
        if let (_, b) = part.buffers.first(where: { $0.key.name == "Lightmap" }),
           let uv = b.get(SIMD2<Float>.self) {
          part.textureCoordinates1 = MeshBuffers.TextureCoordinates(uv.elements)
        }
        parts.append(part)
      }
      model.parts = MeshPartCollection(parts)
      models.append(model)
    }
    contents.models = MeshModelCollection(models)
    let mesh = try MeshResource.generate(from: contents)
    m.mesh = mesh
    e.components.set(m)
    for p in mesh.contents.models.flatMap({ $0.parts }) {
      print(e.name, "after remap uv1", p.textureCoordinates1?.count ?? -1,
            "first", p.textureCoordinates1.map { Array($0.elements.prefix(1)) } ?? [])
    }
  }
  for c in e.children { try remap(c) }
}
@main struct Probe {
  @MainActor static func main() async throws {
    let e = try await Entity(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    try remap(e)
  }
}
