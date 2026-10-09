import SceneKit
import UIKit

/// Home feature «Камень изнутри»: the two Salini materials cut open — S-Stone one homogeneous
/// mass through its thickness, S-Sense a mineral core under Gelcoat (lifted off as an exploded
/// layer) — beside the raw minerals they start from. A live SceneKit scene on a transparent view
/// whose samples rise above the card into the block's own reserved top margin (never over the
/// copy or neighbouring cards). The CTA opens the material studio on a form that sells the
/// chosen finish.
///
/// Integration (Codex): `EssenceFeatureView(open:)` replaces `MaterialFeatureView` on Home; set
/// `active` from the host's visibility (scrolling offscreen, tab switch); the view also pauses by
/// itself when it leaves the window or the app goes to the background.
final class EssenceFeatureView: UIView {
  private(set) var finish: StudioFinish = .stoneMatte
  /// The host's visibility: when false nothing animates and no frames are drawn.
  var active = true {
    didSet { updatePlaying() }
  }
  /// The layered 2.5D stage when its fragments are bundled, otherwise the procedural 3D stage.
  private let stage: EssenceStage = {
    let layers = EssenceLayers.resolved(EssenceLayers.manifest())
    return layers.isEmpty ? EssenceStageView() : EssenceLayerStage(layers: layers)
  }()
  /// Which stage is showing (tests, diagnostics).
  var layered: Bool { stage is EssenceLayerStage }
  /// The stage (with its reserved overflow margins) in this view's coordinates: the host turns
  /// `active` on only while this rect is in the viewport.
  var animationBounds: CGRect { stage.convert(stage.bounds, to: self) }
  private var chips: [(StudioFinish, UIButton)] = []
  private let caption = label("", 15, .regular, Palette.muted)
  private let open: (StudioForm?, StudioFinish) -> Void
  private var observers: [NSObjectProtocol] = []

  init(open: @escaping (StudioForm?, StudioFinish) -> Void) {
    self.open = open
    super.init(frame: .zero)
    let title = label("Камень изнутри.", 40, .regular, serif: true)
    let lead = label(
      "Разрежьте образец — и разница видна сразу. S-Stone однороден по всей толщине. S-Sense — минеральное ядро под слоем Gelcoat.",
      16, .regular, Palette.muted)
    stage.accessibilityIdentifier = "essence.stage"
    stage.onSelect = { [weak self] f in self?.select(f) }
    let tabs = stack([], axis: .horizontal, spacing: 8)
    tabs.distribution = .fillEqually
    for f in StudioFinish.allCases {
      var c = UIButton.Configuration.filled()
      c.title = f.short
      c.cornerStyle = .capsule
      c.contentInsets = .init(top: 13, leading: 4, bottom: 13, trailing: 4)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var a = incoming
        a.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 12.5, weight: .semibold), maximumPointSize: 16)
        return a
      }
      let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.select(f) })
      b.titleLabel?.adjustsFontSizeToFitWidth = true
      b.titleLabel?.minimumScaleFactor = 0.75
      b.titleLabel?.numberOfLines = 1
      b.titleLabel?.textAlignment = .center
      b.accessibilityIdentifier = "essence.\(f.rawValue)"
      b.accessibilityLabel = f.title
      chips.append((f, b))
      tabs.addArrangedSubview(b)
    }
    let note = label(
      "Иллюстрация: формы, разрезы и толщина слоёв условны. Gelcoat S-Sense — 0,8 мм.",
      12, .regular, Palette.muted)
    let more = ActionButton("Студия материалов", icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      self.open(Self.form(for: self.finish), self.finish)
    }
    more.accessibilityIdentifier = "essence.explore"
    more.accessibilityHint = "Открывает студию: формы Salini, сравнение исполнений и цвет"
    let body = stack([eyebrow("МАТЕРИАЛЫ SALINI"), title, lead, stage, tabs, caption, note, more], spacing: 14)
    body.setCustomSpacing(4, after: lead)
    body.setCustomSpacing(16, after: stage)
    body.setCustomSpacing(18, after: note)
    pin(body)
    select(.stoneMatte, animated: false)
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
    observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
    observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  /// A real form that sells the finish (Noemi first, as the studio's default).
  static func form(for finish: StudioFinish) -> StudioForm? {
    if let n = StudioForm.noemi, n.finishes.contains(finish) { return n }
    return StudioForm.all.first { $0.finishes.contains(finish) } ?? StudioForm.noemi
  }

  func select(_ f: StudioFinish, animated: Bool = true) {
    let changed = f != finish
    finish = f
    for (value, b) in chips {
      let on = value == f
      b.configuration?.baseBackgroundColor = on ? Palette.ink : .white
      b.configuration?.baseForegroundColor = on ? .white : Palette.ink
      b.accessibilityTraits = on ? [.button, .selected] : .button
    }
    caption.text = MaterialFacts.short(f)
    stage.show(f, animated: animated && !UIAccessibility.isReduceMotionEnabled)
    if animated && changed { UISelectionFeedbackGenerator().selectionChanged() }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlaying()
  }
  private func updatePlaying() {
    let visible = active && window != nil && UIApplication.shared.applicationState != .background
    stage.setRunning(visible)
  }
}

