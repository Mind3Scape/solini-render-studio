import CoreGraphics
import Foundation
import Metal
import RealityKit
import simd

/// «Отгрузка» in RealityKit 27 on the SAME USD kit as the SceneKit screen (materials and
/// textures come from the USD, written by the kit builder from the app's PBR specs).
/// Shared by the iOS screen and the macOS harness.
///
/// Light model (each part measured on the harness, see tmp/insight-pass3/PROBES-REPORT.md):
/// - inside the hall: local environment probes (Cycles panoramas of the baked scene, parallax
///   boxes) — the hall entities get NO sky receiver, because a sky receiver or an enclosing sky
///   probe suppresses the local probe;
/// - outside (yard, neighbour, plants, truck): the clamped, desaturated sky as image-based light;
/// - static geometry: our baked day irradiance through `LightmapComponent`;
/// - the sun: a distant spot with iOS 27 soft shadows (`lightSize`, `.high`);
/// - camera: `ToneMappingComponent` (exposure, toe, shoulder).
///
/// Night swaps every owner to its night source, never adding one: the baked night irradiance
/// (dim sky + the fixtures, direct and indirect) in the same atlas, night panoramas (same bake
/// light) in the probes and the hall / yard image-based light, a dim moon instead of the sun,
/// glowing fixtures and screens. No live lamp lights: they would light the baked static twice.
@MainActor
final class RealityAtelierScene {
  struct Diagnostics: Equatable {
    var lightmap = true
    var localProbes = true
    var softShadow = true
    var skyEverywhere = false
  }

  let root = Entity()
  let camera = Entity()
  private let sun = Entity()
  private let sky = Entity()
  /// Image-based light from the hall panorama for inside models without lightmap texels (props,
  /// catalogue products, forklift, batches): the local probe alone gives them almost no diffuse
  /// light (measured 0.13 vs 1.42 for the sky).
  private let hallLight = Entity()
  private var insideUnbaked: [Entity] = []
  /// The same hall panorama for what stands at the stations (props, people, basins, the
  /// catalogue products): at night they sit under the fixtures, brighter than the hall average
  /// the movers get (calibrated against the baked static next to them, see `nightFill`).
  private let stationLight = Entity()
  private var stationUnbaked: [Entity] = []
  private var probes: [Entity] = []
  private var insideModels: [Entity] = []
  private var outsideModels: [Entity] = []
  private var staticModels: [Entity] = []
  private var lightmapResource: LightmapResource?
  /// The lightmap atlas; day and night irradiance are written into it in place.
  private var atlas: LowLevelTexture?
  private var probeEnv: [String: EnvironmentResource] = [:]
  private var skyEnv: EnvironmentResource?
  /// Emissive / window materials per model: (entity, material index, material name).
  private var nightMaterials: [(Entity, Int, String)] = []
  private var dayMaterials: [String: PhysicallyBasedMaterial] = [:]
  private(set) var lighting: AtelierLighting = .day
  private(set) var layout = AtelierLayout()
  private(set) var timeline = AtelierTimeline(layout: AtelierLayout())
  private(set) var report: [String] = []
  private(set) var diagnostics = Diagnostics()
  private let folder: URL
  private let models: URL?

  // Movers (posed by `apply`).
  let forklift = Entity()
  private var carriage: Entity?
  private var carriageBase: Float = 0
  let batch = Entity()
  private(set) var loaded: [Entity] = []
  private(set) var truck: Entity?
  private var truckBase = SIMD3<Float>.zero
  private let selection = Entity()
  private(set) var pose: AtelierPose
  private(set) var selected: AtelierSubject?

  /// Camera: orbit about the vertical axis (degrees from the true-isometric diagonal), ground
  /// focus and half-height of the view (m). Clamped to the site.
  var azimuth: Float = 0 { didSet { placeCamera() } }
  var scale: Float = 13 {
    didSet {
      if scale < 3 || scale > 26 { scale = min(26, max(3, scale)) }
      placeCamera()
    }
  }
  var focus = SIMD3<Float>(11, 1.2, 10) {
    didSet {
      let c = SIMD3(min(32, max(-4, focus.x)), focus.y, min(28, max(-4, focus.z)))
      if c != focus { focus = c }
      placeCamera()
    }
  }
  static let fieldOfView: Float = 9

  /// Tone mapper exposure (EV) and the sun; tuned on the harness and iPhone screenshots.
  static var exposure: Float = -1.5
  /// Night exposure relative to the day (SceneKit: +0.9 EV for the same night bake).
  static var nightExposureOffset: Float = 1.0
  static var sunLumens: Float = 1.2e8
  static var sunSize: Float = 2.5
  /// Diagnostics: a constant irradiance instead of the baked lightmap (calibration).
  static var lightmapConstant: Float?

