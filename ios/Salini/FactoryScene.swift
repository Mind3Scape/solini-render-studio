import SceneKit
import UIKit

enum FactoryZone: Int, CaseIterable {
  case casting, finishing, quality, packing, warehouse, dispatch
  var title: String {
    ["Литьё", "Обработка", "Контроль", "Упаковка", "Склад", "Отгрузка"][rawValue]
  }
  var icon: String {
    ["drop.fill", "sparkles", "checkmark.seal", "shippingbox", "square.stack.3d.up", "truck.box"][
      rawValue]
  }
  var code: String { ["01", "02", "03", "04", "05", "06"][rawValue] }
  var position: SCNVector3 {
    SCNVector3(Float(rawValue % 3) * 7.0 - 7.0, 0, rawValue < 3 ? -4.0 : 4.0)
  }
  var count: Int { [24, 18, 8, 12, 146, 3][rawValue] }
  var state: String {
    [
      "Формы заполняются", "Финишная поверхность", "Точность каждой детали",
      "Готовим к путешествию", "Готовая продукция", "Отправляем в салоны",
    ][rawValue]
  }
  var people: Int { [6, 8, 3, 4, 5, 2][rawValue] }
}

final class FactorySimulation {
  var tick = 0
  var paused = false
  var completed = 42
  var priority = false
  var resolved = false
  var selected: FactoryZone = .casting
  var events = ["09:41 · Aria · форма № 04 запущена"]
  func advance() {
    guard !paused else { return }
    tick += 1
    let eventsList = [
      "Greca · обработка поверхности завершена", "Opera · контроль геометрии пройден",
      "Заказ S-2048 · передан в упаковку", "Москва · машина прибыла к воротам",
      "Aria · партия готова к контролю", "Склад · принято 4 изделия",
    ]
    events.insert(
      String(format: "+%02d:%02d", tick * 5 / 60, tick * 5 % 60) + " · "
        + eventsList[(tick - 1) % eventsList.count], at: 0)
    if tick % 3 == 0 { completed += 1 }
    events = Array(events.prefix(20))
  }
  func expedite() {
    guard !priority else { return }
    priority = true
    events.insert("Сейчас · заказ S-2048 получил приоритет", at: 0)
  }
  func resolve() {
    guard !resolved else { return }
    resolved = true
    events.insert("Сейчас · назначен контроль поверхности Aria", at: 0)
  }
  var progress: Float { min(0.98, 0.38 + Float(tick % 13) * 0.045) }
}

private final class SceneClock: NSObject {
  weak var owner: FactorySceneView?
  @objc func tick() { owner?.placeLabels() }
}

