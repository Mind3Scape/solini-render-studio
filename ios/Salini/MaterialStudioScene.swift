import SceneKit
import simd

#if canImport(UIKit)
  import UIKit
  typealias StudioColor = UIColor
  /// SceneKit vector component type: Float on iOS, CGFloat on macOS (offscreen tuning harness).
  typealias SceneFloat = Float
  typealias StudioBezierPath = UIBezierPath
#else
  import AppKit
  typealias StudioColor = NSColor
  typealias SceneFloat = CGFloat
  typealias StudioBezierPath = NSBezierPath
  extension NSBezierPath {
    func addLine(to p: CGPoint) { line(to: p) }
    func addCurve(to p: CGPoint, controlPoint1 c1: CGPoint, controlPoint2 c2: CGPoint) {
      curve(to: p, controlPoint1: c1, controlPoint2: c2)
    }
  }
#endif

/// The three real Salini surfaces. Parameters are an illustration of light response
/// (soft scatter vs. clear Gelcoat reflection), not measured BRDF scans.
enum StudioFinish: String, CaseIterable, Codable {
  case stoneMatte, senseMatte, senseGloss
  var material: String { self == .stoneMatte ? "sStone" : "sSense" }
  var finish: String { self == .senseGloss ? "gloss" : "matte" }
  var title: String {
    switch self {
    case .stoneMatte: return "S-Stone · матовое"
    case .senseMatte: return "S-Sense · матовое"
    case .senseGloss: return "S-Sense · глянцевое"
    }
  }
  var short: String {
    switch self {
    case .stoneMatte: return "S-Stone"
    case .senseMatte: return "S-Sense мат"
    case .senseGloss: return "S-Sense глянец"
    }
  }
  init?(material: String?, finish: String?) {
    switch (material, finish) {
    case ("sStone", _): self = .stoneMatte
    case ("sSense", "matte"): self = .senseMatte
    case ("sSense", "gloss"): self = .senseGloss
    default: return nil
    }
  }
  /// Applies the finish to a physically based material, keeping its colour.
  func apply(to m: SCNMaterial, colour: StudioColor) {
    m.lightingModel = .physicallyBased
    m.diffuse.contents = colour
    m.metalness.contents = 0.0
    switch self {
    case .stoneMatte:
      m.roughness.contents = 0.74
      m.clearCoat.contents = 0.0
    case .senseMatte:
      m.roughness.contents = 0.5
      m.clearCoat.contents = 0.45
      m.clearCoatRoughness.contents = 0.42
    case .senseGloss:
      m.roughness.contents = 0.32
      m.clearCoat.contents = 1.0
      m.clearCoatRoughness.contents = 0.025
    }
  }
}

enum SCNStudioPath {
  /// L-profile with a rounded cove: floor from x = 0…depth, curving up into a wall of `height`.
  static func cyclorama(depth: CGFloat, height: CGFloat, radius: CGFloat) -> StudioBezierPath {
    let p = StudioBezierPath()
    p.move(to: CGPoint(x: 0, y: -0.02))
    p.addLine(to: CGPoint(x: depth - radius, y: -0.02))
    p.addCurve(to: CGPoint(x: depth, y: radius), controlPoint1: CGPoint(x: depth - radius * 0.45, y: -0.02),
               controlPoint2: CGPoint(x: depth, y: radius * 0.55))
    p.addLine(to: CGPoint(x: depth, y: height))
    p.addLine(to: CGPoint(x: depth + 0.05, y: height))
    p.addLine(to: CGPoint(x: depth + 0.05, y: -0.07))
    p.addLine(to: CGPoint(x: 0, y: -0.07))
    p.close()
    return p
  }
}

/// A calm white studio around one official Salini model: cyclorama, soft key light with
/// contact shadow, and a procedural environment whose softboxes show up in glossy reflections.
final class StudioScene {
  enum Shot { case form, macro }
  let scene = SCNScene()
  let model: SCNNode
  let camera = SCNNode()
  private let key = SCNNode()
  private let rig = SCNNode()
  private(set) var size = SCNVector3Zero
  private(set) var finish: StudioFinish
  private(set) var colour: StudioColor

