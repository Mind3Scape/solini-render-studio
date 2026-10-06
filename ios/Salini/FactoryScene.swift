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
  private var orderTags: [InsideOrderID: UIButton] = [:]
  private var orderMarkers: [InsideOrderID: SCNNode] = [:]
  private var stationTags: [(FactoryZone, String, SCNVector3, UIButton)] = []
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
  private var roofs: [FactoryZone: SCNNode] = [:]
  private var outlines: [FactoryZone: SCNNode] = [:]
  private var tags: [FactoryZone: UIButton] = [:]
  private var clock: CADisplayLink?
  private let clockTarget = SceneClock()
  private(set) var mapCamera = CampusCamera()
  private var panOrigin = SCNVector3Zero
  private var pinchScale: Double = 0
  private var lastViewport = CGSize.zero
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
    backgroundColor = UIColor(hex: 0xEDF0F2)
    world.background.contents = UIColor(hex: 0xEDF0F2)
    world.lightingEnvironment.contents = UIColor.white
    world.lightingEnvironment.intensity = 0.4
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
    ambient.light?.intensity = 380
    ambient.light?.color = UIColor(hex: 0xE5EAF0)
    world.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 720
    sun.light?.castsShadow = true
    sun.light?.shadowMode = .forward
    sun.light?.shadowBias = 0.6
    sun.light?.shadowColor = UIColor(hex: 0x344851, alpha: 0.2)
    sun.light?.shadowRadius = 4
    sun.light?.shadowSampleCount = 8
    sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.light?.orthographicScale = 150
    sun.eulerAngles = SCNVector3(-0.95, -0.65, 0)
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
    if bounds.width > 0, bounds.size != lastViewport {
      lastViewport = bounds.size
      mapCamera.viewport = bounds.size
      if let activeZone { mapCamera.frame(activeZone) } else if !explored { mapCamera.overview() }
      updateCamera(duration: 0)
    }
  }
  deinit { clock?.invalidate() }
  private func material(_ color: UIColor, rough: CGFloat = 0.72, glow: Bool = false) -> SCNMaterial
  {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .physicallyBased
    m.roughness.contents = rough
    m.metalness.contents = 0.05
    if glow {
      m.emission.contents = color
      m.emission.intensity = 0.7
    }
    return m
  }
  @discardableResult private func box(
    _ p: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: Float, _ y: Float, _ z: Float,
    _ color: UIColor, r: CGFloat = 0.035
  ) -> SCNNode {
    let g = SCNBox(width: w, height: h, length: d, chamferRadius: r)
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    p.addChildNode(n)
    return n
  }
  @discardableResult private func cylinder(
    _ p: SCNNode, r: CGFloat, h: CGFloat, x: Float, y: Float, z: Float, color: UIColor
  ) -> SCNNode {
    let g = SCNCylinder(radius: r, height: h)
    g.radialSegmentCount = 20
    g.materials = [material(color)]
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
    let m = material(color)
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
    cylinder(n, r: 0.14, h: 0.45, x: 0, y: 0.5, z: 0, color: UIColor(hex: 0x3F6AB6))
    ball(n, r: 0.12, x: 0, y: 0.87, z: 0, color: UIColor(hex: 0xD7BAA0))
    let left = box(n, 0.095, 0.35, 0.1, -0.075, 0.19, 0, UIColor(hex: 0x313B4F))
    let right = box(n, 0.095, 0.35, 0.1, 0.075, 0.19, 0, UIColor(hex: 0x313B4F))
    let armL = box(n, 0.09, 0.34, 0.09, -0.21, 0.49, 0, UIColor(hex: 0x3F6AB6))
    let armR = box(n, 0.09, 0.34, 0.09, 0.21, 0.49, 0, UIColor(hex: 0x3F6AB6))
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
      box(p, 1.15, 0.07, 0.18, x, y + 0.12, z + Float(i) * 0.23 - 0.35, UIColor(hex: 0xB69C7E))
    }
    if filled {
      box(p, 1.06, 0.73, 0.84, x, y + 0.52, z, UIColor(hex: 0xD8C6AE), r: 0.025)
      box(p, 0.035, 0.75, 0.86, x, y + 0.52, z, UIColor(hex: 0xF7ECDD), r: 0)
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
    node.eulerAngles.x = -.pi / 2
    node.position.y = 0.03
    node.castsShadow = false
    parent.addChildNode(node)
  }
  private func vehicleTruck(moving: Bool = true) -> SCNNode {
    let n = SCNNode()
    contactShadow(n, width: 2.7, depth: 6.3)
    let ink = UIColor(hex: 0x455779)
    box(n, 1.45, 1.5, 3.6, 0, 1.05, -0.6, UIColor(hex: 0xFDFDFE), r: 0.09)
    box(n, 1.42, 1.15, 1.15, 0, 0.91, 1.73, UIColor(hex: 0x7899D2), r: 0.16)
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
      UIColor(hex: 0x6581B0), renderingMode: .alwaysOriginal)
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
    let dark = UIColor(hex: 0x526079)
    box(n, 0.92, 0.54, 1.32, 0, 0.54, 0, UIColor(hex: 0xD4B476), r: 0.12)
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
  private let chalk = UIColor(hex: 0xF3F3EE)
  private let steel = UIColor(hex: 0x778C97)
  private let accent = UIColor(hex: 0x597B87)
  private func buildCampus() {
    let root = world.rootNode
    let ground = box(root, 440, 0.1, 440, 0, -1.2, 0, UIColor(hex: 0xEDF0F2), r: 0)
    ground.geometry?.firstMaterial?.lightingModel = .constant
    box(root, 146, 0.8, 108, 5, -0.7, 0, UIColor(hex: 0xD5DCDA), r: 1.8)
    box(root, 143, 0.14, 105, 5, -0.24, 0, UIColor(hex: 0xCDD8D0), r: 1)
    // A ring road and real circulation gaps keep the buildings from reading as tiles.
    road(x: 5, z: -45, w: 136, d: 6)
    road(x: 5, z: 47, w: 136, d: 7)
    road(x: -60, z: 0, w: 6, d: 96)
    road(x: 72, z: 0, w: 6, d: 96)
    road(x: -27, z: 0, w: 6, d: 90)
    road(x: 42, z: 0, w: 6, d: 90)
    road(x: 3, z: -4, w: 76, d: 6)
    for x in stride(from: -55, through: 65, by: 7) {
      for z: Float in [-45, 47] { box(root, 2.4, 0.018, 0.12, Float(x), 0.04, z, chalk, r: 0) }
    }
    for z in stride(from: -39, through: 40, by: 7) {
      for x: Float in [-60, 42, 72] { box(root, 0.12, 0.018, 2.4, x, 0.04, Float(z), chalk, r: 0) }
    }
    for zone in FactoryZone.allCases {
      let n = SCNNode()
      n.name = "zone-\(zone.rawValue)"
      n.position = zone.position
      root.addChildNode(n)
      buildBuilding(zone, node: n)
      populate(zone, node: n)
      addProcessDetail(zone, node: n)
      let tag = UIButton(type: .system)
      var c = UIButton.Configuration.glass()
      c.title = zone.shortTitle
      c.baseForegroundColor = Palette.ink
      c.cornerStyle = .capsule
      c.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 11, weight: .semibold)
        return a
      }
      tag.configuration = c
      tag.accessibilityIdentifier = "map.zone.\(zone.rawValue)"
      tag.addAction(UIAction { [weak self] _ in self?.onSelect?(zone) }, for: .touchUpInside)
      addSubview(tag)
      tags[zone] = tag
    }
    // Entrance plaza, parking, perimeter planting and utilities establish human scale.
    for x: Float in [-51, -45, -39, -33] {
      box(root, 0.1, 0.03, 7, x, 0.1, 43, chalk, r: 0)
      if x != -33 { car(root, x: x + 2.6, z: 43) }
    }
    for z in stride(from: -40, through: 44, by: 12) {
      tree(root, x: -65, z: Float(z))
      tree(root, x: 77, z: Float(z))
    }
    for x in stride(from: -53, through: 64, by: 12) {
      tree(root, x: Float(x), z: -50)
      tree(root, x: Float(x), z: 53)
    }
    for z: Float in [-8, 0, 8] { tree(root, x: -47, z: z) }
    for x: Float in [-18, -9, 0] { tree(root, x: x, z: 38) }
    for z: Float in [-33, 1, 35] {
      for x: Float in [-56, 38, 68] {
        cylinder(root, r: 0.09, h: 6, x: x, y: 3, z: z, color: steel)
        box(root, 1.2, 0.12, 0.5, x + 0.45, 6, z, chalk)
      }
    }
    // Gatehouse and an entrance barrier, not just trucks circling a room.
    box(root, 4, 3, 4, -59, 1.5, 51, chalk)
    box(root, 3, 1.2, 0.1, -59, 2, 53.03, accent)
    box(root, 0.25, 1.7, 0.3, -55, 0.85, 47, steel)
    _ = box(root, 5.5, 0.15, 0.2, -52.5, 1.7, 47, chalk)
    let lift = forklift()
    lift.scale = SCNVector3(1.6, 1.6, 1.6)
    lift.name = "zone-7"
    root.addChildNode(lift)
    lift.position = SCNVector3(42, 0.1, 9)
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
  private func road(x: Float, z: Float, w: CGFloat, d: CGFloat) {
    box(world.rootNode, w + 0.8, 0.12, d + 0.8, x, -0.08, z, chalk, r: 0.15)
    box(world.rootNode, w, 0.05, d, x, 0, z, UIColor(hex: 0xB7C2C9), r: 0.1)
  }
  private func tree(_ p: SCNNode, x: Float, z: Float) {
    cylinder(p, r: 0.15, h: 2.3, x: x, y: 1.05, z: z, color: UIColor(hex: 0xA69E8F))
    let crown = ball(p, r: 1.2, x: x, y: 3.1, z: z, color: UIColor(hex: 0x98ADA1))
    crown.scale.y = 1.5
    ball(p, r: 0.8, x: x + 0.5, y: 3.9, z: z, color: UIColor(hex: 0xACC0AE))
  }
  private func car(_ p: SCNNode, x: Float, z: Float) {
    box(p, 2, 0.75, 4.1, x, 0.6, z, UIColor(hex: 0xE5E8E5), r: 0.4)
    box(p, 1.65, 0.65, 2, x, 1.1, z - 0.1, UIColor(hex: 0x526C7A), r: 0.25)
    for side: Float in [-1, 1] {
      for end: Float in [-1.3, 1.3] {
        let w = cylinder(
          p, r: 0.35, h: 0.22, x: x + side, y: 0.4, z: z + end, color: UIColor(hex: 0x3C4850))
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
    box(n, w + 1.2, 0.24, d + 1.2, 0, 0.12, 0, chalk, r: 0.2)
    box(n, w, 0.08, d, 0, 0.28, 0, UIColor(hex: 0xDEE4E3), r: 0)
    let tint = box(n, w - 0.4, 0.025, d - 0.4, 0, 0.335, 0, UIColor(hex: 0x799BA8), r: 0)
    tint.opacity = 0
    loadFloors[zone] = tint
    let outline = SCNNode()
    n.addChildNode(outline)
    outline.opacity = 0
    for side: Float in [-1, 1] {
      box(outline, 0.22, 0.07, d + 1.5, side * (x + 0.65), 0.3, 0, UIColor(hex: 0x4C839C), r: 0)
      box(outline, w + 1.5, 0.07, 0.22, 0, 0.3, side * (z + 0.65), UIColor(hex: 0x4C839C), r: 0)
    }
    outlines[zone] = outline
    guard h > 0 else { return }
    // Back and west walls stay as an architectural section when the roof opens.
    box(n, w, CGFloat(h), 0.3, 0, h / 2 + 0.3, -z, chalk, r: 0)
    box(n, 0.3, CGFloat(h), d, -x, h / 2 + 0.3, 0, UIColor(hex: 0xD6DFDF), r: 0)
    for columnX in stride(from: -x + 1, through: x - 0.5, by: 5) {
      box(n, 0.22, CGFloat(h), 0.4, columnX, h / 2, -z + 0.3, steel, r: 0)
      box(n, 4.2, 1.25, 0.08, columnX + 2.1, h - 1.1, -z + 0.2, UIColor(hex: 0xA7BDC3), r: 0)
    }
    let roof = SCNNode()
    n.addChildNode(roof)
    roofs[zone] = roof
    // Open front third is visible even in the campus overview.
    box(roof, w + 0.6, 0.35, d * 0.64, 0, h + 0.4, -Float(d * 0.18), chalk, r: 0.08)
    for rib in stride(from: -x, through: x, by: 1.5) {
      box(
        roof, 0.055, 0.045, d * 0.64, rib, h + 0.6, -Float(d * 0.18), UIColor(hex: 0xBFCBCF), r: 0)
    }
    for skylightX in stride(from: -x + 4, through: x - 3, by: 7) {
      box(
        roof, 2.2, 0.22, d * 0.3, skylightX, h + 0.65, -Float(d * 0.16), UIColor(hex: 0x9FB5BE),
        r: 0.08)
    }
    box(n, w + 0.5, 0.5, 0.4, 0, h + 0.1, z, chalk, r: 0)
    for side: Float in [-1, 1] { box(n, 0.25, CGFloat(h), 0.25, side * x, h / 2, z, steel, r: 0) }
    for ventX: Float in [-x + 2.2, x - 2.2] {
      box(roof, 1.7, 0.85, 1.7, ventX, h + 0.95, -z + 2, UIColor(hex: 0xBDCACF))
      cylinder(roof, r: 0.5, h: 0.1, x: ventX, y: h + 1.42, z: -z + 2, color: steel)
    }
    // Dark plinth, service doors and a consistent facade module give the sheds real scale.
    box(n, w, 0.55, 0.34, 0, 0.56, -z - 0.04, steel, r: 0)
    for pier in stride(from: -x + 0.2, through: x - 0.2, by: 4.8) {
      box(n, 0.22, CGFloat(h), 0.24, pier, h / 2 + 0.3, -z - 0.24, UIColor(hex: 0xCBD5D7), r: 0)
    }
    if zone == .finishing {
      box(roof, w - 3, 0.75, 0.85, 0, h + 1.3, -4, steel, r: 0.18)
      for dx: Float in [-7, 0, 7] {
        cylinder(roof, r: 0.35, h: 1.2, x: dx, y: h + 0.8, z: -4, color: steel)
      }
    }
    if zone == .office {
      // Two storeys, a glazed front, reception and a planted entrance terrace.
      box(roof, w - 0.4, 0.23, d - 0.4, 0, 4.1, 0, chalk)
      for floor: Float in [1.8, 5.8] {
        for cx in stride(from: -x + 1.5, through: x - 1, by: 3) {
          box(roof, 2.65, 3.15, 0.12, cx, floor, z, UIColor(hex: 0x8EA9B4), r: 0)
          box(roof, 0.12, 3.8, 0.3, cx - 1.4, floor, z + 0.1, chalk, r: 0)
        }
      }
      brandSign(roof, position: SCNVector3(0, 7.1, z + 0.22), width: 7)
      box(n, w + 2, 0.2, 3, 0, 0.18, z + 1.5, UIColor(hex: 0xC8D2D0))
    } else {
      text3D(zone.code, n, position: SCNVector3(-x + 1, h - 1.6, z + 0.24), size: 1.1, color: steel)
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
    box(p, 4.2, 0.18, 2.7, x, 1.3, z, UIColor(hex: 0xADBCC1))
    for dx: Float in [-1.8, 1.8] { box(p, 0.2, 1.0, 2.3, x + dx, 0.75, z, steel) }
    product(p, kind: kind, x: x, y: 1.43, z: z)
  }
  private func product(_ p: SCNNode, kind: Int, x: Float, y: Float, z: Float) {
    switch kind % 5 {
    case 0: tub(p, x: x, y: y, z: z, scale: 1.2)
    case 1:
      // Basin proportions, with a visibly hollow bowl.
      let bowl = SCNNode()
      bowl.position = SCNVector3(x, y, z)
      bowl.scale = SCNVector3(0.72, 0.6, 1.1)
      p.addChildNode(bowl)
      tub(bowl, x: 0, y: 0, z: 0)
      let bowl2 = bowl.clone()
      bowl2.position.x += 1.3
      p.addChildNode(bowl2)
    case 2:
      box(p, 2.9, 0.13, 2.1, x, y + 0.07, z, .white, r: 0.12)
      box(p, 2.5, 0.035, 1.75, x, y + 0.145, z, UIColor(hex: 0xE0E7E7), r: 0.07)
      cylinder(p, r: 0.09, h: 0.025, x: x + 1, y: y + 0.18, z: z + 0.65, color: steel)
    case 3:
      box(p, 2.8, 1.15, 1.3, x, y + 0.6, z, UIColor(hex: 0xAD9D88), r: 0.06)
      box(p, 2.9, 0.13, 1.45, x, y + 1.25, z, chalk)
      for dx: Float in [-0.7, 0.7] { box(p, 1.28, 0.035, 0.03, x + dx, y + 0.8, z + 0.665, steel) }
      let bowl = SCNNode()
      bowl.position = SCNVector3(x, y + 1.32, z)
      bowl.scale = SCNVector3(0.68, 0.45, 0.7)
      p.addChildNode(bowl)
      tub(bowl, x: 0, y: 0, z: 0)
    default:
      box(p, 1.9, 2.8, 0.15, x, y + 1.4, z, chalk, r: 0.18)
      box(p, 1.7, 2.6, 0.04, x, y + 1.4, z + 0.1, UIColor(hex: 0xAAC2CC), r: 0.14)
      box(p, 2.4, 0.16, 1.3, x, y, z, steel)
    }
  }
  private func populate(_ zone: FactoryZone, node n: SCNNode) {
    switch zone {
    case .office:
      for x: Float in [-7, -1, 5] {
        for z: Float in [-6, 1, 6] {
          box(n, 3.4, 0.16, 1.8, x, 1.3, z, chalk)
          box(n, 1, 0.65, 0.12, x, 1.7, z - 0.3, steel)
          box(n, 2.8, 1, 0.25, x, 0.8, z, UIColor(hex: 0xB4BEB8))
        }
      }
      worker(n, x: 2, z: 5, walking: true)
      box(n, 4.4, 1.3, 1.4, -5, 0.9, 8, UIColor(hex: 0xAE9F89))
    case .materials:
      for x: Float in [-6, 0, 6] {
        cylinder(n, r: 1.8, h: 4.5, x: x, y: 2.5, z: -5, color: UIColor(hex: 0xC0CBCB))
        cylinder(n, r: 1.9, h: 0.15, x: x, y: 4.8, z: -5, color: steel)
        box(n, 0.18, 2, 0.18, x, 1.4, -2.7, steel)
        for z: Float in [2, 6] { pallet(n, x: x, z: z, y: 0.4) }
      }
      worker(n, x: 3, z: 5)
    case .casting, .finishing:
      for (row, z) in [Float(-11), -6, 1, 6, 12].enumerated() {
        for (col, x) in (zone == .casting ? [Float(-12), -6, 0, 6, 12] : [Float(-8), 0, 8])
          .enumerated()
        {
          bench(n, x: x, z: z, kind: (row + col) % 3)
        }
      }
      for x: Float in [-10, 10] { box(n, 0.25, 5.4, 0.25, x, 3, -1, steel) }
      box(n, 20.4, 0.35, 0.4, 0, 5.7, -1, accent)
      let head = SCNNode()
      head.position = SCNVector3(-7, 5.2, -1)
      n.addChildNode(head)
      box(head, 2, 0.7, 1.3, 0, 0, 0, accent)
      cylinder(head, r: 0.2, h: 2.8, x: 0, y: -1.5, z: 0, color: steel)
      let move = SCNAction.moveBy(x: 14, y: 0, z: 0, duration: 8)
      move.timingMode = .easeInEaseOut
      head.runAction(
        .repeatForever(.sequence([move, .wait(duration: 2), move.reversed(), .wait(duration: 2)])),
        forKey: "motion")
      if zone == .finishing {
        for x: Float in [-7, 0, 7] {
          box(n, 3.8, 2.6, 0.2, x, 2.2, -11, UIColor(hex: 0xB4C5CE))
          cylinder(n, r: 0.3, h: 3, x: x, y: 4.5, z: -11, color: steel)
        }
      }
      for x: Float in [-4, 4] { worker(n, x: x, z: 7, walking: true) }
    case .assembly:
      for (row, z) in [Float(-9), -2, 7].enumerated() {
        for (col, x) in [Float(-9), -3, 4, 9].enumerated() {
          product(n, kind: 3 + ((row + col) % 2), x: x, y: 0.4, z: z)
        }
      }
      for x: Float in [-9, -3, 4] { box(n, 4, 0.25, 2, x, 1.3, 12, chalk) }
      worker(n, x: 1, z: 7, walking: true)
      worker(n, x: -6, z: 10)
    case .quality:
      for (index, x) in [Float(-7), 0, 7].enumerated() {
        bench(n, x: x, z: 0, kind: index)
        for side: Float in [-2, 2] { box(n, 0.1, 3, 0.1, x + side, 2, -1.4, steel) }
        box(n, 4.2, 0.12, 0.1, x, 3.5, -1.4, steel)
        let scan = box(n, 3.8, 0.02, 0.045, x, 2, -1.2, UIColor(hex: 0x739BB1))
        let sweep = SCNAction.moveBy(x: 0, y: 0, z: 2.4, duration: 3)
        scan.runAction(.repeatForever(.sequence([sweep, sweep.reversed()])), forKey: "motion")
      }
      worker(n, x: 3, z: 4)
      worker(n, x: -4, z: 4)
    case .packing:
      for z: Float in [-4, 3] {
        box(n, 17, 1, 3, 0, 0.9, z, steel)
        for x in stride(from: -8, through: 8, by: 0.7) {
          let roller = cylinder(
            n, r: 0.12, h: 2.8, x: Float(x), y: 1.5, z: z, color: UIColor(hex: 0xDCE3E3))
          roller.eulerAngles.x = .pi / 2
        }
        for x: Float in [-5, 0, 5] {
          let pack = SCNNode()
          n.addChildNode(pack)
          pallet(pack, x: 0, z: 0, y: 1.6)
          pack.position = SCNVector3(x, 0, z)
          pack.runAction(
            .repeatForever(
              .sequence([
                .moveBy(x: 3, y: 0, z: 0, duration: 9), .fadeOut(duration: 0.3),
                .moveBy(x: -3, y: 0, z: 0, duration: 0), .fadeIn(duration: 0.3),
              ])), forKey: "motion")
        }
      }
      worker(n, x: 2, z: 6, walking: true)
    case .warehouse:
      for z: Float in [-18, -9, 0, 9, 18] {
        for x: Float in [-7, -2, 5] {
          for y: Float in [0.4, 2.4, 4.4] {
            for dx: Float in [-0.8, 0.8] { pallet(n, x: x + dx, z: z, y: y) }
            box(n, 3.8, 0.14, 2, x, y, z, accent)
          }
          for side: Float in [-1.9, 1.9] { box(n, 0.12, 6.6, 0.14, x + side, 3.6, z + 1, steel) }
        }
      }
      worker(n, x: 8, z: 15, walking: true)
    case .dispatch:
      for (i, x) in [Float(-7), 0, 7].enumerated() {
        box(n, 5.6, 0.04, 16, x, 0.35, 0, UIColor(hex: 0xB5C2C5), r: 0.06)
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
  private func buildFlow() {
    let points = [
      SCNVector3(-43, 0.45, 38), SCNVector3(-27, 0.45, 38), SCNVector3(-27, 0.45, -4),
      SCNVector3(-7, 0.45, -4), SCNVector3(27, 0.45, -4), SCNVector3(42, 0.45, -4),
      SCNVector3(42, 0.45, 31), SCNVector3(57, 0.45, 31),
    ]
    for i in 0..<(points.count - 1) {
      let a = points[i]
      let b = points[i + 1]
      let part = box(
        flow, CGFloat(max(0.18, abs(a.x - b.x))), 0.045, CGFloat(max(0.18, abs(a.z - b.z))),
        (a.x + b.x) / 2, 0.45, (a.z + b.z) / 2, UIColor(hex: 0x588AA5), r: 0)
      part.geometry?.firstMaterial = material(UIColor(hex: 0x588AA5), glow: true)
    }
    for i in 0..<4 {
      let particle = ball(flow, r: 0.28, x: -43, y: 0.5, z: 38, color: UIColor(hex: 0x477C9B))
      particle.runAction(
        .sequence([
          .wait(duration: Double(i) * 3),
          .repeatForever(.sequence(points.map { .move(to: $0, duration: 2) })),
        ]), forKey: "motion")
    }
  }
  private func addProcessDetail(_ zone: FactoryZone, node n: SCNNode) {
    let w = Float(zone.footprint.width / 2)
    let d = Float(zone.footprint.height / 2)
    // Pedestrian safety lanes, recessed drains and equipment bays are quiet at campus scale.
    for z in stride(from: -d + 2, through: d - 2, by: 3) {
      box(n, 0.16, 0.02, 1.4, w - 2, 0.37, z, chalk, r: 0)
    }
    if zone != .office && zone != .dispatch {
      box(n, 0.12, 0.02, CGFloat(d * 2 - 2), -w + 1, 0.37, 0, steel, r: 0)
    }
    switch zone {
    case .materials:
      for x: Float in [-6, 0, 6] {
        cylinder(n, r: 0.2, h: 1.8, x: x, y: 5.4, z: -5, color: steel)
        let pipe = cylinder(n, r: 0.18, h: 6, x: x, y: 6.25, z: -2, color: steel)
        pipe.eulerAngles.x = .pi / 2
        box(n, 2.3, 0.15, 2.5, x, 0.45, 7, steel)
        box(n, 1.8, 1.8, 1.8, x, 1.35, 7, UIColor(hex: 0xF2EEE4), r: 0.15)
        for dy: Float in [0.7, 1.3, 1.9] { box(n, 1.86, 0.035, 1.86, x, dy, 7, steel, r: 0) }
      }
      stationMarker(.materials, "M-01", SCNVector3(-6, 7, -5))
      stationMarker(.materials, "M-02", SCNVector3(6, 3.2, 7))
    case .casting:
      // An enclosed mixing station and a warm curing bay distinguish casting from finishing.
      box(n, 7, 3.2, 3.8, -11, 1.9, -12, UIColor(hex: 0xB4C3C6), r: 0.12)
      cylinder(n, r: 1.2, h: 2.5, x: -11, y: 4.6, z: -12, color: steel)
      for x: Float in [5, 11] {
        box(n, 4.8, 2.9, 4, x, 1.9, -12, chalk)
        box(n, 4.1, 2.25, 0.04, x, 1.7, -9.98, UIColor(hex: 0xB8AE97))
      }
      stationMarker(.casting, "C-01", SCNVector3(-10, 3, 3))
      stationMarker(.casting, "C-04", SCNVector3(8, 3, 3))
      stationMarker(.casting, "C-07", SCNVector3(8, 4.5, -12))
    case .finishing:
      for x: Float in [-8, 0, 8] {
        box(n, 4.8, 3.3, 0.14, x, 2.4, -4, UIColor(hex: 0xB4C4C7))
        let duct = cylinder(n, r: 0.32, h: 4, x: x, y: 5.5, z: -4, color: steel)
        duct.opacity = 0.9
        for side: Float in [-2.4, 2.4] {
          box(n, 0.1, 3.3, 3.4, x + side, 2.4, -2.4, UIColor(hex: 0xD7E0E0))
        }
      }
      reserveCover = box(n, 4.4, 0.65, 2.8, 8, 1.7, 6, UIColor(hex: 0xCDD2D3), r: 0.2)
      reserveIndicator = box(n, 0.08, 0.22, 2.4, 10.3, 1.2, 6, InsideStyle.amber, r: 0.04)
      stationMarker(.finishing, "F-01", SCNVector3(-8, 3, 1))
      stationMarker(.finishing, "F-02", SCNVector3(0, 3, -8))
      stationMarker(.finishing, "F-04", SCNVector3(8, 3, 6))
      text3D("F–04", n, position: SCNVector3(6.5, 0.42, 9), size: 0.65, color: steel)
    case .quality:
      box(n, 6, 0.16, 3.4, 0, 4.5, 0, chalk)
      qualityIndicator = box(n, 5.6, 0.045, 0.18, 0, 4.38, 1.5, InsideStyle.amber, r: 0)
      for z: Float in [-4, 4] {
        box(n, 4.7, 0.035, 0.11, -7, 0.41, z, UIColor(hex: 0xC5B081), r: 0)
      }
      stationMarker(.quality, "Q-01", SCNVector3(-7, 3.5, 1))
      stationMarker(.quality, "Q-02", SCNVector3(3, 4.9, 1))
    case .assembly:
      for x: Float in [-9, -3, 4] { pallet(n, x: x, z: -12, y: 0.4) }
      stationMarker(.assembly, "A-01", SCNVector3(-7, 3, 1))
      stationMarker(.assembly, "A-02", SCNVector3(8, 4, 7))
    case .warehouse:
      for (i, z) in [Float(-18), -9, 0, 9, 18].enumerated() {
        text3D("B–0\(i + 1)", n, position: SCNVector3(-7, 6.2, z + 1.15), size: 0.55, color: steel)
      }
      stationMarker(.warehouse, "W-A", SCNVector3(-3, 7, -9))
      stationMarker(.warehouse, "W-B", SCNVector3(6, 7, 9))
    case .packing:
      stationMarker(.packing, "P-01", SCNVector3(-5, 4, -4))
      stationMarker(.packing, "P-02", SCNVector3(5, 4, 3))
    case .dispatch:
      for x: Float in [-7, 0, 7] {
        for side: Float in [-2.3, 2.3] {
          cylinder(n, r: 0.2, h: 0.9, x: x + side, y: 0.75, z: -5, color: steel)
        }
        box(n, 5.8, 0.3, 2.1, x, 3.6, -6.7, chalk)
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
    let button = UIButton(type: .system)
    var c = UIButton.Configuration.glass()
    c.title = code
    c.baseForegroundColor = InsideStyle.blue
    c.cornerStyle = .capsule
    c.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 12, bottom: 13, trailing: 12)
    c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var a = $0
      a.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
      return a
    }
    button.configuration = c
    button.accessibilityLabel = "Пост \(code), \(zone.title)"
    button.addAction(
      UIAction { [weak self] _ in self?.onStationSelect?(zone, code) }, for: .touchUpInside)
    addSubview(button)
    stationTags.append((zone, code, position, button))
  }
  private func addSiteDetail() {
    let root = world.rootNode
    // Crossings belong to real circulation gaps, not arbitrary decoration.
    for x: Float in [-27, 42] {
      for offset in stride(from: -2.2, through: 2.2, by: 0.8) {
        box(root, 0.42, 0.025, 4, x + Float(offset), 0.08, -4, chalk, r: 0)
      }
    }
    for z in stride(from: -46, through: 46, by: 5.5) {
      cylinder(root, r: 0.07, h: 1.6, x: 79, y: 0.6, z: Float(z), color: steel)
    }
    for z: Float in [-1, 0.7] { box(root, 0.06, 0.06, 99, 79, z + 0.8, 0, steel, r: 0) }
    box(root, 5, 2.7, 4, 75.5, 1.3, -48, chalk)
    box(root, 4.1, 0.9, 0.08, 75.5, 1.8, -45.98, accent)
    let gatePivot = SCNNode()
    gatePivot.position = SCNVector3(75, 1.5, -44)
    root.addChildNode(gatePivot)
    box(gatePivot, 5.8, 0.16, 0.2, -2.9, 0, 0, chalk)
    freightGate = gatePivot
    text3D("SALINI", root, position: SCNVector3(-49, 0.08, 51), size: 1.25, color: steel)
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
      let tag = UIButton(type: .system)
      var c = UIButton.Configuration.glass()
      c.title = order.product
      c.subtitle = order.rawValue
      c.cornerStyle = .capsule
      c.baseForegroundColor = Palette.ink
      c.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 11, weight: .semibold)
        return a
      }
      c.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        a.foregroundColor = Palette.muted
        return a
      }
      tag.configuration = c
      tag.accessibilityLabel = "Заказ \(order.rawValue), \(order.product)"
      tag.addAction(UIAction { [weak self] _ in self?.onOrderSelect?(order) }, for: .touchUpInside)
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
      loadFloors[zone]?.opacity = lens == .load ? 0.5 : 0
      loadFloors[zone]?.geometry?.firstMaterial?.diffuse.contents = InsideStyle.loadColor(load)
      tags[zone]?.configuration?.title =
        lens == .load ? "\(zone.shortTitle) · \(load)%" : zone.shortTitle
      tags[zone]?.configuration?.baseForegroundColor =
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
      orderTags[order]?.configuration?.baseForegroundColor =
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
      let move = SCNAction.sequence([
        .move(to: SCNVector3(42, 0.1, 31), duration: 2),
        .rotateTo(x: 0, y: .pi / 2, z: 0, duration: 0.3),
        .move(to: SCNVector3(55, 0.1, 26), duration: 1.7),
      ])
      move.speed = simulationSpeed
      transfer.runAction(move, forKey: "marea-transfer")
      transfer.isPaused = simulationPaused || UIAccessibility.isReduceMotionEnabled
      if UIAccessibility.isReduceMotionEnabled { transfer.position = SCNVector3(55, 0.1, 26) }
    }
    placeLabels()
  }
  func showOrderRoute(_ zones: [FactoryZone]) {
    flow.childNodes.forEach { $0.removeFromParentNode() }
    // Each stage connects through a service aisle. This is a process diagram on the ground,
    // not a navigation route for vehicles through building walls.
    var points: [SCNVector3] = []
    for zone in zones {
      var p = zone.position
      p.y = 0.55
      if let previous = points.last {
        points.append(SCNVector3(p.x, 0.55, previous.z))
      }
      points.append(p)
    }
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
      p.y = zone.buildingHeight + 3
      let point = projectPoint(p)
      b.sizeToFit()
      b.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
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
      if !tag.isHidden { occupied.append(frame) }
    }
    for (zone, _, local, tag) in stationTags {
      var p = zone.position
      p.x += local.x
      p.z += local.z
      p.y = local.y
      let point = projectPoint(p)
      tag.sizeToFit()
      tag.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
      let frame = tag.frame.insetBy(dx: -3, dy: -3)
      tag.isHidden =
        activeZone != zone || !labelsVisible || lens == .orders || trackedOrder != nil
        || mapCamera.scale > 65 || !bounds.insetBy(dx: 12, dy: 45).contains(frame)
        || occupied.contains(where: { $0.intersects(frame) })
      if !tag.isHidden { occupied.append(frame) }
    }
  }
  private func updateCamera(duration: Double) {
    let focus = mapCamera.focus
    let offset = CampusCamera.offset
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    cameraNode.position = SCNVector3(focus.x + offset.x, focus.y + offset.y, focus.z + offset.z)
    cameraNode.look(at: focus)
    cameraNode.camera?.orthographicScale = mapCamera.scale
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
    let x = Float((number - 2) * 7)
    let drive = SCNAction.sequence([
      .move(to: SCNVector3(x, 0.4, 15), duration: 3),
      .rotateTo(x: 0, y: .pi / 2, z: 0, duration: 0.7),
      .move(to: SCNVector3(15, 0.4, 15), duration: 4),
      .rotateTo(x: 0, y: .pi, z: 0, duration: 0.7),
      .move(to: SCNVector3(15, 0.4, -77), duration: 18),
      .fadeOut(duration: 0.5),
    ])
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
      mapCamera.focus = SCNVector3(
        presented.x - CampusCamera.offset.x, 0, presented.z - CampusCamera.offset.z)
      mapCamera.scale = cameraNode.presentation.camera?.orthographicScale ?? mapCamera.scale
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