// MARK: - Stage

/// The 3D stage: a soft card (UIKit) with the scene drawn over it on a transparent view that is
/// taller than the card, so the samples can rise above its top edge; callouts follow the layers.
final class EssenceStageView: UIView {
  /// Space above the card the samples may use (part of this view's own bounds).
  static let overflow: CGFloat = 84
  var onSelect: ((StudioFinish) -> Void)?
  private let card = UIView()
  private let gradient = CAGradientLayer()
  private let sceneView = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
  private var essence: EssenceScene?
  private var callouts: [String: EssenceCallout] = [:]
  private var finish: StudioFinish = .stoneMatte
  private let driver = EssenceDriver()
  private var running = false
  private var opened = false

  init() {
    super.init(frame: .zero)
    height(460)
    card.layer.cornerRadius = 30
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    gradient.colors = [UIColor(hex: 0xEDEBE6).cgColor, UIColor(hex: 0xE1DED7).cgColor]
    gradient.startPoint = CGPoint(x: 0.2, y: 0)
    gradient.endPoint = CGPoint(x: 0.8, y: 1)
    card.layer.addSublayer(gradient)
    card.translatesAutoresizingMaskIntoConstraints = false
    addSubview(card)
    sceneView.backgroundColor = .clear
    sceneView.isOpaque = false
    sceneView.antialiasingMode = .multisampling4X
    sceneView.preferredFramesPerSecond = 60
    sceneView.delegate = driver
    driver.frame = { [weak self] in self?.placeCallouts() }
    sceneView.isUserInteractionEnabled = true
    sceneView.isAccessibilityElement = false
    sceneView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(sceneView)
    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: topAnchor, constant: Self.overflow),
      card.leadingAnchor.constraint(equalTo: leadingAnchor),
      card.trailingAnchor.constraint(equalTo: trailingAnchor),
      card.bottomAnchor.constraint(equalTo: bottomAnchor),
      sceneView.topAnchor.constraint(equalTo: topAnchor),
      sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
      sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
      sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    for (key, text) in [("stone", "Одна масса\nпо всей толщине"), ("coat", "Gelcoat · внешний слой"),
                        ("core", "Ядро: мраморная\nкрошка и смола")] {
      let c = EssenceCallout(text)
      c.alpha = 0
      addSubview(c)
      callouts[key] = c
    }
    isAccessibilityElement = true
    accessibilityTraits = [.image, .adjustable]
    accessibilityHint = "Смахните вверх или вниз, чтобы сравнить S-Stone и S-Sense."
    sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    // The scene (geometry, procedural textures) is built off the main thread.
    Task.detached(priority: .userInitiated) {
      let scene = EssenceScene()
      await MainActor.run { [weak self] in self?.attach(scene) }
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradient.frame = card.bounds
    placeCallouts()
  }

