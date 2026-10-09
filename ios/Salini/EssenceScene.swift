import CoreGraphics
import SceneKit
import simd

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// «Камень изнутри»: two engineered Salini specimens split open along an oblique cut, beside
/// small polished pieces of the raw minerals they come from. S-Stone is one homogeneous mass —
/// its cut shows the same fine mineral grain as its surface. S-Sense is a mineral core (marble
/// crumb in resin) inside a Gelcoat skin — its cut shows the core framed by the skin. The skin
/// is drawn far thicker than 0.8 mm and the specimens are sculptural, not product parts; the UI
/// labels the whole scene as a schematic.
///
/// Geometry is built here: an icosphere displaced by low-frequency noise and chipped by a few
/// random cleavage planes (flat facets), then clipped by the cut plane; the clipped part becomes
/// a flat polished face with planar texture coordinates. Textures are procedural (no bitmaps
/// shipped). Light: a small procedural studio environment plus one low, raking key whose soft
/// shadow falls on the card through a shadow-only catcher (the view is transparent).
final class EssenceScene {
  enum Specimen: String, CaseIterable {
    case stone, sense, bauxite, marble
  }

  let scene = SCNScene()
  let camera = SCNNode()
  private let key = SCNNode()
  private let world = SCNNode()
  private var masses: [Specimen: SplitMass] = [:]
  private var gelcoat: [SCNMaterial] = []
  /// Ground plane height (the card's «table»).
  static let floorY: Float = -1.05

  /// Where each specimen rests and floats (x, y, z, yaw degrees). S-Stone is the hero that rises
  /// past the card's top edge into the stage's reserved margin.
  private static let home: [Specimen: SIMD4<Float>] = [
    .stone: SIMD4(-0.55, 1.08, -0.4, 14),
    .sense: SIMD4(0.42, -0.25, 0.45, -12),
    .bauxite: SIMD4(-1.0, -0.82, 1.2, 0),
    .marble: SIMD4(1.05, -0.95, 1.4, 0),
  ]

  init() {
    scene.rootNode.addChildNode(world)
    buildLight()
    buildCamera()
    let tex = EssenceTextures.shared
    // S-Stone: the same mineral mass outside and in the cut (the cut honed a little finer).
    let stoneOuter = Self.material(tex.stone, rough: 0.62, normal: tex.stoneNormal, normalScale: 0.55)
    let stoneCut = Self.material(tex.stone, rough: 0.34, normal: tex.stoneNormal, normalScale: 0.2)
    let stone = SplitMass(tag: .stone, seed: 3, radius: 0.74, squash: SIMD3(1.12, 0.84, 0.86), facets: 7, tile: 3,
                          cut: simd_normalize(SIMD3(0.72, 0.28, 0.64)), offset: 0.0,
                          outer: stoneOuter, cut: stoneCut, rim: nil, rimDepth: 0)
    // S-Sense: Gelcoat skin outside; the cut shows the core inside a band of the skin.
    let coat = Self.material(nil, rough: 0.4, normal: nil, normalScale: 0, colour: SIMD3(0.86, 0.86, 0.85))
    gelcoat.append(coat)
    let core = Self.material(tex.core, rough: 0.4, normal: tex.coreNormal, normalScale: 0.35)
    // A smooth, moulded body: the Gelcoat skin is a cast surface, not a broken stone.
    let sense = SplitMass(tag: .sense, seed: 11, radius: 0.64, squash: SIMD3(1.14, 0.8, 0.86), facets: 0, relief: 0.035, swing: -1, tile: 1.7,
                          cut: simd_normalize(SIMD3(-0.72, 0.28, 0.64)), offset: 0.0,
                          outer: coat, cut: core, rim: coat, rimDepth: 0.06)
    // Raw minerals: single polished slices of a chipped stone (illustration).
    let bauxite = SplitMass(tag: .bauxite, seed: 7, radius: 0.27, squash: SIMD3(1.15, 0.8, 0.95), facets: 9,
                            cut: simd_normalize(SIMD3(0.62, 0.42, 0.66)), offset: 0.05,
                            outer: Self.material(tex.bauxite, rough: 0.88, normal: tex.rockNormal, normalScale: 1.1),
                            cut: Self.material(tex.bauxite, rough: 0.3, normal: nil, normalScale: 0), rim: nil, rimDepth: 0,
                            single: true)
    let marble = SplitMass(tag: .marble, seed: 19, radius: 0.25, squash: SIMD3(1.1, 0.85, 0.95), facets: 9,
                           cut: simd_normalize(SIMD3(-0.62, 0.42, 0.66)), offset: 0.05,
                           outer: Self.material(tex.marble, rough: 0.72, normal: tex.rockNormal, normalScale: 0.9, tint: 0.88),
                           cut: Self.material(tex.marble, rough: 0.14, normal: nil, normalScale: 0), rim: nil, rimDepth: 0,
                           single: true)
    masses = [.stone: stone, .sense: sense, .bauxite: bauxite, .marble: marble]
    for m in masses.values { world.addChildNode(m.root) }
    // Shadow catcher: the card's surface receives the key's soft shadow only.
    let plane = SCNPlane(width: 12, height: 8)
    let m = SCNMaterial()
    m.lightingModel = .shadowOnly
    m.writesToDepthBuffer = false
    plane.materials = [m]
    let floor = SCNNode(geometry: plane)
    floor.simdEulerAngles.x = -.pi / 2
    floor.simdPosition = SIMD3(0, Self.floorY, 0)
    floor.castsShadow = false
    scene.rootNode.addChildNode(floor)
    setFinish(.stoneMatte)
    pose(time: 0, opening: 1, emphasis: 0, motion: false)
  }

