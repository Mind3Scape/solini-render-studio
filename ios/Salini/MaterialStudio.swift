import SceneKit
import UIKit

enum SaliniMaterial: Int, CaseIterable {
  case stone, sense
  var name: String { self == .stone ? "S-Stone" : "S-Sense" }
  var finish: String { self == .stone ? "Бархатистый матовый" : "Глубокий глянец" }
  var headline: String { self == .stone ? "Свет становится мягче." : "Свет обретает глубину." }
  var composition: String {
    self == .stone
      ? "Solid Surface. Однородная структура и цвет на всю глубину."
      : "Мраморная крошка и смола. Глянцевое защитное покрытие Gelcoat."
  }
  var note: String {
    self == .stone
      ? "Монолитный материал без дополнительного покрытия."
      : "Декоративно-защитный слой допускает косметическую полировку."
  }
}

/// Sculptural samples illustrate light response; these are not measured material scans.
final class MaterialSceneView: SCNView, UIGestureRecognizerDelegate {
  private let world = SCNScene()
  private let lightRig = SCNNode()
  private var samples: [SCNNode] = []
  private var coatingCore: SCNNode?
  private(set) var structureVisible = false
  private var panOrigin: Float = 0
  private(set) var lightPosition: Float = 0.5
  var onTouch: (() -> Void)?
  var active = false { didSet { refreshPlayback() } }
  static let backdrop = UIColor(hex: 0x14191E)
  override init(frame: CGRect, options: [String: Any]? = nil) {
    super.init(frame: frame, options: options)
    scene = world
    backgroundColor = Self.backdrop
    antialiasingMode = .multisampling4X
    preferredFramesPerSecond = 30
    isAccessibilityElement = true
    accessibilityLabel = "Два объёмных образца. Слева матовый S-Stone, справа глянцевый S-Sense."
    accessibilityHint = "Двигайте пальцем по горизонтали, чтобы менять направление света."
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = 2.2
    camera.camera?.wantsHDR = false
    camera.position = SCNVector3(0, 6.2, 8.8)
    camera.look(at: SCNVector3(0, 0.25, 0))
    world.rootNode.addChildNode(camera)
    pointOfView = camera
    world.lightingEnvironment.contents = Self.environment()
    world.lightingEnvironment.intensity = 0.7
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 230
    world.rootNode.addChildNode(ambient)
    world.rootNode.addChildNode(lightRig)
    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.intensity = 800
    key.light?.color = UIColor(hex: 0xEAF0FA)
    key.light?.castsShadow = true
    key.light?.shadowColor = UIColor.black.withAlphaComponent(0.6)
    key.light?.shadowRadius = 10
    key.eulerAngles = SCNVector3(-0.85, -0.65, 0)
    lightRig.addChildNode(key)
    let rim = SCNNode()
    rim.light = SCNLight()
    rim.light?.type = .omni
    rim.light?.intensity = 240
    rim.light?.color = UIColor(hex: 0xFFEDDC)
    rim.position = SCNVector3(2, 3, -3)
    world.rootNode.addChildNode(rim)
    for material in SaliniMaterial.allCases {
      let pivot = SCNNode()
      let sample = SCNNode(geometry: Self.sampleGeometry())
      let surface = SCNMaterial()
      surface.lightingModel = material == .stone ? .lambert : .blinn
      surface.diffuse.contents = UIColor(hex: 0xDEDDD8)
      surface.specular.contents = material == .stone ? UIColor.black : UIColor.white
      surface.shininess = 0.82
      if material == .sense {
        surface.reflective.contents = Self.environment()
        surface.reflective.intensity = 0.22
        surface.fresnelExponent = 2
      }
      surface.roughness.contents = material == .stone ? 0.85 : 0.055
      surface.metalness.contents = 0.0
      sample.geometry?.materials = [surface]
      sample.scale = SCNVector3(1, 1, 1.24)
      sample.eulerAngles = SCNVector3(
        material == .stone ? 0.06 : -0.14, material == .stone ? -0.28 : 0.32,
        material == .stone ? -0.16 : 0.14)
      pivot.addChildNode(sample)
      world.rootNode.addChildNode(pivot)
      samples.append(pivot)
      if material == .sense {
        let base = SCNCylinder(radius: 0.94, height: 0.28)
        base.radialSegmentCount = 96
        let coreMaterial = SCNMaterial()
        coreMaterial.lightingModel = .lambert
        coreMaterial.diffuse.contents = UIColor(hex: 0xA7A098)
        base.materials = [coreMaterial]
        let core = SCNNode(geometry: base)
        core.opacity = 0
        core.position.y = -0.12
        sample.addChildNode(core)
        coatingCore = core
      }
      if !UIAccessibility.isReduceMotionEnabled {
        let rise = SCNAction.moveBy(x: 0, y: 0.08, z: 0, duration: material == .stone ? 4.5 : 5.5)
        rise.timingMode = .easeInEaseOut
        sample.runAction(.repeatForever(.sequence([rise, rise.reversed()])))
        let tilt = SCNAction.rotateBy(x: 0.08, y: 0.14, z: 0.04, duration: 7)
        tilt.timingMode = .easeInEaseOut
        sample.runAction(.repeatForever(.sequence([tilt, tilt.reversed()])))
      }
    }
    let floor = SCNFloor()
    floor.reflectivity = 0
    let floorMaterial = SCNMaterial()
    floorMaterial.diffuse.contents = Self.backdrop
    floorMaterial.lightingModel = .constant
    floor.materials = [floorMaterial]
    let ground = SCNNode(geometry: floor)
    ground.position.y = -1.5
    world.rootNode.addChildNode(ground)
    select(.stone, animated: false)
    startLight()
    let pan = UIPanGestureRecognizer(target: self, action: #selector(dragLight(_:)))
    pan.delegate = self
    addGestureRecognizer(pan)
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshPlayback), name: UIApplication.didBecomeActiveNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshPlayback),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(motionChanged),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    refreshPlayback()
  }
  @objc private func refreshPlayback() {
    isPlaying = active && window != nil && UIApplication.shared.applicationState == .active
  }
  @objc private func motionChanged() {
    world.rootNode.enumerateChildNodes { node, _ in
      node.isPaused = UIAccessibility.isReduceMotionEnabled
    }
    startLight()
  }
  private func startLight() {
    lightRig.removeAllActions()
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    let sweep = SCNAction.rotateBy(x: 0, y: 1.15, z: 0, duration: 9)
    sweep.timingMode = .easeInEaseOut
    lightRig.runAction(.repeatForever(.sequence([sweep, sweep.reversed()])), forKey: "sweep")
  }
  func select(_ material: SaliniMaterial, animated: Bool = true) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.9 : 0
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    for (i, node) in samples.enumerated() {
      let chosen = i == material.rawValue
      node.position = SCNVector3(i == 0 ? -1.3 : 1.3, chosen ? 0.25 : 0.03, chosen ? 0.32 : -0.28)
      let scale: Float = chosen ? 1.1 : 0.91
      node.scale = SCNVector3(scale, scale, scale)
    }
    SCNTransaction.commit()
  }
  func showStructure(_ visible: Bool) {
    structureVisible = visible
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 1.1
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    coatingCore?.opacity = visible ? 1 : 0
    coatingCore?.position.y = visible ? -0.8 : -0.12
    SCNTransaction.commit()
  }
  func moveLight(to position: Float) {
    lightPosition = max(0, min(1, position))
    lightRig.removeAllActions()
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.12
    lightRig.eulerAngles.y = (lightPosition - 0.5) * 3.4
    for node in samples { node.eulerAngles.y = (lightPosition - 0.5) * 0.24 }
    SCNTransaction.commit()
  }
  @objc private func dragLight(_ gesture: UIPanGestureRecognizer) {
    if gesture.state == .began {
      panOrigin = lightPosition
      onTouch?()
    }
    moveLight(to: panOrigin + Float(gesture.translation(in: self).x / max(1, bounds.width)))
  }
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: self)
    return abs(velocity.x) > abs(velocity.y)
  }
  // Lathed, softly concave sample: curved surfaces make matte/gloss differences legible.
  private static func sampleGeometry() -> SCNGeometry {
    let profile: [(Float, Float)] = [
      (0, 0.02), (0.35, 0.03), (0.66, 0.14), (0.88, 0.36), (1.0, 0.49), (1.09, 0.41), (1.12, 0.22),
      (1.08, 0.06), (0.95, -0.06), (0.35, -0.18), (0, -0.18),
    ]
    let segments = 128
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [Int32] = []
    for (j, point) in profile.enumerated() {
      let previous = profile[max(0, j - 1)]
      let next = profile[min(profile.count - 1, j + 1)]
      let dr = next.0 - previous.0
      let dy = next.1 - previous.1
      let length = max(0.0001, sqrt(dr * dr + dy * dy))
      for i in 0...segments {
        let angle = Float(i) / Float(segments) * .pi * 2
        vertices.append(SCNVector3(point.0 * cos(angle), point.1, point.0 * sin(angle)))
        normals.append(
          SCNVector3(-dy / length * cos(angle), dr / length, -dy / length * sin(angle)))
        if j < profile.count - 1 && i < segments {
          let a = Int32(j * (segments + 1) + i)
          let b = a + Int32(segments + 1)
          indices += [a, a + 1, b, a + 1, b + 1, b]
        }
      }
    }
    return SCNGeometry(
      sources: [.init(vertices: vertices), .init(normals: normals)],
      elements: [.init(indices: indices, primitiveType: .triangles)])
  }
  private static func environment() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image {
      context in
      UIColor(white: 0.14, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
      UIColor(white: 0.98, alpha: 1).setFill()
      context.fill(CGRect(x: 110, y: 95, width: 100, height: 240))
      context.fill(CGRect(x: 232, y: 95, width: 22, height: 240))
      UIColor(white: 0.52, alpha: 1).setFill()
      context.fill(CGRect(x: 710, y: 145, width: 200, height: 80))
    }
  }
}