final class FactorySceneView: SCNView, UIGestureRecognizerDelegate {
  private let world = SCNScene()
  private let rig = SCNNode()
  private let cameraNode = SCNNode()
  private let roof = SCNNode()
  private let flow = SCNNode()
  private let beacon = SCNNode()
  private var floors: [FactoryZone: SCNNode] = [:]
  private var zoneNodes: [FactoryZone: SCNNode] = [:]
  private var tags: [FactoryZone: UIButton] = [:]
  private var clock: CADisplayLink?
  private let clockTarget = SceneClock()
  private var focus: SCNVector3 = SCNVector3(0, 0, 0)
  private var yaw: Float = 0.56
  private var pitch: Float = 0.91
  private var scale: Double = 18.8
  private var panOrigin: (Float, Float) = (0, 0)
  private var pinchScale: Double = 0
  private var lastViewport = CGSize.zero
  private var activeZone: FactoryZone?
  var onSelect: ((FactoryZone) -> Void)?
  var onExplore: (() -> Void)?
  private(set) var chosen: FactoryZone = .casting
  private(set) var roofVisible = false
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
    backgroundColor = UIColor(hex: 0xEDF1F7)
    world.background.contents = UIColor(hex: 0xEDF1F7)
    world.lightingEnvironment.contents = UIColor.white
    world.lightingEnvironment.intensity = 0.4
    antialiasingMode = .multisampling4X
    preferredFramesPerSecond = 60
    isPlaying = true
    autoenablesDefaultLighting = false
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.usesOrthographicProjection = true
    cameraNode.camera?.orthographicScale = scale
    cameraNode.camera?.zFar = 180
    cameraNode.camera?.wantsHDR = false
    cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = 0.55
    cameraNode.camera?.screenSpaceAmbientOcclusionRadius = 0.8
    rig.addChildNode(cameraNode)
    world.rootNode.addChildNode(rig)
    pointOfView = cameraNode
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 330
    ambient.light?.color = UIColor(hex: 0xE9EFFF)
    world.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 820
    sun.light?.castsShadow = true
    sun.light?.shadowMode = .deferred
    sun.light?.shadowColor = UIColor(hex: 0x243C6A, alpha: 0.18)
    sun.light?.shadowRadius = 6
    sun.light?.shadowSampleCount = 16
    sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.light?.orthographicScale = 40
    sun.eulerAngles = SCNVector3(-0.95, -0.55, 0)
    world.rootNode.addChildNode(sun)
    buildCampus()
    updateCamera(duration: 0)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(orbit(_:))))
    addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
    gestureRecognizers?.forEach { $0.delegate = self }
    accessibilityLabel = "Интерактивное производство Salini"
    accessibilityHint = "Выберите участок, вращайте одним пальцем, меняйте масштаб двумя"
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
    if activeZone == nil, bounds.width > 0, bounds.size != lastViewport {
      lastViewport = bounds.size
      scale = max(18.8, 16.6 * Double(bounds.height / bounds.width))
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
    for (i, limb) in [left, right, armR, armL].enumerated() {
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
  private func buildCampus() {
    let root = world.rootNode
    let white = UIColor(hex: 0xF9FAFD)
    let steel = UIColor(hex: 0x9AA9BF)
    let blue = UIColor(hex: 0x557CE4)
    let ground = box(root, 110, 0.1, 110, 0, -0.66, 0, UIColor(hex: 0xEDF1F7), r: 0)
    ground.geometry?.firstMaterial?.lightingModel = .constant
    box(root, 34, 0.45, 30, 0, -0.4, 1, UIColor(hex: 0xE0E6EF), r: 0.65)
    box(root, 30, 0.10, 25, 0, -0.12, 1, UIColor(hex: 0xF5F7FB), r: 0.3)
    box(root, 32, 0.04, 4.5, 0, -0.04, 12, UIColor(hex: 0xD0DBEC), r: 0.1)
    box(root, 3.4, 0.04, 25, 14.1, -0.04, -0.3, UIColor(hex: 0xD0DBEC), r: 0.1)
    box(root, 3.4, 0.04, 25, -14.1, -0.04, -0.3, UIColor(hex: 0xD0DBEC), r: 0.1)
    box(root, 32, 0.04, 4.2, 0, -0.04, -11.8, UIColor(hex: 0xD0DBEC), r: 0.1)
    for x in stride(from: -14, through: 14, by: 2) {
      box(root, 0.8, 0.014, 0.045, Float(x), -0.013, 12.1, .white, r: 0)
    }
    for z in stride(from: -10, through: 10, by: 2) {
      box(root, 0.045, 0.014, 0.8, 14.1, -0.013, Float(z), .white, r: 0)
    }
    // Architectural shell and a clear circulation aisle around six work areas.
    box(root, 24.4, 0.32, 18.3, 0, 0.07, 0, white, r: 0.14)
    box(root, 24, 3.4, 0.18, 0, 1.8, -9, UIColor(hex: 0xD6E0EF), r: 0)
    for x in stride(from: -11, through: 11, by: 2) {
      box(root, 1.6, 1.55, 0.20, Float(x), 2.15, -8.99, UIColor(hex: 0xA8C6E2), r: 0.01)
      box(root, 0.11, 3.5, 0.32, Float(x), 1.8, -8.9, white, r: 0)
    }
    box(root, 0.16, 1.1, 17.8, -12, 0.75, 0, UIColor(hex: 0xD6E0EF), r: 0.02)
    for x: Float in [-11.6, -4, 4, 11.6] {
      box(root, 0.18, 3.8, 0.18, x, 2, -8.7, steel)
      box(root, 0.18, 1.1, 0.18, x, 0.7, 8.7, steel)
    }
    let sign = SCNNode()
    sign.position = SCNVector3(-3, 3.2, -8.78)
    root.addChildNode(sign)
    text3D("salini", sign, position: SCNVector3(0, 0, 0), size: 0.85, color: UIColor(hex: 0x496BBA))
    for z: Float in [-0.5, 0.5] {
      for x in stride(from: -11.0, through: 11.0, by: 0.9) {
        box(root, 0.45, 0.012, 0.03, Float(x), 0.24, z, UIColor(hex: 0xBDCAE1), r: 0)
      }
    }
    root.addChildNode(roof)
    roof.opacity = 0
    box(roof, 24.5, 0.27, 18.5, 0, 4.2, 0, white, r: 0.15)
    for x: Float in [-8, -3, 2, 7] {
      box(roof, 2.4, 0.08, 5, x, 4.39, -2, UIColor(hex: 0xB6C7DE), r: 0.02)
      for z: Float in [4, 6] {
        box(roof, 1.25, 0.5, 0.85, x, 4.6, z, UIColor(hex: 0xCAD4E4))
        cylinder(roof, r: 0.34, h: 0.06, x: x, y: 4.88, z: z, color: UIColor(hex: 0x73829D))
      }
    }
    for zone in FactoryZone.allCases {
      let n = SCNNode()
      n.name = "zone-\(zone.rawValue)"
      n.position = zone.position
      root.addChildNode(n)
      zoneNodes[zone] = n
      floors[zone] = box(n, 6.35, 0.05, 6.7, 0, 0.255, 0, UIColor(hex: 0xE7ECF5), r: 0.15)
      // Floor markings give each station scale without enclosing it behind walls.
      for x: Float in [-3.05, 3.05] { box(n, 0.025, 0.018, 6.35, x, 0.29, 0, .white, r: 0) }
      switch zone {
      case .casting:
        for z: Float in [-1.4, 1.3] {
          for x: Float in [-1.45, 1.45] {
            box(n, 2.35, 0.6, 1.55, x, 0.57, z, UIColor(hex: 0xAEBED9))
            box(n, 2.15, 0.06, 1.42, x, 0.9, z, white)
            tub(n, x: x, y: 0.94, z: z, scale: 0.87)
          }
        }
        for x: Float in [-2.65, 2.65] { box(n, 0.14, 3, 0.14, x, 1.77, -1.8, steel) }
        box(n, 5.5, 0.2, 0.3, 0, 3.2, -1.8, steel)
        let nozzle = SCNNode()
        nozzle.position = SCNVector3(-1.6, 2.95, -1.8)
        n.addChildNode(nozzle)
        box(nozzle, 0.7, 0.4, 0.7, 0, 0, 0, blue)
        cylinder(nozzle, r: 0.09, h: 1.2, x: 0, y: -0.7, z: 0, color: steel)
        let move = SCNAction.moveBy(x: 3.2, y: 0, z: 0, duration: 3.5)
        move.timingMode = .easeInEaseOut
        nozzle.runAction(
          .repeatForever(
            .sequence([move, .wait(duration: 1.6), move.reversed(), .wait(duration: 1.6)])),
          forKey: "motion")
        person(n, x: -0.2, z: 2.6)
      case .finishing:
        for z: Float in [-1.35, 1.4] {
          box(n, 4.8, 0.62, 1.7, 0, 0.58, z, UIColor(hex: 0xCBD6E6))
          tub(n, x: -1.2, y: 0.95, z: z, scale: 0.88)
          tub(n, x: 1.2, y: 0.95, z: z, scale: 0.88)
        }
        let arm = SCNNode()
        arm.position = SCNVector3(2.5, 0.5, -0.1)
        n.addChildNode(arm)
        cylinder(arm, r: 0.3, h: 0.9, x: 0, y: 0.4, z: 0, color: blue)
        let pivot = SCNNode()
        pivot.position = SCNVector3(0, 1, 0)
        arm.addChildNode(pivot)
        box(pivot, 1.45, 0.16, 0.2, -0.62, 0, 0, steel)
        cylinder(pivot, r: 0.18, h: 0.17, x: -1.3, y: -0.17, z: 0, color: Palette.ink)
        let sweep = SCNAction.rotateBy(x: 0, y: 1.1, z: 0, duration: 2.1)
        sweep.timingMode = .easeInEaseOut
        pivot.runAction(.repeatForever(.sequence([sweep, sweep.reversed()])), forKey: "motion")
        person(n, x: -2.4, z: 0, walking: true)
      case .quality:
        for x: Float in [-1.45, 1.45] {
          box(n, 2.3, 0.72, 2.1, x, 0.63, 0, white)
          tub(n, x: x, y: 1.02, z: 0, scale: 0.95)
          for z: Float in [-1.0, 1.0] { box(n, 0.08, 2.2, 0.08, x - 1.1, 1.4, z, steel) }
          box(n, 0.09, 0.08, 2.1, x - 1.1, 2.5, 0, steel)
          let scan = box(n, 2.12, 0.016, 0.035, x, 1.7, -0.7, UIColor(hex: 0x558EF3))
          scan.geometry?.firstMaterial = material(UIColor(hex: 0x548BFF), glow: true)
          let pass = SCNAction.moveBy(x: 0, y: 0, z: 1.4, duration: 2.3)
          scan.runAction(.repeatForever(.sequence([pass, pass.reversed()])), forKey: "motion")
        }
        box(n, 0.85, 0.9, 0.2, 0, 0.8, -2.3, Palette.ink)
        box(n, 0.72, 0.45, 0.015, 0, 1, -2.18, UIColor(hex: 0x78B4D6))
        person(n, x: 0, z: 2.4)
      case .packing:
        box(n, 5.2, 0.65, 1.8, 0, 0.62, 0, steel)
        for x in stride(from: -2.3, through: 2.3, by: 0.3) {
          let roller = cylinder(
            n, r: 0.08, h: 1.65, x: Float(x), y: 1, z: 0, color: UIColor(hex: 0xE2E8F1))
          roller.eulerAngles.x = .pi / 2
        }
        let pack = SCNNode()
        n.addChildNode(pack)
        pallet(pack, x: 0, z: 0, y: 1.03)
        pack.position.x = -1.65
        pack.runAction(
          .repeatForever(
            .sequence([
              .moveBy(x: 3.3, y: 0, z: 0, duration: 7), .fadeOut(duration: 0.2),
              .moveBy(x: -3.3, y: 0, z: 0, duration: 0), .fadeIn(duration: 0.2),
            ])), forKey: "motion")
        for x: Float in [-2, 0, 2] { pallet(n, x: x, z: 2.3, y: 0.27) }
        person(n, x: 1, z: -2.2, walking: true)
      case .warehouse:
        for z: Float in [-1.65, 1.15] {
          for x: Float in [-2.0, 0, 2.0] {
            for y: Float in [0.25, 1.45, 2.65] { pallet(n, x: x, z: z, y: y) }
            for side: Float in [-0.72, 0.72] {
              box(n, 0.08, 3.75, 0.08, x + side, 2.15, z - 0.6, blue)
              box(n, 0.08, 3.75, 0.08, x + side, 2.15, z + 0.6, blue)
            }
          }
          for y: Float in [1.43, 2.63, 3.81] { box(n, 5.7, 0.10, 1.4, 0, y, z, steel) }
        }
      case .dispatch:
        for x: Float in [-2, 0, 2] {
          for z: Float in [-1.6, 0.3] { pallet(n, x: x, z: z, y: 0.27) }
        }
        for x: Float in [-2.5, 2.5] {
          box(n, 0.04, 0.02, 6.1, x, 0.3, 0, UIColor(hex: 0xE0C990), r: 0)
        }
        box(n, 5.2, 0.07, 1.1, 0, 0.31, 2.6, UIColor(hex: 0xB5CBEA))
        person(n, x: -2.4, z: 1.2, walking: true)
      }
      let tag = UIButton(type: .system)
      var c = UIButton.Configuration.glass()
      c.title = zone.title
      c.baseForegroundColor = Palette.ink
      c.cornerStyle = .capsule
      c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 10, weight: .semibold)
        return a
      }
      tag.configuration = c
      tag.accessibilityIdentifier = "map.zone.\(zone.rawValue)"
      tag.addAction(UIAction { [weak self] _ in self?.onSelect?(zone) }, for: .touchUpInside)
      addSubview(tag)
      tags[zone] = tag
    }
    // Logistics and landscape establish context beyond the factory footprint.
    for x: Float in [-15.2, 15.6] {
      for z: Float in [-11, -5, 1, 7] {
        cylinder(root, r: 0.45, h: 0.18, x: x, y: -0.01, z: z, color: UIColor(hex: 0xD6E2D9))
        cylinder(root, r: 0.07, h: 1.05, x: x, y: 0.52, z: z, color: UIColor(hex: 0xAFAB9F))
        ball(root, r: 0.56, x: x, y: 1.25, z: z, color: UIColor(hex: 0x9EBEAA))
        ball(root, r: 0.37, x: x + 0.18, y: 1.64, z: z, color: UIColor(hex: 0xB6D0BC))
      }
    }
    for x: Float in [-10, -6, -2, 2] { box(root, 2.8, 0.016, 0.04, x, 0.05, 9.8, white, r: 0) }
    let truck = vehicleTruck()
    truck.name = "zone-5"
    root.addChildNode(truck)
    travel(
      truck,
      points: [
        SCNVector3(-14.1, 0.09, 12), SCNVector3(13.8, 0.09, 12), SCNVector3(13.8, 0.09, -11.8),
        SCNVector3(-14.1, 0.09, -11.8),
      ], speed: 1.05)
    let parked = vehicleTruck(moving: false)
    parked.name = "zone-5"
    parked.position = SCNVector3(8.5, 0.1, 10.5)
    parked.eulerAngles.y = .pi / 2
    root.addChildNode(parked)
    let lift = forklift()
    lift.name = "zone-4"
    root.addChildNode(lift)
    travel(
      lift,
      points: [
        SCNVector3(-10, 0.29, 0), SCNVector3(10.1, 0.29, 0), SCNVector3(10.1, 0.29, 7.7),
        SCNVector3(10.1, 0.29, 0),
      ], speed: 0.9)
    buildFlow()
    root.addChildNode(flow)
    flow.opacity = 0
    let halo = SCNTorus(ringRadius: 0.3, pipeRadius: 0.035)
    halo.materials = [material(UIColor(hex: 0x538BFF), glow: true)]
    beacon.geometry = halo
    beacon.position = SCNVector3(-7, 3.8, -4)
    root.addChildNode(beacon)
    beacon.opacity = 0
    beacon.runAction(
      .repeatForever(.sequence([.scale(to: 1.65, duration: 0.9), .scale(to: 1, duration: 0.9)])),
      forKey: "motion")
  }
  private func vehicleTruck(moving: Bool = true) -> SCNNode {
    let n = SCNNode()
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
  private func buildFlow() {
    let points: [SCNVector3] = [
      SCNVector3(-7, 0.34, -4), SCNVector3(0, 0.34, -4), SCNVector3(7, 0.34, -4),
      SCNVector3(7, 0.34, 0), SCNVector3(-7, 0.34, 0), SCNVector3(-7, 0.34, 4),
      SCNVector3(0, 0.34, 4), SCNVector3(7, 0.34, 4), SCNVector3(7, 0.34, 10),
    ]
    for i in 0..<(points.count - 1) {
      let a = points[i]
      let b = points[i + 1]
      let w = CGFloat(max(0.045, abs(a.x - b.x)))
      let d = CGFloat(max(0.045, abs(a.z - b.z)))
      let segment = box(
        flow, w, 0.025, d, (a.x + b.x) / 2, 0.34, (a.z + b.z) / 2, UIColor(hex: 0x5D8AFA), r: 0)
      segment.geometry?.firstMaterial = material(UIColor(hex: 0x5D8AFA), glow: true)
    }
    for offset in 0..<5 {
      let particle = ball(flow, r: 0.075, x: 0, y: 0, z: 0, color: UIColor(hex: 0x3164E7))
      let path = points.map { SCNAction.move(to: $0, duration: 0.8) }
      particle.runAction(
        .sequence([.wait(duration: Double(offset) * 0.7), .repeatForever(.sequence(path))]),
        forKey: "motion")
    }
  }
  fileprivate func placeLabels() {
    guard bounds.width > 0, window != nil else { return }
    for (zone, b) in tags {
      var p = zone.position
      p.y = zone == .warehouse ? 4.4 : 3.15
      let point = projectPoint(p)
      b.sizeToFit()
      let size = b.bounds.size
      b.center = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
      b.isHidden =
        !labelsVisible || roofVisible || (activeZone != nil && activeZone != zone) || point.z < 0
        || point.z > 1 || b.center.x < size.width / 2 || b.center.x > bounds.width - size.width / 2
        || b.center.y < 10 || b.center.y > bounds.height - 10
    }
  }
  private func updateCamera(duration: Double) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    let distance: Float = 48
    cameraNode.position = SCNVector3(
      focus.x + sin(yaw) * cos(pitch) * distance, focus.y + sin(pitch) * distance,
      focus.z + cos(yaw) * cos(pitch) * distance)
    cameraNode.look(at: focus)
    cameraNode.camera?.orthographicScale = scale
    SCNTransaction.commit()
    defaultCameraController.target = focus
  }
  func resetCamera() {
    activeZone = nil
    focus = SCNVector3(0, 0, 1)
    yaw = 0.56
    pitch = 0.91
    scale = max(18.8, 16.6 * Double(bounds.height / max(1, bounds.width)))
    updateCamera(duration: 1.05)
    select(.casting, animated: false, highlight: false)
  }
  func select(_ zone: FactoryZone, animated: Bool = true, highlight: Bool = true) {
    chosen = zone
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated ? 0.45 : 0
    for (z, n) in floors {
      n.geometry?.firstMaterial?.diffuse.contents =
        highlight && z == zone ? UIColor(hex: 0xC4D9FC) : UIColor(hex: 0xE7ECF5)
    }
    beacon.opacity = highlight ? 1 : 0
    let p = zone.position
    beacon.position = SCNVector3(p.x, zone == .warehouse ? 4.2 : 2.8, p.z)
    SCNTransaction.commit()
  }
  func focusOn(_ zone: FactoryZone, animated: Bool = true) {
    activeZone = zone
    chosen = zone
    select(zone)
    if roofVisible { setRoof(false) }
    let p = zone.position
    focus = SCNVector3(p.x, 0.6, p.z)
    scale = 8.0
    yaw = 0.55
    pitch = 0.88
    updateCamera(duration: animated ? 1.1 : 0)
  }
  func closeUp(_ zone: FactoryZone) {
    focusOn(zone, animated: false)
    labelsVisible = false
  }
  func logistics() {
    activeZone = .dispatch
    focus = SCNVector3(7, 0.2, 9.4)
    scale = 10.5
    yaw = 0.72
    pitch = 0.75
    updateCamera(duration: 1.15)
    select(.dispatch)
  }
  func setRoof(_ visible: Bool) {
    roofVisible = visible
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.8
    roof.opacity = visible ? 1 : 0
    roof.position.y = visible ? 0 : 1.6
    SCNTransaction.commit()
  }
  func showRoute(_ visible: Bool) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.4
    flow.opacity = visible ? 1 : 0
    SCNTransaction.commit()
  }
  func setPaused(_ paused: Bool) {
    // Keep the camera responsive while transport and machinery are paused.
    world.rootNode.enumerateChildNodes { node, _ in
      if !node.actionKeys.isEmpty { node.isPaused = paused }
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
  @objc private func orbit(_ g: UIPanGestureRecognizer) {
    if g.state == .began {
      panOrigin = (yaw, pitch)
      onExplore?()
    }
    let t = g.translation(in: self)
    yaw = panOrigin.0 - Float(t.x) * 0.005
    pitch = min(1.35, max(0.45, panOrigin.1 + Float(t.y) * 0.003))
    updateCamera(duration: 0)
  }
  @objc private func zoom(_ g: UIPinchGestureRecognizer) {
    if g.state == .began {
      pinchScale = scale
      onExplore?()
    }
    scale = min(30, max(4.4, pinchScale / Double(g.scale)))
    updateCamera(duration: 0)
  }
}