  // MARK: Light and camera

  private func buildLight() {
    // A small procedural studio (no HDR decode at launch): soft ceiling, dark floor, a broad box
    // behind and above whose mirror image tells gloss Gelcoat (crisp) from matte (diffused).
    scene.lightingEnvironment.contents = EssenceTextures.studio()
    scene.lightingEnvironment.intensity = 0.72
    // A low raking key from the left: it models the facets and the cut faces and lays a long,
    // soft shadow on the card.
    let l = SCNLight()
    l.type = .directional
    l.intensity = 760
    l.color = StudioColor(red: 1, green: 0.98, blue: 0.95, alpha: 1)
    l.castsShadow = true
    l.shadowMode = .forward
    l.shadowRadius = 22
    l.shadowSampleCount = 24
    l.shadowMapSize = CGSize(width: 2048, height: 2048)
    l.shadowColor = StudioColor(white: 0, alpha: 0.2)
    l.automaticallyAdjustsShadowProjection = true
    key.light = l
    key.simdPosition = SIMD3(-1.6, 5.2, 5.0)
    key.simdLook(at: SIMD3(0, 0, 0))
    scene.rootNode.addChildNode(key)
  }

  private func buildCamera() {
    let c = SCNCamera()
    // Fixed horizontal angle: the whole composition fits any phone width (taller stages simply
    // get more air above and below).
    c.projectionDirection = .horizontal
    c.fieldOfView = 24
    c.zNear = 0.1
    c.zFar = 50
    camera.camera = c
    camera.simdPosition = SIMD3(0, 1.9, 7.6)
    camera.simdLook(at: SIMD3(0, 0.05, 0))
    scene.rootNode.addChildNode(camera)
  }

  // MARK: State

  private(set) var finish: StudioFinish = .stoneMatte
  /// Gelcoat gloss or matte (the S-Sense specimen shows the current S-Sense finish).
  func setFinish(_ f: StudioFinish) {
    finish = f
    let gloss = f == .senseGloss
    for m in gelcoat {
      m.roughness.contents = gloss ? 0.1 : 0.48
      m.clearCoat.contents = gloss ? 1.0 : 0.0
      m.clearCoatRoughness.contents = 0.04
    }
  }

  /// The composition at a time. `opening` 0…1 parts the halves along the cut; `emphasis`
  /// 0 = S-Stone forward, 1 = S-Sense forward; `motion` adds the slow float (off for Reduce
  /// Motion and when paused — the pose is then fully static).
  func pose(time t: Double, opening: Float, emphasis: Float, motion: Bool) {
    let e = max(0, min(1, emphasis))
    for (spec, mass) in masses {
      let h = Self.home[spec]!
      let engineered = spec == .stone || spec == .sense
      let focus: Float = spec == .stone ? 1 - e : spec == .sense ? e : 0
      let phase: Double = [.stone: 0, .sense: 1.7, .bauxite: 0.4, .marble: 2.6][spec]!
      let bob: Float = motion ? (engineered ? 0.04 : 0.025) * Float(sin(t * 0.8 + phase)) : 0
      let sway: Float = motion ? (engineered ? 4 : 7) * Float(sin(t * 0.33 + phase)) : 0
      mass.root.simdPosition = SIMD3(h.x, h.y + 0.08 * focus + bob, h.z + 0.3 * focus)
      mass.root.simdScale = SIMD3(repeating: engineered ? 0.9 + 0.1 * focus : 1)
      mass.root.simdOrientation = simd_quatf(angle: (h.w + sway) * .pi / 180, axis: SIMD3(0, 1, 0))
      mass.open(engineered ? opening * (0.6 + 0.4 * focus) : 0)
    }
  }