final class MaterialShowcase: UIView {
  let sceneView = MaterialSceneView(frame: .zero)
  private let headline = label("", 24, .regular, .white)
  private let detail = label("", 13, .regular, UIColor(white: 0.68, alpha: 1))
  private var choices: [UIButton] = []
  private(set) var selected: SaliniMaterial = .stone
  init(expanded: Bool = false, open: ((SaliniMaterial) -> Void)? = nil) {
    super.init(frame: .zero)
    backgroundColor = MaterialSceneView.backdrop
    rounded(30)
    sceneView.height(expanded ? 300 : 255)
    let layers = ActionButton("", icon: "square.3.layers.3d") { [weak self] in
      guard let self else { return }
      self.sceneView.showStructure(!self.sceneView.structureVisible)
      self.headline.text =
        self.sceneView.structureVisible ? "Монолит и защитный слой." : self.selected.headline
      self.detail.text =
        self.sceneView.structureVisible
        ? "S-Stone — однородный объём. S-Sense — минеральная основа с покрытием Gelcoat."
        : self.selected.composition
    }
    layers.configuration?.baseForegroundColor = .white
    layers.configuration?.contentInsets = .init(top: 9, leading: 9, bottom: 9, trailing: 9)
    layers.accessibilityLabel = "Показать или скрыть структуру материалов"
    layers.accessibilityIdentifier = "material.layers"
    layers.widthAnchor.constraint(equalToConstant: 38).isActive = true
    layers.height(38)
    let heading = stack(
      [eyebrow("МАТЕРИЯ SALINI", color: UIColor(white: 0.63, alpha: 1)), UIView(), layers],
      axis: .horizontal)
    heading.alignment = .center
    let tabs = stack([], axis: .horizontal, spacing: 10)
    tabs.distribution = .fillEqually
    for material in SaliniMaterial.allCases {
      let button = UIButton(type: .system)
      var c = UIButton.Configuration.plain()
      c.title = material.name
      c.subtitle = material.finish
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 21, weight: .regular)
        return a
      }
      c.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 10, weight: .medium)
        return a
      }
      c.titlePadding = 7
      c.contentInsets = .init(top: 13, leading: 8, bottom: 13, trailing: 8)
      c.background.cornerRadius = 19
      button.configuration = c
      button.accessibilityIdentifier = "material.\(material.name)"
      button.addAction(UIAction { [weak self] _ in self?.select(material) }, for: .touchUpInside)
      choices.append(button)
      tabs.addArrangedSubview(button)
    }
    headline.height(32)
    detail.height(46)
    let controls = stack([], axis: .horizontal, spacing: 9)
    let light = ActionButton("Свет", icon: "sun.max") { [weak self] in
      guard let self else { return }
      self.sceneView.moveLight(to: self.sceneView.lightPosition > 0.6 ? 0.15 : 0.85)
    }
    light.accessibilityLabel = "Переместить свет"
    light.accessibilityIdentifier = "material.light"
    light.configuration?.baseForegroundColor = .white
    controls.addArrangedSubview(light)
    if let open {
      let more = ActionButton("Исследовать", icon: "arrow.up.right") { [weak self] in
        guard let self else { return }
        open(self.selected)
      }
      more.accessibilityIdentifier = "material.explore"
      more.configuration?.baseForegroundColor = .white
      controls.addArrangedSubview(more)
      controls.distribution = .fillProportionally
    } else {
      let hint = label(
        "Проведите по образцам,\nчтобы направить свет.", 11, .regular,
        UIColor(white: 0.63, alpha: 1))
      controls.addArrangedSubview(hint)
      controls.alignment = .center
    }
    let text = stack([tabs, spacer(4), headline, detail, controls], spacing: 10)
    let body = stack([heading.inset(24), sceneView, text.inset(22)], spacing: 0)
    pin(body)
    select(.stone, animated: false)
  }
  required init?(coder: NSCoder) { fatalError() }
  func select(_ material: SaliniMaterial, animated: Bool = true) {
    selected = material
    sceneView.select(material, animated: animated)
    for (i, button) in choices.enumerated() {
      let selected = i == material.rawValue
      button.configuration?.baseForegroundColor =
        selected ? Palette.ink : UIColor(white: 0.8, alpha: 1)
      button.configuration?.background.backgroundColor =
        selected ? UIColor(hex: 0xEDECE8) : UIColor.white.withAlphaComponent(0.05)
      button.accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
    UIView.transition(
      with: headline, duration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.3 : 0,
      options: .transitionCrossDissolve
    ) {
      self.headline.text =
        self.sceneView.structureVisible ? "Монолит и защитный слой." : material.headline
      self.detail.text =
        self.sceneView.structureVisible
        ? "S-Stone — однородный объём. S-Sense — минеральная основа с покрытием Gelcoat."
        : material.composition
    }
    if animated { UISelectionFeedbackGenerator().selectionChanged() }
  }
}

