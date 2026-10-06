import SceneKit
import UIKit

enum GrecaModel {
  static func load() throws -> SCNNode {
    guard let url = Bundle.main.url(forResource: "Greca", withExtension: "usdz") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let source = try SCNScene(url: url, options: nil)
    let model = source.rootNode.clone()
    let (lo, hi) = model.boundingBox
    let longest = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
    guard longest.isFinite, longest > 0 else { throw CocoaError(.fileReadCorruptFile) }
    let scale: Float = 4 / longest
    model.scale = SCNVector3(scale, scale, scale)
    model.position = SCNVector3(
      -(lo.x + hi.x) * 0.5 * scale, -lo.y * scale, -(lo.z + hi.z) * 0.5 * scale)
    model.enumerateChildNodes { node, _ in
      node.camera = nil
      node.light = nil
      for material in node.geometry?.materials ?? [] {
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(hex: 0xEFEFEB)
        material.roughness.contents = 0.48
        material.metalness.contents = 0.0
      }
    }
    return model
  }
}

final class ObjectViewerController: UIViewController {
  private let renderer = SCNView()
  private let world = SCNScene()
  private let object = SCNNode()
  private let light = SCNNode()
  private var spinning = true
  private var contrast = false
  private var spin: UIButton!
  init() {
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    renderer.scene = world
    renderer.backgroundColor = Palette.paper
    renderer.antialiasingMode = .multisampling4X
    renderer.allowsCameraControl = true
    renderer.defaultCameraController.interactionMode = .orbitTurntable
    renderer.defaultCameraController.target = SCNVector3(0, 0.65, 0)
    renderer.preferredFramesPerSecond = 60
    renderer.isPlaying = true
    renderer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(renderer)
    NSLayoutConstraint.activate([
      renderer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      renderer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      renderer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 70),
      renderer.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -190),
    ])
    do { object.addChildNode(try GrecaModel.load()) } catch {
      let failure = label("Не удалось открыть 3D-модель", 18, .medium)
      renderer.pin(failure, inset: 24)
    }
    world.rootNode.addChildNode(object)
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = 3.1
    camera.camera?.wantsHDR = false
    camera.position = SCNVector3(5.2, 4.4, 7)
    camera.look(at: SCNVector3(0, 0.65, 0))
    world.rootNode.addChildNode(camera)
    renderer.pointOfView = camera
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 420
    world.rootNode.addChildNode(ambient)
    light.light = SCNLight()
    light.light?.type = .directional
    light.light?.intensity = 900
    light.light?.castsShadow = true
    light.light?.shadowColor = UIColor.black.withAlphaComponent(0.18)
    light.light?.shadowRadius = 6
    light.eulerAngles = SCNVector3(-0.8, -0.7, 0)
    world.rootNode.addChildNode(light)
    world.lightingEnvironment.contents = UIColor.white
    world.lightingEnvironment.intensity = 0.55
    let floor = SCNFloor()
    let m = SCNMaterial()
    m.diffuse.contents = Palette.paper
    m.lightingModel = .constant
    floor.materials = [m]
    floor.reflectivity = 0
    let base = SCNNode(geometry: floor)
    base.position.y = -0.02
    world.rootNode.addChildNode(base)
    let close = ActionButton("", icon: "xmark") { [weak self] in self?.dismiss(animated: true) }
    close.accessibilityLabel = "Закрыть 3D-модель"
    close.widthAnchor.constraint(equalToConstant: 46).isActive = true
    let share = ActionButton("", icon: "square.and.arrow.up") { [weak self] in
      guard let self, let url = Bundle.main.url(forResource: "Greca", withExtension: "usdz") else {
        return
      }
      let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = self.view
      self.present(sheet, animated: true)
    }
    share.accessibilityLabel = "Поделиться моделью Greca"
    share.widthAnchor.constraint(equalToConstant: 46).isActive = true
    let name = label("Greca / 3D", 18, .semibold)
    name.textAlignment = .center
    let top = stack([close, UIView(), name, UIView(), share], axis: .horizontal, spacing: 8)
    top.alignment = .center
    top.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(top)
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      top.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
    ])
    spin = ActionButton("Вращать", icon: "arrow.trianglehead.2.clockwise.rotate.90") {
      [weak self] in self?.toggleSpin()
    }
    spin.accessibilityIdentifier = "model.rotate"
    let lighting = ActionButton("Свет", icon: "sun.max") { [weak self] in
      guard let self else { return }
      self.contrast.toggle()
      SCNTransaction.begin()
      SCNTransaction.animationDuration = 0.7
      self.light.light?.intensity = self.contrast ? 550 : 900
      self.light.eulerAngles = SCNVector3(
        self.contrast ? -0.3 : -0.8, self.contrast ? 0.65 : -0.7, 0)
      SCNTransaction.commit()
    }
    let tools = stack([spin, lighting], axis: .horizontal, spacing: 10)
    tools.distribution = .fillEqually
    let glass = GlassView()
    glass.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(glass)
    let add = ActionButton("Greca в проект", icon: "plus", prominent: true) { [weak self] in
      guard let p = Product.all.first(where: { $0.id == "greca" }) else { return }
      DemoStore.shared.add(p, stone: false)
      self?.dismiss(animated: true)
    }
    glass.contentView.pin(
      stack(
        [
          eyebrow("ОРИГИНАЛЬНАЯ МОДЕЛЬ SALINI"), label("Форма со всех сторон.", 25, .semibold),
          label("Вращайте одним пальцем. Приближайте двумя.", 12, .regular, Palette.muted), tools,
          add,
        ], spacing: 12), inset: 22)
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      glass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      glass.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
    spinning = !UIAccessibility.isReduceMotionEnabled
    updateSpin()
  }
  private func toggleSpin() {
    spinning.toggle()
    updateSpin()
  }
  private func updateSpin() {
    object.removeAction(forKey: "rotate")
    if spinning {
      object.runAction(
        .repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 32)), forKey: "rotate")
    }
    spin.configuration?.title = spinning ? "Пауза" : "Вращать"
    spin.accessibilityLabel = spinning ? "Приостановить вращение" : "Вращать модель"
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    renderer.isPlaying = false
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    renderer.isPlaying = true
  }
}