  private func attach(_ scene: EssenceScene) {
    essence = scene
    driver.scene = scene
    sceneView.scene = scene.scene
    sceneView.pointOfView = scene.camera
    scene.setFinish(finish)
    setRunning(running)
  }

  /// Visible and allowed to move: the scene plays (opens once on first appearance, then floats).
  /// Otherwise, and always with Reduce Motion, it holds a static, fully composed pose.
  func setRunning(_ on: Bool) {
    running = on
    let reduce = UIAccessibility.isReduceMotionEnabled
    if on && !opened && essence != nil {
      opened = true
      driver.set(opening: 1, immediately: reduce)
    }
    if reduce { driver.settle() }
    driver.restart()
    sceneView.isPlaying = on && !reduce && essence != nil
    if !sceneView.isPlaying { posePaused() }
  }

  func show(_ f: StudioFinish, animated: Bool) {
    finish = f
    driver.set(emphasis: f == .stoneMatte ? 0 : 1, immediately: !animated)
    essence?.setFinish(f)
    accessibilityLabel = Self.description(f)
    accessibilityValue = f.title
    if !sceneView.isPlaying { posePaused() }
    UIView.animate(withDuration: animated ? 0.35 : 0) { self.updateCalloutAlpha() }
  }

  /// A static pose (paused, offscreen or Reduce Motion): targets reached, no float.
  private func posePaused() {
    guard let essence else { return }
    driver.settle()
    let s = driver.state
    essence.pose(time: 0, opening: s.opening, emphasis: s.emphasis, motion: false)
    placeCallouts()
  }

  private func placeCallouts() {
    guard let essence, bounds.width > 0 else { return }
    let anchors = essence.anchors()
    for (key, c) in callouts {
      guard let p = anchors[key] else { continue }
      let s = sceneView.projectPoint(SCNVector3(p))
      let point = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
      c.place(at: point, in: bounds, above: key == "coat")
    }
    updateCalloutAlpha()
  }
  private func updateCalloutAlpha() {
    let s = driver.state
    let open = s.opening > 0.6
    let senseFront = s.emphasisTarget > 0.5
    callouts["stone"]?.alpha = open && !senseFront ? 1 : 0
    callouts["coat"]?.alpha = open && senseFront ? 1 : 0
    callouts["core"]?.alpha = open && senseFront ? 1 : 0
  }

  @objc private func tap(_ g: UITapGestureRecognizer) {
    guard let essence, let hit = sceneView.hitTest(g.location(in: sceneView), options: nil).first,
      let spec = essence.specimen(of: hit.node)
    else { return }
    switch spec {
    case .stone, .bauxite: onSelect?(.stoneMatte)
    case .sense, .marble: onSelect?(finish == .stoneMatte ? .senseGloss : finish)
    }
  }

  // VoiceOver: swipe up / down switches the material.
  override func accessibilityIncrement() { step(1) }
  override func accessibilityDecrement() { step(-1) }
  private func step(_ d: Int) {
    let all = StudioFinish.allCases
    guard let i = all.firstIndex(of: finish) else { return }
    onSelect?(all[(i + d + all.count) % all.count])
  }

  static func description(_ f: StudioFinish) -> String {
    let base = "Иллюстрация, схема: минеральные образцы в разрезе. S-Stone — одна однородная масса по всей толщине. S-Sense — ядро из мраморной крошки и смолы под слоем Gelcoat 0,8 миллиметра; толщина слоёв на картинке условна."
    switch f {
    case .stoneMatte: return "\(base) Крупным планом S-Stone."
    case .senseMatte: return "\(base) Крупным планом S-Sense, матовый Gelcoat."
    case .senseGloss: return "\(base) Крупным планом S-Sense, глянцевый Gelcoat."
    }
  }
}