  static let white = StudioColor(red: 0.87, green: 0.868, blue: 0.86, alpha: 1)
  /// Graphite cyclorama: the white product reads as an object, reflections read as light.
  static let floorColour = StudioColor(red: 0.16, green: 0.165, blue: 0.175, alpha: 1)

  init?(modelURL: URL, finish: StudioFinish, colour: StudioColor = StudioScene.white) {
    guard let source = try? SCNScene(url: modelURL, options: nil) else { return nil }
    self.finish = finish
    self.colour = colour
    let holder = SCNNode()
    for child in source.rootNode.childNodes { holder.addChildNode(child.clone()) }
    holder.enumerateHierarchy { n, _ in
      n.camera = nil
      n.light = nil
    }
    // Normalise: longest side → 1.8 units, centred on X/Z, resting on the floor (y = 0).
    let (lo, hi) = holder.boundingBox
    let longest = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
    guard longest.isFinite, longest > 0 else { return nil }
    let s = 1.8 / longest
    holder.scale = SCNVector3(s, s, s)
    holder.position = SCNVector3(-(lo.x + hi.x) * 0.5 * s, -lo.y * s, -(lo.z + hi.z) * 0.5 * s)
    // Long axis along X so every model is framed the same way.
    let wrapper = SCNNode()
    wrapper.addChildNode(holder)
    if (hi.z - lo.z) > (hi.x - lo.x) { wrapper.eulerAngles.y = .pi / 2 }
    model = wrapper
    let (wlo, whi) = wrapper.boundingBox
    size = SCNVector3(whi.x - wlo.x, whi.y - wlo.y, whi.z - wlo.z)
    scene.rootNode.addChildNode(wrapper)
    build()
    apply(finish: finish, colour: colour)
    frame(.form, animated: false)
  }