  /// World points the UI labels point at: the S-Stone cut, the Gelcoat band and the core of the
  /// S-Sense cut, the raw stones.
  func anchors() -> [String: SIMD3<Float>] {
    var out: [String: SIMD3<Float>] = [:]
    if let s = masses[.stone] { out["stone"] = s.anchor(.cut) }
    if let s = masses[.sense] {
      out["coat"] = s.anchor(.rim)
      out["core"] = s.anchor(.cut)
    }
    for k in [Specimen.bauxite, .marble] { if let r = masses[k] { out[k.rawValue] = r.root.simdWorldPosition } }
    return out
  }

  /// Which specimen a hit node belongs to (taps select S-Stone or S-Sense).
  func specimen(of node: SCNNode) -> Specimen? {
    var n: SCNNode? = node
    while let c = n {
      if let s = c.name.flatMap(Specimen.init(rawValue:)) { return s }
      n = c.parent
    }
    return nil
  }

  static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(v, 1)
    return m
  }
  /// A rotation about a point.
  static func about(_ c: SIMD3<Float>, _ q: simd_quatf) -> simd_float4x4 {
    translation(c) * simd_float4x4(q) * translation(-c)
  }

  // MARK: Materials

  static func material(_ image: CGImage?, rough: Float, normal: CGImage?, normalScale: Float,
                       colour: SIMD3<Float> = SIMD3(1, 1, 1), tint: Float = 1) -> SCNMaterial
  {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    if let image {
      m.diffuse.contents = image
      m.diffuse.wrapS = .repeat
      m.diffuse.wrapT = .repeat
      m.diffuse.mipFilter = .linear
      m.multiply.contents = StudioColor(white: CGFloat(min(1, tint)), alpha: 1)
    } else {
      m.diffuse.contents = StudioColor(red: CGFloat(colour.x), green: CGFloat(colour.y), blue: CGFloat(colour.z), alpha: 1)
    }
    m.metalness.contents = 0.0
    m.roughness.contents = rough
    if let normal {
      m.normal.contents = normal
      m.normal.intensity = CGFloat(normalScale)
      m.normal.wrapS = .repeat
      m.normal.wrapT = .repeat
    }
    return m
  }
}

// MARK: - A specimen split along a plane

/// A chipped mineral mass split by a plane into two halves (or one polished slice): each half
/// is the displaced, faceted body clipped by the plane, its clipped part a flat face. With a rim
/// material the cut face shows a band of that material where the body is shallower than
/// `rimDepth` below its outer surface (the skin of S-Sense).
private final class SplitMass {
  enum Anchor { case cut, rim }
  let root = SCNNode()
  private var halves: [SCNNode] = []
  private let normal: SIMD3<Float>
  private var cutCentre = SIMD3<Float>.zero
  private var rimPoint = SIMD3<Float>.zero
  private let radius: Float
  /// Which way the front half opens (mirror for a mass cut the other way).
  private let swing: Float

  init(tag: EssenceScene.Specimen, seed: Int, radius: Float, squash: SIMD3<Float>, facets: Int, relief: Float = 0.13,
       swing: Float = 1, tile: Float = 1, cut n: SIMD3<Float>,
       offset: Float, outer: SCNMaterial, cut: SCNMaterial, rim: SCNMaterial?, rimDepth: Float, single: Bool = false)
  {
    normal = n
    root.name = tag.rawValue
    self.radius = radius * squash.x
    self.swing = swing
    let body = Mass.body(seed: seed, radius: radius, squash: squash, facets: facets, relief: relief)
    // Half 0 keeps the side below the plane: its cut faces +n (the visible face); half 1 the rest.
    let a = Mass.clip(body, normal: n, offset: offset * radius, outer: outer, cut: cut, rim: rim, rimDepth: rimDepth,
                      scale: radius, tile: tile)
    cutCentre = a.centre
    rimPoint = a.rimPoint
    halves.append(a.node)
    if !single {
      let b = Mass.clip(body, normal: -n, offset: -offset * radius, outer: outer, cut: cut, rim: rim, rimDepth: rimDepth,
                        scale: radius, tile: tile)
      halves.append(b.node)
    }
    for h in halves { root.addChildNode(h) }
  }

