import ARKit
import AVFoundation
import SceneKit
import UIKit

/// A camera-backed, metre-scale AR session. Catalogue geometry never adopts the studio's zoom.
final class RoomPlacementController: UIViewController, ARSessionDelegate, ARSCNViewDelegate, UIGestureRecognizerDelegate {
  let product: RoomProduct
  private(set) var stage: RoomStage = .introduction
  private var sceneView: ARSCNView?
  private var model: SCNNode?
  private var placementAnchor: ARAnchor?
  private var placementNode: SCNNode?
  private var candidate: simd_float4x4?
  private var candidateTime: TimeInterval = 0
  private var trackingNormal = false
  private var visible = false
  private var loadGeneration = 0
  private var yaw: Float = 0
  private var rotationStart: Float = 0
  private var dragOffset: SIMD3<Float>?
  private var displayLink: CADisplayLink?
  private var marker: SCNNode?
  private let intro = UIScrollView()
  private let studioPreview = StudioSceneView(frame: .zero)
  private let statusTitle = label("", 20, .semibold)
  private let statusBody = label("", 14, .regular, Palette.muted)
  private let action = UIButton(configuration: .filled())
  private let movement = UIStackView()
  private let board = GlassView()
  private let reticle = UIImageView(image: UIImage(systemName: "plus.viewfinder"))

  init(product: RoomProduct) {
    self.product = product
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }
  required init?(coder: NSCoder) { fatalError() }
  static func present(_ product: RoomProduct, from host: UIViewController) {
    host.present(RoomPlacementController(product: product), animated: true)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    buildInterface()
    NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    renderStage(Self.supported ? .introduction : .unavailable)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    visible = true
    studioPreview.active = sceneView == nil
    if Self.supported, AVCaptureDevice.authorizationStatus(for: .video) == .authorized { openCamera() }
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    visible = false
    loadGeneration += 1
    stopCamera()
    studioPreview.active = false
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  static var supported: Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      return ARWorldTrackingConfiguration.isSupported
    #endif
  }

