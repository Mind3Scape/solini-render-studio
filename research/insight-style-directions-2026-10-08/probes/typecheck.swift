// API availability fixture only (iOS 27 SDK typecheck). `macOnly` is intentionally invalid for iOS
// (negative control: SurfaceExtractor is unavailable). This is NOT a correct example of binding
// AO + GI to one mesh part, nor working lightmap code.
import RealityKit
import Metal

@MainActor func gi(atlas: TextureResource, wall: Entity, mover: Entity, root: Entity) throws {
  var ref = LightmapResource.AtlasReference()
  ref.atlasTextureIndex = 0; ref.atlasTextureSlice = 0
  ref.uvOffset = [0, 0]; ref.uvScale = [1, 1]
  let part = try LightmapResource.MeshPartLightmapDescriptor(
    bakeDescriptor: .indirectDiffuseIrradiance(.init(sourceAtlasReference: ref)))
  let ao = try LightmapResource.MeshPartLightmapDescriptor(
    bakeDescriptor: .ambientOcclusion(.init(sourceAtlasReference: ref)))
  let res = try LightmapResource(atlasTextures: [atlas],
    perEntityData: [try .init(perPartData: [part, ao])])
  var lm = LightmapComponent(resource: res)
  lm.entityIndexInLightmapResource = [wall: 0]
  lm.indirectIrradianceContributionScale = 1
  root.components.set(lm)

  // Diffuse probes created on iOS from our own coefficients.
  let c = InlineArray<3, SIMD4<Float>>(repeating: [0.2, 0, 0, 0])
  let probes = try DiffuseProbeResource(
    positions: [[0,0,0],[1,0,0],[0,1,0],[0,0,1]],
    coefficients: [c, c, c, c],
    tetrahedronIndices: [[0,1,2,3]])
  let group = Entity()
  group.components.set(DiffuseLightProbeGroupComponent(resource: probes))
  mover.components.set(DiffuseLightProbeReceiverComponent(probeGroup: group))
  root.components.set(OcclusionCullingComponent(isEnabled: true))

  var cam = OrthographicCameraComponent(); cam.scale = 16
  root.components.set(cam)
  _ = LightmapComponent.FinalShadedColorBakeMaterial()
}

@MainActor func macOnly(root: Entity) throws {
  _ = try LightmapComponent.SurfaceExtractor(lightmapRootEntity: root)
}