  init(folder: URL, models: URL?) {
    self.folder = folder
    self.models = models
    pose = AtelierTimeline(layout: AtelierLayout()).pose(at: 0)
  }

  // MARK: Loading

  func load(diagnostics d: Diagnostics = Diagnostics()) async throws {
    diagnostics = d
    var t0 = Date()
    func lap(_ what: String) {
      report.append(String(format: "%@ %.2fs", what, Date().timeIntervalSince(t0)))
      t0 = Date()
    }
    let kit = try await Entity(contentsOf: folder.appendingPathComponent("atelier_kit.usdc"))
    root.addChild(kit)
    lap("kit")
    var anchors: [String: simd_float4x4] = [:]
    kit.visit { e in
      if e.name.hasPrefix("anchor_") { anchors[e.name] = e.transformMatrix(relativeTo: nil) }
    }
    layout = AtelierLayout(anchors: anchors.mapValues { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) })
    timeline = AtelierTimeline(layout: layout)
    // Plants: prototypes instanced at their anchors (outside: sky light).
    for proto in ["Tree", "Shrub2", "Shrub3", "Shrub4"] {
      guard let p = kit.findEntity(named: proto) else { continue }
      for (name, t) in anchors where name.hasPrefix("anchor_inst_\(proto)_") {
        let c = p.clone(recursive: true)
        c.setTransformMatrix(t * p.transformMatrix(relativeTo: p.parent), relativeTo: nil)
        root.addChild(c)
        outsideModels.append(c)
      }
      p.isEnabled = false
    }
    if let e = kit.findEntity(named: "Static") { insideModels.append(e) }
    if let e = kit.findEntity(named: "StaticProps") {
      insideModels.append(e)
      stationUnbaked.append(e)
    }
    for name in ["StaticOutside", "StaticPropsOutside"] {
      if let e = kit.findEntity(named: name) { outsideModels.append(e) }
    }
    for name in ["Static", "StaticOutside"] {
      kit.findEntity(named: name)?.visit { e in if e.components.has(ModelComponent.self) { staticModels.append(e) } }
    }
    setupMovers(kit)
    lap("movers")
    try await loadProducts(anchors: anchors)
    lap("products")
    try await setupLight()
    camera.components.set(PerspectiveCameraComponent(near: 1, far: 1200, fieldOfViewInDegrees: Self.fieldOfView))
    setToneMapping(exposure: Self.exposure)
    root.addChild(camera)
    collectNightMaterials()
    placeCamera()
    apply(timeline.pose(at: 0))
  }

  /// Exposure (EV) with a gentle toe and a long shoulder: whites roll off instead of clipping.
  func setToneMapping(exposure: Float) {
    camera.components.set(ToneMappingComponent(
      exposure: exposure, toeStrength: 0.3, toeLength: 0.4, shoulderStrength: 0.9, shoulderLength: 0.85,
      shoulderAngle: 1.0))
  }

  private func setupMovers(_ kit: Entity) {
    if let fork = kit.findEntity(named: "Forklift") {
      root.addChild(forklift)
      forklift.addChild(fork, preservingWorldTransform: true)
      carriage = fork.findEntity(named: "Forklift_Carriage")
      carriageBase = carriage?.position.y ?? 0
      insideModels.append(forklift)
      insideUnbaked.append(forklift)
    }
    forklift.name = "Forklift"
    if let proto = kit.findEntity(named: "Batch") {
      // The kit's up-axis conversion lives on the parents: keep the prototype's WORLD transform
      // for the clones (taken before it leaves the kit), the holders carry only the demo pose.
      let protoWorld = proto.transformMatrix(relativeTo: nil)
      proto.removeFromParent()
      func fill(_ h: Entity, _ name: String) {
        h.name = name
        let c = proto.clone(recursive: true)
        h.addChild(c)
        c.setTransformMatrix(protoWorld, relativeTo: h)
        root.addChild(h)
        insideModels.append(h)
        insideUnbaked.append(h)
      }
      fill(batch, "BatchCurrent")
      loaded = (0..<layout.slots.count).map { _ in
        let h = Entity()
        fill(h, "BatchLoaded")
        return h
      }
    }
    if let t = kit.findEntity(named: "Truck") {
      truck = t
      t.name = "Truck"
      truckBase = t.position
      outsideModels.append(t)
      t.visit { e in
        guard let m = e.components[ModelComponent.self] else { return }
        for (i, material) in m.materials.enumerated() {
          if let p = material as? PhysicallyBasedMaterial, ["M_TrailerRoof", "M_Curtain", "M_Trailer"].contains(p.name ?? "") {
            roofParts.append((e, i, p))
          }
        }
      }
    }
    for e in [forklift, batch, truck].compactMap({ $0 }) + loaded {
      e.generateCollisionShapes(recursive: true)
    }
    // Selection outline: a thin amber frame on the ground (scaled to the subject).
    var amber = UnlitMaterial(color: atelierHex(0xF2AC3D))
    amber.blending = .transparent(opacity: 0.95)
    for (dx, dz, w, d) in [(0, -0.5, 1, 0.03), (0, 0.5, 1, 0.03), (-0.5, 0, 0.02, 1), (0.5, 0, 0.02, 1)] as [(Float, Float, Float, Float)] {
      let bar = ModelEntity(mesh: .generateBox(width: w, height: 0.01, depth: d), materials: [amber])
      bar.position = SIMD3(dx, 0, dz)
      selection.addChild(bar)
    }
    selection.isEnabled = false
    root.addChild(selection)
  }

  private func loadProducts(anchors: [String: simd_float4x4]) async throws {
    guard let models else { return }
    var gel = PhysicallyBasedMaterial()
    gel.baseColor = .init(tint: atelierHex(0xF3F2EE))
    gel.roughness = 0.22
    gel.metallic = 0.0
    gel.clearcoat = 0.6
    gel.clearcoatRoughness = 0.08
    for (name, t) in anchors where name.hasPrefix("anchor_product_") {
      let key = String(name.dropFirst("anchor_product_".count))
      let file = ShippingAtelierScene.catalogueLengths.keys.first { $0.replacingOccurrences(of: "-", with: "_") == key } ?? key
      guard let product = try? await Entity(contentsOf: models.appendingPathComponent(file + ".usdz")) else { continue }
      let b = product.visualBounds(relativeTo: nil)       // RealityKit honours metersPerUnit
      product.visit { e in
        guard var m = e.components[ModelComponent.self] else { return }
        m.materials = m.materials.map { _ in gel }
        e.components.set(m)
      }
      let holder = Entity()
      holder.name = "Product"
      holder.addChild(product)
      product.position = SIMD3(-b.center.x, -b.min.y, -b.center.z)
      if b.extents.z > b.extents.x { holder.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) }
      holder.position = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
      root.addChild(holder)
      insideModels.append(holder)
      stationUnbaked.append(holder)
    }
  }

  // MARK: Light

  private func setupLight() async throws {
    var t0 = Date()
    if let image = AtelierMaterials.environment(folder: folder) {
      let env = try await EnvironmentResource(equirectangular: image, withName: "atelier_sky")
      skyEnv = env
      sky.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: log2(1.25)))
      root.addChild(sky)
      applySkyReceivers()
    }
    report.append(String(format: "sky %.2fs", Date().timeIntervalSince(t0)))
    t0 = Date()
    var spot = SpotLightComponent()
    spot.intensity = Self.sunLumens
    spot.innerAngleInDegrees = 30
    spot.outerAngleInDegrees = 34
    spot.attenuationRadius = 400
    sun.components.set(spot)
    let target = SIMD3<Float>(13, 0, 11)
    let toSun = simd_normalize(SIMD3<Float>(0.6, 0.78, -0.4))
    sun.look(at: target, from: target + toSun * 80, relativeTo: nil)
    root.addChild(sun)
    setSoftShadow(diagnostics.softShadow)
    if diagnostics.lightmap { applyLightmap() }
    report.append(String(format: "lightmap %.2fs", Date().timeIntervalSince(t0)))
    t0 = Date()
    try await addProbes()
    applySkyReceivers()
    setLocalProbes(diagnostics.localProbes)
    report.append(String(format: "probes %.2fs", Date().timeIntervalSince(t0)))
  }

  /// Light ownership:
  /// - lightmapped inside static: diffuse = lightmap, specular = local probes (no receiver);
  /// - inside without lightmap: hall panorama as image-based light (diffuse + specular);
  /// - outside: sky image-based light (diffuse replaced by the lightmap where it exists).
  /// `skyEverywhere` is the diagnostic that puts the sky on everything.
  private func applySkyReceivers() {
    for group in insideModels + outsideModels {
      group.visit { e in
        guard e.components.has(ModelComponent.self) else { return }
        e.components.remove(ImageBasedLightReceiverComponent.self)
      }
    }
    func receive(_ groups: [Entity], _ light: Entity) {
      for group in groups {
        group.visit { e in
          guard e.components.has(ModelComponent.self) else { return }
          e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
      }
    }
    if diagnostics.skyEverywhere {
      receive(insideModels + outsideModels, sky)
      return
    }
    receive(outsideModels, sky)
    if hallLight.components.has(ImageBasedLightComponent.self) { receive(insideUnbaked, hallLight) }
    if stationLight.components.has(ImageBasedLightComponent.self) { receive(stationUnbaked, stationLight) }
  }
  func setSkyEverywhere(_ on: Bool) {
    diagnostics.skyEverywhere = on
    applySkyReceivers()
  }

  func setSun(_ on: Bool) { sun.isEnabled = on }
  func setSky(_ on: Bool) { sky.isEnabled = on }

  func setSoftShadow(_ on: Bool) {
    var shadow = SpotLightComponent.Shadow()
    shadow.depthBias = 2
    if on {
      shadow.lightSize = Self.sunSize
      shadow.quality = .high
    }
    sun.components.set(shadow)
    diagnostics.softShadow = on
  }

  // MARK: Lightmap (our bake, LightmapComponent)

  private func applyLightmap() {
    let materials = AtelierMaterials(folder: folder)
    // The kit stores the Cycles diffuse light pass (E/π). RealityKit's indirectDiffuseIrradiance
    // takes irradiance E (it applies albedo/π) and sums the three directional slices with weights
    // ≈ √3 for a flat normal (measured: constant 1 → albedo·0.52). Our three slices are equal, so
    // the atlas is E/π × π/√3 → diffuse = albedo × light pass, as in the bake and in SceneKit.
    let scale = Float.pi / Float(3).squareRoot()
    let constantScaled = Self.lightmapConstant.flatMap { v in
      RadianceImage(width: 64, height: 64, pixels: [Float](repeating: v * scale, count: 64 * 64 * 3)).cgImage(scale: 1)
    }
    guard let gi = constantScaled ?? materials.lightmap(.day, scale: scale), let device = MTLCreateSystemDefaultDevice() else {
      report.append("lightmap: no GI image")
      return
    }
    do {
      let (texture, atlas) = try Self.directionalAtlas(from: gi, device: device)
      self.atlas = texture
      var ref = LightmapResource.AtlasReference()
      ref.atlasTextureIndex = 0
      ref.atlasTextureSlice = 0
      ref.uvOffset = [0, 0]
      ref.uvScale = [1, 1]
      var perEntity: [LightmapResource.EntityLightmapDescriptor] = []
      for e in staticModels {
        guard var model = e.components[ModelComponent.self] else { continue }
        let (mesh, parts) = try Self.remapLightmapUV(model.mesh)
        model.mesh = mesh
        e.components.set(model)
        let descriptor = try LightmapResource.MeshPartLightmapDescriptor(
          bakeDescriptor: .indirectDiffuseIrradiance(.init(sourceAtlasReference: ref)))
        perEntity.append(try .init(perPartData: Array(repeating: descriptor, count: parts)))
      }
      lightmapResource = try LightmapResource(atlasTextures: [atlas], perEntityData: perEntity)
      setLightmap(true)
      report.append("lightmap \(perEntity.count) entities")
    } catch {
      report.append("lightmap FAILED: \(error)")
    }
  }
  func setLightmap(_ on: Bool) {
    diagnostics.lightmap = on
    guard on, let r = lightmapResource else {
      root.components.remove(LightmapComponent.self)
      return
    }
    var c = LightmapComponent(resource: r)
    var indices: [Entity: Int] = [:]
    for (i, e) in staticModels.enumerated() { indices[e] = i }
    c.entityIndexInLightmapResource = indices
    root.components.set(c)
  }

  /// Copies the importer's «Lightmap» primvar into `textureCoordinates1` (V flipped: the bake is
  /// bottom-up, RealityKit samples top-left) and returns the new mesh and its part count.
  static func remapLightmapUV(_ mesh: MeshResource) throws -> (MeshResource, Int) {
    var contents = mesh.contents
    var count = 0
    var models: [MeshResource.Model] = []
    for var model in contents.models {
      var parts: [MeshResource.Part] = []
      for var part in model.parts {
        if let (_, b) = part.buffers.first(where: { $0.key.name == "Lightmap" || $0.key.name == "primvars:Lightmap" }),
          let uv = b.get(SIMD2<Float>.self)
        {
          part.textureCoordinates1 = MeshBuffers.TextureCoordinates(uv.elements.map { SIMD2($0.x, 1 - $0.y) })
        }
        parts.append(part)
        count += 1
      }
      model.parts = MeshPartCollection(parts)
      models.append(model)
    }
    contents.models = MeshModelCollection(models)
    return (try MeshResource.generate(from: contents), count)
  }

  /// A 2D-array texture with the irradiance in all three directional slices (the bake is
  /// non-directional; the three-basis bake is a later step).
  static func directionalAtlas(from image: CGImage, device: MTLDevice) throws -> (LowLevelTexture, TextureResource) {
    let w = image.width, h = image.height
    var d = LowLevelTexture.Descriptor()
    d.textureType = .type2DArray
    d.pixelFormat = .rgba16Float
    d.width = w
    d.height = h
    d.arrayLength = 3
    d.mipmapLevelCount = 1
    d.textureUsage = [.shaderRead]
    let texture = try LowLevelTexture(descriptor: d)
    try fill(texture, with: image, device: device)
    return (texture, try TextureResource(from: texture))
  }
  /// Writes an irradiance image into all three slices of the atlas (in place: the lightmap
  /// resource keeps pointing at the same texture).
  static func fill(_ texture: LowLevelTexture, with image: CGImage, device: MTLDevice) throws {
    let w = image.width, h = image.height
    guard w == texture.descriptor.width, h == texture.descriptor.height,
      let data = image.dataProvider?.data as Data?, let queue = device.makeCommandQueue(),
      let cb = queue.makeCommandBuffer(),
      let staging = data.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: data.count) }),
      let blit = cb.makeBlitCommandEncoder()
    else { throw CocoaError(.fileReadCorruptFile) }
    let target = texture.replace(using: cb)
    for slice in 0..<3 {
      blit.copy(
        from: staging, sourceOffset: 0, sourceBytesPerRow: image.bytesPerRow, sourceBytesPerImage: image.bytesPerRow * h,
        sourceSize: MTLSize(width: w, height: h, depth: 1), to: target, destinationSlice: slice, destinationLevel: 0,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
    }
    blit.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
  }

  // MARK: Local environment probes (hall, dock)

  private func addProbes() async throws {
    let f = layout.floor
    let defs: [(String, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
      ("probe_hall", SIMD3(7, f + 1.6, 10), SIMD3(0.2, f - 0.1, 0.2), SIMD3(13.9, f + 7, 19.9)),
      ("probe_dock", SIMD3(21, 2.0, 13.5), SIMD3(14.0, -0.1, 3), SIMD3(34, 9, 24)),
    ]
    for (name, center, lo, hi) in defs {
      let url = folder.appendingPathComponent(name + ".hdr")
      guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let hdr = RadianceImage(data: data),
        let image = hdr.cgImage(scale: 1)
      else { continue }
      let env = try await EnvironmentResource(equirectangular: image, withName: name)
      probeEnv[name] = env
      if name == "probe_hall" {
        hallLight.name = "HallLight"
        stationLight.name = "StationLight"
        hallLight.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0))
        stationLight.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0))
        root.addChild(hallLight)
        root.addChild(stationLight)
      }
      let e = Entity()
      e.name = name
      e.position = center
      e.components.set(VirtualEnvironmentProbeComponent(
        source: .single(.init(environment: env, intensityExponent: 0)),
        influence: .local(parallaxBounds: BoundingBox(min: lo - center, max: hi - center), blendDistance: 1.0)))
      root.addChild(e)
      probes.append(e)
    }
  }
  func setLocalProbes(_ on: Bool) {
    diagnostics.localProbes = on
    probes.forEach { $0.isEnabled = on }
  }

  // MARK: Day / night

  /// Emission per material: colour, day and night intensity (as the SceneKit screen).
  private static let emission: [String: (UInt, Float, Float)] = [
    "M_Lamp": (0xFFF1D8, 0, 2.2), "M_Screen": (0x7FB7E6, 0.2, 0.9), "M_Beacon": (0xFF9A2E, 0.3, 1.8),
  ]
  /// Night image-based light for unbaked models (EV over the hall panorama): matched to the baked
  /// static beside them under the same fixtures (harness measurement, tmp/insight-pass3).
  static var nightFill: (station: Float, hall: Float) = (2.75, 1.25)
  /// Night moon: a dim, cool sun (SceneKit 60 vs 1250).
  static var moonFraction: Float = 0.05

  private func collectNightMaterials() {
    root.visit { e in
      guard let m = e.components[ModelComponent.self] else { return }
      for (i, material) in m.materials.enumerated() {
        guard let p = material as? PhysicallyBasedMaterial, let name = p.name,
          Self.emission[name] != nil || name == "M_Window"
        else { continue }
        nightMaterials.append((e, i, name))
        if dayMaterials[name] == nil { dayMaterials[name] = p }
      }
    }
    setFixtures(night: false)
  }
  private func setFixtures(night: Bool) {
    for (e, i, name) in nightMaterials {
      guard var model = e.components[ModelComponent.self], i < model.materials.count, var p = dayMaterials[name] else { continue }
      if let (color, day, nightValue) = Self.emission[name] {
        p.emissiveColor = .init(color: atelierHex(color))
        p.emissiveIntensity = night ? nightValue : day
      } else if night {                                   // windows: the dark sky instead of daylight
        p.baseColor = .init(tint: atelierHex(0x1C2731))
      }
      model.materials[i] = p
      e.components.set(model)
    }
  }

  /// Night panoramas (the night bake's light), loaded on first use.
  private func environment(_ name: String) async -> EnvironmentResource? {
    if let e = probeEnv[name] { return e }
    let url = folder.appendingPathComponent(name + ".hdr")
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let hdr = RadianceImage(data: data),
      let image = hdr.cgImage(scale: 1), let env = try? await EnvironmentResource(equirectangular: image, withName: name)
    else {
      report.append("night: \(name) missing")
      return nil
    }
    probeEnv[name] = env
    return env
  }

  /// Switches every light owner between day and night (see the type comment).
  func setLighting(_ mode: AtelierLighting) async {
    lighting = mode
    let night = mode == .night
    let suffix = night ? "_night" : ""
    let folder = self.folder
    let scale = Float.pi / Float(3).squareRoot()
    if diagnostics.lightmap, Self.lightmapConstant == nil, let atlas, let device = MTLCreateSystemDefaultDevice() {
      let image = await Task.detached { AtelierMaterials(folder: folder).lightmap(mode, scale: scale) }.value
      guard lighting == mode else { return }
      if let image {
        do { try Self.fill(atlas, with: image, device: device) } catch { report.append("lightmap \(mode) FAILED: \(error)") }
      }
    }
    let hall = await environment("probe_hall" + suffix)
    let dock = await environment("probe_dock" + suffix)
    guard lighting == mode else { return }
    if let hall {
      hallLight.components.set(ImageBasedLightComponent(source: .single(hall), intensityExponent: night ? Self.nightFill.hall : 0))
      stationLight.components.set(ImageBasedLightComponent(source: .single(hall), intensityExponent: night ? Self.nightFill.station : 0))
    }
    // Outside: the sky by day; by night the yard panorama (night sky + the pole lamps).
    if night, let dock {
      sky.components.set(ImageBasedLightComponent(source: .single(dock), intensityExponent: 0))
    } else if let skyEnv {
      sky.components.set(ImageBasedLightComponent(source: .single(skyEnv), intensityExponent: log2(1.25)))
    }
    for probe in probes {
      guard let env = probe.name == "probe_hall" ? hall : dock, var c = probe.components[VirtualEnvironmentProbeComponent.self] else { continue }
      c.source = .single(.init(environment: env, intensityExponent: 0))
      probe.components.set(c)
    }
    if var spot = sun.components[SpotLightComponent.self] {
      spot.intensity = Self.sunLumens * (night ? Self.moonFraction : 1)
      spot.color = night ? atelierHex(0x9DB2D6) : atelierHex(0xFFFAF3)
      sun.components.set(spot)
    }
    setFixtures(night: night)
    setToneMapping(exposure: Self.exposure + (night ? Self.nightExposureOffset : 0))
  }

  /// Diagnostic mirror objects in the hall (chrome sphere, polished plate) to judge reflections.
  func addProbeTestObjects() {
    var chrome = PhysicallyBasedMaterial()
    chrome.baseColor = .init(tint: atelierHex(0xE6E8EA))
    chrome.metallic = 1.0
    chrome.roughness = 0.04
    let sphere = ModelEntity(mesh: .generateSphere(radius: 0.45), materials: [chrome])
    sphere.position = SIMD3(6.2, layout.floor + 0.45, 11.8)
    let plate = ModelEntity(mesh: .generateBox(width: 2.2, height: 0.02, depth: 1.6, cornerRadius: 0.01), materials: [chrome])
    plate.position = SIMD3(7.9, layout.floor + 0.012, 11.6)
    for e in [sphere, plate] {
      e.name = "ProbeTest"
      root.addChild(e)
      insideModels.append(e)
    }
  }

  // MARK: Demonstration pose

  func apply(_ p: AtelierPose) {
    pose = p
    let floor = layout.floor
    forklift.position = SIMD3(p.forklift.x, floor, p.forklift.y)
    forklift.orientation = simd_quatf(angle: p.heading, axis: [0, 1, 0])
    carriage?.position.y = carriageBase + p.fork
    switch p.batch {
    case .pickup(let opacity):
      batch.position = SIMD3(layout.pickup.x, floor, layout.pickup.y)
      batch.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
      batch.components.set(OpacityComponent(opacity: opacity))
    case .forks:
      let fwd = SIMD3<Float>(cos(p.heading), 0, -sin(p.heading))
      batch.position = SIMD3(p.forklift.x, floor, p.forklift.y) + fwd * AtelierTimeline.forkReach
        + SIMD3(0, AtelierTimeline.lift(p.fork), 0)
      batch.orientation = simd_quatf(angle: p.heading - .pi, axis: [0, 1, 0])
      batch.components.set(OpacityComponent(opacity: 1))
    case .slot(let k):
      batch.position = SIMD3(layout.slots[k] + p.truckOffset, floor, layout.dockZ)
      batch.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
      batch.components.set(OpacityComponent(opacity: p.truckOpacity))
    }
    for (k, e) in loaded.enumerated() {
      e.isEnabled = k < p.loaded
      e.position = SIMD3(layout.slots[k] + p.truckOffset, floor, layout.dockZ)
      e.components.set(OpacityComponent(opacity: p.truckOpacity))
    }
    if let truck {
      truck.position = truckBase + SIMD3(p.truckOffset, 0, 0)
      truck.components.set(OpacityComponent(opacity: p.truckOpacity))
      truck.isEnabled = p.truckOpacity > 0.01
    }
    if let selected { placeSelection(selected) }
  }

  // MARK: Selection

  func subject(of entity: Entity) -> AtelierSubject? {
    var e: Entity? = entity
    while let current = e {
      switch current.name {
      case "BatchCurrent": return .batch
      case "Forklift": return .forklift
      case "Truck", "BatchLoaded": return .truck
      default: e = current.parent
      }
    }
    return nil
  }
  func select(_ subject: AtelierSubject?) {
    selected = subject
    selection.isEnabled = subject != nil
    if let subject { placeSelection(subject) }
  }
  private func placeSelection(_ s: AtelierSubject) {
    let floor = layout.floor
    switch s {
    case .batch:
      selection.position = SIMD3(batch.position.x, floor + 0.02, batch.position.z)
      selection.orientation = batch.orientation
      selection.scale = SIMD3(1.5, 1, 2.3)
    case .forklift:
      let fwd = SIMD3<Float>(cos(pose.heading), 0, -sin(pose.heading))
      selection.position = SIMD3(pose.forklift.x, floor + 0.02, pose.forklift.y) - fwd * 0.4
      selection.orientation = simd_quatf(angle: pose.heading, axis: [0, 1, 0])
      selection.scale = SIMD3(3.2, 1, 1.8)
    case .truck:
      selection.position = SIMD3(layout.truck.x + 2.2 + pose.truckOffset, 0.03, layout.truck.z)
      selection.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
      selection.scale = SIMD3(18.8, 1, 3.4)
    }
  }

  // MARK: Section cut

  private var roofParts: [(Entity, Int, PhysicallyBasedMaterial)] = []
  /// The trailer body — roof sheet, walls and the drawn-back curtain — is shown as a faint ghost
  /// (bows, rails, posts, straps and the deck stay) so the followed batch inside the trailer is
  /// visible; the UI marks it «Разрез». Measured at t = 34 (slot 0 behind the curtain and the
  /// front wall): 31 visible batch pixels with the body, 20 646 with the cut (585×1266 frame).
  private(set) var trailerCut = false
  static let cutOpacity: Float = 0.12

  /// The batch is inside the docked trailer (under its roof).
  var batchInTrailer: Bool {
    batch.position.x > layout.dockX + 0.3 && pose.truckOffset == 0 && pose.truckOpacity > 0.99
  }
  func setTrailerCut(_ on: Bool) {
    guard on != trailerCut else { return }
    trailerCut = on
    for (e, i, day) in roofParts {
      guard var model = e.components[ModelComponent.self], i < model.materials.count else { continue }
      var p = day
      if on { p.blending = .transparent(opacity: .init(floatLiteral: Self.cutOpacity)) }
      model.materials[i] = p
      e.components.set(model)
    }
  }
  /// Diagnostics/tests: the current opacity of the trailer body.
  var roofOpacity: Float {
    guard let (e, i, _) = roofParts.first, let p = e.components[ModelComponent.self]?.materials[i] as? PhysicallyBasedMaterial,
      case .transparent(let o) = p.blending
    else { return 1 }
    return o.scale
  }

  // MARK: Following a live subject

  /// The closest framing of the batch or the forklift: the subject with the hall around it.
  static let followMinScale: Float = 8
  /// How far east the camera can see the truck (beyond it the yard ends in the haze).
  static let siteLimitX: Float = 34
  private var truckDocked: BoundingBox?

  /// The part of a subject the camera keeps in view: the batch (the next batch's pickup once
  /// the loaded truck has pulled out), the forklift, or the visible part of the truck (its bay
  /// while it is away).
  func followBounds(_ s: AtelierSubject) -> BoundingBox {
    let floor = layout.floor
    switch s {
    case .batch:
      if case .slot = pose.batch, pose.truckOffset > 6 || pose.truckOpacity < 0.5 {
        let h = AtelierTimeline.batchSize / 2
        let c = SIMD3(layout.pickup.x, floor + h.y, layout.pickup.y)
        return BoundingBox(min: c - h, max: c + h)
      }
      return batch.visualBounds(relativeTo: nil)
    case .forklift:
      return forklift.visualBounds(relativeTo: nil)
    case .truck:
      guard let truck, truck.isEnabled, pose.truckOpacity > 0.05 else {
        return truckDocked ?? BoundingBox(min: layout.truck - 2, max: layout.truck + 2)
      }
      var b = truck.visualBounds(relativeTo: nil)
      if truckDocked == nil, pose.truckOffset == 0 { truckDocked = b }
      b.max.x = min(b.max.x, Self.siteLimitX)
      b.min.x = min(b.min.x, b.max.x - 2)
      return b
    }
  }

  /// Screen axes (world) of the current orbit: right and up.
  private var screenAxes: (right: SIMD3<Float>, up: SIMD3<Float>) {
    let a = (45 + azimuth) * .pi / 180
    let elevation: Float = 35.264 * .pi / 180
    let forward = -SIMD3<Float>(cos(elevation) * cos(a), sin(elevation), cos(elevation) * sin(a))
    let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
    return (right, simd_cross(right, forward))
  }

  /// The focus that shows a subject in the middle of the free band of the screen (between the
  /// header, `top` of the height, and the card, `bottom`) at the current scale.
  func followFocus(_ s: AtelierSubject, top: Float, bottom: Float) -> SIMD3<Float> {
    followBounds(s).center + screenAxes.up * (top - bottom) * scale
  }

  /// The scale (half-height of the view, m) that fits a subject into the free band with a margin;
  /// small subjects keep some surroundings.
  func fitScale(_ s: AtelierSubject, aspect: Float, top: Float, bottom: Float) -> Float {
    let b = followBounds(s)
    let (right, up) = screenAxes
    var hx: Float = 0, hy: Float = 0
    for i in 0..<8 {
      let corner = SIMD3(i & 1 == 0 ? b.min.x : b.max.x, i & 2 == 0 ? b.min.y : b.max.y, i & 4 == 0 ? b.min.z : b.max.z)
      let o = corner - b.center
      hx = max(hx, abs(simd_dot(o, right)))
      hy = max(hy, abs(simd_dot(o, up)))
    }
    let free = max(0.3, 1 - top - bottom)
    let fit = max(hy * 1.3 / free, hx * 1.12 / max(0.2, aspect))
    return min(26, max(s == .truck ? 6 : Self.followMinScale, fit))
  }

  // MARK: Camera

  /// Places the user picks: quality control, packing, shipping, the whole section.
  enum Zone: String, CaseIterable {
    case quality, packing, shipping, site
    var title: String {
      switch self {
      case .quality: return "Контроль"
      case .packing: return "Упаковка"
      case .shipping: return "Отгрузка"
      case .site: return "Весь участок"
      }
    }
    var view: (focus: SIMD3<Float>, scale: Float) {
      switch self {
      case .quality: return (SIMD3(5.0, 1.2, 4.8), 6.5)
      case .packing: return (SIMD3(6.0, 1.2, 9.6), 6.0)
      case .shipping: return (SIMD3(14.0, 1.2, 13.0), 9.5)
      case .site: return (SIMD3(11, 1.2, 10), 13)
      }
    }
  }

  func placeCamera() {
    let a = (45 + azimuth) * .pi / 180
    let elevation: Float = 35.264 * .pi / 180
    let dir = SIMD3<Float>(cos(elevation) * cos(a), sin(elevation), cos(elevation) * sin(a))
    let distance = scale / tan(Self.fieldOfView / 2 * .pi / 180)
    camera.look(at: focus, from: focus + dir * distance, relativeTo: nil)
  }
}

extension Entity {
  /// Depth-first visit of this entity and its descendants.
  func visit(_ body: (Entity) -> Void) {
    body(self)
    for child in children { child.visit(body) }
  }
}
