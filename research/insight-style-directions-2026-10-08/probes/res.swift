import RealityKit
import Metal
import Foundation

@MainActor func page(_ fmt: MTLPixelFormat, side: Int, slices: Int, mips: Int) throws -> TextureResource {
  var d = LowLevelTexture.Descriptor()
  d.textureType = .type2DArray; d.pixelFormat = fmt
  d.width = side; d.height = side; d.arrayLength = slices; d.mipmapLevelCount = mips
  d.textureUsage = [.shaderRead]
  return try TextureResource(from: LowLevelTexture(descriptor: d))
}
@MainActor func lightmap(_ tex: TextureResource, slices: Int) throws -> LightmapResource {
  var parts: [LightmapResource.MeshPartLightmapDescriptor] = []
  var r = LightmapResource.AtlasReference(); r.uvScale = [1, 1]
  parts.append(try .init(bakeDescriptor: .indirectDiffuseIrradiance(.init(sourceAtlasReference: r))))
  return try LightmapResource(atlasTextures: [tex], perEntityData: [try .init(perPartData: parts)])
}
@main struct Probe {
  @MainActor static func main() async throws {
    for (name, f) in [("rgba16Float", MTLPixelFormat.rgba16Float), ("rgb9e5Float", .rgb9e5Float),
                      ("astc_4x4_hdr", .astc_4x4_hdr), ("rgba8Unorm", .rgba8Unorm)] {
      for slices in [3, 1] {
        do { let lm = try lightmap(try page(f, side: 512, slices: slices, mips: 10), slices: slices)
             print(name, "slices", slices, "OK", lm.bakeTypes, "entities", lm.entityCount) }
        catch { print(name, "slices", slices, "FAIL", error) }
      }
    }
    do {
      let c = InlineArray<3, SIMD4<Float>>(repeating: [0.3, 0, 0, 0])
      let p = try DiffuseProbeResource(positions: [[0,0,0],[1,0,0],[0,1,0],[0,0,1]], coefficients: [c,c,c,c], tetrahedronIndices: [[0,1,2,3]])
      print("DiffuseProbeResource OK", p)
    } catch { print("DiffuseProbeResource FAIL", error) }
    let bath = try await Entity(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("bath bounds extents (m in RealityKit):", bath.visualBounds(relativeTo: nil).extents)
  }
}
