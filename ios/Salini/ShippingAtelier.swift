import SceneKit
import UIKit

/// «Участок отгрузки»: a native screen for the shipping-section graphics proof, opened from Salini
/// Inside (a visible card and the map menu) or directly with the `-shipping-atelier` launch
/// argument. Pan and pinch move a fixed true-isometric camera; tapping the batch, the forklift or
/// the truck opens a glass status card. All movement is a labelled demonstration.
final class ShippingAtelierController: UIViewController, UIGestureRecognizerDelegate {
  private let sceneView = SCNView(frame: .zero, options: nil)
  private let atelier: ShippingAtelierScene
  private let header = GlassView()
  private let card = GlassView()
  private let zoomBar = GlassView()
  private let cardTitle = label("", 17, .semibold, Atelier.ink)
  private let cardStatus = label("", 14, .regular, Atelier.muted)
  private let cardEyebrow = eyebrow("ПАРТИЯ", color: Atelier.accent)
  private let cardNote = label("Демонстрация: движение и статусы смоделированы, это не телеметрия завода.", 11, .regular, Atelier.muted)
  private let progress = UIProgressView(progressViewStyle: .default)
  private let route = UIStackView()
  private var details: [UIView] = []
  private var expandButton: UIButton!
  private var expanded = false
  private var lightButton: UIButton!
  private var pauseButton: UIButton!
  private var refresh: CADisplayLink?
  private var panStart: SIMD3<Float>?
  private var pinchStart: Double = 0
  private var selected: AtelierSubject?
  private var observers: [NSObjectProtocol] = []