  /// 0 = whole, 1 = opened like a book: the front half swings about a vertical hinge on the
  /// cut's right edge until both cut faces look at the viewer (as a split geode is shown).
  func open(_ t: Float) {
    let e = t * t * (3 - 2 * t)
    guard halves.count == 2 else { return }
    let side = simd_normalize(simd_cross(SIMD3(0, 1, 0), normal)) * swing
    let hinge = side * radius * 1.04
    halves[1].simdTransform = EssenceScene.about(hinge, simd_quatf(angle: 1.75 * e * swing, axis: SIMD3(0, 1, 0)))
      * EssenceScene.translation(side * 0.06 * e)
    halves[0].simdTransform = EssenceScene.about(-side * radius, simd_quatf(angle: -0.18 * e * swing, axis: SIMD3(0, 1, 0)))
  }

  func anchor(_ a: Anchor) -> SIMD3<Float> {
    halves[0].simdConvertPosition(a == .cut ? cutCentre : rimPoint, to: nil)
  }
}

private enum Mass {
  struct Body {
    let unit: [SIMD3<Float>]
    let points: [SIMD3<Float>]
    let tris: [SIMD3<UInt32>]
  }

  /// Unit-sphere directions displaced by noise and chipped by `facets` cleavage planes, scaled.
  static func body(seed: Int, radius: Float, squash: SIMD3<Float>, facets: Int, relief: Float) -> Body {
    let (verts, tris) = icosphere(subdivisions: 5)
    var rng = SplitMix(seed: UInt64(seed * 7919 + 13))
    var planes: [(SIMD3<Float>, Float)] = []
    for _ in 0..<facets {
      let d = simd_normalize(SIMD3(rng.next() * 2 - 1, rng.next() * 2 - 1, rng.next() * 2 - 1))
      planes.append((d, 0.8 + 0.12 * rng.next()))
    }
    let points = verts.map { v -> SIMD3<Float> in
      var r = 1 + relief * EssenceNoise.fbm(v * 1.3, seed: seed, octaves: 4) + relief * 0.27 * EssenceNoise.fbm(v * 5, seed: seed + 3, octaves: 3)
      for (d, o) in planes {
        let c = simd_dot(v, d)
        if c > 0.05 { r = min(r, o / c) }
      }
      return v * r * radius * squash
    }
    return Body(unit: verts, points: points, tris: tris)
  }

  struct Half {
    let node: SCNNode
    let centre: SIMD3<Float>
    let rimPoint: SIMD3<Float>
  }