  private var floorMaterial: SCNMaterial?
  private var overheadLight: SCNNode?
  private var fillLight: SCNNode?
  private var cyclorama: SCNNode?
  static let floorOnly = 1 << 3
  static let modelOnly = 1 << 4
  /// Tight contact darkening built from the model's own vertices near the floor (feet, base,
  /// plinth), blurred into a soft map: it follows the real footprint, not a drawn ellipse.
  private func contactOcclusion(reach: Float = 0.25, falloff: Float = 0.05, radius: Int = 4, passes: Int = 3,
                                strength: CGFloat = 0.8, margin: Float = 0.12) {
    let (lo, hi) = model.boundingBox
    let minX = Float(lo.x) - margin, maxX = Float(hi.x) + margin
    let minZ = Float(lo.z) - margin, maxZ = Float(hi.z) + margin
    let w = 160
    let h = max(16, Int(Float(w) * (maxZ - minZ) / max(0.01, maxX - minX)))
    var grid = [Float](repeating: 0, count: w * h)
    model.enumerateHierarchy { node, _ in
      guard let geometry = node.geometry,
        let source = geometry.sources(for: .vertex).first, source.usesFloatComponents,
        source.bytesPerComponent == 4
      else { return }
      let transform = node.simdWorldTransform
      let count = source.vectorCount
      let step = max(1, count / 60000)
      source.data.withUnsafeBytes { raw in
        var i = 0
        while i < count {
          let base = source.dataOffset + i * source.dataStride
          let x = raw.load(fromByteOffset: base, as: Float.self)
          let y = raw.load(fromByteOffset: base + 4, as: Float.self)
          let z = raw.load(fromByteOffset: base + 8, as: Float.self)
          let p = transform * SIMD4<Float>(x, y, z, 1)
          let height = p.y
          if height < reach {
            let gx = Int((p.x - minX) / (maxX - minX) * Float(w - 1))
            let gz = Int((p.z - minZ) / (maxZ - minZ) * Float(h - 1))
            if gx >= 0, gx < w, gz >= 0, gz < h {
              let weight = exp(-max(0, height) / falloff)
              grid[gz * w + gx] = max(grid[gz * w + gx], weight)
            }
          }
          i += step
        }
      }
    }
    // Box blur, three passes, radius 4 px: a soft but footprint-shaped falloff.
    for _ in 0..<passes {
      var tmp = grid
      for z in 0..<h {
        for x in 0..<w {
          var sum: Float = 0
          var n: Float = 0
          for dx in -radius...radius where x + dx >= 0 && x + dx < w { sum += grid[z * w + x + dx]; n += 1 }
          tmp[z * w + x] = sum / n
        }
      }
      for z in 0..<h {
        for x in 0..<w {
          var sum: Float = 0
          var n: Float = 0
          for dz in -radius...radius where z + dz >= 0 && z + dz < h { sum += tmp[(z + dz) * w + x]; n += 1 }
          grid[z * w + x] = sum / n
        }
      }
    }
    let peak = max(0.001, grid.max() ?? 1)
    // rgbZero: black is opaque, white is clear — so the contact (dark) area is black.
    var bytes = grid.map { 255 - UInt8(min(255, max(0, $0 / peak * 255 * Float(strength)))) }
    guard let provider = CGDataProvider(data: Data(bytes: &bytes, count: bytes.count) as CFData),
      let mask = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return }
    let plane = SCNPlane(width: CGFloat(maxX - minX), height: CGFloat(maxZ - minZ))
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = StudioColor.black
    m.transparent.contents = mask
    m.transparencyMode = .rgbZero
    m.writesToDepthBuffer = false
    plane.materials = [m]
    let node = SCNNode(geometry: plane)
    node.eulerAngles.x = -SceneFloat.pi / 2
    node.position = SCNVector3((minX + maxX) / 2, 0.002, (minZ + maxZ) / 2)
    node.castsShadow = false
    node.renderingOrder = 5
    scene.rootNode.addChildNode(node)
  }
  /// Print variant for the PDF: a light warm-grey sweep so dark RAL colours keep their edge,
  /// plus a soft rim light from behind that outlines the form.
  /// Print lighting presets. Print renders run without HDR tone mapping so iOS and macOS keep
  /// the same balance; they differ in fill, key, bounce on the model and shadow strength.
  /// Live studio exposure presets. The iOS runtime renders this scene about a stop darker than
  /// macOS off-screen renders, so the live default is lifted; clearcoat and roughness stay as
  /// they are — only exposure, fill and environment strength change.
  /// Live studio exposure presets for review on the iOS runtime (clearcoat and roughness are
  /// never changed — only exposure, fill and environment strength).
  enum LiveLighting: String, CaseIterable {
    case reference, lifted, airy
    var exposure: CGFloat { [-0.32, -0.15, 0.05][index] }
    var fill: CGFloat { [60, 110, 170][index] }
    var environment: CGFloat { [2.6, 2.8, 3.0][index] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
  }
  static var liveLighting: LiveLighting = .lifted
  /// Print tone mapping (chosen on iOS fixtures): highlights roll off so a white bowl keeps its
  /// inner gradient; dark RAL colours keep the accepted `balanced` look.
  static var printExposure: CGFloat = -0.25
  static var printWhitePoint: CGFloat = 1.45
  func useLiveLighting(_ lighting: LiveLighting) {
    camera.camera?.exposureOffset = lighting.exposure
    fillLight?.light?.intensity = lighting.fill
    scene.lightingEnvironment.intensity = lighting.environment
  }
  enum PrintLighting: String, CaseIterable {
    case balanced, bright, highKey
    var ambient: CGFloat { [400, 520, 640][index] }
    var key: CGFloat { [640, 720, 560][index] }
    var bounce: CGFloat { [620, 760, 700][index] }
    var shadow: CGFloat { [0.5, 0.42, 0.34][index] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
  }
  func usePrintBackdrop(_ lighting: PrintLighting = .balanced) {
    // HDR tone mapping rolls highlights off instead of clipping: a white bowl keeps its curve.
    // (The earlier dark iOS frames came from deferred shadows, not from HDR.)
    camera.camera?.wantsHDR = true
    camera.camera?.wantsExposureAdaptation = false
    camera.camera?.exposureOffset = StudioScene.printExposure
    camera.camera?.whitePoint = StudioScene.printWhitePoint
    camera.camera?.bloomIntensity = 0
    camera.camera?.vignettingIntensity = 0
    scene.lightingEnvironment.intensity = 2.6
    // The background is not rendered at all: a transparent frame over an invisible floor that
    // only receives shadows. The page supplies the light neutral ground, identical on every
    // platform; the render carries the product, its contact darkening and its cast shadow.
    scene.background.contents = StudioColor.clear
    cyclorama?.isHidden = true
    // A broad, soft shadow from the model's own silhouette under the tight contact layer.
    contactOcclusion(reach: 0.9, falloff: 0.35, radius: 9, passes: 4, strength: lighting.shadow, margin: 0.55)
    overheadLight?.light?.intensity = 0
    overheadLight?.light?.castsShadow = false
    // Print shadows come from the model's own geometry layers; no light runs a shadow pass.
    key.light?.castsShadow = false
    fillLight?.light?.intensity = lighting.ambient
    key.light?.intensity = lighting.key
    key.light?.shadowColor = StudioColor(white: 0, alpha: lighting.shadow)
    // Soft rim from behind outlines dark colours against the sweep.
    let rim = SCNNode()
    rim.light = SCNLight()
    rim.light?.type = .directional
    rim.light?.intensity = 380
    rim.light?.color = StudioColor(red: 0.96, green: 0.97, blue: 1, alpha: 1)
    rim.eulerAngles = SCNVector3(-0.5, SceneFloat.pi, 0)
    scene.rootNode.addChildNode(rim)
    // A broad bounce from the viewer's side, high up and on the model only: it opens the inner
    // bowl so a dark RAL reads as a curved surface without changing the colour itself.
    let bounce = SCNNode()
    bounce.light = SCNLight()
    bounce.light?.type = .directional
    bounce.light?.intensity = lighting.bounce
    bounce.light?.categoryBitMask = StudioScene.modelOnly
    model.enumerateHierarchy { n, _ in n.categoryBitMask |= StudioScene.modelOnly }
    bounce.light?.color = StudioColor(red: 1, green: 0.985, blue: 0.96, alpha: 1)
    bounce.eulerAngles = SCNVector3(-1.1, 0.35, 0)
    scene.rootNode.addChildNode(bounce)
  }
  private func build() {
    scene.background.contents = StudioScene.backdrop()
    scene.lightingEnvironment.contents = StudioScene.environment()
    scene.lightingEnvironment.intensity = 2.6
    // Seamless cyclorama (floor sweeping up into a wall): no horizon line in any shot.
    let profile = SCNStudioPath.cyclorama(depth: 9, height: 7, radius: 2.4)
    let sweep = SCNShape(path: profile, extrusionDepth: 40)
    let fm = SCNMaterial()
    fm.lightingModel = .physicallyBased
    fm.diffuse.contents = StudioScene.floorColour
    fm.roughness.contents = 0.95
    fm.isDoubleSided = true
    sweep.materials = [fm]
    floorMaterial = fm
    let cyc = SCNNode(geometry: sweep)
    cyclorama = cyc
    // Path is drawn in the X/Y plane (x = depth, y = height); rotate so depth runs along -Z.
    cyc.eulerAngles.y = .pi / 2
    cyc.position = SCNVector3(0, 0, 4)
    cyc.castsShadow = false
    cyc.categoryBitMask = 1 | StudioScene.floorOnly
    scene.rootNode.addChildNode(cyc)
    // Overhead softbox that lights only the floor: the model's real shadow from it reads as a
    // soft pool of shade under the form, so the object stands instead of floating.
    let overhead = SCNNode()
    overheadLight = overhead
    overhead.light = SCNLight()
    overhead.light?.type = .spot
    overhead.light?.categoryBitMask = StudioScene.floorOnly
    overhead.light?.intensity = 240
    overhead.light?.spotInnerAngle = 30
    overhead.light?.spotOuterAngle = 72
    overhead.light?.attenuationStartDistance = 0
    overhead.light?.attenuationEndDistance = 12
    overhead.light?.castsShadow = true
    overhead.light?.shadowMode = .forward
    overhead.light?.shadowRadius = 22
    overhead.light?.shadowSampleCount = 32
    overhead.light?.shadowColor = StudioColor(white: 0, alpha: 0.78)
    overhead.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
    overhead.position = SCNVector3(0, 3.0, 0.15)
    overhead.eulerAngles = SCNVector3(-SceneFloat.pi / 2, 0, 0)
    scene.rootNode.addChildNode(overhead)
    contactOcclusion()
    scene.rootNode.addChildNode(rig)
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.intensity = 1250
    key.light?.color = StudioColor(red: 1, green: 0.985, blue: 0.965, alpha: 1)
    key.light?.castsShadow = true
    // Forward shadows: computed in the light's own shader pass. With `.deferred` the iOS runtime
    // dropped this light's contribution entirely (flat, grey model; no cast shadow).
    key.light?.shadowMode = .forward
    key.light?.shadowRadius = 14
    key.light?.shadowSampleCount = 24
    key.light?.shadowColor = StudioColor(white: 0, alpha: 0.55)
    key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    key.light?.orthographicScale = 2.6
    key.light?.automaticallyAdjustsShadowProjection = true
    key.eulerAngles = SCNVector3(-1.05, 0, 0)
    rig.addChildNode(key)
    let fill = SCNNode()
    fillLight = fill
    fill.light = SCNLight()
    fill.light?.type = .ambient
    fill.light?.intensity = 60
    scene.rootNode.addChildNode(fill)
    camera.camera = SCNCamera()
    camera.camera?.wantsHDR = true
    camera.camera?.exposureOffset = -0.32
    camera.camera?.wantsExposureAdaptation = false
    camera.camera?.bloomIntensity = 0
    camera.camera?.vignettingIntensity = 0.18
    camera.camera?.vignettingPower = 0.6
    camera.camera?.zNear = 0.02
    camera.camera?.zFar = 40
    scene.rootNode.addChildNode(camera)
    useLiveLighting(Self.liveLighting)
    setLight(0.42)
  }

  func apply(finish: StudioFinish, colour: StudioColor) {
    self.finish = finish
    self.colour = colour
    model.enumerateHierarchy { n, _ in
      for m in n.geometry?.materials ?? [] { finish.apply(to: m, colour: colour) }
    }
  }

  /// 0…1 moves the key light and rotates the softbox environment together around the model.
  func setLight(_ t: Double) {
    let angle = SceneFloat(-1.35 + 2.2 * t)
    rig.eulerAngles.y = angle
    let rotation = SCNMatrix4MakeRotation(-angle, 0, 1, 0)
    scene.lightingEnvironment.contentsTransform = rotation
  }

  /// Viewport width / height. Framing is recomputed for it, so narrow phones never crop the form.
  var aspect: CGFloat = 1.3 {
    didSet { if abs(aspect - oldValue) > 0.01 { frame(shot, animated: false) } }
  }
  private(set) var shot: Shot = .form

  /// Form: the whole object and its contact shadow, fitted by projecting every corner of the
  /// bounds for the actual aspect ratio. Macro: the real front rim large, curvature readable.
  func frame(_ shot: Shot, animated: Bool) {
    self.shot = shot
    let L = Float(size.x), H = Float(size.y), W = Float(size.z)
    let vfov: Float = shot == .form ? 26 : 32
    let dir: SIMD3<Float>
    let initialTarget: SIMD3<Float>
    let margin: Float
    var corners: [SIMD3<Float>] = []
    switch shot {
    case .form:
      dir = simd_normalize(SIMD3(-0.46, 0.52, 0.72))
      initialTarget = SIMD3(0, H * 0.36, 0)
      margin = 0.07
      // Whole object plus a strip of floor around it for the contact shadow.
      for x in [-L * 0.53, L * 0.53] { for y in [Float(0), H] { for z in [-W * 0.6, W * 0.6] { corners.append(SIMD3(x, y, z)) } } }
    case .macro:
      // The near end of the front rim, inner bowl and outer wall: a real crop, still a bath.
      dir = simd_normalize(SIMD3(-0.52, 0.5, 0.69))
      initialTarget = SIMD3(-L * 0.24, H * 0.8, W * 0.12)
      margin = 0.04
      for x in [-L * 0.52, L * 0.02] { for y in [H * 0.45, H] { for z in [-W * 0.5, W * 0.5] { corners.append(SIMD3(x, y, z)) } } }
    }
    let up = SIMD3<Float>(0, 1, 0)
    let forward = -dir
    let right = simd_normalize(simd_cross(forward, up))
    let camUp = simd_cross(right, forward)
    let tanV = tan(vfov * .pi / 360) * (1 - margin)
    let tanH = tan(vfov * .pi / 360) * Float(aspect) * (1 - margin)
    // Fit, then re-centre the projected bounds and fit again (converges in a few passes).
    var target = initialTarget
    var distance: Float = 0.5
    for _ in 0..<4 {
      distance = 0.5
      for c in corners {
        let v = c - target
        let along = simd_dot(v, dir)
        distance = max(distance, along + abs(simd_dot(v, right)) / tanH, along + abs(simd_dot(v, camUp)) / tanV)
      }
      var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
      var hi = -lo
      for c in corners {
        let v = c - target
        let depth = distance - simd_dot(v, dir)
        let ndc = SIMD2(simd_dot(v, right) / (depth * tanH), simd_dot(v, camUp) / (depth * tanV))
        lo = simd_min(lo, ndc)
        hi = simd_max(hi, ndc)
      }
      let centre = (lo + hi) / 2
      target += right * (centre.x * tanH * distance) + camUp * (centre.y * tanV * distance)
    }
    let p = target + dir * distance
    let position = SCNVector3(SceneFloat(p.x), SceneFloat(p.y), SceneFloat(p.z))
    let look = SCNVector3(SceneFloat(target.x), SceneFloat(target.y), SceneFloat(target.z))
    let apply = {
      self.camera.position = position
      self.camera.look(at: look)
      self.camera.camera?.projectionDirection = .vertical
      self.camera.camera?.fieldOfView = CGFloat(vfov)
      self.camera.camera?.wantsDepthOfField = shot == .macro
      self.camera.camera?.fStop = 2.4
      self.camera.camera?.focusDistance = CGFloat(distance)
    }
    if animated {
      SCNTransaction.begin()
      SCNTransaction.animationDuration = 0.9
      SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      apply()
      SCNTransaction.commit()
    } else {
      apply()
    }
  }

  // MARK: Procedural imagery (no bundled HDR needed)

  /// Equirectangular studio: dim grey room, one large softbox, one tall strip, a dark flag below.
  static func environment(width: Int = 1024, height: Int = 512) -> CGImage? {
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let w = CGFloat(width), h = CGFloat(height)
    let space = CGColorSpaceCreateDeviceRGB()
    let room = CGGradient(
      colorsSpace: space,
      colors: [
        CGColor(red: 0.30, green: 0.30, blue: 0.31, alpha: 1), CGColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1),
        CGColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1),
      ] as CFArray, locations: [0, 0.5, 1])!
    // CGContext origin is bottom-left; the image top is the zenith.
    ctx.drawLinearGradient(room, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
    func softbox(_ rect: CGRect, _ level: CGFloat) {
      ctx.saveGState()
      ctx.setShadow(offset: .zero, blur: 18, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
      ctx.setFillColor(CGColor(red: level, green: level, blue: level * 0.985, alpha: 1))
      ctx.fill(rect)
      ctx.restoreGState()
    }
    // Overhead softbox band and four tall strip lights around the set: on Gelcoat gloss they
    // read as crisp vertical reflections, on matte surfaces they melt into soft gradients.
    softbox(CGRect(x: w * 0.18, y: h * 0.88, width: w * 0.3, height: h * 0.1), 0.75)
    for (u, level) in [(0.10, 1.0), (0.36, 0.9), (0.61, 1.0), (0.86, 0.8)] as [(CGFloat, CGFloat)] {
      softbox(CGRect(x: w * u, y: h * 0.40, width: w * 0.028, height: h * 0.36), level)
    }
    // A low reflector card all around: the flared outer wall of a bath faces slightly down,
    // so this band is what the Gelcoat mirrors there as one crisp horizontal line.
    softbox(CGRect(x: 0, y: h * 0.31, width: w, height: h * 0.05), 1.0)
    softbox(CGRect(x: 0, y: h * 0.235, width: w, height: h * 0.018), 0.85)
    return ctx.makeImage()
  }

  /// Seamless warm-white cyclorama behind the object.
  static func backdrop(width: Int = 64, height: Int = 512) -> CGImage? {
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let g = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [CGColor(red: 0.24, green: 0.245, blue: 0.255, alpha: 1), CGColor(red: 0.16, green: 0.165, blue: 0.175, alpha: 1)]
        as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
    return ctx.makeImage()
  }
}