  init() {
    atelier = ShippingAtelierScene(resources: .bundled())
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = atelierHex(0xE9ECEB)
    sceneView.scene = atelier.scene
    sceneView.pointOfView = atelier.cameraNode
    sceneView.delegate = atelier
    sceneView.antialiasingMode = .multisampling4X
    sceneView.preferredFramesPerSecond = 60
    sceneView.rendersContinuously = true
    sceneView.isPlaying = true
    sceneView.backgroundColor = .clear
    sceneView.technique = atelier.technique(for: atelier.lighting)
    sceneView.accessibilityIdentifier = "atelier.scene"
    sceneView.isAccessibilityElement = true
    sceneView.accessibilityLabel = "Участок отгрузки, демонстрация"
    sceneView.accessibilityHint = "Перемещайте одним пальцем, масштабируйте двумя. Выберите партию или погрузчик."
    view.pin(sceneView)
    let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
    pan.maximumNumberOfTouches = 1
    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
    [tap, pan, pinch].forEach {
      $0.delegate = self
      sceneView.addGestureRecognizer($0)
    }
    makeHeader()
    makeCard()
    makeZoom()
    sceneView.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "Выбрать партию") { [weak self] _ in self?.choose(.batch); return true },
      UIAccessibilityCustomAction(name: "Выбрать погрузчик") { [weak self] _ in self?.choose(.forklift); return true },
      UIAccessibilityCustomAction(name: "Выбрать фуру") { [weak self] _ in self?.choose(.truck); return true },
      UIAccessibilityCustomAction(name: "Переключить день и ночь") { [weak self] _ in self?.toggleLight(); return true },
      UIAccessibilityCustomAction(name: "Приблизить") { [weak self] _ in self?.zoom(by: 0.75); return true },
      UIAccessibilityCustomAction(name: "Отдалить") { [weak self] _ in self?.zoom(by: 1 / 0.75); return true },
    ]
    if !atelier.loadedKit {
      cardTitle.text = "Ресурсы участка не найдены"
      cardStatus.text = "InsightAssets отсутствует в сборке"
    }
    let args = ProcessInfo.processInfo.arguments
    if args.contains("-shipping-atelier-night") {
      atelier.setLighting(.night, animated: false)
    }
    // QA: `-shipping-atelier-time 20.5` freezes the demonstration at that second (any cycle);
    // `-shipping-atelier-paused` starts paused at the beginning.
    if let i = args.firstIndex(of: "-shipping-atelier-time"), i + 1 < args.count, let t = Double(args[i + 1]) {
      atelier.show(time: t)
      atelier.paused = true
    } else if args.contains("-shipping-atelier-paused") {
      atelier.paused = true
    }
    updateLightButton()
    if atelier.paused {
      pauseButton.configuration?.image = UIImage(systemName: "play")
      pauseButton.accessibilityLabel = "Продолжить демонстрацию"
    }
    updateCard()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    resume()
    if observers.isEmpty {
      let center = NotificationCenter.default
      observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
        [weak self] _ in self?.suspend()
      })
      observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
        [weak self] _ in
        guard let self, self.view.window != nil else { return }
        self.resume()
      })
    }
    // Reduce Motion: the demonstration waits for an explicit play.
    if UIAccessibility.isReduceMotionEnabled && !atelier.paused {
      atelier.paused = true
      pauseButton.configuration?.image = UIImage(systemName: "play")
      pauseButton.accessibilityLabel = "Продолжить демонстрацию"
    }
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    suspend()
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  /// Hidden or in the background: no GPU work, no card refresh. The demonstration clock simply
  /// stops (the renderer advances it), so it resumes exactly where it was — no jump.
  private func suspend() {
    refresh?.invalidate()
    refresh = nil
    sceneView.rendersContinuously = false
    sceneView.isPlaying = false
    atelier.resetClock()
  }
  private func resume() {
    atelier.resetClock()
    sceneView.isPlaying = true
    sceneView.rendersContinuously = true
    guard refresh == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 8, preferred: 6)
    link.add(to: .main, forMode: .common)
    refresh = link
  }

  // MARK: Header

  private func makeHeader() {
    let back = iconButton("chevron.left", "Назад") { [weak self] in
      self?.navigationController?.popViewController(animated: true)
    }
    let name = label("Отгрузка", 17, .semibold, Atelier.ink)
    name.numberOfLines = 1
    let badge = Atelier.badge("ДЕМО")
    let title = stack([name, badge], axis: .horizontal, spacing: 8)
    title.alignment = .center
    lightButton = iconButton("moon", "Ночь") { [weak self] in self?.toggleLight() }
    lightButton.accessibilityIdentifier = "atelier.light"
    pauseButton = iconButton("pause", "Приостановить демонстрацию") { [weak self] in
      guard let self else { return }
      self.atelier.paused.toggle()
      self.pauseButton.configuration?.image = UIImage(systemName: self.atelier.paused ? "play" : "pause")
      self.pauseButton.accessibilityLabel = self.atelier.paused ? "Продолжить демонстрацию" : "Приостановить демонстрацию"
    }
    let home = iconButton("viewfinder", "Весь участок") { [weak self] in
      guard let self else { return }
      SCNTransaction.begin()
      SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.6
      self.atelier.camera = AtelierCamera()
      SCNTransaction.commit()
    }
    let row = stack([back, title, UIView(), home, lightButton, pauseButton], axis: .horizontal, spacing: 0)
    row.alignment = .center
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    header.contentView.pin(row, inset: 4)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
  }
  private func iconButton(_ icon: String, _ name: String, action: @escaping () -> Void) -> UIButton {
    let b = insideAction("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    b.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    // insideAction() uses the fixed light-theme ink; the overlay follows day/night.
    b.configuration?.baseForegroundColor = Atelier.ink
    return b
  }
  private func toggleLight() {
    let next: AtelierLighting = atelier.lighting == .day ? .night : .day
    atelier.setLighting(next, animated: !UIAccessibility.isReduceMotionEnabled)
    updateLightButton()
  }
  /// Day: light glass and ink text; night: dark glass and light text (the same dynamic colours,
  /// switched by the interface style of the overlay).
  private func updateLightButton() {
    let night = atelier.lighting == .night
    sceneView.technique = atelier.technique(for: atelier.lighting)
    lightButton.configuration?.image = UIImage(systemName: night ? "sun.max" : "moon")
    lightButton.accessibilityLabel = night ? "День" : "Ночь"
    for glass in [header, card, zoomBar] {
      glass.overrideUserInterfaceStyle = night ? .dark : .light
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = night ? UIColor(white: 0.04, alpha: 0.55) : nil
      effect.isInteractive = true
      glass.effect = effect
    }
    progress.progressTintColor = night ? UIColor(white: 0.95, alpha: 1) : InsideStyle.ink
    progress.trackTintColor = (night ? UIColor.white : InsideStyle.ink).withAlphaComponent(0.15)
    UIView.animate(withDuration: 0.6) {
      self.view.backgroundColor = night ? atelierHex(0x0C1217) : atelierHex(0xE9ECEB)
    }
    updateCard()
  }

  // MARK: Zoom

  private func makeZoom() {
    let plus = iconButton("plus", "Приблизить") { [weak self] in self?.zoom(by: 0.75) }
    let minus = iconButton("minus", "Отдалить") { [weak self] in self?.zoom(by: 1 / 0.75) }
    plus.accessibilityIdentifier = "atelier.zoomIn"
    minus.accessibilityIdentifier = "atelier.zoomOut"
    let column = stack([plus, minus], spacing: 0)
    zoomBar.rounded(22)
    zoomBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(zoomBar)
    zoomBar.contentView.pin(column, inset: 0)
    NSLayoutConstraint.activate([
      zoomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      zoomBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
    ])
  }
  private func zoom(by factor: Double) {
    var cam = atelier.camera
    cam.scale *= factor
    cam.clamp()
    SCNTransaction.begin()
    SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.3
    atelier.camera = cam
    SCNTransaction.commit()
  }

  // MARK: Card

  private func makeCard() {
    route.axis = .horizontal
    route.spacing = 6
    route.distribution = .fillEqually
    for step in ["Контроль", "Погрузчик", "Док 02", "Фура"] {
      let l = label(step, 11, .medium, Atelier.muted)
      l.textAlignment = .center
      route.addArrangedSubview(l)
    }
    // A compact board: one line by default, details on demand (or when something is chosen).
    expandButton = iconButton("chevron.up", "Показать подробности") { [weak self] in
      guard let self else { return }
      self.setExpanded(!self.expanded)
    }
    expandButton.accessibilityIdentifier = "atelier.expand"
    cardTitle.numberOfLines = 2
    let top = stack([stack([cardEyebrow, cardTitle], spacing: 3), UIView(), expandButton], axis: .horizontal, spacing: 8)
    top.alignment = .center
    details = [cardStatus, progress, route, cardNote]
    let content = stack([top] + details, spacing: 9)
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)
    card.contentView.pin(content, inset: 14)
    setExpanded(false, animated: false)
    card.accessibilityIdentifier = "atelier.card"
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
    ])
  }
  @objc private func tick() { updateCard() }

  private func setExpanded(_ value: Bool, animated: Bool = true) {
    expanded = value
    expandButton.configuration?.image = UIImage(systemName: value ? "chevron.down" : "chevron.up")
    expandButton.accessibilityLabel = value ? "Свернуть подробности" : "Показать подробности"
    let change = { self.details.forEach { $0.isHidden = !value; $0.alpha = value ? 1 : 0 } }
    if animated && !UIAccessibility.isReduceMotionEnabled {
      UIView.animate(withDuration: 0.25, animations: { change(); self.view.layoutIfNeeded() })
    } else {
      change()
    }
    if value { updateCard() }
  }

  private func updateCard() {
    let p = atelier.pose
    let showsRoute = selected == .batch || selected == nil
    if expanded {
      route.isHidden = !showsRoute
      progress.isHidden = selected == .truck
    }
    switch selected {
    case .batch?:
      cardEyebrow.text = "ПАРТИЯ"
      cardTitle.text = "Партия D-\(p.batchNumber) · Alda 160×70"
      cardStatus.text = "2 изделия в упаковке · \(p.stage.batchText)"
      progress.setProgress(Float(p.progress), animated: false)
    case .forklift?:
      cardEyebrow.text = "ПОГРУЗЧИК"
      cardTitle.text = "Погрузчик F-02"
      cardStatus.text = p.stage.forkliftText + (p.stage == .waiting ? "" : " · партия D-\(p.batchNumber)")
      progress.setProgress(Float(p.progress), animated: false)
    case .truck?:
      cardEyebrow.text = "ФУРА"
      let slots = atelier.layout.slots.count
      cardTitle.text = "Рейс 02 · " + p.truck.text
      switch p.truck {
      case .docked:
        cardStatus.text = "Загружено \(p.inTruck) из \(slots) мест · отправка после полной загрузки"
      case .departing, .away:
        cardStatus.text = "\(slots) из \(slots) мест · следующая партия поедет в новую фуру"
      case .arriving:
        cardStatus.text = "Пустая фура · 0 из \(slots) мест"
      }
    case nil:
      cardEyebrow.text = "УЧАСТОК"
      cardTitle.text = "Партия D-\(p.batchNumber) · \(p.stage.batchText)"
      cardStatus.text = "Нажмите на партию, погрузчик или фуру"
      progress.setProgress(Float(p.progress), animated: false)
    }
    for (k, v) in route.arrangedSubviews.enumerated() {
      (v as? UILabel)?.textColor = k <= p.stage.routeStep ? Atelier.ink : Atelier.muted.withAlphaComponent(0.6)
    }
    card.accessibilityLabel = [cardTitle.text, cardStatus.text].compactMap { $0 }.joined(separator: ". ")
  }

  private func choose(_ subject: AtelierSubject?) {
    selected = subject
    atelier.select(subject)
    UISelectionFeedbackGenerator().selectionChanged()
    if subject != nil && !expanded { setExpanded(true) }
    updateCard()
  }

  // MARK: Gestures

  /// The ground point (at the hall floor height) under a screen point.
  private func ground(_ point: CGPoint) -> SIMD3<Float>? {
    let near = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
    let far = sceneView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
    let a = SIMD3<Float>(near.x, near.y, near.z), b = SIMD3<Float>(far.x, far.y, far.z)
    let h = atelier.layout.floor
    guard abs(b.y - a.y) > 1e-4 else { return nil }
    let t = (h - a.y) / (b.y - a.y)
    return a + (b - a) * t
  }
  @objc private func tap(_ g: UITapGestureRecognizer) {
    let point = g.location(in: sceneView)
    let hits = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
    let subject = hits.lazy.compactMap { self.atelier.subject(of: $0.node) }.first
    choose(subject)
  }
  @objc private func pan(_ g: UIPanGestureRecognizer) {
    let point = g.location(in: sceneView)
    switch g.state {
    case .began:
      panStart = ground(point)
    case .changed:
      guard let start = panStart, let now = ground(point) else { return }
      var cam = atelier.camera
      cam.focus += SIMD3(start.x - now.x, 0, start.z - now.z)
      cam.clamp()
      atelier.camera = cam
    default:
      panStart = nil
    }
  }
  @objc private func pinch(_ g: UIPinchGestureRecognizer) {
    switch g.state {
    case .began:
      pinchStart = atelier.camera.scale
    case .changed:
      var cam = atelier.camera
      cam.scale = pinchStart / Double(max(0.1, g.scale))
      cam.clamp()
      atelier.camera = cam
    default: break
    }
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    (g is UIPinchGestureRecognizer) != (other is UIPinchGestureRecognizer)
  }
}