  /// The part of the body with dot(p, n) ≤ offset; beyond it the body is pressed onto the plane.
  static func clip(_ b: Body, normal n: SIMD3<Float>, offset: Float, outer: SCNMaterial, cut: SCNMaterial,
                   rim: SCNMaterial?, rimDepth: Float, scale: Float, tile: Float) -> Half
  {
    var p = b.points
    var depth = [Float](repeating: 0, count: p.count)
    var onPlane = [Bool](repeating: false, count: p.count)
    for i in p.indices {
      let s = simd_dot(p[i], n) - offset
      if s > 0 {
        p[i] -= n * s
        onPlane[i] = true
        depth[i] = s
      }
    }
    let u = simd_normalize(simd_cross(n, abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)))
    let w = simd_cross(n, u)
    var smooth = [SIMD3<Float>](repeating: .zero, count: p.count)
    for t in b.tris where !(onPlane[Int(t.x)] && onPlane[Int(t.y)] && onPlane[Int(t.z)]) {
      let a = p[Int(t.x)], c1 = p[Int(t.y)], c2 = p[Int(t.z)]
      let fn = simd_cross(c1 - a, c2 - a)
      for i in [t.x, t.y, t.z] { smooth[Int(i)] += fn }
    }
    var outerPos: [SIMD3<Float>] = [], outerN: [SIMD3<Float>] = [], outerUV: [SIMD2<Float>] = [], outerIdx: [UInt32] = []
    var cutPos: [SIMD3<Float>] = [], cutUV: [SIMD2<Float>] = [], cutIdx: [UInt32] = [], rimIdx: [UInt32] = []
    var map = [Int: UInt32]()
    var centre = SIMD3<Float>.zero, count: Float = 0
    var rimPoint = SIMD3<Float>.zero, rimBest = -Float.greatestFiniteMagnitude
    // The rim band: points of the cut within `rimDepth` of the outer surface. For a body of
    // radius R cut near its middle, a point that lay `s` beyond the plane is pressed onto the cut
    // at ≈ R − s²/(2R) from the centre, so «within b of the edge» is s < √(2bR).
    let band = (2 * rimDepth * scale * scale).squareRoot()
    for t in b.tris {
      let ids = [Int(t.x), Int(t.y), Int(t.z)]
      if ids.allSatisfy({ onPlane[$0] }) {
        let skin = rim != nil && ids.map({ depth[$0] }).max()! < band
        for i in ids {
          let k = UInt32(cutPos.count)
          if skin { rimIdx.append(k) } else { cutIdx.append(k) }
          cutPos.append(p[i])
          cutUV.append(SIMD2(simd_dot(p[i], u), simd_dot(p[i], w)) * tile / (scale * 2.2) + 0.5)
          centre += p[i]
          count += 1
          if skin, p[i].y > rimBest { rimBest = p[i].y; rimPoint = p[i] }
        }
      } else {
        for i in ids {
          if let k = map[i] { outerIdx.append(k); continue }
          let k = UInt32(outerPos.count)
          map[i] = k
          outerPos.append(p[i])
          outerN.append(simd_normalize(smooth[i]))
          // Triplanar-ish: project on the dominant axis of the unit direction (no pole pinch).
          let q = b.unit[i], a = abs(q)
          let uv = a.x > a.y && a.x > a.z ? SIMD2(p[i].z, p[i].y) : a.y > a.z ? SIMD2(p[i].x, p[i].z) : SIMD2(p[i].x, p[i].y)
          outerUV.append(uv * tile / (scale * 2.2) + 0.5)
          outerIdx.append(k)
        }
      }
    }
    let node = SCNNode()
    let surface = geometry(outerPos, outerN, outerUV, [outerIdx], [outer])
    var elements = [cutIdx], mats = [cut]
    if let rim, !rimIdx.isEmpty {
      elements.append(rimIdx)
      mats.append(rim)
    }
    let face = geometry(cutPos, [SIMD3<Float>](repeating: n, count: cutPos.count), cutUV, elements, mats)
    for g in [surface, face] {
      let c = SCNNode(geometry: g)
      c.castsShadow = true
      node.addChildNode(c)
    }
    if rimBest == -Float.greatestFiniteMagnitude { rimPoint = count > 0 ? centre / count : .zero }
    return Half(node: node, centre: count > 0 ? centre / count : .zero, rimPoint: rimPoint)
  }

  static func geometry(_ p: [SIMD3<Float>], _ n: [SIMD3<Float>], _ uv: [SIMD2<Float>], _ elements: [[UInt32]],
                       _ m: [SCNMaterial]) -> SCNGeometry
  {
    let g = SCNGeometry(sources: [SCNGeometrySource(vertices: p.map { SCNVector3($0) }), SCNGeometrySource(normals: n.map { SCNVector3($0) }),
                                  SCNGeometrySource(textureCoordinates: uv.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })],
                        elements: elements.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
    g.materials = m
    return g
  }

  static func icosphere(subdivisions: Int) -> ([SIMD3<Float>], [SIMD3<UInt32>]) {
    let t: Float = (1 + Float(5).squareRoot()) / 2
    var v: [SIMD3<Float>] = [
      SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0), SIMD3(0, -1, t), SIMD3(0, 1, t),
      SIMD3(0, -1, -t), SIMD3(0, 1, -t), SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1),
    ].map { simd_normalize($0) }
    var f: [SIMD3<UInt32>] = [
      SIMD3(0, 11, 5), SIMD3(0, 5, 1), SIMD3(0, 1, 7), SIMD3(0, 7, 10), SIMD3(0, 10, 11), SIMD3(1, 5, 9), SIMD3(5, 11, 4),
      SIMD3(11, 10, 2), SIMD3(10, 7, 6), SIMD3(7, 1, 8), SIMD3(3, 9, 4), SIMD3(3, 4, 2), SIMD3(3, 2, 6), SIMD3(3, 6, 8),
      SIMD3(3, 8, 9), SIMD3(4, 9, 5), SIMD3(2, 4, 11), SIMD3(6, 2, 10), SIMD3(8, 6, 7), SIMD3(9, 8, 1),
    ]
    for _ in 0..<subdivisions {
      var cache = [UInt64: UInt32]()
      func mid(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
        if let k = cache[key] { return k }
        v.append(simd_normalize((v[Int(a)] + v[Int(b)]) / 2))
        let k = UInt32(v.count - 1)
        cache[key] = k
        return k
      }
      f = f.flatMap { t -> [SIMD3<UInt32>] in
        let a = mid(t.x, t.y), b = mid(t.y, t.z), c = mid(t.z, t.x)
        return [SIMD3(t.x, a, c), SIMD3(t.y, b, a), SIMD3(t.z, c, b), SIMD3(a, b, c)]
      }
    }
    return (v, f)
  }
}