  private func buildInterface() {
    intro.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(intro)
    let introBody = stack([
      eyebrow("SALINI · В ВАШЕМ ПРОСТРАНСТВЕ"),
      label("Место для\nвашей Salini.", 39, .regular, serif: true),
      label("Посмотрите, как изделие выглядит в комнате — в натуральную величину.", 17, .regular, Palette.muted),
      studioPreview,
      label("01  Наведите камеру на пол\n02  Выберите место\n03  Поставьте и поверните изделие", 16, .medium),
      label("Камера работает только во время примерки. Кадры комнаты не записываются и не отправляются.", 13, .regular, Palette.muted),
    ], spacing: 20)
    studioPreview.height(250)
    studioPreview.rounded(26)
    studioPreview.load(product.form, finish: product.finish, colour: product.ral?.colour ?? StudioScene.white, shot: .form)
    introBody.translatesAutoresizingMaskIntoConstraints = false
    intro.addSubview(introBody)
    let close = UIButton(configuration: .glass(), primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    close.configuration?.image = UIImage(systemName: "xmark")
    close.accessibilityLabel = "Закрыть примерку"
    close.accessibilityIdentifier = "room.close"
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)
    board.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(board)
    let dimensions = label("1:1  ·  \(product.form.product.dimensions.text ?? "")", 14, .semibold)
    dimensions.accessibilityIdentifier = "room.dimensions"
    let details = label("\(product.form.name)\n\(product.subtitle)", 14, .medium)
    let note = label("Размер — по каталогу. Точность размещения зависит от сканирования; перед монтажом проверьте рулеткой. Цвет — экранное приближение.", 11, .regular, Palette.muted)
    movement.axis = .horizontal
    movement.spacing = 8
    movement.distribution = .fillEqually
    for (title, icon, delta) in [("Влево", "rotate.left", Float.pi / 12), ("Вправо", "rotate.right", -Float.pi / 12)] {
      let b = UIButton(configuration: .glass(), primaryAction: UIAction { [weak self] _ in self?.turn(by: delta) })
      b.configuration?.title = title
      b.configuration?.image = UIImage(systemName: icon)
      b.configuration?.imagePadding = 6
      b.accessibilityLabel = "Повернуть на 15 градусов \(title.lowercased())"
      movement.addArrangedSubview(b)
    }
    action.configuration?.cornerStyle = .capsule
    action.configuration?.baseBackgroundColor = Palette.ink
    action.configuration?.baseForegroundColor = .white
    action.configuration?.contentInsets = .init(top: 15, leading: 18, bottom: 15, trailing: 18)
    action.accessibilityIdentifier = "room.primary"
    action.addAction(UIAction { [weak self] _ in self?.primaryAction() }, for: .touchUpInside)
    statusTitle.accessibilityIdentifier = "room.status"
    let boardBody = stack([dimensions, details, line(), statusTitle, statusBody, movement, action, note], spacing: 10)
    board.contentView.pin(boardBody, inset: 20)
    reticle.tintColor = .white
    reticle.isUserInteractionEnabled = false
    reticle.translatesAutoresizingMaskIntoConstraints = false
    view.insertSubview(reticle, belowSubview: board)
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      close.widthAnchor.constraint(equalToConstant: 46), close.heightAnchor.constraint(equalToConstant: 46),
      board.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      board.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      board.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      intro.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 12),
      intro.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      intro.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      intro.bottomAnchor.constraint(equalTo: board.topAnchor, constant: -12),
      introBody.topAnchor.constraint(equalTo: intro.contentLayoutGuide.topAnchor, constant: 12),
      introBody.bottomAnchor.constraint(equalTo: intro.contentLayoutGuide.bottomAnchor, constant: -20),
      introBody.leadingAnchor.constraint(equalTo: intro.frameLayoutGuide.leadingAnchor, constant: 24),
      introBody.trailingAnchor.constraint(equalTo: intro.frameLayoutGuide.trailingAnchor, constant: -24),
      reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -70),
      reticle.widthAnchor.constraint(equalToConstant: 40), reticle.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  private func renderStage(_ next: RoomStage) {
    if stage == next, statusTitle.text?.isEmpty == false { return }
    let changed = stage != next
    stage = next
    intro.isHidden = sceneView != nil
    movement.isHidden = !next.canManipulate
    reticle.isHidden = !(next == .searching || next == .ready)
    reticle.tintColor = next == .ready ? UIColor.systemMint : .white
    marker?.isHidden = next != .ready
    action.isEnabled = true
    switch next {
    case .introduction:
      statusTitle.text = "Примерка в комнате"
      statusBody.text = "Разрешите доступ к задней камере, чтобы найти поверхность и поставить изделие."
      action.configuration?.title = "Открыть камеру"
    case .unavailable:
      statusTitle.text = "AR — на iPhone и iPad"
      statusBody.text = "На этом устройстве камера AR недоступна. Откройте Salini на совместимом iPhone или iPad; здесь можно изучить модель в студии."
      action.configuration?.title = "Открыть 3D-студию"
    case .denied:
      statusTitle.text = "Нужен доступ к камере"
      statusBody.text = "Разрешите камеру для Salini в настройках и вернитесь сюда."
      action.configuration?.title = "Настройки камеры"
    case .loading:
      statusTitle.text = "Готовим вашу модель"
      statusBody.text = "Проверяем геометрию и натуральный размер изделия."
      action.configuration?.title = "Загрузка…"
      action.isEnabled = false
    case .searching:
      statusTitle.text = "Найдём пол"
      statusBody.text = "Медленно перемещайте телефон. Наведите центр экрана на освещённый свободный участок пола."
      action.configuration?.title = "Ищем поверхность…"
      action.isEnabled = false
    case .ready:
      statusTitle.text = "Здесь можно поставить"
      statusBody.text = "Контур показывает размер изделия. Подойдите ближе и выберите удобное место."
      action.configuration?.title = "Поставить здесь"
    case .placed:
      statusTitle.text = "В натуральную величину"
      statusBody.text = "Перетащите изделие одним пальцем. Поверните двумя пальцами или кнопками. Масштаб закреплён: 1:1."
      action.configuration?.title = "Выбрать другое место"
    case .interrupted:
      statusTitle.text = "Вернёмся к примерке"
      statusBody.text = "Камера потеряла ориентиры. Наведите её на прежнее место; можно начать сканирование заново."
      action.configuration?.title = "Сканировать заново"
    case .failed(let message):
      statusTitle.text = "Не удалось начать примерку"
      statusBody.text = message
      action.configuration?.title = "Повторить"
    }
    if changed, UIAccessibility.isVoiceOverRunning {
      UIAccessibility.post(notification: .announcement, argument: statusTitle.text)
    }
  }

  private func primaryAction() {
    switch stage {
    case .introduction, .failed: openCamera()
    case .denied:
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    case .unavailable:
      MaterialStudioController.present(form: product.form, finish: product.finish, ral: product.ral, from: self)
    case .ready: place()
    case .placed: removePlacement(resetTracking: false)
    case .interrupted: removePlacement(resetTracking: true)
    case .loading, .searching: break
    }
  }
  private func openCamera() {
    guard visible, Self.supported else { renderStage(.unavailable); return }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: loadAndStart()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main.async {
          guard let self, self.visible else { return }
          if allowed { self.loadAndStart() } else { self.renderStage(.denied) }
        }
      }
    default: renderStage(.denied)
    }
  }
  private func loadAndStart() {
    if model != nil { startSession(reset: sceneView == nil); return }
    renderStage(.loading)
    loadGeneration += 1
    let generation = loadGeneration, product = product
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try RoomAssetBuilder.build(product) }
      DispatchQueue.main.async {
        guard let self, self.visible, generation == self.loadGeneration else { return }
        switch result {
        case .success(let node): self.model = node; self.startSession(reset: true)
        case .failure:
          self.renderStage(.failed("Размеры 3D-модели не удалось подтвердить. Модель остаётся доступна в 3D-студии; повторите загрузку или выберите другое изделие."))
        }
      }
    }
  }
  private func configuration() -> ARWorldTrackingConfiguration {
    let config = ARWorldTrackingConfiguration()
    config.planeDetection = [.horizontal]
    config.environmentTexturing = .automatic
    config.isLightEstimationEnabled = true
    return config
  }
  private func startSession(reset: Bool) {
    guard visible, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
    if sceneView == nil {
      let ar = ARSCNView(frame: view.bounds)
      ar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      ar.scene = SCNScene()
      ar.automaticallyUpdatesLighting = true
      ar.preferredFramesPerSecond = 60
      ar.antialiasingMode = .multisampling2X
      ar.session.delegate = self
      ar.session.delegateQueue = .main
      ar.delegate = self
      ar.accessibilityIdentifier = "room.camera"
      view.insertSubview(ar, at: 0)
      sceneView = ar
      for gesture in [UITapGestureRecognizer(target: self, action: #selector(tapped(_:))),
                      UIPanGestureRecognizer(target: self, action: #selector(panned(_:))),
                      UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))] {
        gesture.delegate = self
        if let pan = gesture as? UIPanGestureRecognizer { pan.maximumNumberOfTouches = 1 }
        ar.addGestureRecognizer(gesture)
      }
      marker = makeFootprint()
      if let marker { ar.scene.rootNode.addChildNode(marker) }
    }
    studioPreview.active = false
    trackingNormal = false
    candidate = nil
    sceneView?.session.run(configuration(), options: reset ? [.resetTracking, .removeExistingAnchors] : [])
    if displayLink == nil {
      let link = CADisplayLink(target: self, selector: #selector(updateTarget))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
      link.add(to: .main, forMode: .common)
      displayLink = link
    }
    renderStage(placementAnchor == nil ? .searching : .interrupted)
  }
  private func stopCamera() {
    displayLink?.invalidate()
    displayLink = nil
    sceneView?.session.pause()
    candidate = nil
    trackingNormal = false
  }
  @objc private func background() {
    guard sceneView != nil else { return }
    stopCamera()
    placementNode?.isHidden = true
    renderStage(.interrupted)
  }
  @objc private func foreground() {
    guard visible else { return }
    // This also handles a permission change in Settings without creating a second camera session.
    if stage == .denied || sceneView != nil { openCamera() }
  }

  @objc private func updateTarget() {
    guard visible, placementAnchor == nil, trackingNormal, let ar = sceneView,
      let frame = ar.session.currentFrame else { return }
    let p = ar.convert(reticle.center, from: view)
    guard let query = ar.raycastQuery(from: p, allowing: .existingPlaneGeometry, alignment: .horizontal),
      let hit = ar.session.raycast(query).first,
      simd_distance(SIMD3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z),
                    SIMD3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)) < 7 else {
      candidate = nil
      renderStage(.searching)
      return
    }
    var transform = matrix_identity_float4x4
    transform.columns.3 = hit.worldTransform.columns.3
    candidate = transform
    candidateTime = CACurrentMediaTime()
    yaw = RoomPlacementMath.normalizedAngle(atan2(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.z))
    marker?.simdTransform = transform
    marker?.eulerAngles.y = yaw
    renderStage(.ready)
  }
  private func place() {
    guard stage.canPlace, trackingNormal, CACurrentMediaTime() - candidateTime < 0.3,
      let transform = candidate, let ar = sceneView, model != nil else { return }
    let anchor = ARAnchor(name: "Salini.product", transform: transform)
    placementAnchor = anchor
    candidate = nil
    ar.session.add(anchor: anchor)
    renderStage(.placed)
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
  }
  private func removePlacement(resetTracking: Bool) {
    model?.removeFromParentNode()
    placementNode = nil
    if let anchor = placementAnchor { sceneView?.session.remove(anchor: anchor) }
    placementAnchor = nil
    dragOffset = nil
    candidate = nil
    if resetTracking { startSession(reset: true) } else { renderStage(.searching) }
  }
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    DispatchQueue.main.async { [weak self, weak node] in
      guard let self, self.visible, let node, anchor.identifier == self.placementAnchor?.identifier,
        let model = self.model else { return }
      model.simdPosition = .zero
      model.eulerAngles = SCNVector3(0, self.yaw, 0)
      model.simdScale = SIMD3(repeating: 1)
      node.addChildNode(model)
      node.isHidden = !self.trackingNormal
      self.placementNode = node
    }
  }
  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    guard visible else { return }
    if case .normal = camera.trackingState {
      trackingNormal = true
      placementNode?.isHidden = false
      renderStage(placementAnchor == nil ? .searching : .placed)
    } else {
      trackingNormal = false
      candidate = nil
      marker?.isHidden = true
      placementNode?.isHidden = true
      if placementAnchor != nil { renderStage(.interrupted) } else { renderStage(.searching) }
    }
  }
  func sessionWasInterrupted(_ session: ARSession) { background() }
  func sessionInterruptionEnded(_ session: ARSession) { if visible { startSession(reset: false) } }
  func session(_ session: ARSession, didFailWithError error: Error) {
    guard visible else { return }
    stopCamera()
    removePlacement(resetTracking: false)
    if AVCaptureDevice.authorizationStatus(for: .video) != .authorized { renderStage(.denied) }
    else { renderStage(.failed("Камера не смогла продолжить сканирование. Вернитесь к освещённому участку пола и повторите попытку.")) }
  }

  @objc private func tapped(_ recognizer: UITapGestureRecognizer) { if stage.canPlace { place() } }
  @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
    guard stage.canManipulate, trackingNormal else { return }
    if recognizer.state == .began { rotationStart = yaw }
    yaw = RoomPlacementMath.normalizedAngle(rotationStart - Float(recognizer.rotation))
    model?.eulerAngles.y = yaw
  }
  private func turn(by delta: Float) {
    guard stage.canManipulate, trackingNormal else { return }
    yaw = RoomPlacementMath.normalizedAngle(yaw + delta)
    model?.eulerAngles.y = yaw
    UISelectionFeedbackGenerator().selectionChanged()
  }
  @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
    guard stage.canManipulate, trackingNormal, let ar = sceneView,
      let node = placementNode, let model else { return }
    let p = recognizer.location(in: ar)
    let near = ar.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
    let far = ar.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
    let origin = model.simdWorldPosition
    guard let point = RoomPlacementMath.floorPoint(near: SIMD3(near.x, near.y, near.z), far: SIMD3(far.x, far.y, far.z), floorY: origin.y) else { return }
    if recognizer.state == .began { dragOffset = origin - point }
    if let offset = dragOffset {
      model.simdPosition = node.simdConvertPosition(point + offset, from: nil)
    }
    if recognizer.state == .ended || recognizer.state == .cancelled { dragOffset = nil }
  }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer {
      guard stage.canManipulate, let ar = sceneView, let model else { return false }
      return ar.hitTest(gestureRecognizer.location(in: ar)).contains { hit in
        var n: SCNNode? = hit.node
        while let node = n { if node === model { return true }; n = node.parent }
        return false
      }
    }
    return stage.canPlace
  }
  private func makeFootprint() -> SCNNode {
    let root = SCNNode()
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = UIColor.systemMint.withAlphaComponent(0.8)
    m.readsFromDepthBuffer = false
    for (w, d, x, z) in [(product.metres.x, Float(0.009), Float(0), product.metres.z / 2),
                         (product.metres.x, 0.009, 0, -product.metres.z / 2),
                         (Float(0.009), product.metres.z, product.metres.x / 2, Float(0)),
                         (0.009, product.metres.z, -product.metres.x / 2, 0)] {
      let line = SCNBox(width: CGFloat(w), height: 0.002, length: CGFloat(d), chamferRadius: 0)
      line.firstMaterial = m
      let n = SCNNode(geometry: line)
      n.position = SCNVector3(x, 0.003, z)
      root.addChildNode(n)
    }
    root.isHidden = true
    return root
  }
}