/// The visible way into the proof from Salini Inside.
final class ShippingAtelierEntry: UIControl {
  init() {
    super.init(frame: .zero)
    let glass = GlassView()
    glass.isUserInteractionEnabled = false
    glass.rounded(20)
    let icon = UIImageView(image: UIImage(systemName: "shippingbox"))
    icon.tintColor = InsideStyle.ink
    icon.setContentHuggingPriority(.required, for: .horizontal)
    let text = stack(
      [label("Участок отгрузки", 13, .semibold, InsideStyle.ink), label("3D · демонстрация", 11, .regular, InsideStyle.muted)],
      spacing: 1)
    let row = stack([icon, text], axis: .horizontal, spacing: 8)
    row.alignment = .center
    row.isUserInteractionEnabled = false
    pin(glass)
    glass.contentView.pin(row, inset: 10)
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityLabel = "Участок отгрузки, 3D демонстрация"
    accessibilityIdentifier = "insight.atelier"
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
}

/// Overlay colours that follow the overlay's interface style (light glass by day, dark at night).
@MainActor enum Atelier {
  static let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.97, alpha: 1) : InsideStyle.ink }
  static let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.78, alpha: 1) : InsideStyle.muted }
  static let accent = UIColor { $0.userInterfaceStyle == .dark ? atelierHex(0xB9D3EA) : InsideStyle.blue }
  /// The compact «ДЕМО» capsule in the header.
  static func badge(_ text: String) -> UIView {
    let l = label(text, 10, .semibold, accent)
    l.numberOfLines = 1
    l.attributedText = NSAttributedString(string: text, attributes: [.kern: 1.4, .font: l.font as Any])
    l.textColor = accent
    let pill = UIView()
    pill.layer.cornerRadius = 9
    pill.layer.borderWidth = 1
    pill.layer.borderColor = accent.withAlphaComponent(0.5).cgColor
    pill.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (v: UIView, _: UITraitCollection) in
      v.layer.borderColor = accent.withAlphaComponent(0.5).resolvedColor(with: v.traitCollection).cgColor
    }
    l.translatesAutoresizingMaskIntoConstraints = false
    pill.addSubview(l)
    NSLayoutConstraint.activate([
      pill.heightAnchor.constraint(equalToConstant: 18),
      l.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
      l.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
      l.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
    ])
    pill.isAccessibilityElement = true
    pill.accessibilityLabel = "Демонстрация"
    pill.setContentHuggingPriority(.required, for: .horizontal)
    return pill
  }
}