// MARK: - Noise

enum EssenceNoise {
  private static func hash(_ x: Int32, _ y: Int32, _ z: Int32, _ seed: Int) -> Float {
    var h = UInt32(bitPattern: x &* 374761393 &+ y &* 668265263 &+ z &* 2147483647 &+ Int32(truncatingIfNeeded: seed) &* 1274126177)
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFF) / 65535 * 2 - 1
  }
  /// 3D value noise in −1…1 (smooth).
  static func value(_ p: SIMD3<Float>, seed: Int) -> Float {
    let i = floor(p), f = p - i
    let u = f * f * (3 - 2 * f)
    let x = Int32(i.x), y = Int32(i.y), z = Int32(i.z)
    func h(_ dx: Int32, _ dy: Int32, _ dz: Int32) -> Float { hash(x + dx, y + dy, z + dz, seed) }
    let x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * u.x, x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * u.x
    let x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * u.x, x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * u.x
    let y0 = x00 + (x10 - x00) * u.y, y1 = x01 + (x11 - x01) * u.y
    return y0 + (y1 - y0) * u.z
  }
  static func fbm(_ p: SIMD3<Float>, seed: Int, octaves: Int) -> Float {
    var a: Float = 0.5, s: Float = 0, q = p
    for o in 0..<octaves {
      s += a * value(q, seed: seed + o * 31)
      q *= 2.03
      a *= 0.5
    }
    return s
  }
}

// MARK: - Procedural textures

/// Surface images for the samples, generated once (≈ 0.1 s in release) and cached. Colours are
/// art-directed approximations of the real materials, not scans: S-Stone white with very fine
/// mineral specks; S-Sense core with angular marble crumb in a light resin; bauxite red-brown
/// with round concretions; marble white with soft grey veins.
final class EssenceTextures {
  static let shared = EssenceTextures()
  let stone: CGImage?, stoneNormal: CGImage?
  let core: CGImage?, coreNormal: CGImage?
  let bauxite: CGImage?, marble: CGImage?, rockNormal: CGImage?

