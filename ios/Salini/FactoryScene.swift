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
    SCNVector3(Float(rawValue % 3) * 5.3 - 5.3, 0, rawValue < 3 ? -3.6 : 2.1)
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

final class FactorySceneView: SCNView {
  private let world = SCNScene()
  private let cameraNode = SCNNode()
  private var floors: [FactoryZone: SCNNode] = [:]
  var onSelect: ((FactoryZone) -> Void)?
  private(set) var chosen: FactoryZone = .casting
  init() {
    super.init(frame: .zero, options: nil)
    scene = world
    backgroundColor = Palette.paper
    world.background.contents = Palette.paper
    world.lightingEnvironment.contents = UIColor.white
    world.lightingEnvironment.intensity = 0.65
    autoenablesDefaultLighting = false
    antialiasingMode = .multisampling4X
    isPlaying = true
    preferredFramesPerSecond = 30
    allowsCameraControl = true
    defaultCameraController.interactionMode = .orbitTurntable
    defaultCameraController.inertiaEnabled = true
    defaultCameraController.target = SCNVector3(0, 0, 0)
    accessibilityLabel = "Объёмная модель производства Salini"
    accessibilityHint = "Выберите участок кнопками под моделью"
    accessibilityIdentifier = "factory.scene"
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.usesOrthographicProjection = true
    cameraNode.camera?.orthographicScale = 12.6
    cameraNode.camera?.zFar = 100
    cameraNode.camera?.wantsHDR = false
    cameraNode.position = SCNVector3(18, 24, 25)
    cameraNode.look(at: SCNVector3(0, 0, 0))
    world.rootNode.addChildNode(cameraNode)
    pointOfView = cameraNode
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 650
    ambient.light?.color = UIColor(hex: 0xF1F4FA)
    world.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 1100
    sun.light?.castsShadow = true
    sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.16)
    sun.light?.shadowRadius = 5
    sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.light?.orthographicScale = 25
    sun.eulerAngles = SCNVector3(-Float.pi / 3, -Float.pi / 4, 0)
    world.rootNode.addChildNode(sun)
    build()
    select(.casting, animated: false)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
  }
  required init?(coder: NSCoder) { fatalError() }
  private func material(_ color: UIColor, rough: CGFloat = 0.75) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = color
    m.lightingModel = .physicallyBased
    m.roughness.contents = rough
    return m
  }
  @discardableResult private func box(
    _ parent: SCNNode, _ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ x: Float, _ y: Float, _ z: Float,
    _ color: UIColor, r: CGFloat = 0.05
  ) -> SCNNode {
    let g = SCNBox(width: w, height: h, length: l, chamferRadius: r)
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    parent.addChildNode(n)
    return n
  }
  private func cylinder(
    _ parent: SCNNode, r: CGFloat, h: CGFloat, x: Float, y: Float, z: Float, color: UIColor
  ) -> SCNNode {
    let g = SCNCylinder(radius: r, height: h)
    g.radialSegmentCount = 16
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    parent.addChildNode(n)
    return n
  }
  private func ball(_ parent: SCNNode, r: CGFloat, x: Float, y: Float, z: Float, color: UIColor) {
    let g = SCNSphere(radius: r)
    g.segmentCount = 16
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(x, y, z)
    parent.addChildNode(n)
  }
  private func caption(
    _ text: String, at pos: SCNVector3, parent: SCNNode, size: CGFloat = 0.22,
    color: UIColor = Palette.ink
  ) {
    let g = SCNText(string: text, extrusionDepth: 0.002)
    g.font = UIFont.systemFont(ofSize: size, weight: .semibold)
    g.flatness = 0.1
    g.materials = [material(color)]
    let n = SCNNode(geometry: g)
    let (min, max) = n.boundingBox
    n.pivot = SCNMatrix4MakeTranslation((max.x + min.x) / 2, min.y, 0)
    n.position = pos
    let c = SCNBillboardConstraint()
    c.freeAxes = .all
    n.constraints = [c]
    parent.addChildNode(n)
  }
  private func tub(_ parent: SCNNode, at p: SCNVector3, scale: Float = 1, color: UIColor = .white) {
    let rings: [(Float, Float)] = [
      (0.72, 0.10), (0.81, 0.18), (0.99, 0.70), (1, 0.77), (0.91, 0.78), (0.89, 0.68), (0.68, 0.28),
      (0.55, 0.22), (0, 0.22),
    ]
    let segments = 40
    var v: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [Int32] = []
    for (i, r) in rings.enumerated() {
      for s in 0...segments {
        let a = Float(s) / Float(segments) * 2 * Float.pi
        v.append(SCNVector3(cos(a) * r.0 * 1.05, r.1, sin(a) * r.0 * 0.56))
        let outer: Float = i < 4 ? 1 : -1
        normals.append(
          SCNVector3(cos(a) * outer, i == 3 || i == 4 || i > 6 ? 1 : 0.25, sin(a) * outer))
      }
    }
    for r in 0..<(rings.count - 1) {
      for s in 0..<segments {
        let a = Int32(r * (segments + 1) + s)
        let b = a + Int32(segments + 1)
        indices += [a, b, a + 1, a + 1, b, b + 1]
      }
    }
    let geo = SCNGeometry(
      sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: normals)],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    let m = material(color, rough: 0.28)
    m.isDoubleSided = true
    geo.materials = [m]
    let n = SCNNode(geometry: geo)
    n.position = p
    n.scale = SCNVector3(scale, scale, scale)
    parent.addChildNode(n)
  }
  private func person(_ parent: SCNNode, x: Float, z: Float, walking: Bool = false) {
    let n = SCNNode()
    n.position = SCNVector3(x, 0.2, z)
    parent.addChildNode(n)
    _ = cylinder(n, r: 0.13, h: 0.43, x: 0, y: 0.38, z: 0, color: Palette.ink)
    ball(n, r: 0.11, x: 0, y: 0.71, z: 0, color: UIColor(hex: 0xD5BFA2))
    box(n, 0.09, 0.28, 0.10, -0.07, 0.1, 0, UIColor(hex: 0x596064))
    box(n, 0.09, 0.28, 0.10, 0.07, 0.1, 0, UIColor(hex: 0x596064))
    if walking {
      let move = SCNAction.moveBy(x: 0.9, y: 0, z: 0.15, duration: 4)
      move.timingMode = .easeInEaseOut
      n.runAction(
        .repeatForever(.sequence([move, .wait(duration: 2), move.reversed(), .wait(duration: 2)])))
    }
  }
  private func pallet(_ parent: SCNNode, x: Float, z: Float, level: Float = 0, filled: Bool = true)
  {
    for i in 0..<3 {
      box(
        parent, 0.95, 0.07, 0.17, x, level + 0.1, z + Float(i) * 0.25 - 0.25, UIColor(hex: 0xBBA585)
      )
    }
    if filled {
      box(parent, 0.84, 0.6, 0.73, x, level + 0.43, z, UIColor(hex: 0xCEBC9D), r: 0.03)
      box(parent, 0.025, 0.62, 0.75, x, level + 0.43, z, UIColor(hex: 0xEEE9D9), r: 0)
      box(parent, 0.86, 0.04, 0.015, x, level + 0.58, z + 0.375, Palette.ink, r: 0)
    }
  }
  private func build() {
    let root = world.rootNode
    box(root, 19, 0.4, 16, 0, -0.25, 0, UIColor(hex: 0xFCFCF7), r: 0.4)
    box(root, 18, 0.03, 2.5, 0, -0.025, 6, UIColor(hex: 0xD4DAE3), r: 0.1)
    for i in -8...8 {
      if i % 2 == 0 { box(root, 0.65, 0.015, 0.07, Float(i), 0.003, 6, UIColor.white, r: 0) }
    }
    box(root, 18, 0.18, 0.3, 0, 0.02, 4.6, UIColor(hex: 0xF4F5ED))
    // Six cutaway workshop areas follow the production flow, not a claimed floor plan.
    for zone in FactoryZone.allCases {
      let n = SCNNode()
      n.name = "zone-\(zone.rawValue)"
      n.position = zone.position
      root.addChildNode(n)
      let floor = box(n, 4.8, 0.08, 4.8, 0, 0.06, 0, UIColor(hex: 0xE0E6EE), r: 0.16)
      floors[zone] = floor
      box(n, 4.8, 0.8, 0.12, 0, 0.48, -2.3, UIColor(hex: 0xE4E8ED), r: 0.02)
      box(n, 0.12, 0.8, 4.6, -2.3, 0.48, 0, UIColor(hex: 0xF0F2F5), r: 0.02)
      caption(
        "\(zone.code)  \(zone.title.uppercased())", at: SCNVector3(0, 2.7, -0.8), parent: n,
        size: 0.23)
      switch zone {
      case .casting:
        for x: Float in [-1.1, 1.1] {
          for z: Float in [-0.8, 0.9] {
            box(n, 1.8, 0.48, 1.15, x, 0.35, z, UIColor(hex: 0xABBED4))
            tub(n, at: SCNVector3(x, 0.6, z), scale: 0.69)
          }
        }
        for x: Float in [-1.9, 1.9] { box(n, 0.09, 2.15, 0.09, x, 1.15, -1.4, Palette.ink) }
        box(n, 3.9, 0.13, 0.16, 0, 2.2, -1.4, Palette.ink)
        box(n, 0.6, 0.6, 0.4, 0, 1.85, -1.4, UIColor(hex: 0xBACAC0))
        person(n, x: 0, z: 1.6, walking: true)
      case .finishing:
        for z: Float in [-0.9, 0.9] {
          box(n, 3.9, 0.35, 1.3, 0, 0.35, z, UIColor(hex: 0xB8C2CF))
          for x: Float in [-1.0, 1.0] { tub(n, at: SCNVector3(x, 0.55, z), scale: 0.67) }
        }
        person(n, x: -1.4, z: 1.9)
        person(n, x: 1, z: -1.8, walking: true)
      case .quality:
        for x: Float in [-1.05, 1.05] {
          box(n, 1.9, 0.5, 1.3, x, 0.38, 0, UIColor.white)
          tub(n, at: SCNVector3(x, 0.63, 0), scale: 0.76)
          box(n, 0.05, 1.9, 0.05, x - 0.88, 1.1, -0.6, UIColor(hex: 0x8DAD98))
          box(n, 1.8, 0.06, 0.12, x, 2.04, -0.6, Palette.lime)
        }
        person(n, x: 0, z: 1.5)
        box(n, 0.7, 0.7, 0.2, 0, 0.7, -1.8, Palette.ink)
      case .packing:
        box(n, 3.4, 0.35, 1.5, 0, 0.35, 0, UIColor(hex: 0xB8C6B6))
        tub(n, at: SCNVector3(-0.7, 0.57, 0), scale: 0.74)
        for x: Float in [-1.3, 0, 1.3] { pallet(n, x: x, z: 1.6) }
        person(n, x: 1.4, z: -1.2, walking: true)
      case .warehouse:
        for z: Float in [-1.2, 0.8] {
          for x: Float in [-1.5, 0, 1.5] {
            for y: Float in [0, 0.9] { pallet(n, x: x, z: z, level: y) }
            box(n, 0.08, 2.15, 0.08, x - 0.57, 1.1, z - 0.5, UIColor(hex: 0x729582))
            box(n, 0.08, 2.15, 0.08, x + 0.57, 1.1, z - 0.5, UIColor(hex: 0x729582))
          }
          box(n, 4.4, 0.07, 1.08, 0, 0.95, z, Palette.ink)
        }
      case .dispatch:
        for x: Float in [-1.4, 0, 1.4] {
          pallet(n, x: x, z: -1.1)
          pallet(n, x: x, z: 0.2)
        }
        person(n, x: -1.3, z: 1.6, walking: true)
        box(n, 3.7, 0.03, 0.7, 0, 0.15, 1.65, UIColor(hex: 0xC3CDB8))
      }
    }
    for x: Float in [-8.6, 8.6] {
      for z: Float in [-6.5, 5.7] {
        _ = cylinder(root, r: 0.3, h: 0.28, x: x, y: 0.1, z: z, color: UIColor(hex: 0xC4CDBA))
        _ = cylinder(root, r: 0.05, h: 0.9, x: x, y: 0.55, z: z, color: UIColor(hex: 0x9B937D))
        ball(root, r: 0.48, x: x, y: 1.15, z: z, color: UIColor(hex: 0x88A17F))
      }
    }
    let truck = SCNNode()
    truck.name = "zone-5"
    truck.position = SCNVector3(4, 0.25, 6)
    root.addChildNode(truck)
    box(truck, 2.8, 1.13, 1.1, 0, 0.8, 0, UIColor(hex: 0xF7F6EF), r: 0.12)
    box(truck, 0.72, 0.9, 1.08, -1.8, 0.65, 0, Palette.ink, r: 0.12)
    box(truck, 0.2, 0.39, 0.92, -2.14, 0.94, 0, UIColor(hex: 0x88B5AC), r: 0.04)
    for x: Float in [-1.8, 0.8] {
      for z: Float in [-0.58, 0.58] {
        let wheel = cylinder(
          truck, r: 0.23, h: 0.13, x: x, y: 0.2, z: z, color: UIColor(hex: 0x3F4E48))
        wheel.eulerAngles.x = .pi / 2
      }
    }
    caption("SALINI", at: SCNVector3(0, 1.4, 0.65), parent: truck, size: 0.28)
    let drive = SCNAction.moveBy(x: -9, y: 0, z: 0, duration: 18)
    drive.timingMode = .easeInEaseOut
    truck.runAction(
      .repeatForever(.sequence([.wait(duration: 4), drive, .wait(duration: 3), drive.reversed()])))
    let lift = SCNNode()
    lift.name = "zone-4"
    lift.position = SCNVector3(2.7, 0.18, 2.5)
    root.addChildNode(lift)
    box(lift, 0.8, 0.45, 1.1, 0, 0.38, 0, UIColor(hex: 0xC9A866), r: 0.1)
    box(lift, 0.09, 1.2, 0.08, -0.3, 0.8, -0.35, Palette.ink)
    box(lift, 0.09, 1.2, 0.08, 0.3, 0.8, -0.35, Palette.ink)
    box(lift, 0.8, 0.07, 0.8, 0, 1.4, 0, Palette.ink)
    let move = SCNAction.moveBy(x: 0, y: 0, z: -5, duration: 12)
    lift.runAction(
      .repeatForever(.sequence([move, .wait(duration: 3), move.reversed(), .wait(duration: 3)])))
  }
  @objc private func tap(_ g: UITapGestureRecognizer) {
    for hit in hitTest(g.location(in: self), options: nil) {
      var n: SCNNode? = hit.node
      while let node = n {
        if let name = node.name, name.hasPrefix("zone-"), let id = Int(name.dropFirst(5)),
          let zone = FactoryZone(rawValue: id)
        {
          select(zone)
          onSelect?(zone)
          return
        }
        n = node.parent
      }
    }
  }
  func select(_ zone: FactoryZone, animated: Bool = true) {
    chosen = zone
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated ? 0.35 : 0
    for (z, node) in floors {
      node.geometry?.firstMaterial?.diffuse.contents =
        z == zone ? UIColor(hex: 0xBDCEE3) : UIColor(hex: 0xE0E6EE)
    }
    SCNTransaction.commit()
  }
  func resetCamera() {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.6
    cameraNode.position = SCNVector3(18, 24, 25)
    cameraNode.look(at: SCNVector3(0, 0, 0))
    cameraNode.camera?.orthographicScale = 12.6
    pointOfView = cameraNode
    SCNTransaction.commit()
  }
  func closeUp(_ zone: FactoryZone) {
    cameraNode.camera?.orthographicScale = 4.6
    let p = zone.position
    cameraNode.position = SCNVector3(p.x + 5, 7, p.z + 7)
    cameraNode.look(at: SCNVector3(p.x, 0.7, p.z))
    select(zone, animated: false)
    allowsCameraControl = false
  }
  func setPaused(_ paused: Bool) {
    world.isPaused = paused
    isPlaying = !paused
  }
}
