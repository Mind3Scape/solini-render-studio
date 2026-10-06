import SceneKit
import UIKit

private final class SceneClock: NSObject {
  weak var owner: FactorySceneView?
  @objc func tick() { owner?.placeLabels() }
}

final class FactorySceneView: SCNView, UIGestureRecognizerDelegate {
  private let world = SCNScene()
  private let cameraNode = SCNNode()
  private let flow = SCNNode()
  private var outboundTrucks: [Int: SCNNode] = [:]
  private var departures: Set<Int> = []
  private var loadFloors: [FactoryZone: SCNNode] = [:]
  private var orderTags: [InsideOrderID: CampusAnnotation] = [:]
  private var orderMarkers: [InsideOrderID: SCNNode] = [:]
  private var stationTags: [(FactoryZone, String, SCNVector3, CampusAnnotation)] = []
  private var reserveIndicator: SCNNode?
  private var qualityIndicator: SCNNode?
  private var reserveCover: SCNNode?
  private var batchTransfer: SCNNode?
  private var transferStarted = false
  private var freightGate: SCNNode?
  private var followingShipment = false
  private weak var simulation: FactorySimulation?
  private var lens: CampusLens = .campus
  private var trackedOrder: InsideOrderID?
  var onOrderSelect: ((InsideOrderID) -> Void)?
  var onStationSelect: ((FactoryZone, String) -> Void)?
  private var simulationPaused = false
  private var buildingMaterials: [FactoryZone: [(SCNMaterial, UIColor, UIColor?, CGFloat)]] = [:]
  var excludedAnnotationRects: [CGRect] = []
  private var roofs: [FactoryZone: SCNNode] = [:]
  private var outlines: [FactoryZone: SCNNode] = [:]
  private var tags: [FactoryZone: CampusAnnotation] = [:]
  private var clock: CADisplayLink?
  private let clockTarget = SceneClock()
  private(set) var mapCamera = CampusCamera()
  private var panOrigin = SCNVector3Zero
  private var pinchScale: Double = 0
  private var lastViewport = CGSize.zero
  private var lastVisibleRect = CGRect.zero
  var mapContentInsets: UIEdgeInsets = .zero {
    didSet { if oldValue != mapContentInsets { setNeedsLayout() } }
  }
  private var visibleMapRect: CGRect {
    let proposed = bounds.inset(by: mapContentInsets)
    return proposed.width > 40 && proposed.height > 80 ? proposed : bounds
  }
  private var framingShift: SCNVector3 {
    let rect = visibleMapRect
    let units = Float(2 * mapCamera.scale / Double(max(1, rect.height)))
    let right = Float(rect.midX - bounds.midX) * units / sqrt(2)
    let forward = Float(rect.midY - bounds.midY) * units * sqrt(1.5)
    return SCNVector3(-right - forward, 0, right - forward)
  }
  private var framingScale: Double { Double(bounds.height / max(1, visibleMapRect.height)) }
  private var activeZone: FactoryZone?
  private var explored = false
  var onSelect: ((FactoryZone) -> Void)?
  var onExplore: (() -> Void)?
  var onViewport: ((CampusCamera) -> Void)?
  private(set) var chosen: FactoryZone = .casting
  private(set) var roofVisible = true
  var labelsVisible = true { didSet { placeLabels() } }
  var simulationSpeed: CGFloat = 1 {
    didSet {
      world.rootNode.enumerateChildNodes { node, _ in
        for key in node.actionKeys { node.action(forKey: key)?.speed = self.simulationSpeed }
      }
    }
  }
  init() {
    super.init(frame: .zero, options: nil)
    scene = world
    backgroundColor = InsideStyle.canvas
    world.background.contents = InsideStyle.canvas
    world.lightingEnvironment.contents = UIColor.white
    world.lightingEnvironment.intensity = 0.34
    antialiasingMode = .multisampling4X
    preferredFramesPerSecond = 60
    isPlaying = true
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.usesOrthographicProjection = true
    cameraNode.camera?.zFar = 700
    cameraNode.camera?.zNear = 0.5
    cameraNode.camera?.wantsHDR = false
    // Screen-space AO produces stippling in the iOS 27 simulator; directional shadows stay clean.
    cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = 0
    cameraNode.camera?.screenSpaceAmbientOcclusionRadius = 2.5
    world.rootNode.addChildNode(cameraNode)
    pointOfView = cameraNode
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    // Cool sky fill and a slightly warm sun: warm facades, cool shadows, clean whites.
    ambient.light?.intensity = 320
    ambient.light?.color = UIColor(hex: 0xE4ECF5)
    world.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 960
    sun.light?.color = UIColor(hex: 0xFFF5E6)
    sun.light?.castsShadow = true
    sun.light?.shadowMode = .forward
    // The camera is >300 units from the site; SceneKit's default 100-unit shadow
    // distance silently excluded the entire campus from shadow rendering.
    sun.light?.maximumShadowDistance = 650
    sun.light?.zFar = 700
    sun.light?.shadowBias = 0.3
    sun.light?.shadowColor = UIColor(hex: 0x3A5063, alpha: 0.44)
    sun.light?.shadowRadius = 6
    sun.light?.shadowSampleCount = 8
    sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.light?.orthographicScale = 240
    sun.position = SCNVector3(0, 160, 80)
    sun.eulerAngles = SCNVector3(-0.88, -0.9, 0)
    world.rootNode.addChildNode(sun)
    buildCampus()
    updateCamera(duration: 0)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
    gestureRecognizers?.forEach { $0.delegate = self }
    accessibilityLabel = "Пространственная карта Salini"
    accessibilityHint =
      "Перемещайте карту одним пальцем. Масштабируйте двумя. Выберите корпус, чтобы открыть его процессы."
    accessibilityIdentifier = "factory.scene"
    clockTarget.owner = self
  }
  required init?(coder: NSCoder) { fatalError() }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    clock?.invalidate()
    clock = nil
    if window != nil {
      let link = CADisplayLink(target: clockTarget, selector: #selector(SceneClock.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
      link.add(to: .main, forMode: .common)
      clock = link
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.width > 0, bounds.size != lastViewport || visibleMapRect != lastVisibleRect {
      let firstLayout = lastViewport == .zero
      lastViewport = bounds.size
      lastVisibleRect = visibleMapRect
      mapCamera.viewport = visibleMapRect.size
      if let activeZone { mapCamera.frame(activeZone) } else if !explored { mapCamera.overview() }
      updateCamera(duration: firstLayout ? 0 : 0.45)
    }
  }
  deinit { clock?.invalidate() }
  /// While a building is being built its materials are shared by colour, so the merged
  /// static mesh carries a handful of materials instead of thousands.
  private var buildingZone: FactoryZone?
  private var materialCache: [String: SCNMaterial] = [:]
  private func material(
    _ color: UIColor, rough: CGFloat = 0.88, glow: Bool = false, metal: CGFloat = 0,
    glowIntensity: CGFloat = 0.7
  ) -> SCNMaterial {
    var key = ""
    if let zone = buildingZone {
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      color.getRed(&r, green: &g, blue: &b, alpha: &a)
      key = "\(zone.rawValue)|\(Int(r * 255))|\(Int(g * 255))|\(Int(b * 255))|\(Int(a * 255))"
        + "|\(rough)|\(metal)|\(glow ? glowIntensity : 0)"
      if let cached = materialCache[key] { return cached }
    }
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .physicallyBased
    m.roughness.contents = rough
    m.metalness.contents = metal
    if glow {
      m.emission.contents = color
      m.emission.intensity = glowIntensity
    }
    if !key.isEmpty { materialCache[key] = m }
    return m
  }
  /// State-coloured parts must not share a material with the rest of their building.
  private func isolate(_ node: SCNNode) {
    node.geometry?.materials = node.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
  }
  @discardableResult private func box(
    _ p: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: Float, _ y: Float, _ z: Float,
    _ color: UIColor, r: CGFloat = 0.035, rough: CGFloat = 0.88, metal: CGFloat = 0,
    glow: CGFloat = 0
  ) -> SCNNode {
    let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(r, min(w, h, d) / 2))
    // Small bevels catch the light; more chamfer segments only add vertices at this scale.
    g.chamferSegmentCount = r >= 0.15 ? 3 : 1
    g.materials = [material(color, rough: rough, glow: glow > 0, metal: metal, glowIntensity: glow)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    p.addChildNode(n)
    return n
  }
  @discardableResult private func cylinder(
    _ p: SCNNode, r: CGFloat, h: CGFloat, x: Float, y: Float, z: Float, color: UIColor,
    metal: CGFloat = 0
  ) -> SCNNode {
    let g = SCNCylinder(radius: r, height: h)
    g.radialSegmentCount = 20
    g.materials = [material(color, rough: metal > 0 ? 0.4 : 0.88, metal: metal)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    p.addChildNode(n)
    return n
  }
  @discardableResult private func cone(
    _ p: SCNNode, top: CGFloat, bottom: CGFloat, h: CGFloat, x: Float, y: Float, z: Float,
    color: UIColor, metal: CGFloat = 0
  ) -> SCNNode {
    let g = SCNCone(topRadius: top, bottomRadius: bottom, height: h)
    g.radialSegmentCount = 24
    g.materials = [material(color, rough: metal > 0 ? 0.4 : 0.88, metal: metal)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    p.addChildNode(n)
    return n
  }
  @discardableResult private func ball(
    _ p: SCNNode, r: CGFloat, x: Float, y: Float, z: Float, color: UIColor
  ) -> SCNNode {
    let g = SCNSphere(radius: r)
    g.segmentCount = 16
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    p.addChildNode(n)
    return n
  }
  private func text3D(
    _ text: String, _ parent: SCNNode, position: SCNVector3, size: CGFloat, color: UIColor
  ) {
    let g = SCNText(string: text, extrusionDepth: 0.003)
    g.font = UIFont.systemFont(ofSize: size, weight: .bold)
    g.flatness = 0.15
    // Own material: constant lighting must not leak into the shared building palette.
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .constant
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = position
    parent.addChildNode(n)
  }
  private func tub(_ p: SCNNode, x: Float, y: Float, z: Float, scale: Float = 1) {
    let rings: [(Float, Float)] = [
      (0.73, 0.08), (0.79, 0.16), (0.98, 0.69), (1, 0.78), (0.91, 0.8), (0.87, 0.67), (0.66, 0.27),
      (0.5, 0.22), (0, 0.22),
    ]
    let count = 44
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [Int32] = []
    for (i, ring) in rings.enumerated() {
      for s in 0...count {
        let a = Float(s) / Float(count) * .pi * 2
        let sign: Float = i < 4 ? 1 : -1
        vertices.append(SCNVector3(cos(a) * ring.0 * 1.12, ring.1, sin(a) * ring.0 * 0.57))
        normals.append(
          SCNVector3(cos(a) * sign, i == 3 || i == 4 || i > 6 ? 1 : 0.22, sin(a) * sign))
      }
    }
    for r in 0..<(rings.count - 1) {
      for s in 0..<count {
        let a = Int32(r * (count + 1) + s)
        let b = a + Int32(count + 1)
        indices += [a, b, a + 1, a + 1, b, b + 1]
      }
    }
    let g = SCNGeometry(
      sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    let m = material(UIColor(hex: 0xFAFAFC), rough: 0.22)
    m.isDoubleSided = true
    m.clearCoat.contents = 0.65
    m.clearCoatRoughness.contents = 0.16
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    n.scale = SCNVector3(scale, scale, scale)
    p.addChildNode(n)
    cylinder(n, r: 0.055, h: 0.008, x: 0.5, y: 0.23, z: 0, color: UIColor(hex: 0xA5ACB8))
  }
  private func person(_ p: SCNNode, x: Float, z: Float, walking: Bool = false) {
    let n = SCNNode()
    n.position = SCNVector3(x, 0.16, z)
    p.addChildNode(n)
    contactShadow(n, width: 0.9, depth: 0.8)
    // Navy workwear reads as people at every zoom without becoming a colour accent.
    let workwear = UIColor(hex: 0x46647F)
    cylinder(n, r: 0.14, h: 0.45, x: 0, y: 0.5, z: 0, color: workwear)
    ball(n, r: 0.12, x: 0, y: 0.87, z: 0, color: UIColor(hex: 0xDADCDB))
    let left = box(n, 0.095, 0.35, 0.1, -0.075, 0.19, 0, UIColor(hex: 0x2F3A44))
    let right = box(n, 0.095, 0.35, 0.1, 0.075, 0.19, 0, UIColor(hex: 0x2F3A44))
    let armL = box(n, 0.09, 0.34, 0.09, -0.21, 0.49, 0, workwear)
    let armR = box(n, 0.09, 0.34, 0.09, 0.21, 0.49, 0, workwear)
    for (i, limb) in (walking ? [left, right, armR, armL] : [armL]).enumerated() {
      let a = SCNAction.rotateBy(x: i % 2 == 0 ? 0.42 : -0.42, y: 0, z: 0, duration: 0.42)
      limb.runAction(.repeatForever(.sequence([a, a.reversed()])), forKey: "motion")
    }
    if walking {
      travel(
        n,
        points: [
          SCNVector3(x, 0.16, z), SCNVector3(x + 1.4, 0.16, z), SCNVector3(x + 1.4, 0.16, z + 0.8),
          SCNVector3(x, 0.16, z + 0.8),
        ], speed: 0.4)
    }
  }
  private func pallet(_ p: SCNNode, x: Float, z: Float, y: Float = 0, filled: Bool = true) {
    for i in 0..<4 {
      box(p, 1.15, 0.07, 0.18, x, y + 0.12, z + Float(i) * 0.23 - 0.35, UIColor(hex: 0xB59366), r: 0)
    }
    if filled {
      box(p, 1.06, 0.73, 0.84, x, y + 0.52, z, UIColor(hex: 0xE6EBEC), r: 0.025, rough: 0.35)
      box(p, 0.035, 0.75, 0.86, x, y + 0.52, z, UIColor(hex: 0xC4A06E), r: 0)
      box(p, 0.35, 0.23, 0.005, x - 0.24, y + 0.52, z + 0.424, UIColor.white, r: 0)
      for i in 0..<5 {
        box(
          p, 0.018, 0.15, 0.009, x - 0.36 + Float(i) * 0.04, y + 0.5, z + 0.43,
          UIColor(hex: 0x62646B), r: 0)
      }
    }
  }
  private func travel(_ node: SCNNode, points: [SCNVector3], speed: Double) {
    var actions: [SCNAction] = []
    for i in points.indices {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      let distance = sqrt(pow(Double(b.x - a.x), 2) + pow(Double(b.z - a.z), 2))
      let rotate = SCNAction.rotateTo(
        x: 0, y: CGFloat(atan2(b.x - a.x, b.z - a.z)), z: 0, duration: 0.6,
        usesShortestUnitArc: true)
      let move = SCNAction.move(to: b, duration: distance / speed)
      move.timingMode = .linear
      actions.append(.group([rotate, move]))
    }
    node.position = points[0]
    node.runAction(.repeatForever(.sequence(actions)), forKey: "travel")
  }
  private static let plinthShadowTexture: UIImage = {
    UIGraphicsImageRenderer(size: CGSize(width: 330, height: 252)).image { renderer in
      let ctx = renderer.cgContext
      ctx.setShadow(
        offset: CGSize(width: 0, height: 5), blur: 18,
        color: UIColor.black.withAlphaComponent(0.28).cgColor)
      UIColor.black.withAlphaComponent(0.16).setFill()
      UIBezierPath(roundedRect: CGRect(x: 19, y: 19, width: 292, height: 214), cornerRadius: 4)
        .fill()
    }
  }()
  private static let contactTexture: UIImage = {
    UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { renderer in
      let ctx = renderer.cgContext
      let colors = [UIColor(hex: 0x40545F, alpha: 0.2).cgColor, UIColor.clear.cgColor] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      {
        ctx.drawRadialGradient(
          gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 2,
          endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
      }
    }
  }()
  private func contactShadow(_ parent: SCNNode, width: CGFloat, depth: CGFloat) {
    let plane = SCNPlane(width: width, height: depth)
    let m = SCNMaterial()
    m.diffuse.contents = Self.contactTexture
    m.lightingModel = .constant
    m.writesToDepthBuffer = false
    plane.materials = [m]
    let node = SCNNode(geometry: plane)
    node.name = "contact"
    node.eulerAngles.x = -.pi / 2
    node.position.y = 0.03
    node.castsShadow = false
    node.renderingOrder = 10
    parent.addChildNode(node)
  }
  private func vehicleTruck(moving: Bool = true) -> SCNNode {
    let n = SCNNode()
    contactShadow(n, width: 2.7, depth: 6.3)
    let ink = UIColor(hex: 0x4E565C)
    box(n, 1.45, 1.5, 3.6, 0, 1.05, -0.6, UIColor(hex: 0xFDFDFE), r: 0.09)
    box(n, 1.42, 1.15, 1.15, 0, 0.91, 1.73, UIColor(hex: 0xD3D8DA), r: 0.16)
    box(n, 1.21, 0.5, 0.07, 0, 1.22, 2.31, UIColor(hex: 0x3C526B), r: 0.035)
    box(n, 1.55, 0.12, 0.17, 0, 0.38, 2.33, ink)
    for x: Float in [-0.53, 0.53] {
      let light = box(n, 0.18, 0.12, 0.07, x, 0.74, 2.32, UIColor(hex: 0xFFFAE0))
      light.geometry?.firstMaterial = material(UIColor(hex: 0xFFFAE0), glow: true)
    }
    for x: Float in [-0.76, 0.76] {
      for z: Float in [-1.6, -0.7, 1.7] {
        let wheel = cylinder(n, r: 0.28, h: 0.15, x: x, y: 0.27, z: z, color: ink)
        wheel.eulerAngles.z = .pi / 2
        if moving {
          wheel.runAction(
            .repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 1.8)),
            forKey: "motion")
        }
      }
    }
    let logo = SCNPlane(width: 1.25, height: 0.51)
    let m = SCNMaterial()
    m.diffuse.contents = UIImage(named: "salini-logo.png")?.withTintColor(
      UIColor(hex: 0x45545D), renderingMode: .alwaysOriginal)
    m.isDoubleSided = true
    m.lightingModel = .constant
    logo.materials = [m]
    let left = SCNNode(geometry: logo)
    left.position = SCNVector3(-0.73, 1.2, -0.5)
    left.eulerAngles.y = -.pi / 2
    n.addChildNode(left)
    return n
  }
  private func forklift() -> SCNNode {
    let n = SCNNode()
    contactShadow(n, width: 1.7, depth: 3.3)
    let dark = UIColor(hex: 0x3A4148)
    box(n, 0.92, 0.54, 1.32, 0, 0.54, 0, UIColor(hex: 0xC98A35), r: 0.12, rough: 0.5)
    for x: Float in [-0.43, 0.43] {
      box(n, 0.08, 1.25, 0.08, x, 1.08, -0.4, dark)
      box(n, 0.08, 1.7, 0.08, x, 1.0, 0.85, dark)
    }
    box(n, 1.04, 0.08, 0.95, 0, 1.73, -0.1, dark)
    for x: Float in [-0.49, 0.49] {
      for z: Float in [-0.38, 0.48] {
        let w = cylinder(n, r: 0.21, h: 0.13, x: x, y: 0.25, z: z, color: dark)
        w.eulerAngles.z = .pi / 2
      }
    }
    let fork = SCNNode()
    n.addChildNode(fork)
    for x: Float in [-0.32, 0.32] { box(fork, 0.11, 0.09, 1, x, 0.4, 1.1, dark) }
    pallet(fork, x: 0, z: 1.1, y: 0.44)
    fork.runAction(
      .repeatForever(
        .sequence([
          .moveBy(x: 0, y: 0.8, z: 0, duration: 2), .wait(duration: 4),
          .moveBy(x: 0, y: -0.8, z: 0, duration: 2), .wait(duration: 4),
        ])), forKey: "motion")
    return n
  }
  // Warm facades, cool concrete and living planting. Saturated colour is reserved for
  // process equipment so the model reads as architecture rather than a toy.
  private let chalk = UIColor(hex: 0xF3F0E9)
  private let steel = UIColor(hex: 0x5D6C73)
  private let graphite = UIColor(hex: 0x3B444A)
  private let accent = UIColor(hex: 0x2F6F78)
  private let roofWhite = UIColor(hex: 0xF6F7F6)
  private let glass = UIColor(hex: 0x7FA9BC)
  private let floorConcrete = UIColor(hex: 0xD2DADB)
  private let safetyLane = UIColor(hex: 0xD6B14C)
  private let mould = UIColor(hex: 0x394247)
  private let crateWood = UIColor(hex: 0xC99E66)
  private let palletWood = UIColor(hex: 0xB59366)
  private let kraft = UIColor(hex: 0xC4A06E)
  private let galvanized = UIColor(hex: 0xC9D1D4)
  private let walnut = UIColor(hex: 0x8B5E3F)
  private let mirrorGlass = UIColor(hex: 0xD5E0E5)
  private func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
  }
  private func buildCampus() {
    let root = world.rootNode
    let ground = box(root, 440, 0.1, 440, 0, -2.7, 0, InsideStyle.canvas, r: 0)
    ground.geometry?.firstMaterial?.lightingModel = .constant
    // The object has the weight and edge treatment of a physical architectural model.
    let plinthShadow = SCNPlane(width: 246, height: 191)
    let shadowMaterial = SCNMaterial()
    shadowMaterial.lightingModel = .constant
    shadowMaterial.diffuse.contents = Self.plinthShadowTexture
    shadowMaterial.writesToDepthBuffer = false
    plinthShadow.materials = [shadowMaterial]
    let shadow = SCNNode(geometry: plinthShadow)
    shadow.position = SCNVector3(5, -2.6, 0)
    shadow.eulerAngles.x = -.pi / 2
    shadow.castsShadow = false
    root.addChildNode(shadow)
    box(root, CampusSite.bounds.width, 2, CampusSite.bounds.height, 5, -1.2, 0,
        UIColor(hex: 0x52605C), r: 0.45)
    box(root, 222, 0.14, 168, 5, -0.24, 0, InsideStyle.paving, r: 1)
    // Roads and courtyards occupy real space between unchanged building footprints.
    buildRoadNetwork()
    landscape(x: -100, z: 0, width: 8, depth: 158)
    landscape(x: 114, z: 0, width: 4, depth: 158)
    landscape(x: 7, z: -82, width: 200, depth: 5)
    landscape(x: 7, z: 82, width: 200, depth: 5)
    landscape(x: -69, z: 12, width: 32, depth: 18)
    landscape(x: -69, z: 58, width: 32, depth: 10)
    landscape(x: -69, z: -61, width: 32, depth: 8)
    landscape(x: 10, z: 35, width: 10, depth: 58)
    landscape(x: 13.5, z: -40, width: 9, depth: 40)
    // A 44-unit separation between warehouse and dispatch becomes a real freight yard.
    box(root, 32, 0.08, 40, 83, 0.01, 10, UIColor(hex: 0xB3BEC1), r: 1.5)
    for x in stride(from: 70.0, through: 97.0, by: 6) {
      box(root, 0.035, 0.012, 40, Float(x), 0.058, 10, UIColor(hex: 0x9EABAE), r: 0)
    }
    for z in stride(from: -8.0, through: 28.0, by: 6) {
      box(root, 32, 0.012, 0.035, 83, 0.059, Float(z), UIColor(hex: 0x9EABAE), r: 0)
    }
    for x: Float in [73, 83, 93] {
      box(root, 0.12, 0.02, 12, x, 0.07, 15, chalk, r: 0)
    }
    for x: Float in [73, 93] {
      box(root, 2.4, 0.18, 0.3, x, 0.16, 24, FactoryZone.dispatch.accent, r: 0.07)
    }
    // Three-unit pedestrian paths are visually separate from the freight network.
    box(root, 26, 0.13, 3, -63, 0.04, 5, chalk, r: 0.25)
    box(root, 40, 0.13, 3, -16, 0.04, 5, chalk, r: 0.25)
    box(root, 3, 0.13, 57, 1, 0.04, 34, chalk, r: 0.25)
    box(root, 3, 0.13, 25, -69, 0.04, 17, chalk, r: 0.25)
    box(root, 28, 0.13, 6, -68, 0.04, 49, chalk, r: 0.25)
    for zone in FactoryZone.allCases {
      let n = SCNNode()
      n.name = "zone-\(zone.rawValue)"
      n.position = zone.position
      root.addChildNode(n)
      // Materials are shared per building so the static detail can be merged cheaply.
      buildingZone = zone
      buildBuilding(zone, node: n)
      populate(zone, node: n)
      addProcessDetail(zone, node: n)
      buildingZone = nil
      consolidate(zone, node: n)
      var seen = Set<ObjectIdentifier>()
      var originals: [(SCNMaterial, UIColor, UIColor?, CGFloat)] = []
      n.enumerateChildNodes { child, _ in
        for m in child.geometry?.materials ?? [] where seen.insert(ObjectIdentifier(m)).inserted {
          guard let color = m.diffuse.contents as? UIColor else { continue }
          // Self-lit details (oven windows, inspection light) keep their glow when faded.
          var r: CGFloat = 0
          var g: CGFloat = 0
          var b: CGFloat = 0
          var a: CGFloat = 0
          let emission = m.emission.contents as? UIColor
          _ = emission?.getRed(&r, green: &g, blue: &b, alpha: &a)
          originals.append((m, color, max(r, g, b) > 0.02 ? emission : nil, m.emission.intensity))
        }
      }
      buildingMaterials[zone] = originals
      let tag = CampusAnnotation("\(zone.code)  \(zone.shortTitle)") { [weak self] in
        self?.onSelect?(zone)
      }
      tag.accessibilityIdentifier = "map.zone.\(zone.rawValue)"
      tag.accessibilityLabel = zone.title
      addSubview(tag)
      tags[zone] = tag
    }
    // Visitor parking stays on the office side; the freight court stays unobstructed.
    for x: Float in [-79, -74, -69, -64, -59] {
      box(root, 0.1, 0.03, 5.5, x, 0.1, 64, chalk, r: 0)
      if x == -79 || x == -69 || x == -59 { car(root, x: x + 2, z: 64) }
    }
    for z in stride(from: -65, through: 65, by: 18) { tree(root, x: -100, z: Float(z)) }
    for x in stride(from: -81, through: 99, by: 20) {
      tree(root, x: Float(x), z: -82)
      tree(root, x: Float(x), z: 82)
    }
    for z: Float in [13, 31, 50] { tree(root, x: 10, z: z) }
    for z: Float in [-52, -34] { tree(root, x: 13.5, z: z) }
    for x: Float in [-79, -60] {
      tree(root, x: x, z: 13)
      tree(root, x: x, z: 57)
      // Minimal stone seating and a planted arrival court, at human scale.
      box(root, 3.5, 0.45, 0.7, x, 0.28, 22, chalk, r: 0.15)
    }
    for z: Float in [-59, 7, 62] {
      for x: Float in [-50, 66, 96] {
        cylinder(root, r: 0.09, h: 6, x: x, y: 3, z: z, color: steel)
        box(root, 1.2, 0.12, 0.5, x + 0.45, 6, z, chalk)
      }
    }
    box(root, 4, 3, 4, -80, 1.5, 77, chalk)
    box(root, 3, 1.2, 0.1, -80, 2, 79.03, accent)
    let lift = forklift()
    lift.scale = SCNVector3(1.6, 1.6, 1.6)
    lift.name = "zone-6"
    root.addChildNode(lift)
    lift.position = CampusSite.transferRoute()[0]
    batchTransfer = lift
    lift.removeAllActions()
    lift.enumerateChildNodes { node, _ in node.removeAllActions() }
    buildOperationsMarkers()
    addSiteDetail()
    buildFlow()
    root.addChildNode(flow)
    flow.opacity = 0
    if UIAccessibility.isReduceMotionEnabled { setPaused(true) }
  }
  /// Static detail of one building is merged into a single draw node. Anything animated,
  /// state-coloured or hidden on focus keeps its own node.
  private func consolidate(_ zone: FactoryZone, node n: SCNNode) {
    let dynamic: [SCNNode?] = [
      roofs[zone], outlines[zone], loadFloors[zone], reserveCover, reserveIndicator, qualityIndicator,
    ]
    let keep = Set(dynamic.compactMap { $0 }.map { ObjectIdentifier($0) })
    // The bucket is never attached to the scene: `flattenedClone()` bakes the transforms of
    // attached ancestors, which would apply the building position twice once re-parented.
    let bucket = SCNNode()
    // Named nodes (shipment trucks, contact planes) are addressed later and stay separate.
    for child in n.childNodes
    where child.name == nil && !keep.contains(ObjectIdentifier(child)) && !Self.isAnimated(child) {
      child.removeFromParentNode()
      bucket.addChildNode(child)
    }
    // Soft contact planes depend on draw order, so they stay outside the merged mesh. The
    // detached bucket sits at identity, so its space equals the building's local space.
    var contacts: [SCNNode] = []
    bucket.enumerateChildNodes { node, _ in if node.name == "contact" { contacts.append(node) } }
    for contact in contacts {
      let local = contact.convertTransform(SCNMatrix4Identity, to: bucket)
      contact.removeFromParentNode()
      contact.transform = local
      n.addChildNode(contact)
    }
    n.addChildNode(Self.merged(bucket))
    if let roof = roofs[zone], !roof.childNodes.isEmpty {
      let surface = SCNNode()
      for child in roof.childNodes {
        child.removeFromParentNode()
        surface.addChildNode(child)
      }
      roof.addChildNode(Self.merged(surface))
    }
  }
  /// Merges a detached, identity-transformed subtree into one node in its own local space.
  private static func merged(_ detached: SCNNode) -> SCNNode {
    let result = detached.flattenedClone()
    result.transform = SCNMatrix4Identity
    return result
  }
  private static func isAnimated(_ node: SCNNode) -> Bool {
    !node.actionKeys.isEmpty || node.childNodes.contains { isAnimated($0) }
  }
  private func buildRoadNetwork() {
    let paths = CampusSite.roadSurfaces()
    let curb = paths.outline.copy(strokingWithWidth: 1, lineCap: .round, lineJoin: .round, miterLimit: 2)
    for (path, color, elevation) in [(curb, UIColor(hex: 0xE3E7E6), Float(0.025)),
                                    (paths.primary, InsideStyle.asphalt, Float(0.06)),
                                    (paths.service, InsideStyle.serviceRoad, Float(0.06))] {
      let outline = UIBezierPath(cgPath: path)
      outline.flatness = 0.05
      let geometry = SCNShape(path: outline, extrusionDepth: 0.025)
      geometry.materials = [material(color, rough: 0.94)]
      let node = SCNNode(geometry: geometry)
      node.eulerAngles.x = .pi / 2
      node.position.y = elevation
      node.castsShadow = false
      world.rootNode.addChildNode(node)
    }
  }
  private func landscape(x: Float, z: Float, width: CGFloat, depth: CGFloat) {
    box(world.rootNode, width + 0.35, 0.1, depth + 0.35, x, -0.07, z,
        UIColor(hex: 0xC6CFCB), r: 0.6)
    box(world.rootNode, width, 0.06, depth, x, 0, z, InsideStyle.lawn, r: 0.6)
  }
  private func tree(_ parent: SCNNode, x: Float, z: Float) {
    let seed = abs(Int(x * 13 + z * 7))
    let columnar = seed % 3 == 0
    let variation = Float(0.9 + Double(seed % 5) * 0.055)
    let n = SCNNode()
    n.position = SCNVector3(x, 0, z)
    n.scale = SCNVector3(variation, variation, variation)
    n.eulerAngles.y = Float(seed % 12) * .pi / 6
    parent.addChildNode(n)
    contactShadow(n, width: 5.5, depth: 5)
    cylinder(n, r: 0.12, h: 3.2, x: 0, y: 1.6, z: 0, color: UIColor(hex: 0x6B5A4A))
    // One irregular, smooth crown avoids the repeated four-ball silhouette.
    let rows = 14
    let segments = 22
    let radius: Float = columnar ? 1.2 : 2.05
    let height: Float = columnar ? 3.2 : 2.35
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [Int32] = []
    for row in 0...rows {
      let theta = Float(row) / Float(rows) * .pi
      for segment in 0...segments {
        let phi = Float(segment) / Float(segments) * .pi * 2
        let contour: Float = 1 + 0.07 * sin(phi * 3 + Float(seed)) * sin(theta * 2)
        let px = radius * sin(theta) * cos(phi) * contour
        let py = height * cos(theta)
        let pz = radius * sin(theta) * sin(phi) * contour * 0.88
        vertices.append(SCNVector3(px, py, pz))
        let v = SCNVector3(px / (radius * radius), py / (height * height),
                          pz / (radius * radius * 0.88 * 0.88))
        let length = max(0.001, sqrt(v.x*v.x + v.y*v.y + v.z*v.z))
        normals.append(SCNVector3(v.x / length, v.y / length, v.z / length))
        if row < rows && segment < segments {
          let a = Int32(row * (segments + 1) + segment)
          let b = a + Int32(segments + 1)
          indices += [a, a + 1, b, a + 1, b + 1, b]
        }
      }
    }
    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                        SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    // Three living greens: deep columnar, mid canopy and a lighter, sunlit canopy.
    let tone: UInt = columnar ? 0x3F7553 : (seed % 2 == 0 ? 0x4E8A5B : 0x6C9D5E)
    let leaf = material(UIColor(hex: tone), rough: 0.82)
    leaf.isDoubleSided = true
    geometry.materials = [leaf]
    let crown = SCNNode(geometry: geometry)
    crown.position.y = columnar ? 4.5 : 4
    n.addChildNode(crown)
  }
  private func car(_ p: SCNNode, x: Float, z: Float) {
    let body: UInt = [0xE9ECEB, 0x50606B, 0xB9C3C7][abs(Int(x)) % 3]
    box(p, 2, 0.75, 4.1, x, 0.6, z, UIColor(hex: body), r: 0.4, rough: 0.35)
    box(p, 1.65, 0.65, 2, x, 1.1, z - 0.1, UIColor(hex: 0x3E5866), r: 0.25, rough: 0.2)
    for side: Float in [-1, 1] {
      for end: Float in [-1.3, 1.3] {
        let w = cylinder(
          p, r: 0.35, h: 0.22, x: x + side, y: 0.4, z: z + end, color: UIColor(hex: 0x30393F))
        w.eulerAngles.z = .pi / 2
      }
    }
  }
  private func buildBuilding(_ zone: FactoryZone, node n: SCNNode) {
    let w = zone.footprint.width
    let d = zone.footprint.height
    let x = Float(w / 2)
    let z = Float(d / 2)
    let h = zone.buildingHeight
    let facade = zone.facade
    box(n, w + 1.2, 0.24, d + 1.2, 0, 0.12, 0, UIColor(hex: 0xE2E7E6), r: 0.2)
    box(n, w, 0.08, d, 0, 0.28, 0, floorConcrete, r: 0, rough: 0.55)
    let tint = box(n, w - 0.4, 0.025, d - 0.4, 0, 0.335, 0, UIColor(hex: 0x799BA8), r: 0)
    isolate(tint)
    tint.opacity = 0
    loadFloors[zone] = tint
    let outline = SCNNode()
    n.addChildNode(outline)
    outline.opacity = 0
    for side: Float in [-1, 1] {
      box(outline, 0.22, 0.07, d + 1.5, side * (x + 0.65), 0.3, 0, UIColor(hex: 0x3F7E98), r: 0)
      box(outline, w + 1.5, 0.07, 0.22, 0, 0.3, side * (z + 0.65), UIColor(hex: 0x3F7E98), r: 0)
    }
    outlines[zone] = outline
    guard h > 0 else { return }
    // Back and west walls stay as an architectural section when the roof opens. Their
    // inner faces are what the fixed camera sees, so the detail lives on that side.
    box(n, w, CGFloat(h), 0.3, 0, h / 2 + 0.3, -z, facade, r: 0)
    box(n, 0.3, CGFloat(h), d, -x, h / 2 + 0.3, 0, shade(facade, 0.97), r: 0)
    box(n, w, 0.12, 0.34, 0, h + 0.36, -z, graphite, r: 0)
    box(n, 0.34, 0.12, d, -x, h + 0.36, 0, graphite, r: 0)
    box(n, w - 0.4, 0.7, 0.06, 0, 0.65, -z + 0.18, UIColor(hex: 0x56636A), r: 0)
    box(n, 0.06, 0.7, d - 0.4, -x + 0.18, 0.65, 0, UIColor(hex: 0x56636A), r: 0)
    let joint = shade(facade, 0.9)
    for jx in stride(from: -x + 3, through: x - 1, by: 3) {
      box(n, 0.05, CGFloat(h - 1.2), 0.02, jx, h / 2 + 0.9, -z + 0.16, joint, r: 0)
    }
    for jz in stride(from: -z + 3, through: z - 1, by: 3) {
      box(n, 0.02, CGFloat(h - 1.2), 0.05, -x + 0.16, h / 2 + 0.9, jz, joint, r: 0)
    }
    for columnX in stride(from: -x + 1, through: x - 0.5, by: 5) {
      box(n, 0.22, CGFloat(h), 0.4, columnX, h / 2, -z + 0.3, steel, r: 0)
      box(n, 4.2, 1.25, 0.08, columnX + 2.1, h - 1.1, -z + 0.2, glass, r: 0, rough: 0.2)
    }
    // Services on the section wall: cable tray, electrical cabinets, a door and an extinguisher.
    box(n, w - 1.2, 0.1, 0.5, 0, h - 0.25, -z + 0.6, galvanized, r: 0)
    box(n, 1.2, 2, 0.45, -x + 2.4, 1.3, -z + 0.45, graphite, r: 0.03)
    box(n, 0.9, 1.6, 0.45, -x + 3.7, 1.1, -z + 0.45, UIColor(hex: 0x6E7B82), r: 0.03)
    cylinder(n, r: 0.13, h: 0.55, x: -x + 4.6, y: 0.95, z: -z + 0.35, color: UIColor(hex: 0xB4453B))
    box(n, 0.06, 2.4, 1.7, -x + 0.2, 1.5, z - 4, graphite, r: 0)
    let roof = SCNNode()
    n.addChildNode(roof)
    roofs[zone] = roof
    // The roof covers the back two thirds; the front third stays open even in overview.
    let roofDepth = d * 0.64
    let roofZ = -Float(d * 0.18)
    switch zone {
    case .casting: sawtoothRoof(roof, width: w, depth: roofDepth, h: h, z: roofZ)
    case .assembly: vaultRoof(roof, width: w, depth: roofDepth, h: h, z: roofZ)
    case .packing: pitchedRoof(roof, width: w, depth: roofDepth, h: h, z: roofZ)
    case .quality:
      flatRoof(roof, width: w, depth: roofDepth, h: h, z: roofZ, skylights: false)
      box(roof, w * 0.68, 0.9, 2.6, 0, h + 1.0, roofZ, roofWhite, r: 0.05)
      box(roof, w * 0.68 - 0.3, 0.55, 0.08, 0, h + 1.0, roofZ + 1.32, glass, r: 0, rough: 0.2)
    default: flatRoof(roof, width: w, depth: roofDepth, h: h, z: roofZ, skylights: zone != .office)
    }
    // Front fascia: a thin process-colour band identifies each hall without painting it.
    box(n, w + 0.5, 0.5, 0.4, 0, h + 0.1, z, roofWhite, r: 0)
    box(n, 0.4, 0.5, d + 0.5, x, h + 0.1, 0, roofWhite, r: 0)
    box(n, w + 0.52, 0.14, 0.42, 0, h - 0.22, z, zone.accent, r: 0)
    box(n, 0.42, 0.14, d + 0.52, x, h - 0.22, 0, zone.accent, r: 0)
    for side: Float in [-1, 1] { box(n, 0.25, CGFloat(h), 0.25, side * x, h / 2, z, steel, r: 0) }
    box(n, 0.25, CGFloat(h), 0.25, x, h / 2, -z, steel, r: 0)
    box(n, w, 0.5, 0.12, 0, 0.55, z - 0.05, UIColor(hex: 0x56636A), r: 0)
    box(n, 0.12, 0.5, d, x - 0.05, 0.55, 0, UIColor(hex: 0x56636A), r: 0)
    for ventX: Float in [-x + 2.2, x - 2.2] where zone != .office {
      box(roof, 1.7, 0.85, 1.7, ventX, h + 0.95, -z + 2, UIColor(hex: 0xC5D0D4))
      cylinder(roof, r: 0.5, h: 0.1, x: ventX, y: h + 1.42, z: -z + 2, color: steel)
    }
    if zone == .finishing {
      // Dust extraction main above the sanding booths, with three roof fans.
      box(roof, w - 3, 0.75, 0.85, 0, h + 1.3, -11.4, galvanized, r: 0.18, rough: 0.4, metal: 0.45)
      for dx: Float in [-7.5, 0, 7.5] {
        cylinder(roof, r: 0.42, h: 1.3, x: dx, y: h + 0.9, z: -11.4, color: galvanized, metal: 0.45)
        cylinder(roof, r: 0.62, h: 0.35, x: dx, y: h + 1.85, z: -11.4, color: zone.accent)
      }
    }
    if zone == .office {
      // Two storeys, a glazed front with timber fins, reception and a planted terrace.
      box(roof, w - 0.4, 0.23, d - 0.4, 0, 4.1, 0, chalk)
      for floor: Float in [1.8, 5.8] {
        for cx in stride(from: -x + 1.5, through: x - 1, by: 3) {
          box(roof, 2.65, 3.15, 0.12, cx, floor, z, glass, r: 0, rough: 0.18)
          box(roof, 0.14, 3.8, 0.42, cx - 1.4, floor, z + 0.12, zone.accent, r: 0, rough: 0.6)
        }
      }
      brandSign(roof, position: SCNVector3(0, 7.1, z + 0.22), width: 7)
      box(n, w + 2, 0.2, 3, 0, 0.18, z + 1.5, UIColor(hex: 0xCCD4D2))
      box(n, 6, 0.18, 2.6, -2, 3.4, z + 1.4, roofWhite, r: 0.05)
      for postX: Float in [-4.6, 0.6] { box(n, 0.12, 3.1, 0.12, postX, 1.85, z + 2.5, steel, r: 0) }
    } else {
      text3D(zone.code, n, position: SCNVector3(-x + 5.4, max(2.6, h - 3.4), -z + 0.2), size: 1.1,
             color: steel)
    }
  }
  private func flatRoof(_ roof: SCNNode, width w: CGFloat, depth: CGFloat, h: Float, z: Float,
                        skylights: Bool) {
    let x = Float(w / 2)
    box(roof, w + 0.6, 0.35, depth, 0, h + 0.4, z, roofWhite, r: 0.08)
    for rib in stride(from: -x, through: x, by: 2) {
      box(roof, 0.038, 0.006, depth, rib, h + 0.579, z, UIColor(hex: 0xE6EAEA), r: 0)
    }
    box(roof, w + 0.6, 0.12, 0.2, 0, h + 0.62, z + Float(depth / 2) - 0.1, graphite, r: 0)
    guard skylights else { return }
    for skylightX in stride(from: -x + 4, through: x - 3, by: 7) {
      box(roof, 2.42, 0.13, depth * 0.47 + 0.22, skylightX, h + 0.59, z + 0.02 * Float(depth),
          UIColor(hex: 0x9EABB0), r: 0.05)
      box(roof, 2.2, 0.22, depth * 0.47, skylightX, h + 0.65, z + 0.02 * Float(depth), glass,
          r: 0.08, rough: 0.2)
    }
  }
  /// North-light sawtooth: sloped solid bays with vertical glazing toward the camera.
  private func sawtoothRoof(_ roof: SCNNode, width w: CGFloat, depth: CGFloat, h: Float, z: Float) {
    let teeth = max(2, Int(depth / 4))
    let pitch = Float(depth) / Float(teeth)
    let rise: Float = 1.9
    let slope = sqrt(pitch * pitch + rise * rise)
    let angle = atan2(rise, pitch)
    let start = z - Float(depth / 2)
    box(roof, w + 0.6, 0.3, depth, 0, h + 0.4, z, roofWhite, r: 0.06)
    for i in 0..<teeth {
      let z0 = start + Float(i) * pitch
      let panel = box(roof, w + 0.6, 0.22, CGFloat(slope), 0, h + 0.55 + rise / 2, z0 + pitch / 2,
                      roofWhite, r: 0.04)
      panel.eulerAngles.x = -angle
      box(roof, w + 0.3, CGFloat(rise), 0.1, 0, h + 0.55 + rise / 2, z0 + pitch - 0.06, glass,
          r: 0, rough: 0.18)
      box(roof, w + 0.6, 0.12, 0.22, 0, h + 0.6 + rise, z0 + pitch - 0.06, graphite, r: 0)
    }
  }
  private func vaultRoof(_ roof: SCNNode, width w: CGFloat, depth: CGFloat, h: Float, z: Float) {
    let span = w + 0.6
    let rise: CGFloat = 2.3
    box(roof, span, 0.3, depth, 0, h + 0.4, z, roofWhite, r: 0.06)
    let path = UIBezierPath()
    path.move(to: CGPoint(x: -span / 2, y: 0))
    path.addQuadCurve(to: CGPoint(x: span / 2, y: 0), controlPoint: CGPoint(x: 0, y: rise * 2))
    path.close()
    path.flatness = 0.08
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.materials = [material(roofWhite)]
    let vault = SCNNode(geometry: shape)
    let (low, high) = vault.boundingBox
    vault.pivot = SCNMatrix4MakeTranslation(0, 0, (low.z + high.z) / 2)
    vault.position = SCNVector3(0, h + 0.55, z)
    roof.addChildNode(vault)
    box(roof, 1.8, 0.14, depth * 0.86, 0, h + 0.55 + Float(rise), z, glass, r: 0.05, rough: 0.2)
    box(roof, span, 0.5, 0.18, 0, h + 0.75, z + Float(depth / 2), graphite, r: 0)
  }
  private func pitchedRoof(_ roof: SCNNode, width w: CGFloat, depth: CGFloat, h: Float, z: Float) {
    let slab = box(roof, w + 0.6, 0.32, depth, 0, h + 0.85, z, roofWhite, r: 0.06)
    slab.eulerAngles.x = 0.08
    box(roof, w + 0.6, 0.25, 0.3, 0, h + 0.4, z + Float(depth / 2), graphite, r: 0)
    for skylightX in stride(from: -Float(w / 2) + 4, through: Float(w / 2) - 3, by: 7) {
      let light = box(roof, 2.2, 0.18, depth * 0.4, skylightX, h + 1.05, z, glass, r: 0.06, rough: 0.2)
      light.eulerAngles.x = 0.08
    }
  }
  private func brandSign(_ p: SCNNode, position: SCNVector3, width: CGFloat) {
    let g = SCNPlane(width: width, height: width * 0.3)
    let m = SCNMaterial()
    m.diffuse.contents = UIImage(named: "salini-logo.png")?.withTintColor(
      chalk, renderingMode: .alwaysOriginal)
    m.lightingModel = .constant
    m.isDoubleSided = true
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.position = position
    p.addChildNode(n)
  }
  private func worker(_ p: SCNNode, x: Float, z: Float, walking: Bool = false) {
    let holder = SCNNode()
    holder.position = SCNVector3(x, 0.35, z)
    holder.scale = SCNVector3(1.65, 1.65, 1.65)
    p.addChildNode(holder)
    person(holder, x: 0, z: 0, walking: walking)
  }
  private func bench(_ p: SCNNode, x: Float, z: Float, kind: Int) {
    let shadow = SCNNode()
    shadow.position = SCNVector3(x, 0.35, z)
    p.addChildNode(shadow)
    contactShadow(shadow, width: 5.2, depth: 3.5)
    box(p, 4.2, 0.18, 2.7, x, 1.3, z, UIColor(hex: 0x8C989E))
    for dx: Float in [-1.8, 1.8] { box(p, 0.2, 1.0, 2.3, x + dx, 0.75, z, steel) }
    product(p, kind: kind, x: x, y: 1.43, z: z)
  }
  /// Distinct silhouettes: oval bath, paired basins, flat shower tray, vanity set, mirror.
  private func product(_ p: SCNNode, kind: Int, x: Float, y: Float, z: Float) {
    switch kind % 5 {
    case 0: tub(p, x: x, y: y, z: z, scale: 1.2)
    case 1:
      let bowl = SCNNode()
      bowl.position = SCNVector3(x - 0.65, y, z)
      bowl.scale = SCNVector3(0.62, 0.55, 0.95)
      p.addChildNode(bowl)
      tub(bowl, x: 0, y: 0, z: 0)
      let bowl2 = bowl.clone()
      bowl2.position.x += 1.3
      p.addChildNode(bowl2)
    case 2:
      box(p, 2.9, 0.13, 2.1, x, y + 0.07, z, UIColor(hex: 0xFBFBFC), r: 0.06, rough: 0.3)
      box(p, 2.5, 0.035, 1.75, x, y + 0.145, z, UIColor(hex: 0xE3E9EA), r: 0.017, rough: 0.3)
      cylinder(p, r: 0.09, h: 0.025, x: x + 1, y: y + 0.18, z: z + 0.65, color: steel, metal: 0.6)
    case 3:
      box(p, 2.8, 1.15, 1.3, x, y + 0.6, z, walnut, r: 0.06, rough: 0.6)
      box(p, 2.9, 0.13, 1.45, x, y + 1.25, z, UIColor(hex: 0xF4F3EF), rough: 0.4)
      for dx: Float in [-0.7, 0.7] {
        box(p, 1.28, 0.035, 0.03, x + dx, y + 0.8, z + 0.665, UIColor(hex: 0x2E2A27), r: 0)
      }
      let bowl = SCNNode()
      bowl.position = SCNVector3(x, y + 1.32, z)
      bowl.scale = SCNVector3(0.68, 0.45, 0.7)
      p.addChildNode(bowl)
      tub(bowl, x: 0, y: 0, z: 0)
    default:
      box(p, 1.9, 2.8, 0.15, x, y + 1.4, z, graphite, r: 0.07)
      box(p, 1.7, 2.6, 0.04, x, y + 1.4, z + 0.1, mirrorGlass, r: 0.02, rough: 0.06, metal: 0.9)
      box(p, 2.4, 0.16, 1.3, x, y, z, steel)
    }
  }
  private func silo(_ p: SCNNode, x: Float, z: Float, top: Float) {
    let shell = UIColor(hex: 0xD6DDE0)
    for dx: Float in [-1.15, 1.15] {
      for dz: Float in [-1.15, 1.15] { box(p, 0.16, 2.6, 0.16, x + dx, 1.6, z + dz, steel, r: 0) }
    }
    cone(p, top: 1.72, bottom: 0.32, h: 1.7, x: x, y: 3.05, z: z, color: shell, metal: 0.55)
    let body = top - 3.9
    cylinder(p, r: 1.72, h: CGFloat(body), x: x, y: 3.9 + body / 2, z: z, color: shell, metal: 0.55)
    cone(p, top: 0.25, bottom: 1.72, h: 0.7, x: x, y: top + 0.35, z: z, color: shell, metal: 0.55)
    for y in [3.9 + body * 0.33, 3.9 + body * 0.66] {
      cylinder(p, r: 1.76, h: 0.09, x: x, y: y, z: z, color: graphite)
    }
    box(p, 0.5, 0.6, 0.5, x, 1.9, z, graphite, r: 0.04)
    for dz: Float in [-0.25, 0.25] {
      box(p, 0.05, CGFloat(top - 2), 0.05, x + 1.8, (top + 2) / 2, z + dz, steel, r: 0)
    }
  }
  private func ibc(_ p: SCNNode, x: Float, z: Float, valve: UIColor) {
    box(p, 1.2, 0.16, 1.0, x, 0.42, z, graphite, r: 0.02)
    box(p, 1.04, 0.98, 0.9, x, 1.0, z, UIColor(hex: 0xEEF1EC), r: 0.08, rough: 0.5)
    for dx: Float in [-0.55, 0.55] {
      for dz: Float in [-0.47, 0.47] { box(p, 0.04, 1.04, 0.04, x + dx, 1.0, z + dz, steel, r: 0) }
    }
    for y: Float in [0.98, 1.5] {
      box(p, 1.14, 0.04, 0.04, x, y, z + 0.47, steel, r: 0)
      box(p, 0.04, 0.04, 0.98, x + 0.55, y, z, steel, r: 0)
    }
    cylinder(p, r: 0.12, h: 0.08, x: x, y: 1.53, z: z, color: graphite)
    box(p, 0.16, 0.14, 0.12, x, 0.62, z + 0.5, valve, r: 0.02)
  }
  private func mixingStation(_ p: SCNNode, x: Float, z: Float, color: UIColor) {
    let deck: Float = 2.6
    for dx: Float in [-2.6, 2.6] {
      for dz: Float in [-1.9, 1.9] {
        box(p, 0.18, CGFloat(deck), 0.18, x + dx, deck / 2 + 0.33, z + dz, steel, r: 0)
      }
    }
    box(p, 5.6, 0.16, 4.2, x, deck + 0.4, z, UIColor(hex: 0xAEB7BA), r: 0)
    box(p, 5.6, 0.05, 0.05, x, deck + 1.45, z + 2.1, safetyLane, r: 0)
    box(p, 0.05, 0.05, 4.2, x + 2.8, deck + 1.45, z, safetyLane, r: 0)
    for i in 0..<6 {
      let t = Float(i)
      box(p, 0.42, 0.1, 1.0, x + 5.0 - t * 0.38, 0.55 + t * 0.4, z + 1.2, steel, r: 0)
    }
    cone(p, top: 1.15, bottom: 0.3, h: 1.3, x: x - 0.8, y: deck - 0.1, z: z - 0.2, color: color)
    cylinder(p, r: 1.15, h: 2.4, x: x - 0.8, y: deck + 1.7, z: z - 0.2, color: color)
    let dome = ball(p, r: 1.15, x: x - 0.8, y: deck + 2.9, z: z - 0.2, color: color)
    dome.scale = SCNVector3(1, 0.35, 1)
    box(p, 0.8, 0.8, 0.8, x - 0.8, deck + 3.6, z - 0.2, graphite, r: 0.05)
    let fan = SCNNode()
    fan.position = SCNVector3(x - 0.8, deck + 4.05, z - 0.2)
    p.addChildNode(fan)
    box(fan, 0.9, 0.06, 0.16, 0, 0, 0, steel, r: 0)
    fan.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2)), forKey: "motion")
    box(p, 1.2, 0.9, 0.9, x + 1.6, deck + 0.95, z - 1.2, graphite, r: 0.05)
    cone(p, top: 0.7, bottom: 0.15, h: 1.2, x: x + 1.5, y: deck + 1.2, z: z + 0.9,
         color: galvanized, metal: 0.45)
  }
  private func sprayBooth(_ p: SCNNode, x: Float, z: Float) {
    box(p, 5.6, 3.6, 0.3, x, 2.13, z - 2, UIColor(hex: 0x8FAAB0), r: 0)
    for dx in stride(from: -2.4, through: 2.4, by: 0.8) {
      box(p, 0.04, 3.2, 0.02, x + Float(dx), 2.13, z - 1.84, UIColor(hex: 0x6E8990), r: 0)
    }
    for side: Float in [-2.8, 2.8] {
      box(p, 0.1, 3.6, 4, x + side, 2.13, z, UIColor(hex: 0xDCE3E4), r: 0)
    }
    box(p, 5.8, 0.25, 4.2, x, 4.05, z, galvanized, r: 0.05)
    cylinder(p, r: 0.4, h: 3, x: x, y: 5.6, z: z - 1.4, color: galvanized, metal: 0.45)
    box(p, 2.2, 0.9, 1.2, x, 0.78, z + 0.2, steel)
    tub(p, x: x, y: 1.25, z: z + 0.2, scale: 1.3)
  }
  private func curingOven(_ p: SCNNode, x: Float, z: Float) {
    box(p, 5.2, 3.1, 6, x, 1.9, z, UIColor(hex: 0xE4E7E6), r: 0.1)
    box(p, 4, 2.4, 0.08, x, 1.65, z + 3.02, graphite, r: 0)
    box(p, 3.6, 0.22, 0.06, x, 2.55, z + 3.07, UIColor(hex: 0xE9A04A), r: 0, glow: 0.55)
    box(p, 0.5, 0.9, 0.3, x + 2.2, 1.6, z + 3.12, graphite, r: 0.03)
    box(p, 0.12, 0.12, 0.04, x + 2.2, 1.85, z + 3.28, InsideStyle.green, r: 0, glow: 0.6)
    cylinder(p, r: 0.28, h: 3.5, x: x - 1.6, y: 5.2, z: z - 1.5, color: galvanized, metal: 0.45)
    for dx: Float in [-0.9, 0.9] {
      box(p, 0.08, 0.05, 4.2, x + dx, 0.37, z + 5.1, steel, r: 0)
    }
    // A mould cart rides into the oven, cures and comes back out.
    let cart = SCNNode()
    cart.position = SCNVector3(x, 0, z + 5.2)
    p.addChildNode(cart)
    box(cart, 2.2, 0.14, 2.9, 0, 0.62, 0, graphite, r: 0.03)
    for dx: Float in [-0.95, 0.95] {
      for dz: Float in [-1.1, 1.1] {
        let wheel = cylinder(cart, r: 0.16, h: 0.12, x: dx, y: 0.47, z: dz, color: steel)
        wheel.eulerAngles.z = .pi / 2
      }
    }
    box(cart, 2.1, 0.42, 2.7, 0, 0.9, 0, mould, r: 0.08, rough: 0.35)
    let turned = SCNNode()
    turned.eulerAngles.y = .pi / 2
    cart.addChildNode(turned)
    tub(turned, x: 0, y: 1.1, z: 0, scale: 1.05)
    let travel = SCNAction.moveBy(x: 0, y: 0, z: -4.6, duration: 5)
    travel.timingMode = .easeInEaseOut
    cart.runAction(.repeatForever(.sequence([
      .wait(duration: 3), travel, .wait(duration: 10), travel.reversed(), .wait(duration: 4),
    ])), forKey: "motion")
  }
  private func mouldTable(_ p: SCNNode, x: Float, z: Float, kind: Int) {
    let shadow = SCNNode()
    shadow.position = SCNVector3(x, 0.35, z)
    p.addChildNode(shadow)
    contactShadow(shadow, width: 5.4, depth: 3.6)
    for dx: Float in [-2, 2] {
      for dz: Float in [-1.1, 1.1] { box(p, 0.16, 0.9, 0.16, x + dx, 0.78, z + dz, steel, r: 0) }
    }
    box(p, 4.6, 0.5, 2.8, x, 1.42, z, mould, r: 0.1, rough: 0.35)
    switch kind {
    case 0: tub(p, x: x, y: 1.55, z: z, scale: 1.5)
    case 1: product(p, kind: 1, x: x, y: 1.6, z: z)
    default: product(p, kind: 2, x: x, y: 1.65, z: z)
    }
  }
  private func sandingBooth(_ p: SCNNode, x: Float, z: Float, color: UIColor) {
    box(p, 5.6, 1.2, 0.8, x, 0.93, z - 1.9, color, r: 0.06, rough: 0.5)
    for dx in stride(from: -2.2, through: 2.2, by: 0.55) {
      box(p, 0.05, 0.85, 0.02, x + Float(dx), 0.95, z - 1.49, graphite, r: 0)
    }
    box(p, 5.6, 2.3, 0.3, x, 2.7, z - 2.15, UIColor(hex: 0xC6D2D6), r: 0)
    for side: Float in [-2.8, 2.8] {
      box(p, 0.08, 3.4, 4, x + side, 2.03, z, UIColor(hex: 0xDDE5E7), r: 0)
    }
    box(p, 5.8, 0.22, 4.2, x, 3.85, z, galvanized, r: 0.05)
    cylinder(p, r: 0.38, h: 3.6, x: x, y: 5.75, z: z - 1.4, color: galvanized, metal: 0.45)
    // The part turns slowly on its fixture so every face reaches the sander.
    let fixture = SCNNode()
    fixture.position = SCNVector3(x, 0, z + 0.4)
    p.addChildNode(fixture)
    cylinder(fixture, r: 1.25, h: 0.5, x: 0, y: 0.6, z: 0, color: graphite)
    tub(fixture, x: 0, y: 0.86, z: 0, scale: 1.25)
    fixture.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)),
                      forKey: "motion")
  }
  private func polishingStation(_ p: SCNNode, x: Float, z: Float, color: UIColor) {
    cylinder(p, r: 0.35, h: 0.9, x: x, y: 0.78, z: z, color: steel)
    cylinder(p, r: 0.9, h: 0.12, x: x, y: 1.29, z: z, color: graphite)
    let bowl = SCNNode()
    bowl.position = SCNVector3(x, 1.36, z)
    bowl.scale = SCNVector3(0.62, 0.55, 0.95)
    p.addChildNode(bowl)
    tub(bowl, x: 0, y: 0, z: 0)
    box(p, 0.5, 1.9, 0.5, x - 1.6, 1.28, z - 0.6, color, r: 0.08, rough: 0.5)
    let arm = box(p, 1.7, 0.18, 0.2, x - 0.9, 2.3, z - 0.4, steel, r: 0.04)
    arm.eulerAngles.y = 0.35
    cylinder(p, r: 0.18, h: 0.4, x: x - 0.15, y: 2.0, z: z - 0.15, color: color)
  }
  private func drillStation(_ p: SCNNode, x: Float, z: Float, color: UIColor) {
    box(p, 3.4, 0.9, 2.2, x, 0.78, z, steel)
    tub(p, x: x, y: 1.25, z: z, scale: 1.1)
    box(p, 0.4, 3.2, 0.4, x - 1.6, 1.93, z - 0.9, graphite, r: 0.04)
    box(p, 2, 0.5, 0.5, x - 0.7, 3.4, z - 0.9, color, r: 0.06, rough: 0.5)
    cylinder(p, r: 0.08, h: 0.7, x: x + 0.2, y: 2.9, z: z - 0.9, color: steel, metal: 0.6)
  }
  private func partsCart(_ p: SCNNode, x: Float, z: Float) {
    box(p, 3.4, 0.14, 2.2, x, 0.75, z, graphite, r: 0.03)
    for dx: Float in [-1.5, 1.5] {
      for dz: Float in [-0.95, 0.95] {
        let wheel = cylinder(p, r: 0.18, h: 0.12, x: x + dx, y: 0.52, z: z + dz, color: steel)
        wheel.eulerAngles.z = .pi / 2
      }
    }
    box(p, 0.08, 1.1, 2.2, x - 1.66, 1.3, z, steel, r: 0)
    tub(p, x: x, y: 0.85, z: z, scale: 1.25)
  }
  private func inspectionDesk(_ p: SCNNode, x: Float, z: Float) {
    box(p, 2.6, 0.1, 1.2, x, 1.3, z, chalk, r: 0.03)
    for dx: Float in [-1.1, 1.1] { box(p, 0.08, 0.95, 1, x + dx, 0.8, z, steel, r: 0) }
    box(p, 1.1, 0.7, 0.06, x, 1.8, z - 0.35, graphite, r: 0.02)
    box(p, 1.0, 0.6, 0.02, x, 1.8, z - 0.31, UIColor(hex: 0xBFD8E4), r: 0, glow: 0.25)
  }
  private func holdCage(_ p: SCNNode, x: Float, z: Float) {
    let w: Float = 4.6
    let d: Float = 2.8
    box(p, CGFloat(w), 0.03, CGFloat(d), x, 0.35, z, graphite, r: 0)
    for side: Float in [-1, 1] {
      box(p, CGFloat(w), 0.035, 0.14, x, 0.37, z + side * (d / 2 - 0.07), InsideStyle.amber, r: 0)
      box(p, 0.14, 0.035, CGFloat(d), x + side * (w / 2 - 0.07), 0.37, z, InsideStyle.amber, r: 0)
    }
    for (dx, dz) in [(-w / 2, -d / 2), (w / 2, -d / 2), (-w / 2, d / 2), (w / 2, d / 2)] {
      box(p, 0.08, 2.2, 0.08, x + dx, 1.43, z + dz, steel, r: 0)
    }
    for y: Float in [1.0, 2.5] {
      box(p, CGFloat(w), 0.05, 0.05, x, y, z + d / 2, steel, r: 0)
      box(p, 0.05, 0.05, CGFloat(d), x + w / 2, y, z, steel, r: 0)
    }
    for bar in stride(from: -w / 2 + 0.4, through: w / 2 - 0.4, by: 0.4) {
      box(p, 0.025, 1.5, 0.025, x + bar, 1.75, z + d / 2, steel, r: 0)
    }
    for bar in stride(from: -d / 2 + 0.4, through: d / 2 - 0.4, by: 0.4) {
      box(p, 0.025, 1.5, 0.025, x + w / 2, 1.75, z + bar, steel, r: 0)
    }
    box(p, 1.2, 0.14, 1.0, x - 0.6, 0.45, z, palletWood, r: 0)
    product(p, kind: 1, x: x - 0.6, y: 0.55, z: z)
  }
  private func stretchWrapper(_ p: SCNNode, x: Float, z: Float, color: UIColor) {
    cylinder(p, r: 1.25, h: 0.22, x: x, y: 0.44, z: z, color: graphite)
    let turntable = SCNNode()
    turntable.position = SCNVector3(x, 0.45, z)
    p.addChildNode(turntable)
    pallet(turntable, x: 0, z: 0, y: 0)
    turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 6)),
                        forKey: "motion")
    box(p, 0.35, 3.4, 0.35, x + 1.4, 2.03, z, color, r: 0.05, rough: 0.5)
    let carriage = SCNNode()
    carriage.position = SCNVector3(x + 1.12, 0.95, z)
    p.addChildNode(carriage)
    box(carriage, 0.3, 0.55, 0.6, 0, 0, 0, graphite, r: 0.03)
    cylinder(carriage, r: 0.12, h: 0.5, x: -0.2, y: 0, z: 0, color: UIColor(hex: 0xF3F6F7))
    let rise = SCNAction.moveBy(x: 0, y: 1.3, z: 0, duration: 3)
    rise.timingMode = .easeInEaseOut
    carriage.runAction(.repeatForever(.sequence([rise, rise.reversed()])), forKey: "motion")
  }
  private func crateStation(_ p: SCNNode, x: Float, z: Float) {
    box(p, 4.6, 0.16, 2.6, x, 0.42, z, crateWood, r: 0)
    tub(p, x: x, y: 0.55, z: z, scale: 1.45)
    for dx: Float in [-2.2, 2.2] {
      for dz: Float in [-1.2, 1.2] { box(p, 0.14, 1.6, 0.14, x + dx, 1.2, z + dz, crateWood, r: 0) }
    }
    for y: Float in [0.9, 1.9] {
      box(p, 4.6, 0.12, 0.1, x, y, z + 1.25, crateWood, r: 0)
      box(p, 4.6, 0.12, 0.1, x, y, z - 1.25, crateWood, r: 0)
      box(p, 0.1, 0.12, 2.6, x + 2.25, y, z, crateWood, r: 0)
    }
    for i in 0..<4 {
      box(p, 4.2, 0.08, 0.3, x, 0.4 + Float(i) * 0.09, z + 2.0, shade(crateWood, 0.92), r: 0)
    }
  }
  private func rackRun(_ p: SCNNode, x: Float, from z0: Float, bays: Int, levels: Int, seed: Int,
                       upright: UIColor) {
    let bay: Float = 2.7
    let heights = (0..<levels).map { 0.35 + Float($0) * 2 }
    let top = heights.last! + 1.65
    for i in 0...bays {
      let z = z0 + Float(i) * bay
      for dx: Float in [-0.55, 0.55] {
        box(p, 0.1, CGFloat(top - 0.3), 0.1, x + dx, (top + 0.3) / 2, z, upright, r: 0)
      }
    }
    let length = CGFloat(Float(bays) * bay)
    let middle = z0 + Float(bays) * bay / 2
    for y in heights.dropFirst() {
      for dx: Float in [-0.55, 0.55] {
        box(p, 0.12, 0.16, length, x + dx, y, middle, UIColor(hex: 0xC7742F), r: 0)
      }
    }
    for b in 0..<bays {
      for (l, y) in heights.enumerated() {
        for slot in 0..<2 {
          let k = (b * 7 + l * 3 + slot * 5 + seed) % 11
          // A few open locations read as working stock rather than a solid block.
          if k == 0 || k == 6 { continue }
          load(p, x: x, y: y + (l == 0 ? 0 : 0.08), z: z0 + Float(b) * bay + 0.68 + Float(slot) * 1.34,
               kind: k % 3)
        }
      }
    }
  }
  private func load(_ p: SCNNode, x: Float, y: Float, z: Float, kind: Int) {
    box(p, 1, 0.14, 1.15, x, y + 0.07, z, palletWood, r: 0)
    switch kind {
    case 0:
      box(p, 0.95, 1.05, 1.1, x, y + 0.67, z, crateWood, r: 0.02)
      for dy: Float in [0.45, 0.9] {
        box(p, 0.97, 0.06, 1.12, x, y + dy, z, shade(crateWood, 0.82), r: 0)
      }
    case 1:
      box(p, 0.92, 1.2, 1.05, x, y + 0.74, z, kraft, r: 0.03)
      box(p, 0.94, 0.05, 0.12, x, y + 1.34, z, UIColor(hex: 0xE6DAC2), r: 0)
    default:
      box(p, 0.92, 1.3, 1.05, x, y + 0.79, z, UIColor(hex: 0xE9EDEE), r: 0.06, rough: 0.35)
    }
  }
  private func dockPortal(_ p: SCNNode, x: Float, z: Float, bumper: UIColor) {
    box(p, 4, 4.4, 0.25, x, 2.53, z, UIColor(hex: 0x23292D), r: 0.05)
    box(p, 3.2, 3.5, 0.08, x, 2.08, z + 0.15, UIColor(hex: 0x56616A), r: 0)
    for i in 1..<5 {
      box(p, 3.2, 0.03, 0.02, x, 0.35 + Float(i) * 0.7, z + 0.2, UIColor(hex: 0x6E7A82), r: 0)
    }
    box(p, 2.6, 0.1, 1.0, x, 0.38, z + 0.65, steel, r: 0)
    for dx: Float in [-1.55, 1.55] {
      box(p, 0.28, 0.45, 0.3, x + dx, 0.75, z + 0.3, bumper, r: 0.04)
    }
    box(p, 0.2, 0.2, 0.08, x + 1.85, 3.3, z + 0.17, InsideStyle.green, r: 0, glow: 0.5)
  }
  private func mirrorRack(_ p: SCNNode, x: Float, z: Float) {
    box(p, 3.6, 0.18, 1.6, x, 0.44, z, graphite, r: 0.03)
    for side: Float in [-1, 1] {
      for i in 0..<3 {
        let panel = box(p, CGFloat(3.2 - Float(i) * 0.35), 2, 0.05, x,
                        1.5, z + side * (0.32 + Float(i) * 0.12), mirrorGlass, r: 0, rough: 0.06,
                        metal: 0.9)
        panel.eulerAngles.x = -side * 0.22
      }
    }
    for dx: Float in [-1.75, 1.75] { box(p, 0.1, 2.3, 0.1, x + dx, 1.65, z, steel, r: 0) }
    box(p, 3.6, 0.1, 0.1, x, 2.8, z, steel, r: 0)
  }
  private func populate(_ zone: FactoryZone, node n: SCNNode) {
    switch zone {
    case .office:
      // Order desks, a reception counter and a small showroom behind the glazed front.
      for x: Float in [-6, 0] {
        for z: Float in [-6, -1] {
          box(n, 3.4, 0.12, 1.7, x, 1.25, z, chalk)
          box(n, 0.9, 0.6, 0.06, x, 1.65, z - 0.45, graphite, r: 0.02)
          for dx: Float in [-1.5, 1.5] { box(n, 0.08, 0.95, 1.5, x + dx, 0.78, z, steel, r: 0) }
        }
      }
      box(n, 5, 1.1, 1.2, -4, 0.88, 5.5, walnut, r: 0.05, rough: 0.6)
      box(n, 5.2, 0.1, 1.4, -4, 1.48, 5.5, chalk, r: 0.03)
      box(n, 4.8, 0.45, 3, 4.5, 0.55, 4.8, chalk, r: 0.1)
      product(n, kind: 0, x: 4.5, y: 0.78, z: 4.8)
      box(n, 2.8, 0.9, 1.2, 5.2, 0.75, -0.5, chalk, r: 0.05)
      product(n, kind: 1, x: 5.2, y: 1.22, z: -0.5)
      worker(n, x: 2, z: 5, walking: true)
    case .materials:
      // Mineral filler silos, resin totes on a spill tray, pigment drums and RAL samples.
      for x: Float in [-6, 0, 6] { silo(n, x: x, z: -6, top: 11) }
      box(n, 16.5, 0.18, 1.1, 0, 11.5, -6, steel, r: 0)
      for dz: Float in [-0.5, 0.5] { box(n, 16.5, 0.05, 0.05, 0, 12.4, -6 + dz, safetyLane, r: 0) }
      box(n, 8.6, 0.28, 5.4, 4.5, 0.47, 5, zone.accent, r: 0.05, rough: 0.6)
      for x: Float in [2, 4.5, 7] {
        for z: Float in [3.6, 6.4] { ibc(n, x: x, z: z, valve: graphite) }
      }
      for (x, z) in [(-8, 2.5), (-7.2, 3.3), (-8, 4.1), (-6.4, 2.5), (-6.4, 4.1)] as [(Float, Float)] {
        cylinder(n, r: 0.32, h: 0.9, x: x, y: 0.78, z: z, color: UIColor(hex: 0x2E5D88))
        cylinder(n, r: 0.33, h: 0.04, x: x, y: 1.24, z: z, color: graphite)
      }
      box(n, 3.2, 0.1, 1.2, -4.5, 1.2, 8, chalk, r: 0.03)
      for (i, tone) in [0xF4F4F2, 0x3A3F44, 0xB0634A, 0x7C9A7B, 0x2E5D88].enumerated() {
        cylinder(n, r: 0.22, h: 0.4, x: -5.8 + Float(i) * 0.65, y: 1.45, z: 8,
                 color: UIColor(hex: UInt(tone)))
      }
      for dx: Float in [-1.4, 1.4] { box(n, 0.1, 0.85, 1, -4.5 + dx, 0.75, 8, steel, r: 0) }
      worker(n, x: 0, z: 2)
    case .casting:
      // Mix → gelcoat → moulds → oven: the conditional demo route of mineral casting.
      mixingStation(n, x: -12, z: -11.5, color: zone.accent)
      sprayBooth(n, x: -2.5, z: -12)
      for x: Float in [7, 13] { curingOven(n, x: x, z: -11) }
      for x: Float in [-12, -4, 4, 12] { mouldTable(n, x: x, z: -1, kind: 0) }
      for x: Float in [-12, -4, 4, 12] { mouldTable(n, x: x, z: 5.5, kind: 1) }
      for x: Float in [-12, -4, 4, 12] { mouldTable(n, x: x, z: 11.5, kind: 2) }
      for z: Float in [2.3, 8.6] {
        box(n, 32, 0.02, 0.12, 0, 0.345, z, safetyLane, r: 0)
      }
      // Bridge crane with the dosing head travels over the three mould rows.
      for x: Float in [-16.6, 16.6] {
        for z: Float in [-5.5, 14.5] { box(n, 0.3, 6.2, 0.3, x, 3.4, z, steel, r: 0) }
      }
      for z: Float in [-5.5, 14.5] { box(n, 33.5, 0.35, 0.35, 0, 6.55, z, steel, r: 0) }
      let bridge = SCNNode()
      bridge.position = SCNVector3(-12, 0, 0)
      n.addChildNode(bridge)
      box(bridge, 0.55, 0.5, 20.6, 0, 6.98, 4.5, zone.accent, r: 0.04, rough: 0.5)
      box(bridge, 1.4, 0.75, 1.3, 0, 6.35, 5.5, graphite, r: 0.05)
      cylinder(bridge, r: 0.09, h: 2.9, x: 0, y: 4.5, z: 5.5, color: steel)
      box(bridge, 0.6, 0.4, 0.6, 0, 2.95, 5.5, zone.accent, r: 0.05)
      let move = SCNAction.moveBy(x: 24, y: 0, z: 0, duration: 14)
      move.timingMode = .easeInEaseOut
      bridge.runAction(
        .repeatForever(.sequence([move, .wait(duration: 3), move.reversed(), .wait(duration: 3)])),
        forKey: "motion")
      for x: Float in [-8, 8] { worker(n, x: x, z: 8.6, walking: true) }
      worker(n, x: -8, z: -8)
    case .finishing:
      // Sanding booths with extraction, polishing posts, overflow drilling and staging.
      for x: Float in [-7.5, 0, 7.5] { sandingBooth(n, x: x, z: -11.5, color: zone.accent) }
      for x: Float in [-7.5, 0, 7.5] { polishingStation(n, x: x, z: -3.5, color: zone.accent) }
      bench(n, x: -8, z: 6, kind: 0)
      bench(n, x: 0, z: 6, kind: 1)
      bench(n, x: 8, z: 6, kind: 0)
      drillStation(n, x: -7.5, z: 12, color: zone.accent)
      partsCart(n, x: 1.5, z: 12.5)
      partsCart(n, x: 6.5, z: 12.5)
      for z: Float in [1.5, 9.4] { box(n, 22, 0.02, 0.12, 0, 0.345, z, safetyLane, r: 0) }
      worker(n, x: -4, z: 1.5, walking: true)
      worker(n, x: 3.5, z: 9.4, walking: true)
      worker(n, x: -6, z: -2.2)
    case .assembly:
      // Furniture and mirrors arrive finished from suppliers: this hall only kits orders.
      let back = SCNNode()
      back.eulerAngles.y = .pi / 2
      back.position = SCNVector3(0, 0, -12.7)
      n.addChildNode(back)
      rackRun(back, x: 0, from: -12.2, bays: 9, levels: 3, seed: 3, upright: zone.accent)
      mirrorRack(n, x: 9.5, z: -6.5)
      mirrorRack(n, x: 9.5, z: -1.5)
      for (row, z) in [Float(-6), 0, 6].enumerated() {
        for (col, x) in [Float(-10), -4, 2].enumerated() {
          product(n, kind: 3 + ((row + col) % 2), x: x, y: 0.4, z: z)
        }
      }
      for x: Float in [-9, -3, 4] {
        box(n, 4, 0.14, 2, x, 1.3, 12, UIColor(hex: 0xE6E1D8), r: 0.03)
        for dx: Float in [-1.8, 1.8] { box(n, 0.1, 0.95, 1.8, x + dx, 0.8, 12, steel, r: 0) }
        box(n, 1.2, 0.5, 0.9, x - 0.8, 1.62, 12, kraft, r: 0.02)
      }
      partsCart(n, x: 9.5, z: 7.5)
      worker(n, x: 1, z: 9, walking: true)
      worker(n, x: -6, z: 10)
    case .quality:
      for (index, x) in [Float(-7), 0, 7].enumerated() {
        bench(n, x: x, z: 0, kind: index)
        for side: Float in [-2, 2] { box(n, 0.1, 3, 0.1, x + side, 2, -1.4, steel, r: 0) }
        box(n, 4.2, 0.12, 0.1, x, 3.5, -1.4, steel, r: 0)
        // Daylight-balanced inspection canopy over each bay.
        box(n, 4, 0.06, 2.4, x, 3.48, -0.2, UIColor(hex: 0xF1F7FB), r: 0, glow: 0.45)
        let scan = box(n, 3.8, 0.02, 0.045, x, 2, -1.2, zone.accent, r: 0)
        let sweep = SCNAction.moveBy(x: 0, y: 0, z: 2.4, duration: 3)
        scan.runAction(.repeatForever(.sequence([sweep, sweep.reversed()])), forKey: "motion")
      }
      holdCage(n, x: 7, z: -5.6)
      inspectionDesk(n, x: -7, z: 5.6)
      worker(n, x: 3, z: 4)
      worker(n, x: -4, z: 4)
    case .packing:
      for z: Float in [-4, 3] {
        box(n, 15, 1, 3, -0.5, 0.9, z, steel)
        for x in stride(from: -7.5, through: 6.5, by: 0.7) {
          let roller = cylinder(
            n, r: 0.12, h: 2.8, x: Float(x), y: 1.5, z: z, color: UIColor(hex: 0xDCE3E3), metal: 0.4)
          roller.eulerAngles.x = .pi / 2
        }
        for x: Float in [-5, 0, 5] {
          let pack = SCNNode()
          n.addChildNode(pack)
          pallet(pack, x: 0, z: 0, y: 1.6)
          pack.position = SCNVector3(x - 1.5, 0, z)
          pack.runAction(
            .repeatForever(
              .sequence([
                .moveBy(x: 3, y: 0, z: 0, duration: 9), .fadeOut(duration: 0.3),
                .moveBy(x: -3, y: 0, z: 0, duration: 0), .fadeIn(duration: 0.3),
              ])), forKey: "motion")
        }
      }
      stretchWrapper(n, x: 9.2, z: -4, color: zone.accent)
      crateStation(n, x: -7, z: 6.3)
      for (i, y) in [Float(0.6), 1.3, 2.0].enumerated() {
        box(n, 1.3, 0.68, 1.1, 1.5 + Float(i % 2) * 0.15, y, 7, kraft, r: 0.03)
      }
      box(n, 1.4, 1.1, 0.9, 5.5, 0.88, 7, graphite, r: 0.05)
      box(n, 0.5, 0.02, 0.35, 5.5, 1.45, 7, UIColor.white, r: 0)
      for i in 0..<3 {
        let roll = cylinder(n, r: 0.18, h: 0.5, x: 9.6, y: 0.6, z: 1 + Float(i) * 0.45,
                            color: UIColor(hex: 0xF3F6F7))
        roll.eulerAngles.z = .pi / 2
      }
      worker(n, x: 2, z: 5.5, walking: true)
    case .warehouse:
      for (i, x) in [Float(-9.9), -3.65, -2.45, 3.55, 4.75].enumerated() {
        rackRun(n, x: x, from: -22, bays: 13, levels: 4, seed: i * 4, upright: zone.accent)
      }
      for (i, x) in [Float(-9.9), -3.05, 4.15].enumerated() {
        text3D("B–0\(i + 1)", n, position: SCNVector3(x - 0.5, 8.2, 13.2), size: 0.55, color: steel)
      }
      // Dock staging lanes in front of the doors.
      for x: Float in [-6.5, 0, 6.5] {
        box(n, 3, 0.02, 0.1, x, 0.345, 16, safetyLane, r: 0)
        for dx: Float in [-1.5, 1.5] { box(n, 0.1, 0.02, 6, x + dx, 0.345, 19, safetyLane, r: 0) }
      }
      for (x, z) in [(-6.5, 18.2), (-6.5, 20.6), (6.5, 18.2)] as [(Float, Float)] {
        load(n, x: x, y: 0.35, z: z, kind: Int(z) % 3)
      }
      let reach = forklift()
      reach.scale = SCNVector3(1.4, 1.4, 1.4)
      n.addChildNode(reach)
      travel(reach, points: [SCNVector3(0.6, 0.35, -19), SCNVector3(0.6, 0.35, 11)], speed: 1.6)
      worker(n, x: 8, z: 15, walking: true)
    case .dispatch:
      for (i, x) in [Float(-7), 0, 7].enumerated() {
        box(n, 5.6, 0.04, 16, x, 0.35, 0, UIColor(hex: 0xBAC5C8), r: 0.02)
        for side: Float in [-2.7, 2.7] { box(n, 0.1, 0.02, 16, x + side, 0.39, 0, chalk, r: 0) }
        let truck = vehicleTruck(moving: false)
        truck.scale = SCNVector3(1.7, 1.7, 1.7)
        truck.position = SCNVector3(x, 0.4, 3)
        n.addChildNode(truck)
        outboundTrucks[i + 1] = truck
        truck.name = "shipment-\(i + 1)"
        pallet(n, x: x, z: -5, y: 0.4)
        text3D("0\(i + 1)", n, position: SCNVector3(x - 0.8, 0.4, -8), size: 0.9, color: steel)
      }
      worker(n, x: -4, z: -5, walking: true)
    }
  }
  private func buildFlow() { showOrderRoute(FactoryZone.orderRoute) }
  private func addProcessDetail(_ zone: FactoryZone, node n: SCNNode) {
    let w = Float(zone.footprint.width / 2)
    let d = Float(zone.footprint.height / 2)
    // Pedestrian walkways are marked in a restrained safety yellow along both sides.
    if zone != .office && zone != .dispatch {
      for side: Float in [-1, 1] {
        box(n, 0.1, 0.02, CGFloat(d * 2 - 2), side * (w - 1.1), 0.345, 0, safetyLane, r: 0)
      }
    }
    switch zone {
    case .materials:
      stationMarker(.materials, "M-01", SCNVector3(-6, 7, -5))
      stationMarker(.materials, "M-02", SCNVector3(6, 3.2, 7))
    case .casting:
      stationMarker(.casting, "C-01", SCNVector3(-10, 3, 3))
      stationMarker(.casting, "C-04", SCNVector3(8, 3, 3))
      stationMarker(.casting, "C-07", SCNVector3(8, 4.5, -12))
    case .finishing:
      reserveCover = box(n, 4.4, 0.65, 2.8, 8, 1.7, 6, UIColor(hex: 0xCDD2D3), r: 0.2)
      reserveIndicator = box(n, 0.08, 0.22, 2.4, 10.3, 1.2, 6, InsideStyle.amber, r: 0.04)
      if let indicator = reserveIndicator { isolate(indicator) }
      if let cover = reserveCover { isolate(cover) }
      stationMarker(.finishing, "F-01", SCNVector3(-8, 3, 1))
      stationMarker(.finishing, "F-02", SCNVector3(0, 3, -8))
      stationMarker(.finishing, "F-04", SCNVector3(8, 3, 6))
      text3D("F–04", n, position: SCNVector3(6.5, 0.42, 9), size: 0.65, color: steel)
    case .quality:
      box(n, 6, 0.16, 3.4, 0, 4.5, 0, chalk)
      qualityIndicator = box(n, 5.6, 0.045, 0.18, 0, 4.38, 1.5, InsideStyle.amber, r: 0)
      if let indicator = qualityIndicator { isolate(indicator) }
      for z: Float in [-4, 4] {
        box(n, 4.7, 0.035, 0.11, -7, 0.41, z, safetyLane, r: 0)
      }
      stationMarker(.quality, "Q-01", SCNVector3(-7, 3.5, 1))
      stationMarker(.quality, "Q-02", SCNVector3(3, 4.9, 1))
    case .assembly:
      for x: Float in [-9, -3, 4] { pallet(n, x: x, z: -9.6, y: 0.4) }
      stationMarker(.assembly, "A-01", SCNVector3(-7, 3, 1))
      stationMarker(.assembly, "A-02", SCNVector3(8, 4, 7))
    case .warehouse:
      for x: Float in [-6.5, 0, 6.5] {
        dockPortal(n, x: x, z: d, bumper: FactoryZone.dispatch.accent)
      }
      // Dock canopy on slender ties over the three doors.
      box(n, 20, 0.22, 2.6, 0, 4.95, d + 1.3, roofWhite, r: 0.05)
      for x: Float in [-9.6, 0, 9.6] { box(n, 0.08, 1.6, 0.08, x, 5.85, d + 2.4, steel, r: 0) }
      stationMarker(.warehouse, "W-A", SCNVector3(-3, 7, -9))
      stationMarker(.warehouse, "W-B", SCNVector3(6, 7, 9))
    case .packing:
      stationMarker(.packing, "P-01", SCNVector3(-5, 4, -4))
      stationMarker(.packing, "P-02", SCNVector3(5, 4, 3))
    case .dispatch:
      for x: Float in [-7, 0, 7] {
        for side: Float in [-2.3, 2.3] {
          cylinder(n, r: 0.2, h: 0.9, x: x + side, y: 0.75, z: -5, color: zone.accent)
        }
        box(n, 5.8, 0.3, 2.1, x, 3.6, -6.7, roofWhite)
        for side: Float in [-2.6, 2.6] { box(n, 0.12, 3.2, 0.12, x + side, 1.95, -7.5, steel, r: 0) }
      }
      stationMarker(.dispatch, "D-01", SCNVector3(-7, 5, -1))
      stationMarker(.dispatch, "D-02", SCNVector3(0, 5, -1))
      stationMarker(.dispatch, "D-03", SCNVector3(7, 5, -1))
    case .office:
      stationMarker(.office, "O-01", SCNVector3(-4, 3, -3))
      stationMarker(.office, "O-02", SCNVector3(4, 3, 5))
    }
  }
  private func stationMarker(_ zone: FactoryZone, _ code: String, _ position: SCNVector3) {
    let button = CampusAnnotation(code) { [weak self] in self?.onStationSelect?(zone, code) }
    button.color = InsideStyle.blue
    button.accessibilityLabel = "Пост \(code), \(zone.title)"
    addSubview(button)
    stationTags.append((zone, code, position, button))
  }
  private func addSiteDetail() {
    let root = world.rootNode
    // Crossings link the office pedestrian promenade across the service street.
    for x: Float in [-43] {
      for offset in stride(from: -4.0, through: 4.0, by: 1.2) {
        box(root, 0.6, 0.025, 3, x + Float(offset), 0.08, 5, chalk, r: 0)
      }
    }
    // Pneumatic filler line from the silo catwalk to the casting hall, carried over the
    // service street on two slender portals.
    let siloLine = SCNNode()
    root.addChildNode(siloLine)
    for x: Float in [-52, -35.5] {
      for dz: Float in [-0.9, 0.9] { box(siloLine, 0.28, 6.1, 0.28, x, 3.05, -46 + dz, steel, r: 0) }
      box(siloLine, 0.3, 0.3, 2.2, x, 6.2, -46, steel, r: 0)
    }
    for dz: Float in [-0.35, 0.35] {
      let pipe = cylinder(siloLine, r: 0.17, h: 28.5, x: -46.2, y: 6.6, z: -46 + dz,
                          color: galvanized, metal: 0.45)
      pipe.eulerAngles.z = .pi / 2
      cylinder(siloLine, r: 0.17, h: 4.8, x: -60.4, y: 9, z: -46 + dz, color: galvanized, metal: 0.45)
    }
    // Fence and freight gate frame the widened eastern road without blocking the yard.
    for z in stride(from: -57, through: 73, by: 8) {
      cylinder(root, r: 0.07, h: 1.6, x: 112, y: 0.8, z: Float(z), color: steel)
    }
    for height: Float in [0.6, 1.5] {
      box(root, 0.06, 0.06, 136, 112, height, 8, steel, r: 0)
    }
    box(root, 5, 2.7, 4, 112, 1.3, -65, chalk)
    box(root, 4.1, 0.9, 0.08, 112, 1.8, -62.98, accent)
    let gatePivot = SCNNode()
    gatePivot.position = SCNVector3(110, 1.5, -64)
    root.addChildNode(gatePivot)
    box(gatePivot, 12, 0.16, 0.2, -6, 0, 0, chalk)
    freightGate = gatePivot
    text3D("SALINI", root, position: SCNVector3(-74, 0.08, 53), size: 1.4, color: steel)
  }
  private func buildOperationsMarkers() {
    for order in InsideOrderID.allCases {
      let marker = SCNNode()
      let ring = SCNTorus(ringRadius: 2.1, pipeRadius: 0.06)
      ring.materials = [material(InsideStyle.blue, glow: true)]
      marker.addChildNode(SCNNode(geometry: ring))
      world.rootNode.addChildNode(marker)
      orderMarkers[order] = marker
      marker.opacity = 0
      let tag = CampusAnnotation("\(order.product) · \(order.rawValue)") { [weak self] in
        self?.onOrderSelect?(order)
      }
      tag.accessibilityLabel = "Заказ \(order.rawValue), \(order.product)"
      tag.isHidden = true
      addSubview(tag)
      orderTags[order] = tag
    }
  }
  func apply(_ simulation: FactorySimulation, lens: CampusLens, tracked: InsideOrderID?) {
    self.simulation = simulation
    self.lens = lens
    self.trackedOrder = tracked
    if tracked == nil { followingShipment = false }
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.5
    for zone in FactoryZone.allCases {
      let load = simulation.load(zone)
      loadFloors[zone]?.opacity = lens == .load ? 0.12 : 0
      loadFloors[zone]?.geometry?.firstMaterial?.diffuse.contents = InsideStyle.loadColor(load)
      tags[zone]?.text =
        lens == .load ? "\(zone.shortTitle)  \(load)%" : "\(zone.code)  \(zone.shortTitle)"
      tags[zone]?.emphasized = activeZone == zone
      tags[zone]?.accessibilityValue = lens == .load ? "Загрузка \(load) процентов" : nil
      tags[zone]?.color =
        lens == .load ? InsideStyle.loadColor(load) : Palette.ink
    }
    for order in InsideOrderID.allCases {
      let zone = simulation.zone(for: order)
      var p = zone.position
      p.y = 0.65
      if order == .domino {
        p.x -= 6
        p.z -= 4
      }
      if order == .marea && zone == .dispatch { p.z += 4 }
      orderMarkers[order]?.position = p
      orderMarkers[order]?.opacity = tracked == order || lens == .orders ? 1 : 0
      orderTags[order]?.color =
        simulation.needsAttention(order) ? InsideStyle.amber : InsideStyle.blue
    }
    reserveCover?.opacity = simulation.reserve == .available ? 1 : 0
    reserveIndicator?.geometry?.firstMaterial?.diffuse.contents =
      simulation.reserve == .available
      ? steel : simulation.reserve == .preparing ? InsideStyle.amber : chalk
    qualityIndicator?.geometry?.firstMaterial?.diffuse.contents =
      simulation.quality == .held ? InsideStyle.amber : InsideStyle.green
    SCNTransaction.commit()
    if simulation.dispatchReleased { releaseDispatch(1) }
    if simulation.quality == .departed { releaseDispatch(2) }
    if simulation.quality == .loading && !transferStarted, let transfer = batchTransfer {
      transferStarted = true
      let points = CampusSite.transferRoute()
      var steps: [SCNAction] = []
      for (a, b) in zip(points, points.dropFirst()) {
        steps.append(.group([
          .rotateTo(x: 0, y: CGFloat(atan2(b.x - a.x, b.z - a.z)), z: 0,
                    duration: 0.18, usesShortestUnitArc: true),
          .move(to: b, duration: 0.85),
        ]))
      }
      let move = SCNAction.sequence(steps)
      move.speed = simulationSpeed
      transfer.runAction(move, forKey: "marea-transfer")
      transfer.isPaused = simulationPaused || UIAccessibility.isReduceMotionEnabled
      if UIAccessibility.isReduceMotionEnabled { transfer.position = CampusSite.transferRoute().last! }
    }
    placeLabels()
  }
  func showOrderRoute(_ zones: [FactoryZone]) {
    flow.childNodes.forEach { $0.removeFromParentNode() }
    // Draw along shared front-door spurs and actual service aisles.
    let points = CampusSite.processRoute(zones)
    for i in 0..<max(0, points.count - 1) {
      let a = points[i]
      let b = points[i + 1]
      let length = max(abs(a.x - b.x), abs(a.z - b.z))
      guard length > 0.1 else { continue }
      let segment = box(
        flow, CGFloat(max(0.13, abs(a.x - b.x))), 0.035, CGFloat(max(0.13, abs(a.z - b.z))),
        (a.x + b.x) / 2, 0.55, (a.z + b.z) / 2, InsideStyle.blue, r: 0)
      segment.opacity = 0.6
    }
    showRoute(true)
  }
  fileprivate func placeLabels() {
    guard bounds.width > 0, window != nil else { return }
    var occupied: [CGRect] = []
    let overview = mapCamera.scale > mapCamera.overviewScale * 0.72
    let priority = FactoryZone.allCases.sorted {
      if lens == .load, let simulation {
        let lhs = $0 == activeZone ? 1000 : simulation.load($0)
        let rhs = $1 == activeZone ? 1000 : simulation.load($1)
        return lhs == rhs ? $0.rawValue < $1.rawValue : lhs > rhs
      }
      return ($0 == activeZone ? -1 : $0.rawValue) < ($1 == activeZone ? -1 : $1.rawValue)
    }
    for zone in priority {
      guard let b = tags[zone] else { continue }
      var p = zone.position
      p.y = zone.buildingHeight + 2
      if zone == .dispatch { p.z += 19 }
      let point = projectPoint(p)
      b.sizeToFit()
      b.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y) - 22)
      let frame = b.frame.insetBy(dx: -5, dy: -5)
      let major: Set<FactoryZone> =
        lens == .load
        ? [.casting, .finishing, .quality, .warehouse] : [.office, .casting, .warehouse, .dispatch]
      let ordersLayer = lens == .orders || trackedOrder != nil
      b.isHidden =
        !labelsVisible || ordersLayer || (overview && !major.contains(zone))
        || (!overview && activeZone != nil && zone != activeZone) || point.z < 0 || point.z > 1
        || !bounds.insetBy(dx: 9, dy: 24).contains(frame)
        || occupied.contains(where: { $0.intersects(frame) })
        || excludedAnnotationRects.contains(where: { $0.intersects(frame) })
      if !b.isHidden { occupied.append(frame) }
    }
    for order in InsideOrderID.allCases {
      guard let tag = orderTags[order], let marker = orderMarkers[order] else { continue }
      var departedAndGone = false
      if simulation?.quality == .departed && (order == .marea || order == .domino),
        let truck = outboundTrucks[2]
      {
        let location = truck.presentation.convertPosition(SCNVector3Zero, to: nil)
        marker.position = SCNVector3(location.x, 0.65, location.z)
        departedAndGone = truck.presentation.opacity < 0.05
        marker.opacity = departedAndGone ? 0 : (trackedOrder == order || lens == .orders ? 1 : 0)
        if followingShipment && trackedOrder == order && !departedAndGone {
          mapCamera.focus = SCNVector3(location.x, 0, location.z)
          mapCamera.clamp()
          updateCamera(duration: 0)
        }
      }
      let point = projectPoint(marker.presentation.position)
      tag.sizeToFit()
      tag.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y) - 18)
      let frame = tag.frame.insetBy(dx: -4, dy: -4)
      let visible = lens == .orders || trackedOrder == order
      tag.isHidden =
        !visible || departedAndGone || !labelsVisible
        || !bounds.insetBy(dx: 10, dy: 50).contains(frame)
        || occupied.contains(where: { $0.intersects(frame) })
        || excludedAnnotationRects.contains(where: { $0.intersects(frame) })
      if !tag.isHidden { occupied.append(frame) }
    }
    for (zone, _, local, tag) in stationTags {
      var p = zone.position
      p.x += local.x
      p.z += local.z
      p.y = local.y
      let point = projectPoint(p)
      tag.sizeToFit()
      tag.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y) - 22)
      let frame = tag.frame.insetBy(dx: -3, dy: -3)
      tag.isHidden =
        activeZone != zone || !labelsVisible || lens == .orders || trackedOrder != nil
        || mapCamera.scale > 65 || !bounds.insetBy(dx: 12, dy: 45).contains(frame)
        || occupied.contains(where: { $0.intersects(frame) })
        || excludedAnnotationRects.contains(where: { $0.intersects(frame) })
      if !tag.isHidden { occupied.append(frame) }
    }
  }
  private func updateCamera(duration: Double) {
    let logical = mapCamera.focus
    let shift = framingShift
    let focus = SCNVector3(logical.x + shift.x, logical.y, logical.z + shift.z)
    let offset = CampusCamera.offset
    let animated = duration > 0 && !UIAccessibility.isReduceMotionEnabled
    if !animated {
      cameraNode.removeAllAnimations()
      cameraNode.camera?.removeAllAnimations()
    }
    SCNTransaction.begin()
    SCNTransaction.disableActions = !animated
    SCNTransaction.animationDuration = animated ? duration : 0
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    cameraNode.position = SCNVector3(focus.x + offset.x, focus.y + offset.y, focus.z + offset.z)
    cameraNode.look(at: focus)
    cameraNode.camera?.orthographicScale = mapCamera.scale * framingScale
    SCNTransaction.commit()
    onViewport?(mapCamera)
  }
  func resetCamera() {
    activeZone = nil
    explored = false
    mapCamera.overview()
    updateCamera(duration: 1.2)
    select(.casting, highlight: false)
    updateRoofs()
  }
  func select(_ zone: FactoryZone, animated: Bool = true, highlight: Bool = true) {
    chosen = zone
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.45 : 0
    for (z, outline) in outlines { outline.opacity = highlight && z == zone ? 1 : 0 }
    SCNTransaction.commit()
  }
  func focusOn(_ zone: FactoryZone, animated: Bool = true) {
    activeZone = zone
    explored = true
    select(zone)
    mapCamera.frame(zone)
    updateCamera(duration: animated ? 0.85 : 0)
    updateRoofs()
  }
  func closeUp(_ zone: FactoryZone) {
    focusOn(zone, animated: false)
    labelsVisible = false
  }
  func logistics() { focusOn(.dispatch) }
  func setRoof(_ visible: Bool) {
    roofVisible = visible
    updateRoofs()
  }
  private func updateRoofs() {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.8
    for (zone, pairs) in buildingMaterials {
      let fade: CGFloat = activeZone != nil && zone != activeZone ? 0.18 : 0
      for (material, original, glow, glowIntensity) in pairs {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        original.getRed(&r, green: &g, blue: &b, alpha: &a)
        material.diffuse.contents = UIColor(
          red: r + (0.94 - r) * fade, green: g + (0.945 - g) * fade, blue: b + (0.95 - b) * fade,
          alpha: a)
        if let glow {
          material.emission.contents = glow
          material.emission.intensity = glowIntensity * (1 - fade * 2.5)
        } else {
          material.emission.contents = InsideStyle.canvas
          material.emission.intensity = 0.03 + fade * 0.07
        }
      }
    }
    for (zone, roof) in roofs {
      let visible = roofVisible && zone != activeZone
      roof.opacity = visible ? 1 : 0
      roof.position.y = visible ? 0 : 3
    }
    SCNTransaction.commit()
  }
  func releaseDispatch(_ number: Int = 1) {
    guard !departures.contains(number), let truck = outboundTrucks[number] else { return }
    departures.insert(number)
    if number == 2 && trackedOrder != nil { followingShipment = true }
    freightGate?.removeAllActions()
    freightGate?.runAction(
      .sequence([
        .wait(duration: 8), .rotateTo(x: 0, y: 0, z: -.pi / 2, duration: 1.2), .wait(duration: 20),
        .rotateTo(x: 0, y: 0, z: 0, duration: 1.2),
      ]), forKey: "gate")
    freightGate?.action(forKey: "gate")?.speed = simulationSpeed
    freightGate?.isPaused = simulationPaused || UIAccessibility.isReduceMotionEnabled
    let origin = FactoryZone.dispatch.position
    let points = CampusSite.departureRoute(number).map {
      SCNVector3($0.x - origin.x, $0.y, $0.z - origin.z)
    }
    var steps: [SCNAction] = []
    let durations: [Double] = [3, 4, 18]
    for (i, pair) in zip(points, points.dropFirst()).enumerated() {
      steps.append(.rotateTo(x: 0, y: CGFloat(atan2(pair.1.x - pair.0.x, pair.1.z - pair.0.z)),
                             z: 0, duration: 0.7, usesShortestUnitArc: true))
      steps.append(.move(to: pair.1, duration: durations[i]))
    }
    steps.append(.fadeOut(duration: 0.5))
    let drive = SCNAction.sequence(steps)
    drive.speed = simulationSpeed
    truck.runAction(drive, forKey: "departure")
    truck.isPaused = simulationPaused || UIAccessibility.isReduceMotionEnabled
    if UIAccessibility.isReduceMotionEnabled { truck.opacity = 0 }
  }
  func stepZoom(_ closer: Bool) {
    followingShipment = false
    onExplore?()
    explored = true
    mapCamera.zoom(mapCamera.scale * (closer ? 0.72 : 1.38))
    updateCamera(duration: 0.65)
  }
  func showRoute(_ visible: Bool) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.4
    flow.opacity = visible ? 1 : 0
    SCNTransaction.commit()
  }
  func setPaused(_ paused: Bool) {
    simulationPaused = paused
    world.rootNode.enumerateChildNodes { node, _ in
      if !node.actionKeys.isEmpty {
        node.isPaused = paused || UIAccessibility.isReduceMotionEnabled
      }
    }
    isPlaying = true
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool
  {
    var current = touch.view
    while let v = current, v !== self {
      if v is UIControl { return false }
      current = v.superview
    }
    return true
  }
  @objc private func tap(_ gesture: UITapGestureRecognizer) {
    for hit in hitTest(gesture.location(in: self), options: nil) {
      var n: SCNNode? = hit.node
      while let node = n {
        if let name = node.name, name.hasPrefix("shipment-") {
          onSelect?(.dispatch)
          return
        }
        if let name = node.name, name.hasPrefix("zone-"), let i = Int(name.dropFirst(5)),
          let zone = FactoryZone(rawValue: i)
        {
          onSelect?(zone)
          return
        }
        n = node.parent
      }
    }
  }
  @objc private func pan(_ g: UIPanGestureRecognizer) {
    if g.state == .began {
      // Adopt the presentation camera so a touch can interrupt a flight without jumping.
      let presented = cameraNode.presentation.position
      mapCamera.scale =
        (cameraNode.presentation.camera?.orthographicScale ?? (mapCamera.scale * framingScale))
        / framingScale
      let shift = framingShift
      mapCamera.focus = SCNVector3(
        presented.x - CampusCamera.offset.x - shift.x, 0,
        presented.z - CampusCamera.offset.z - shift.z)
      cameraNode.removeAllAnimations()
      followingShipment = false
      panOrigin = mapCamera.focus
      explored = true
      onExplore?()
    }
    mapCamera.pan(g.translation(in: self), from: panOrigin)
    updateCamera(duration: 0)
    if g.state == .ended && !UIAccessibility.isReduceMotionEnabled {
      let v = g.velocity(in: self)
      let travel = CGPoint(x: min(180, max(-180, v.x * 0.12)), y: min(180, max(-180, v.y * 0.12)))
      mapCamera.pan(travel, from: mapCamera.focus)
      updateCamera(duration: 0.5)
    }
  }
  @objc private func zoom(_ g: UIPinchGestureRecognizer) {
    if g.state == .began {
      followingShipment = false
      pinchScale = mapCamera.scale
      explored = true
      onExplore?()
    }
    mapCamera.zoom(pinchScale / Double(g.scale))
    updateCamera(duration: 0)
  }
}