/// A small callout: a dot on the layer and a label beside it.
final class EssenceCallout: UIView {
  private let text: UILabel
  private let dot = UIView()
  private let line = UIView()
  init(_ string: String) {
    text = label(string, 12, .semibold, Palette.ink)
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    dot.backgroundColor = Palette.ink
    dot.layer.cornerRadius = 3
    dot.layer.borderColor = UIColor.white.cgColor
    dot.layer.borderWidth = 1.5
    line.backgroundColor = Palette.ink.withAlphaComponent(0.4)
    for v in [line, dot, text] { addSubview(v) }
    text.numberOfLines = 0
  }
  required init?(coder: NSCoder) { fatalError() }

  /// Dot at the anchor and a short vertical leader to the label centred above or below it,
  /// kept inside the stage.
  func place(at p: CGPoint, in bounds: CGRect, above: Bool) {
    let size = text.sizeThatFits(CGSize(width: 190, height: 80))
    let lead: CGFloat = 30
    let x = min(max(8, p.x - size.width / 2), bounds.width - size.width - 8)
    var y = above ? p.y - lead - size.height : p.y + lead
    y = min(max(4, y), bounds.height - size.height - 4)
    frame = bounds
    dot.frame = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
    text.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    text.textAlignment = .center
    let y0 = above ? y + size.height + 3 : p.y + 4, y1 = above ? p.y - 4 : y - 3
    line.frame = CGRect(x: p.x - 0.25, y: min(y0, y1), width: 0.5, height: max(0, abs(y1 - y0)))
  }
}

/// The render-thread side of the stage: eases opening and emphasis towards their targets each
/// frame and poses the scene (with the slow float). Main-thread writes go through the lock.
final class EssenceDriver: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
  struct State {
    var opening: Float = 0
    var openingTarget: Float = 0
    var emphasis: Float = 0
    var emphasisTarget: Float = 0
  }
  private let lock = NSLock()
  private var _state = State()
  private var last: TimeInterval?
  /// The opening is choreographed (not eased from rest): a short hold, then 2.2 s smootherstep.
  private var openFrom: Float = 0
  private var openStart: TimeInterval?
  private var openPending = false
  static let openDelay: TimeInterval = 0.35
  static let openDuration: TimeInterval = 2.2
  var scene: EssenceScene?
  /// Called on the main queue after each rendered update (callouts follow the samples).
  var frame: (() -> Void)?

  var state: State {
    lock.lock()
    defer { lock.unlock() }
    return _state
  }
  func set(opening: Float? = nil, emphasis: Float? = nil, immediately: Bool) {
    lock.lock()
    if let opening {
      _state.openingTarget = opening
      if immediately {
        _state.opening = opening
        openPending = false
      } else {
        openFrom = _state.opening
        openPending = true
        openStart = nil
      }
    }
    if let emphasis {
      _state.emphasisTarget = emphasis
      if immediately { _state.emphasis = emphasis }
    }
    lock.unlock()
  }
  /// Jump to the targets (static compositions).
  func settle() {
    lock.lock()
    openPending = false
    _state.opening = _state.openingTarget
    _state.emphasis = _state.emphasisTarget
    lock.unlock()
  }
  /// After a pause the float continues without a jump in the eased values.
  func restart() {
    lock.lock()
    last = nil
    lock.unlock()
  }

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    lock.lock()
    let dt = Float(min(0.05, max(0, time - (last ?? time))))
    last = time
    if openPending {
      if openStart == nil { openStart = time + Self.openDelay }
      let u = Float(max(0, min(1, (time - (openStart ?? time)) / Self.openDuration)))
      let e = u * u * u * (u * (u * 6 - 15) + 10)
      _state.opening = openFrom + (_state.openingTarget - openFrom) * e
      if u >= 1 { openPending = false }
    } else {
      _state.opening += (_state.openingTarget - _state.opening) * (1 - exp(-dt / 0.3))
    }
    // Between the two materials: a critically damped ~0.8 s move.
    _state.emphasis += (_state.emphasisTarget - _state.emphasis) * (1 - exp(-dt / 0.25))
    let s = _state
    lock.unlock()
    scene?.pose(time: time, opening: s.opening, emphasis: s.emphasis, motion: true)
    let frame = self.frame
    DispatchQueue.main.async { frame?() }
  }
}