final class MaterialStudioController: ScrollController {
  private let showcase = MaterialShowcase(expanded: true)
  private let initial: SaliniMaterial
  init(_ initial: SaliniMaterial = .stone) {
    self.initial = initial
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Студия материалов"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    add(showcase, inset: 14)
    showcase.select(initial, animated: false)
    add(
      stack(
        [
          eyebrow("ДВА ХАРАКТЕРА ПОВЕРХНОСТИ"),
          label("Ощущение начинается\nсо света.", 29, .regular),
          label(
            "Меняйте направление света и сравнивайте мягкое рассеивание с чётким отражением.", 15,
            .regular, Palette.muted),
          line(), label("S-Stone", 22, .medium),
          label(SaliniMaterial.stone.note, 15, .regular, Palette.muted),
          label("S-Sense", 22, .medium),
          label(SaliniMaterial.sense.note, 15, .regular, Palette.muted),
          label(
            "Образцы и разрез — стилизованная схема, не масштабная модель слоёв. Точный цвет и тактильность раскрывает физический образец. Доступность исполнений зависит от модели.",
            12, .regular, Palette.muted),
          ActionButton("Посмотреть на Aria", icon: "arrow.up.right", prominent: true) {
            [weak self] in
            guard let p = Product.all.first(where: { $0.id == "aria" }) else { return }
            guard let self else { return }
            self.navigationController?.pushViewController(
              ProductController(p, stone: self.showcase.selected == .stone), animated: true)
          },
        ], spacing: 16))
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    showcase.sceneView.active = true
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    showcase.sceneView.active = false
  }
}