  private init() {
    let n = 256
    var rng = SplitMix(seed: 42)
    let fine = Self.field(n, scale: 22, seed: 3, octaves: 3)
    let broad = Self.field(n, scale: 3, seed: 5, octaves: 3)
    // S-Stone: warm white, a breath of mottling, tiny grey / beige specks.
    var px = [Float](repeating: 0, count: n * n * 3)
    for i in 0..<(n * n) {
      var c = SIMD3<Float>(0.86, 0.845, 0.815) * (1 + 0.025 * broad[i] + 0.015 * fine[i])
      let r = rng.next()
      if r < 0.05 { c *= 0.8 + 0.08 * rng.next() } else if r < 0.075 { c *= SIMD3(0.97, 0.92, 0.84) } else if r < 0.085 { c *= 1.06 }
      px[i * 3] = c.x
      px[i * 3 + 1] = c.y
      px[i * 3 + 2] = c.z
    }
    stone = Self.image(px, n)
    stoneNormal = Self.normal(fine.map { $0 * 0.6 }, n, strength: 1.2)
    // S-Sense core: angular crumb drawn as polygons over the resin.
    let size = 512
    var height = [Float](repeating: 0, count: size * size)
    core = Self.crumb(size, rng: &rng, height: &height)
    coreNormal = Self.normal(height, size, strength: 0.8)
    // Bauxite: red-brown, ochre patches, round concretions (pisoliths).
    var b = [Float](repeating: 0, count: n * n * 3)
    let blot = Self.field(n, scale: 6, seed: 11, octaves: 4)
    for y in 0..<n {
      for x in 0..<n {
        let i = y * n + x
        var c = SIMD3<Float>(0.47, 0.25, 0.15) + SIMD3(0.16, 0.12, 0.06) * max(0, blot[i]) - SIMD3(0.12, 0.08, 0.05) * max(0, -blot[i])
        c *= 1 + 0.08 * fine[i]
        b[i * 3] = c.x
        b[i * 3 + 1] = c.y
        b[i * 3 + 2] = c.z
      }
    }
    for _ in 0..<90 {                                           // concretions
      let cx = Int(rng.next() * Float(n)), cy = Int(rng.next() * Float(n)), r = 2 + Int(rng.next() * 5)
      let tone = SIMD3<Float>(0.58, 0.33, 0.18) * (0.85 + 0.3 * rng.next())
      for dy in -r...r {
        for dx in -r...r where dx * dx + dy * dy <= r * r {
          let x = (cx + dx + n) % n, y = (cy + dy + n) % n, i = (y * n + x) * 3
          let rim: Float = dx * dx + dy * dy > (r - 1) * (r - 1) ? 0.75 : 1
          b[i] = tone.x * rim
          b[i + 1] = tone.y * rim
          b[i + 2] = tone.z * rim
        }
      }
    }
    bauxite = Self.image(b, n)
    // Marble: white with soft grey veins (turbulent bands).
    var m = [Float](repeating: 0, count: n * n * 3)
    let turb = Self.field(n, scale: 4, seed: 23, octaves: 5)
    for y in 0..<n {
      for x in 0..<n {
        let i = y * n + x
        let v = abs(sin((Float(x) * 0.9 + Float(y) * 0.45) / Float(n) * 2 * .pi * 2.5 + turb[i] * 4.5))
        let vein = pow(1 - v, 9)
        var c = SIMD3<Float>(0.82, 0.815, 0.805) * (1 + 0.03 * fine[i]) - SIMD3(0.34, 0.33, 0.31) * vein
        c += SIMD3(0.01, 0.01, 0.015) * broad[i]
        m[i * 3] = c.x
        m[i * 3 + 1] = c.y
        m[i * 3 + 2] = c.z
      }
    }
    marble = Self.image(m, n)
    rockNormal = Self.normal(zip(blot, fine).map { $0 * 0.8 + $1 * 0.4 }, n, strength: 2.4)
  }

  /// Tileable value-noise field in −1…1 (lattice wraps).
  static func field(_ n: Int, scale: Int, seed: Int, octaves: Int) -> [Float] {
    var out = [Float](repeating: 0, count: n * n)
    var amp: Float = 0.5, s = scale
    for o in 0..<octaves {
      var rng = SplitMix(seed: UInt64(seed * 97 + o))
      let lattice = (0..<(s * s)).map { _ in rng.next() * 2 - 1 }
      for y in 0..<n {
        let fy = Float(y) / Float(n) * Float(s)
        let y0 = Int(fy) % s, y1 = (y0 + 1) % s, ty = fy - floor(fy)
        let uy = ty * ty * (3 - 2 * ty)
        for x in 0..<n {
          let fx = Float(x) / Float(n) * Float(s)
          let x0 = Int(fx) % s, x1 = (x0 + 1) % s, tx = fx - floor(fx)
          let ux = tx * tx * (3 - 2 * tx)
          let a = lattice[y0 * s + x0] + (lattice[y0 * s + x1] - lattice[y0 * s + x0]) * ux
          let b = lattice[y1 * s + x0] + (lattice[y1 * s + x1] - lattice[y1 * s + x0]) * ux
          out[y * n + x] += amp * (a + (b - a) * uy)
        }
      }
      amp *= 0.5
      s *= 2
    }
    return out
  }

