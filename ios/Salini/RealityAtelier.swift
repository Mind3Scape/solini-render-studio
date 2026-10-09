import Combine
import RealityKit
import UIKit

/// «Отгрузка» in RealityKit 27: the live shipping section (the same demonstration timeline as
/// the SceneKit screen, which stays only as the QA fallback, `-shipping-atelier`). The camera
/// follows the selected live subject — the batch on entry — gently; tapping the batch, the
/// forklift or the truck selects, frames and follows it. Pan, pinch (zoom) and two-finger
/// rotation (orbit) take the camera over and stop following; «К действию» resumes it. Chips jump
/// to quality control, packing, shipping or the whole section. Day / night in the header.
/// Opened from Insight or with `-shipping-atelier-reality`; diagnostics only with
/// `-reality-diagnostics`.
final class RealityAtelierController: UIViewController, UIGestureRecognizerDelegate {
  private var arView: ARView!
  private var atelier: RealityAtelierScene?
  private var update: Cancellable?
  private let header = GlassView()
  private let card = GlassView()
  private let cardEyebrow = eyebrow("УЧАСТОК", color: Atelier.accent)
  private let cardTitle = label("Загрузка участка…", 16, .semibold, Atelier.ink)
  private let cardStatus = label("", 13, .regular, Atelier.muted)
  private let cardNote = label("Демонстрация: движение и статусы смоделированы, это не телеметрия завода.", 11, .regular, Atelier.muted)
  private let progress = UIProgressView(progressViewStyle: .default)
  private var zoneButtons: [UIButton] = []
  private var pauseButton: UIButton!
  private var lightButton: UIButton!
  private let followGlass = GlassView()
  /// «Разрез»: shown while the trailer body is ghosted to show the followed batch inside.
  private let cutGlass = GlassView()
  /// The subject the camera follows (nil: the user's own camera) and the scale it eases to.
  private var following: AtelierSubject?
  private var followScale: Float?
  private var lighting: AtelierLighting = .day
  private var selected: AtelierSubject?
  private var demoTime: Double = 0
  /// QA (`-shipping-atelier-speed`): slow-motion inspection of the handling.
  private var speed: Double = 1
  private var paused = false
  private var panStart: SIMD3<Float>?
  private var pinchStart: Float = 0
  private var rotateStart: Float = 0
  private var lastCard: TimeInterval = 0
  private let args = ProcessInfo.processInfo.arguments
  /// One camera flight at a time; any new command, gesture or leaving the screen stops it.
  private var flight: Timer?
  private var loadTask: Task<Void, Never>?
  private var observers: [NSObjectProtocol] = []
  /// The first frame after a resume does not advance the demonstration (no jump).
  private var skipNextStep = true
  /// Opening: a working moment of the cycle (batch on its way to the dock) at the shipping view.
  static let openingTime: Double = 19

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = atelierHex(0xE4E7EA)
    arView = ARView(frame: view.bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
    arView.environment.background = .color(atelierHex(0xE4E7EA))
    arView.renderOptions.formUnion([.disableMotionBlur, .disableCameraGrain, .disableAREnvironmentLighting])
    arView.accessibilityIdentifier = "reality.scene"
    arView.isAccessibilityElement = true
    arView.accessibilityLabel = "Отгрузка, демонстрация"
    arView.accessibilityHint = "Камера следует за выбранным объектом. Перемещайте одним пальцем, масштабируйте и поворачивайте двумя. Выберите партию, погрузчик или фуру."
    view.pin(arView)
    demoTime = Self.openingTime
    let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
    pan.maximumNumberOfTouches = 1
    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
    let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
    [tap, pan, pinch, rotate].forEach {
      $0.delegate = self
      arView.addGestureRecognizer($0)
    }
    makeHeader()
    makeCard()
    makeFollowButton()
    makeCutBadge()
    arView.accessibilityCustomActions = RealityAtelierScene.Zone.allCases.map { zone in
      UIAccessibilityCustomAction(name: "Показать: \(zone.title)") { [weak self] _ in self?.show(zone); return true }
    } + [
      UIAccessibilityCustomAction(name: "Приблизить") { [weak self] _ in self?.nudge(scale: 0.75); return true },
      UIAccessibilityCustomAction(name: "Отдалить") { [weak self] _ in self?.nudge(scale: 1 / 0.75); return true },
      UIAccessibilityCustomAction(name: "Повернуть влево") { [weak self] _ in self?.nudge(azimuth: -20); return true },
      UIAccessibilityCustomAction(name: "Повернуть вправо") { [weak self] _ in self?.nudge(azimuth: 20); return true },
      UIAccessibilityCustomAction(name: "Выбрать партию") { [weak self] _ in self?.choose(.batch); return true },
      UIAccessibilityCustomAction(name: "Выбрать погрузчик") { [weak self] _ in self?.choose(.forklift); return true },
      UIAccessibilityCustomAction(name: "Выбрать фуру") { [weak self] _ in self?.choose(.truck); return true },
      UIAccessibilityCustomAction(name: "К действию") { [weak self] _ in self?.resumeFollowing(); return true },
      UIAccessibilityCustomAction(name: "Переключить день и ночь") { [weak self] _ in self?.toggleLight(); return true },
    ]
    paused = UIAccessibility.isReduceMotionEnabled
    if let i = args.firstIndex(of: "-shipping-atelier-time"), i + 1 < args.count, let t = Double(args[i + 1]) {
      demoTime = t
      paused = !args.contains("-shipping-atelier-play")
    }
    if let i = args.firstIndex(of: "-reality-exposure"), i + 1 < args.count, let e = Float(args[i + 1]) {
      RealityAtelierScene.exposure = e
    }
    updatePauseButton()
    loadTask = Task { [weak self] in await self?.load() }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.suspend() }
    })
    observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated {
        guard let self, self.view.window != nil else { return }
        self.resume()
      }
    })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    resume()
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    suspend()
    if isMovingFromParent {
      loadTask?.cancel()
      loadTask = nil
    }
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  /// Hidden or in the background: no per-frame work and no camera flight; the demonstration
  /// time simply stops and continues from the same moment.
  private func suspend() {
    update?.cancel()
    update = nil
    flight?.invalidate()
    flight = nil
  }
  private func resume() {
    guard update == nil, atelier != nil else { return }
    skipNextStep = true
    update = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
      MainActor.assumeIsolated { self?.step(event.deltaTime) }
    }
  }

  /// `-reality-perf`: load time and frame pacing (SceneEvents.Update intervals, the CPU time of
  /// the per-frame pose) written to tmp/reality-perf.json after 60 s. Simulator numbers are
  /// host-GPU numbers, not device FPS.
  private var perf: (start: CFTimeInterval, loaded: Double, frames: [Double], apply: [Double])?
  private func recordPerf(dt: Double, apply: Double) {
    guard var p = perf else { return }
    p.frames.append(dt)
    p.apply.append(apply)
    perf = p
    guard p.frames.count >= 3600 || CACurrentMediaTime() - p.start > 75 else { return }
    perf = nil
    let f = p.frames.dropFirst(30).sorted(), a = p.apply.sorted()
    func q(_ v: [Double], _ x: Double) -> Double { v.isEmpty ? 0 : v[min(v.count - 1, Int(Double(v.count) * x))] }
    let report: [String: Any] = [
      "load_seconds": p.loaded, "frames": f.count, "mean_frame_ms": f.reduce(0, +) / Double(max(1, f.count)) * 1000,
      "p50_frame_ms": q(f, 0.5) * 1000, "p95_frame_ms": q(f, 0.95) * 1000, "p99_frame_ms": q(f, 0.99) * 1000,
      "max_frame_ms": (f.last ?? 0) * 1000, "frames_over_25ms": f.filter { $0 > 0.025 }.count,
      "apply_p50_ms": q(a, 0.5) * 1000, "apply_p99_ms": q(a, 0.99) * 1000,
      "device": UIDevice.current.model, "system": UIDevice.current.systemVersion,
      "simulator": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "no",
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("reality-perf.json"))
    }
  }

  private func load() async {
    let loadStart = CACurrentMediaTime()
    guard let folder = Bundle.main.url(forResource: "InsightAssets", withExtension: nil) else {
      cardTitle.text = "Ресурсы участка не найдены"
      return
    }
    let models = Bundle.main.url(forResource: "CatalogMedia", withExtension: nil)?.appendingPathComponent("models")
    let scene = RealityAtelierScene(folder: folder, models: models)
    do {
      try await scene.load()
      if args.contains("-reality-probe-test") { scene.addProbeTestObjects() }
      let anchor = AnchorEntity(world: .zero)
      anchor.addChild(scene.root)
      arView.scene.addAnchor(anchor)
      if Task.isCancelled { return }
      atelier = scene
      scene.apply(scene.timeline.pose(at: demoTime))
      view.layoutIfNeeded()
      follow(.batch, animated: false)
      if args.contains("-shipping-atelier-night") { setLighting(.night) }
      // QA: a reproducible camera — a zone (manual view) or a selected, followed subject.
      if let i = args.firstIndex(of: "-reality-select"), i + 1 < args.count {
        let subject: AtelierSubject? = ["batch": .batch, "forklift": .forklift, "truck": .truck][args[i + 1]]
        if let subject { follow(subject, animated: false) }
      }
      if let i = args.firstIndex(of: "-reality-scale"), i + 1 < args.count, let v = Float(args[i + 1]) {
        followScale = nil
        scene.scale = v
      }
      if let i = args.firstIndex(of: "-reality-azimuth"), i + 1 < args.count, let v = Float(args[i + 1]) {
        scene.azimuth = v
      }
      if let i = args.firstIndex(of: "-shipping-atelier-speed"), i + 1 < args.count, let v = Double(args[i + 1]) {
        speed = max(0.05, min(4, v))
      }
      if let i = args.firstIndex(of: "-reality-zone"), i + 1 < args.count,
        let zone = RealityAtelierScene.Zone(rawValue: args[i + 1])
      {
        show(zone, animated: false)
      }
      if args.contains("-reality-perf") { perf = (CACurrentMediaTime(), CACurrentMediaTime() - loadStart, [], []) }
      if args.contains("-reality-diagnostics") { makeDiagnostics(scene) }
      if view.window != nil { resume() }
      updateCard()
    } catch {
      cardTitle.text = "Участок не загрузился"
      cardStatus.text = error.localizedDescription
    }
  }

  private func step(_ dt: TimeInterval) {
    guard let scene = atelier else { return }
    if skipNextStep {
      skipNextStep = false
    } else if !paused {
      demoTime += min(dt, 0.1) * speed
    }
    let t0 = CACurrentMediaTime()
    scene.apply(scene.timeline.pose(at: demoTime))
    if perf != nil { recordPerf(dt: dt, apply: CACurrentMediaTime() - t0) }
    track(scene, dt: Float(min(dt, 0.1)))
    updateCut(scene)
    let now = CACurrentMediaTime()
    if now - lastCard > 0.2 {
      lastCard = now
      updateCard()
    }
  }

  // MARK: Header: title, demo badge, play/pause, zones

  private func iconButton(_ icon: String, _ name: String, action: @escaping () -> Void) -> UIButton {
    let b = insideAction("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    b.configuration?.baseForegroundColor = Atelier.ink
    return b
  }
  private func makeHeader() {
    let back = iconButton("chevron.left", "Назад") { [weak self] in self?.navigationController?.popViewController(animated: true) }
    let name = label("Отгрузка", 17, .semibold, Atelier.ink)
    name.numberOfLines = 1
    let title = stack([name, Atelier.badge("ДЕМО")], axis: .horizontal, spacing: 8)
    title.alignment = .center
    pauseButton = iconButton("pause", "Приостановить демонстрацию") { [weak self] in
      guard let self else { return }
      self.paused.toggle()
      self.updatePauseButton()
    }
    pauseButton.accessibilityIdentifier = "reality.pause"
    lightButton = iconButton("moon", "Ночь") { [weak self] in self?.toggleLight() }
    lightButton.accessibilityIdentifier = "reality.light"
    let row = stack([back, title, UIView(), lightButton, pauseButton], axis: .horizontal, spacing: 0)
    row.alignment = .center
    let chips = stack(RealityAtelierScene.Zone.allCases.map { zone in
      let b = UIButton(type: .system)
      var c = UIButton.Configuration.plain()
      c.title = zone.title
      c.baseForegroundColor = Atelier.ink
      c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var v = $0
        v.font = .systemFont(ofSize: 13, weight: .medium)
        return v
      }
      b.configuration = c
      b.accessibilityIdentifier = "reality.zone.\(zone.rawValue)"
      b.addAction(UIAction { [weak self] _ in self?.show(zone) }, for: .touchUpInside)
      zoneButtons.append(b)
      return b
    }, axis: .horizontal, spacing: 0)
    chips.distribution = .fillProportionally
    let content = stack([row, chips], spacing: 2)
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    header.contentView.pin(content, inset: 6)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    ])
  }
  private func updatePauseButton() {
    pauseButton?.configuration?.image = UIImage(systemName: paused ? "play" : "pause")
    pauseButton?.accessibilityLabel = paused ? "Продолжить демонстрацию" : "Приостановить демонстрацию"
  }
  private func nudge(scale factor: Float = 1, azimuth delta: Float = 0) {
    guard let scene = atelier else { return }
    flight?.invalidate()
    flight = nil
    stopFollowing()
    scene.scale *= factor
    scene.azimuth += delta
  }
  private func show(_ zone: RealityAtelierScene.Zone, animated: Bool = true) {
    guard let scene = atelier else { return }
    flight?.invalidate()
    flight = nil
    stopFollowing()
    let v = zone.view
    highlight(zone)
    if !animated || UIAccessibility.isReduceMotionEnabled {
      scene.focus = v.focus
      scene.scale = v.scale
      return
    }
    // A short eased flight of focus and scale (the orbit angle stays as the user left it).
    let from = (scene.focus, scene.scale)
    let start = CACurrentMediaTime()
    flight = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        guard let self, let scene = self.atelier else { return timer.invalidate() }
        let u = Float(min(1, (CACurrentMediaTime() - start) / 0.6))
        let e = u * u * (3 - 2 * u)
        scene.focus = from.0 + (v.focus - from.0) * e
        scene.scale = from.1 + (v.scale - from.1) * e
        if u >= 1 {
          timer.invalidate()
          self.flight = nil
        }
      }
    }
  }

  // MARK: Card

  private func makeCard() {
    progress.progressTintColor = InsideStyle.ink
    progress.trackTintColor = InsideStyle.ink.withAlphaComponent(0.12)
    cardTitle.numberOfLines = 2
    let content = stack([cardEyebrow, cardTitle, cardStatus, progress, cardNote], spacing: 6)
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)
    card.contentView.pin(content, inset: 14)
    card.accessibilityIdentifier = "reality.card"
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
    ])
  }
  private func updateCard() {
    guard let scene = atelier else { return }
    let p = scene.pose
    let slots = scene.layout.slots.count
    progress.isHidden = selected == .truck
    progress.setProgress(Float(p.progress), animated: false)
    switch selected {
    case .batch?:
      cardEyebrow.text = "ЗАКАЗ 1427 · ПАРТИЯ"
      cardTitle.text = "Партия D-\(p.batchNumber) · \(p.stage.batchText)"
      cardStatus.text = "Alda 160×70, 2 изделия · загружено \(p.inTruck) из \(slots) мест"
    case .forklift?:
      cardEyebrow.text = "ПОГРУЗЧИК"
      cardTitle.text = "Погрузчик F-02"
      cardStatus.text = p.stage.forkliftText + (p.stage == .waiting ? "" : " · партия D-\(p.batchNumber)")
    case .truck?:
      cardEyebrow.text = "ФУРА"
      cardTitle.text = "Рейс 02 · " + p.truck.text
      switch p.truck {
      case .docked: cardStatus.text = "Загружено \(p.inTruck) из \(slots) мест · отправка после полной загрузки"
      case .departing, .away: cardStatus.text = "\(slots) из \(slots) мест · следующая партия поедет в новую фуру"
      case .arriving: cardStatus.text = "Пустая фура · 0 из \(slots) мест"
      }
    case nil:
      cardEyebrow.text = "ЗАКАЗ 1427 · РЕЙС 02"
      cardTitle.text = "Партия D-\(p.batchNumber) · \(p.stage.batchText)"
      cardStatus.text = "Загружено \(p.inTruck) из \(slots) мест · нажмите на партию, погрузчик или фуру"
    }
    card.accessibilityLabel = [cardTitle.text, cardStatus.text].compactMap { $0 }.joined(separator: ". ")
  }
  private func choose(_ subject: AtelierSubject?) {
    UISelectionFeedbackGenerator().selectionChanged()
    if let subject {
      follow(subject, animated: true)
    } else {
      selected = nil
      atelier?.select(nil)
      stopFollowing()
      updateCard()
    }
  }

  // MARK: Following the live subject

  /// The free band of the screen between the header and the card (fractions of the height).
  private var band: (aspect: Float, top: Float, bottom: Float) {
    let b = arView.bounds
    guard b.height > 0 else { return (0.46, 0.17, 0.22) }
    let top = Float((header.frame.maxY + 8) / b.height)
    let bottom = Float((b.height - card.frame.minY + 8) / b.height)
    return (Float(b.width / b.height), min(0.4, top), min(0.45, bottom))
  }
  /// Selects a subject and lets the camera frame it (fit to the free band) and follow it.
  private func follow(_ subject: AtelierSubject, animated: Bool) {
    guard let scene = atelier else { return }
    flight?.invalidate()
    flight = nil
    selected = subject
    scene.select(subject)
    following = subject
    highlight(nil)
    let b = band
    let fit = scene.fitScale(subject, aspect: b.aspect, top: b.top, bottom: b.bottom)
    if animated && !UIAccessibility.isReduceMotionEnabled {
      followScale = fit
    } else {
      followScale = nil
      scene.scale = fit
      scene.focus = scene.followFocus(subject, top: b.top, bottom: b.bottom)
    }
    updateFollowButton()
    updateCard()
  }
  private func stopFollowing() {
    guard following != nil || followScale != nil else { return }
    following = nil
    followScale = nil
    updateFollowButton()
  }
  private func resumeFollowing() {
    follow(selected ?? .batch, animated: true)
  }
  /// Per frame: ease the focus (and the framing scale) towards the followed subject. A gentle
  /// critically damped approach with a speed limit, so a new batch at the pickup is reached in
  /// a calm pan, not a jump; with Reduce Motion the camera simply stays on it.
  private func track(_ scene: RealityAtelierScene, dt: Float) {
    guard let subject = following, dt > 0 else { return }
    let b = band
    let reduce = UIAccessibility.isReduceMotionEnabled
    let k = reduce ? 1 : 1 - exp(-dt / 0.45)
    if let target = followScale {
      scene.scale += (target - scene.scale) * k
      if abs(target - scene.scale) < 0.01 { followScale = nil }
    }
    var delta = (scene.followFocus(subject, top: b.top, bottom: b.bottom) - scene.focus) * k
    let limit = 9 * dt
    if !reduce, simd_length(delta) > limit { delta *= limit / simd_length(delta) }
    if simd_length(delta) > 1e-4 { scene.focus += delta }
  }
  private func makeFollowButton() {
    let b = insideAction("К действию", icon: "scope") { [weak self] in self?.resumeFollowing() }
    b.configuration?.baseForegroundColor = Atelier.ink
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
    b.configuration?.imagePlacement = .leading
    b.accessibilityIdentifier = "reality.follow"
    b.accessibilityHint = "Камера снова следует за выбранным объектом"
    followGlass.rounded(22)
    followGlass.translatesAutoresizingMaskIntoConstraints = false
    followGlass.contentView.pin(b, inset: 0)
    followGlass.isHidden = true
    view.addSubview(followGlass)
    NSLayoutConstraint.activate([
      followGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      followGlass.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -10),
    ])
  }
  private func updateFollowButton() {
    let hide = following != nil
    guard followGlass.isHidden != hide else { return }
    if UIAccessibility.isReduceMotionEnabled {
      followGlass.isHidden = hide
      return
    }
    followGlass.alpha = hide ? 1 : 0
    followGlass.isHidden = false
    UIView.animate(withDuration: 0.25, animations: { self.followGlass.alpha = hide ? 0 : 1 }) { _ in
      self.followGlass.isHidden = self.following != nil
      self.followGlass.alpha = 1
    }
  }
  /// Section cut: only while the camera follows the batch inside the docked trailer; in any
  /// other view the trailer keeps its body.
  private func updateCut(_ scene: RealityAtelierScene) {
    let cut = following == .batch && scene.batchInTrailer
    guard cut != scene.trailerCut else { return }
    scene.setTrailerCut(cut)
    cutGlass.isHidden = !cut
    if cut { UIAccessibility.post(notification: .announcement, argument: "Разрез: кузов прицепа прозрачный, груз виден") }
  }
  private func makeCutBadge() {
    let icon = UIImageView(image: UIImage(systemName: "square.split.diagonal"))
    icon.tintColor = Atelier.ink
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    let text = label("Разрез · кузов прицепа прозрачный", 12, .medium, Atelier.ink)
    text.numberOfLines = 1
    let row = stack([icon, text], axis: .horizontal, spacing: 6)
    row.alignment = .center
    cutGlass.rounded(15)
    cutGlass.translatesAutoresizingMaskIntoConstraints = false
    cutGlass.contentView.pin(row, inset: 8)
    cutGlass.isHidden = true
    cutGlass.isAccessibilityElement = true
    cutGlass.accessibilityLabel = "Разрез: кузов прицепа показан прозрачным, чтобы был виден груз"
    cutGlass.accessibilityIdentifier = "reality.cut"
    view.addSubview(cutGlass)
    NSLayoutConstraint.activate([
      cutGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      cutGlass.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
    ])
  }
  private func highlight(_ zone: RealityAtelierScene.Zone?) {
    for (b, z) in zip(zoneButtons, RealityAtelierScene.Zone.allCases) {
      b.configuration?.baseForegroundColor = z == zone ? Atelier.accent : Atelier.ink
    }
  }

  // MARK: Day / night

  private func toggleLight() {
    setLighting(lighting == .day ? .night : .day)
  }
  /// Night: the scene swaps every light owner; the overlay turns to dark glass and light text.
  private func setLighting(_ mode: AtelierLighting) {
    guard let scene = atelier else { return }
    lighting = mode
    let night = mode == .night
    lightButton.configuration?.image = UIImage(systemName: night ? "sun.max" : "moon")
    lightButton.accessibilityLabel = night ? "День" : "Ночь"
    for glass in [header, card, followGlass, cutGlass] {
      glass.overrideUserInterfaceStyle = night ? .dark : .light
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = night ? UIColor(white: 0.04, alpha: 0.55) : nil
      effect.isInteractive = true
      glass.effect = effect
    }
    progress.progressTintColor = night ? UIColor(white: 0.95, alpha: 1) : InsideStyle.ink
    progress.trackTintColor = (night ? UIColor.white : InsideStyle.ink).withAlphaComponent(0.15)
    let background = night ? atelierHex(0x0C1217) : atelierHex(0xE4E7EA)
    arView.environment.background = .color(background)
    view.backgroundColor = background
    Task { await scene.setLighting(mode) }
  }

  // MARK: Gestures

  private func ground(_ point: CGPoint) -> SIMD3<Float>? {
    guard let ray = arView.ray(through: point), let scene = atelier else { return nil }
    let h = scene.layout.floor
    guard abs(ray.direction.y) > 1e-4 else { return nil }
    let t = (h - ray.origin.y) / ray.direction.y
    return t > 0 ? ray.origin + ray.direction * t : nil
  }
  @objc private func tap(_ g: UITapGestureRecognizer) {
    guard let scene = atelier else { return }
    let hit = arView.entity(at: g.location(in: arView))
    choose(hit.flatMap { scene.subject(of: $0) })
  }
  @objc private func pan(_ g: UIPanGestureRecognizer) {
    guard let scene = atelier else { return }
    if g.state == .began { flight?.invalidate(); flight = nil; stopFollowing() }
    let p = g.location(in: arView)
    switch g.state {
    case .began: panStart = ground(p)
    case .changed:
      guard let start = panStart, let now = ground(p) else { return }
      scene.focus += SIMD3(start.x - now.x, 0, start.z - now.z)
    default: panStart = nil
    }
  }
  @objc private func pinch(_ g: UIPinchGestureRecognizer) {
    guard let scene = atelier else { return }
    if g.state == .began { flight?.invalidate(); flight = nil; stopFollowing() }
    switch g.state {
    case .began: pinchStart = scene.scale
    case .changed: scene.scale = pinchStart / Float(max(0.1, g.scale))
    default: break
    }
  }
  @objc private func rotate(_ g: UIRotationGestureRecognizer) {
    guard let scene = atelier else { return }
    if g.state == .began { flight?.invalidate(); flight = nil; stopFollowing() }
    switch g.state {
    case .began: rotateStart = scene.azimuth
    case .changed: scene.azimuth = rotateStart - Float(g.rotation) * 180 / .pi
    default: break
    }
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    (g is UIPinchGestureRecognizer && other is UIRotationGestureRecognizer)
      || (g is UIRotationGestureRecognizer && other is UIPinchGestureRecognizer)
  }

  // MARK: Diagnostics (launch argument only)

  private func makeDiagnostics(_ scene: RealityAtelierScene) {
    func toggle(_ title: String, _ id: String, _ initial: Bool, _ apply: @escaping (Bool) -> Void) -> UIButton {
      let b = UIButton(type: .system)
      var on = initial
      func style() {
        var c = UIButton.Configuration.plain()
        c.title = (on ? "● " : "○ ") + title
        c.baseForegroundColor = Atelier.ink
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
          var v = $0
          v.font = .systemFont(ofSize: 11, weight: .medium)
          return v
        }
        b.configuration = c
      }
      style()
      b.accessibilityIdentifier = id
      b.addAction(UIAction { _ in on.toggle(); apply(on); style() }, for: .touchUpInside)
      return b
    }
    let d = scene.diagnostics
    let report = label(scene.report.joined(separator: " · "), 9, .regular, Atelier.muted)
    let rows = stack([
      stack([toggle("Лайтмапа", "reality.lightmap", d.lightmap) { scene.setLightmap($0) },
             toggle("Пробы", "reality.probes", d.localProbes) { scene.setLocalProbes($0) },
             toggle("Мягкая тень", "reality.soft", d.softShadow) { scene.setSoftShadow($0) }], axis: .horizontal, spacing: 0),
      stack([toggle("Небо везде", "reality.sky", d.skyEverywhere) { scene.setSkyEverywhere($0) },
             toggle("Солнце", "reality.sun", true) { scene.setSun($0) }], axis: .horizontal, spacing: 0),
      report,
    ], spacing: 0)
    let glass = GlassView()
    glass.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(glass)
    glass.contentView.pin(rows, inset: 6)
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      glass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      glass.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -8),
    ])
  }
}