  /// Marble crumb in resin: thousands of small angular grains (3–14 px at 512 px ≈ 10 cm).
  private static func crumb(_ n: Int, rng: inout SplitMix, height: inout [Float]) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setFillColor(red: 0.6, green: 0.57, blue: 0.52, alpha: 1)        // resin
    ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
    var hctx = [Float](repeating: 0, count: n * n)
    for k in 0..<2600 {
      let big = k < 260
      let r = CGFloat(big ? 7 + rng.next() * 9 : 2.5 + rng.next() * 5)
      let cx = CGFloat(rng.next()) * CGFloat(n), cy = CGFloat(rng.next()) * CGFloat(n)
      let sides = 5 + Int(rng.next() * 3)
      let tone = CGFloat(0.66 + 0.12 * rng.next()) - (rng.next() < 0.15 ? 0.14 : 0)
      let warm = CGFloat(0.015 + rng.next() * 0.03)
      ctx.setFillColor(red: tone + warm, green: tone + warm * 0.6, blue: tone, alpha: 1)
      let rot = CGFloat(rng.next()) * .pi * 2
      // Tile: draw wrapped copies near the edges.
      for ox in [-1, 0, 1] {
        for oy in [-1, 0, 1] {
          let px = cx + CGFloat(ox * n), py = cy + CGFloat(oy * n)
          guard px > -r * 2, px < CGFloat(n) + r * 2, py > -r * 2, py < CGFloat(n) + r * 2 else { continue }
          ctx.beginPath()
          for s in 0..<sides {
            let a = rot + CGFloat(s) / CGFloat(sides) * .pi * 2 + CGFloat(rng.next() - 0.5) * 0.5
            let rr = r * CGFloat(0.65 + 0.45 * rng.next())
            let p = CGPoint(x: px + cos(a) * rr, y: py + sin(a) * rr)
            if s == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
          }
          ctx.closePath()
          ctx.fillPath()
          // Height: grains stand a hair above the resin (for the normal map).
          let ir = Int(r * 0.7)
          for dy in -ir...ir {
            for dx in -ir...ir where dx * dx + dy * dy <= ir * ir {
              let x = Int(px) + dx, y = Int(py) + dy
              guard x >= 0, x < n, y >= 0, y < n else { continue }
              hctx[y * n + x] = 1
            }
          }
        }
      }
    }
    height = hctx
    return ctx.makeImage()
  }

  static func image(_ px: [Float], _ n: Int) -> CGImage? {
    var bytes = [UInt8](repeating: 255, count: n * n * 4)
    for i in 0..<(n * n) {
      for c in 0..<3 { bytes[i * 4 + c] = UInt8(max(0, min(255, px[i * 3 + c] * 255))) }
    }
    return cg(bytes, n)
  }

  /// Tangent-space normal map from a height field (wrapping).
  static func normal(_ h: [Float], _ n: Int, strength: Float) -> CGImage? {
    var bytes = [UInt8](repeating: 255, count: n * n * 4)
    for y in 0..<n {
      for x in 0..<n {
        let l = h[y * n + (x - 1 + n) % n], r = h[y * n + (x + 1) % n]
        let d = h[((y + 1) % n) * n + x], u = h[((y - 1 + n) % n) * n + x]
        let v = simd_normalize(SIMD3<Float>((l - r) * strength, (d - u) * strength, 1)) * 0.5 + 0.5
        let i = (y * n + x) * 4
        bytes[i] = UInt8(v.x * 255)
        bytes[i + 1] = UInt8(v.y * 255)
        bytes[i + 2] = UInt8(v.z * 255)
      }
    }
    return cg(bytes, n)
  }

  private static func cg(_ bytes: [UInt8], _ n: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  /// The studio environment (equirectangular, linear): image azimuth 0° = +x, 90° = +z
  /// (towards the camera), 270° = −z (measured on a chrome sphere).
  static func studio() -> CGImage? {
    let w = 512, h = 256
    var px = [Float](repeating: 0, count: w * h * 3)
    for y in 0..<h {
      let elevation = 90 - (Float(y) + 0.5) / Float(h) * 180
      let t = elevation / 90
      let v: Float = t > 0 ? 0.42 + 0.38 * t : 0.42 + 0.3 * t      // ceiling 0.8 … horizon 0.42 … floor 0.12
      for x in 0..<w {
        let i = (y * w + x) * 3
        px[i] = v * 1.02
        px[i + 1] = v
        px[i + 2] = v * 0.97
      }
    }
    var img = RadianceImage(width: w, height: h, pixels: px)
    img.add([
      // Mirror direction of the tilted tops seen from the camera: behind, ~45° up.
      RadianceImage.Card(azimuth: 268, elevation: 44, width: 70, height: 22, radiance: 3.4, warmth: 0.1, soft: 5),
      RadianceImage.Card(azimuth: 145, elevation: 55, width: 46, height: 34, radiance: 3.6, warmth: 0.25, soft: 10),
      RadianceImage.Card(azimuth: 330, elevation: 22, width: 8, height: 60, radiance: 2.6, warmth: -0.3, soft: 3),
    ], mean: 1)
    return img.cgImage(scale: 1)
  }
}

/// Deterministic random numbers (stable textures between runs).
struct SplitMix {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> Float {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Float(z >> 40) / Float(1 << 24)
  }
}
