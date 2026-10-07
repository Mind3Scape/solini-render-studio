import SceneKit
import UIKit

// MARK: - Forms with real executions

/// A real Salini form from an official USDZ, with the executions the catalogue sells for it.
struct StudioForm: Hashable {
  let product: CatalogProduct
  let modelURL: URL
  let finishes: [StudioFinish]
  var name: String { product.name }
  var comparable: Bool { finishes.count > 1 }

  func variantKey(for finish: StudioFinish) -> String? {
    product.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == finish }?.key
  }
  func price(for finish: StudioFinish) -> Int? {
    product.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == finish }?.price
  }

  /// Forms with a bundled model, ordered for the studio: two-finish freestanding Noemi first,
  /// then built-ins with all three executions, then other models.
  static let all: [StudioForm] = {
    let order = ["НОЭМИ 170", "ОРНЕЛЛА 170х75", "КАСКАТА 180x80", "СОФИЯ 170", "МОНА 170", "АЛЬДА 160х70",
                 "ОРЛАНДА 160x70", "ЛУЧЕ 170", "НИНФЕЯ", "GRECA 180"]
    let forms = Catalog.shared.products.compactMap { p -> StudioForm? in
      guard let model = p.model else { return nil }
      let url = model == "Greca"
        ? Bundle.main.url(forResource: "Greca", withExtension: "usdz")
        : Catalog.mediaURL?.appendingPathComponent("models/\(model).usdz")
      guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
      let finishes = StudioFinish.allCases.filter { f in
        p.variants.contains { StudioFinish(material: $0.material, finish: $0.finish) == f }
      }
      return finishes.isEmpty ? nil : StudioForm(product: p, modelURL: url, finishes: finishes)
    }
    return forms.sorted {
      (order.firstIndex(of: $0.product.siteName) ?? 99) < (order.firstIndex(of: $1.product.siteName) ?? 99)
    }
  }()
  static var noemi: StudioForm? { all.first { $0.product.siteName == "НОЭМИ 170" } ?? all.first }
}

// MARK: - Scene view

/// One live studio render. The model loads off the main thread; whatever the user chose
/// meanwhile (finish, colour, shot, light) is kept as the desired state and applied on arrival.
final class StudioSceneView: SCNView, UIGestureRecognizerDelegate {
  private(set) var studio: StudioScene?
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var link: CADisplayLink?
  private var started = CACurrentMediaTime()
  private var loadToken = 0
  private var appActive = UIApplication.shared.applicationState != .background
  private(set) var desiredFinish: StudioFinish = .stoneMatte
  private(set) var desiredColour: UIColor = StudioScene.white
  private(set) var desiredShot: StudioScene.Shot = .form
  var lightPosition: Double = 0.42 {
    didSet {
      studio?.setLight(lightPosition)
      onLightChange?(lightPosition)
      if lightPanEnabled { updateLightValue() }
    }
  }
  var onLightChange: ((Double) -> Void)?
  /// Slow, calm light drift (home feature). Stops for Reduce Motion and once the user takes over.
  var drifting = false { didSet { updatePlayback() } }
  /// Visible and onscreen: SceneKit plays (camera moves, light drift); otherwise it is idle.
  var active = false { didSet { updatePlayback() } }
  /// Horizontal drag moves the light; vertical drags keep scrolling the page.
  var lightPanEnabled = false {
    didSet {
      if lightPanEnabled, lightPan == nil {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panLight(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        lightPan = pan
      }
      lightPan?.isEnabled = lightPanEnabled
      // VoiceOver: the same light is adjustable with a vertical swipe.
      accessibilityTraits = lightPanEnabled ? .adjustable : .none
      updateLightValue()
    }
  }
  private func updateLightValue() {
    let t = lightPosition
    accessibilityValue = t < 0.34 ? "Свет слева" : t > 0.66 ? "Свет справа" : "Свет спереди"
  }
  override func accessibilityIncrement() {
    drifting = false
    lightPosition = min(1, lightPosition + 0.17)
  }
  override func accessibilityDecrement() {
    drifting = false
    lightPosition = max(0, lightPosition - 0.17)
  }
  private var lightPan: UIPanGestureRecognizer?
  private var panStart: Double = 0

  override init(frame: CGRect, options: [String: Any]? = nil) {
    super.init(frame: frame, options: options)
    backgroundColor = StudioSceneView.backdrop
    antialiasingMode = .multisampling4X
    // When the frame is still, SceneKit refines it with sub-pixel jitter (calm rims, no crawl).
    isJitteringEnabled = true
    preferredFramesPerSecond = 30
    rendersContinuously = false
    isPlaying = false
    spinner.color = .white
    spinner.translatesAutoresizingMaskIntoConstraints = false
    addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor), spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(updatePlayback), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    center.addObserver(self, selector: #selector(appResigned), name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(appReturned), name: UIApplication.didBecomeActiveNotification, object: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { link?.invalidate() }
  static let backdrop = UIColor(red: 0.16, green: 0.165, blue: 0.175, alpha: 1)

  func load(_ form: StudioForm, finish: StudioFinish, colour: UIColor, shot: StudioScene.Shot) {
    desiredFinish = finish
    desiredColour = colour
    desiredShot = shot
    loadToken += 1
    let token = loadToken
    spinner.startAnimating()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let studio = StudioScene(modelURL: form.modelURL, finish: finish, colour: colour)
      DispatchQueue.main.async { [weak self] in
        guard let self, token == self.loadToken else { return }
        self.spinner.stopAnimating()
        if let studio {
          // The latest choices win over the ones captured when loading started.
          studio.apply(finish: self.desiredFinish, colour: self.desiredColour)
          if self.bounds.height > 0 { studio.aspect = self.bounds.width / self.bounds.height }
          studio.frame(self.desiredShot, animated: false)
          studio.setLight(self.lightPosition)
        }
        self.studio = studio
        // The physical look maps its half-float frame itself (nil for the legacy look).
        self.technique = studio?.technique
        self.scene = studio?.scene
        self.pointOfView = studio?.camera
      }
    }
  }
  func apply(finish: StudioFinish, colour: UIColor) {
    desiredFinish = finish
    desiredColour = colour
    studio?.apply(finish: finish, colour: colour)
  }
  func frame(_ shot: StudioScene.Shot, animated: Bool) {
    desiredShot = shot
    studio?.frame(shot, animated: animated && !UIAccessibility.isReduceMotionEnabled)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.height > 0 { studio?.aspect = bounds.width / bounds.height }
  }
  @objc private func appResigned() {
    appActive = false
    updatePlayback()
  }
  @objc private func appReturned() {
    appActive = true
    updatePlayback()
  }
  @objc func updatePlayback() {
    let visible = active && appActive && window != nil
    isPlaying = visible
    let run = visible && drifting && !UIAccessibility.isReduceMotionEnabled
    if run, link == nil {
      started = CACurrentMediaTime() - asin(max(-1, min(1, (lightPosition - 0.45) / 0.33))) / 0.22
      let l = CADisplayLink(target: self, selector: #selector(step))
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
      l.add(to: .main, forMode: .common)
      link = l
    } else if !run {
      link?.invalidate()
      link = nil
    }
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlayback()
  }
  @objc private func step() {
    let t = CACurrentMediaTime() - started
    lightPosition = 0.45 + 0.33 * sin(t * 0.22)
  }
  @objc private func panLight(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .began:
      panStart = lightPosition
      drifting = false
    case .changed:
      let dx = Double(g.translation(in: self).x / max(1, bounds.width))
      lightPosition = min(1, max(0, panStart + dx))
    default: break
    }
  }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === lightPan, let pan = lightPan else { return super.gestureRecognizerShouldBegin(g) }
    let v = pan.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2
  }
}

// MARK: - Comparison: same form, same light, two surfaces

/// Two renders of the identical form and camera; the right one is revealed from the seam.
/// The seam is moved with a separate, accessible slider — not with a gesture on the render.
final class StudioCompareView: UIView {
  let left = StudioSceneView(frame: .zero)
  let right = StudioSceneView(frame: .zero)
  private let reveal = CALayer()
  private let seamLine = UIView()
  private let leftLabel = StudioCompareView.chip()
  private let rightLabel = StudioCompareView.chip()
  var comparing = true { didSet { setNeedsLayout() } }
  var seam: CGFloat = 0.5 { didSet { setNeedsLayout() } }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = StudioSceneView.backdrop
    clipsToBounds = true
    pin(left)
    pin(right)
    reveal.backgroundColor = UIColor.black.cgColor
    right.layer.mask = reveal
    seamLine.backgroundColor = UIColor.white.withAlphaComponent(0.85)
    seamLine.isUserInteractionEnabled = false
    addSubview(seamLine)
    for chip in [leftLabel, rightLabel] { addSubview(chip) }
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError() }

  private static func chip() -> UILabel {
    let l = UILabel()
    l.font = .systemFont(ofSize: 12, weight: .semibold)
    l.textColor = .white
    l.backgroundColor = UIColor.black.withAlphaComponent(0.32)
    l.textAlignment = .center
    l.layer.cornerRadius = 13
    l.layer.cornerCurve = .continuous
    l.clipsToBounds = true
    return l
  }
  func setLabels(left l: String, right r: String?) {
    leftLabel.text = "  \(l)  "
    rightLabel.text = r.map { "  \($0)  " }
    accessibilityLabel = r.map { "Сравнение на одной форме: слева \(l), справа \($0)" } ?? "Исполнение \(l)"
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let x = comparing ? bounds.width * seam : bounds.width
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    reveal.frame = CGRect(x: x, y: 0, width: max(0, bounds.width - x), height: bounds.height)
    CATransaction.commit()
    right.isHidden = !comparing
    seamLine.isHidden = !comparing
    rightLabel.isHidden = !comparing
    seamLine.frame = CGRect(x: x - 1, y: 0, width: 2, height: bounds.height)
    leftLabel.sizeToFit()
    rightLabel.sizeToFit()
    leftLabel.frame = CGRect(x: 14, y: 14, width: leftLabel.bounds.width, height: 26)
    rightLabel.frame = CGRect(
      x: bounds.width - rightLabel.bounds.width - 14, y: 14, width: rightLabel.bounds.width, height: 26)
  }
  var active = false {
    didSet {
      left.active = active
      right.active = active && comparing
    }
  }
  var lightPosition: Double = 0.42 {
    didSet {
      left.lightPosition = lightPosition
      right.lightPosition = lightPosition
    }
  }
}

// MARK: - Honest structure diagram

/// Enlarged schematic, scale not to size: S-Stone solid throughout; S-Sense mineral core under
/// a 0.8 mm Gelcoat layer (facts: Salini FAQ and 2026 presentation).
final class StructureDiagram: UIView {
  var finish: StudioFinish = .stoneMatte { didSet { setNeedsDisplay(); updateAccessibility() } }
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .white
    contentMode = .redraw
    isAccessibilityElement = true
    updateAccessibility()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func updateAccessibility() {
    accessibilityLabel = finish == .stoneMatte
      ? "Схема S-Stone: однородный материал на всю толщину, без покрытия."
      : "Схема S-Sense: минеральная основа и защитный слой Gelcoat толщиной 0,8 миллиметра. Масштаб условный."
  }
  override func draw(_ rect: CGRect) {
    // Shape only: titles and notes are real labels around the drawing, so they wrap.
    let body = rect.insetBy(dx: 8, dy: 8)
    let radius = min(46, body.width / 2.2)
    let wall = UIBezierPath(roundedRect: body, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius))
    let mineral = UIColor(hex: 0xE9E6DF)
    mineral.setFill()
    wall.fill()
    // Mineral grain: denser for the marble-flour core, uniform for S-Stone.
    var seed: UInt64 = 7
    func next() -> CGFloat {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return CGFloat(seed >> 33) / CGFloat(1 << 31)
    }
    UIColor(hex: 0xC9C4B9).setFill()
    for _ in 0..<(finish == .stoneMatte ? 260 : 340) {
      let p = CGPoint(x: body.minX + next() * body.width, y: body.minY + 14 + next() * (body.height - 14))
      if wall.contains(p) { UIBezierPath(ovalIn: CGRect(x: p.x, y: p.y, width: 1.6, height: 1.6)).fill() }
    }
    if finish != .stoneMatte {
      let coat = UIBezierPath(roundedRect: body, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius))
      coat.lineWidth = 9
      UIColor(hex: finish == .senseGloss ? 0xFFFFFF : 0xF6F5F2).setStroke()
      coat.stroke()
      UIColor(hex: 0x9AA0A8).setStroke()
      let outline = UIBezierPath(roundedRect: body.insetBy(dx: -4.5, dy: -4.5), byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius + 4, height: radius + 4))
      outline.lineWidth = 0.6
      outline.stroke()
    }
  }
}

// MARK: - Home feature: one large, calm editorial block

final class MaterialFeatureView: UIView {
  let sceneView = StudioSceneView(frame: .zero)
  private(set) var finish: StudioFinish = .stoneMatte
  private var chips: [UIButton] = []
  private let form = StudioForm.noemi
  private let caption = label("", 15, .regular, Palette.muted)
  init(open: @escaping (StudioForm?, StudioFinish) -> Void) {
    super.init(frame: .zero)
    let title = label("Свет на камне.", 40, .regular, serif: true)
    let lead = label(
      "Одна форма Salini — две поверхности. Проведите пальцем по сцене вправо или влево — свет пойдёт за ним — и сравните бархатистый S-Stone с Gelcoat S-Sense.",
      16, .regular, Palette.muted)
    sceneView.height(430)
    sceneView.rounded(30)
    sceneView.drifting = true
    sceneView.lightPanEnabled = true
    sceneView.isAccessibilityElement = true
    sceneView.accessibilityHint = "Проведите по сцене вправо или влево, чтобы вести свет. В VoiceOver — смахните вверх или вниз."
    sceneView.accessibilityLabel = "Ванна \(form?.name ?? "Salini") крупным планом в студии"
    sceneView.accessibilityIdentifier = "material.hero"
    let tabs = stack([], axis: .horizontal, spacing: 8)
    tabs.distribution = .fillEqually
    for f in form?.finishes ?? [.stoneMatte] {
      var c = UIButton.Configuration.filled()
      c.title = f.title
      c.cornerStyle = .capsule
      c.contentInsets = .init(top: 13, leading: 10, bottom: 13, trailing: 10)
      let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.select(f) })
      b.titleLabel?.adjustsFontSizeToFitWidth = true
      b.accessibilityIdentifier = "material.\(f.rawValue)"
      chips.append(b)
      tabs.addArrangedSubview(b)
    }
    let more = ActionButton("Студия материалов", icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      open(self.form, self.finish)
    }
    more.accessibilityIdentifier = "material.explore"
    let body = stack(
      [eyebrow("МАТЕРИАЛЫ SALINI"), title, lead, spacer(6), sceneView, tabs, caption, more], spacing: 14)
    body.setCustomSpacing(18, after: sceneView)
    pin(body)
    if let form { sceneView.load(form, finish: finish, colour: StudioScene.white, shot: .macro) }
    select(form?.finishes.first ?? .stoneMatte, animated: false)
  }
  required init?(coder: NSCoder) { fatalError() }
  func select(_ f: StudioFinish, animated: Bool = true) {
    finish = f
    sceneView.apply(finish: f, colour: StudioScene.white)
    for (b, value) in zip(chips, form?.finishes ?? []) {
      let on = value == f
      b.configuration?.baseBackgroundColor = on ? Palette.ink : .white
      b.configuration?.baseForegroundColor = on ? .white : Palette.ink
      b.accessibilityTraits = on ? [.button, .selected] : .button
    }
    caption.text = MaterialFacts.short(f)
    if animated { UISelectionFeedbackGenerator().selectionChanged() }
  }
}

enum MaterialFacts {
  static func short(_ f: StudioFinish) -> String {
    switch f {
    case .stoneMatte: return "Минералы на основе бокситов, смолы и пигменты. Однородный Solid Surface без покрытия."
    case .senseMatte: return "Мраморная крошка и смола под матовым Gelcoat 0,8 мм."
    case .senseGloss: return "Мраморная крошка и смола под глянцевым Gelcoat 0,8 мм."
    }
  }
  static func composition(_ f: StudioFinish) -> String {
    f == .stoneMatte
      ? "Современный композит: природные минералы на основе бокситов, связующие смолы и натуральные пигменты. Технология Solid Surface — полностью однородная структура, дополнительное покрытие не требуется."
      : "Смесь мраморной крошки с полиэфирной смолой по итальянской рецептуре. Сверху — декоративно-защитный Gelcoat английского производства толщиной 0,8 мм; толщина позволяет косметическую полировку."
  }
  static func care(_ f: StudioFinish) -> String {
    f == .stoneMatte
      ? "Ежедневно — мягкая ткань и неабразивное средство, например Salini Fresco. Для застарелых загрязнений S-Stone допускает порошки с лёгкими абразивами."
      : "Ежедневно — мягкая ткань и неабразивное средство, например Salini Fresco. Для въевшихся пятен на S-Sense — только средства без абразивов."
  }
  static let never = "Нельзя: песок, пемза, металлические щётки, абразивные губки и растворители, кислоты и щёлочи."
  static let warranty = "Гарантия Salini на сантехнику — 10 лет при правильной установке и эксплуатации (FAQ Salini). Мебель и зеркала — 2 года, фурнитура — 5 лет, комплектующие — 1 год."
}

// MARK: - Full studio: one immersive screen

/// Fixed render on top (~44% of the safe height), light and seam always visible beneath it,
/// and a compact panel "Поверхность / Цвет / Структура" that alone scrolls with Dynamic Type.
final class MaterialStudioController: UIViewController {
  private enum Panel: Int, CaseIterable {
    case surface, colour, structure
    var title: String { ["Поверхность", "Цвет", "Структура"][rawValue] }
  }
  private let compare = StudioCompareView()
  private var form: StudioForm?
  private var leftFinish: StudioFinish = .stoneMatte
  private var rightFinish: StudioFinish = .senseGloss
  private var comparing = true
  private var shot: StudioScene.Shot = .form
  private var ral: RALColour?
  private var panel: Panel = .surface
  private let seamSlider = UISlider()
  private let lightSlider = UISlider()
  private let seamRow = UIStackView()
  private let shotControl = UISegmentedControl(items: ["Вся форма", "Борт крупно"])
  private let modeControl = UISegmentedControl(items: [
    StudioIcons.image("rectangle.split.2x1", label: "Сравнение двух исполнений"),
    StudioIcons.image("rectangle", label: "Одно исполнение"),
  ])
  private let formChip = UILabel()
  private var swatches: [(RALColour?, UIButton)] = []
  private let colourName = label("", 15, .semibold)
  private let panelControl = UISegmentedControl(items: Panel.allCases.map(\.title))
  private let panelScroll = UIScrollView()
  private let panelContent = UIStackView()

  init(form: StudioForm? = StudioForm.noemi, finish: StudioFinish? = nil) {
    self.form = form
    super.init(nibName: nil, bundle: nil)
    if let form { reset(to: form, finish: finish) }
  }
  convenience init() { self.init(form: StudioForm.noemi) }
  /// Every entry opens the studio the same way: a large-only sheet with its own close button,
  /// so the scene and the bottom panel always have the full height.
  static func present(form: StudioForm? = StudioForm.noemi, finish: StudioFinish? = nil, from host: UIViewController) {
    let nav = UINavigationController(rootViewController: MaterialStudioController(form: form, finish: finish))
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    host.present(nav, animated: true)
  }
  required init?(coder: NSCoder) { fatalError() }

  private func reset(to form: StudioForm, finish: StudioFinish? = nil) {
    leftFinish = form.finishes.first ?? .stoneMatte
    rightFinish = form.finishes.last ?? leftFinish
    comparing = form.comparable
    if let finish, form.finishes.contains(finish), finish != leftFinish { rightFinish = finish }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    title = "Студия материалов"
    if presentingViewController != nil || navigationController?.presentingViewController != nil {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }
    navigationItem.rightBarButtonItem = formItem()

    compare.rounded(26)
    compare.accessibilityIdentifier = "studio.compare"
    compare.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(compare)

    // Overlay over the scene: shot and compare mode, compact and glass-backed.
    shotControl.accessibilityIdentifier = "studio.shot"
    shotControl.addAction(UIAction { [weak self] _ in self?.changeShot() }, for: .valueChanged)
    modeControl.accessibilityIdentifier = "studio.mode"
    modeControl.addAction(UIAction { [weak self] _ in self?.changeMode() }, for: .valueChanged)
    for c in [shotControl, modeControl] {
      c.backgroundColor = UIColor.black.withAlphaComponent(0.28)
      c.selectedSegmentTintColor = .white
      c.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
      c.setTitleTextAttributes([.foregroundColor: Palette.ink, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
    }
    modeControl.accessibilityLabel = "Режим"
    formChip.font = .systemFont(ofSize: 13, weight: .semibold)
    formChip.textColor = .white
    formChip.backgroundColor = UIColor.black.withAlphaComponent(0.32)
    formChip.layer.cornerRadius = 12
    formChip.layer.cornerCurve = .continuous
    formChip.clipsToBounds = true
    formChip.isAccessibilityElement = false
    let controlsRow = stack([shotControl, UIView(), modeControl], axis: .horizontal, spacing: 8)
    let chipRow = stack([formChip, UIView()], axis: .horizontal)
    // A sibling over the render, not a child: the render is one AX element, its controls stay reachable.
    let overlay = stack([chipRow, controlsRow], spacing: 8)
    overlay.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(overlay)

    // Light and seam: always visible directly under the render.
    lightSlider.value = 0.42
    lightSlider.accessibilityLabel = "Направление света"
    lightSlider.accessibilityHint = "Поворачивает свет вокруг формы"
    lightSlider.accessibilityIdentifier = "studio.light"
    lightSlider.addAction(UIAction { [weak self] _ in
      self?.compare.lightPosition = Double(self?.lightSlider.value ?? 0.42)
    }, for: .valueChanged)
    seamSlider.minimumValue = 0.08
    seamSlider.maximumValue = 0.92
    seamSlider.value = 0.5
    seamSlider.accessibilityLabel = "Граница сравнения"
    seamSlider.accessibilityIdentifier = "studio.seam"
    seamSlider.addAction(UIAction { [weak self] _ in
      self?.compare.seam = CGFloat(self?.seamSlider.value ?? 0.5)
    }, for: .valueChanged)
    for s in [seamSlider, lightSlider] { s.tintColor = Palette.ink }
    let lightRow = sliderRow(lightSlider, "sun.max")
    seamRow.axis = .horizontal
    seamRow.spacing = 10
    seamRow.alignment = .center
    seamRow.addArrangedSubview(symbol("rectangle.split.2x1", size: 15, color: Palette.muted))
    seamRow.addArrangedSubview(seamSlider)
    seamRow.accessibilityElements = [seamSlider]
    let sliders = stack([lightRow, seamRow], axis: .horizontal, spacing: 18)
    sliders.distribution = .fillEqually
    sliders.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(sliders)

    panelControl.selectedSegmentIndex = panel.rawValue
    panelControl.accessibilityIdentifier = "studio.panel"
    panelControl.addAction(UIAction { [weak self] _ in
      guard let self, let p = Panel(rawValue: self.panelControl.selectedSegmentIndex) else { return }
      self.panel = p
      self.renderPanel()
    }, for: .valueChanged)
    panelControl.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panelControl)

    panelScroll.translatesAutoresizingMaskIntoConstraints = false
    panelScroll.alwaysBounceVertical = false
    panelScroll.showsVerticalScrollIndicator = true
    view.addSubview(panelScroll)
    panelContent.axis = .vertical
    panelContent.spacing = 14
    panelContent.translatesAutoresizingMaskIntoConstraints = false
    panelScroll.addSubview(panelContent)

    let safe = view.safeAreaLayoutGuide
    let sceneHeight = compare.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: 0.44)
    sceneHeight.priority = .defaultHigh
    NSLayoutConstraint.activate([
      compare.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
      compare.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
      compare.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
      sceneHeight,
      compare.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
      overlay.leadingAnchor.constraint(equalTo: compare.leadingAnchor, constant: 12),
      overlay.trailingAnchor.constraint(equalTo: compare.trailingAnchor, constant: -12),
      overlay.bottomAnchor.constraint(equalTo: compare.bottomAnchor, constant: -12),
      sliders.topAnchor.constraint(equalTo: compare.bottomAnchor, constant: 10),
      sliders.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 22),
      sliders.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -22),
      panelControl.topAnchor.constraint(equalTo: sliders.bottomAnchor, constant: 12),
      panelControl.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
      panelControl.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
      panelScroll.topAnchor.constraint(equalTo: panelControl.bottomAnchor, constant: 8),
      panelScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panelScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panelScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      panelContent.topAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.topAnchor, constant: 8),
      panelContent.bottomAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.bottomAnchor, constant: -24),
      panelContent.leadingAnchor.constraint(equalTo: panelScroll.frameLayoutGuide.leadingAnchor, constant: 20),
      panelContent.trailingAnchor.constraint(equalTo: panelScroll.frameLayoutGuide.trailingAnchor, constant: -20),
    ])
    view.bringSubviewToFront(overlay)
    reloadScene()
    renderChrome()
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.renderPanel() }
  }
  /// Selects a panel programmatically (also used by the structure layout test).
  func showPanel(_ index: Int) {
    guard let p = Panel(rawValue: index) else { return }
    panel = p
    panelControl.selectedSegmentIndex = index
    renderPanel()
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    compare.active = true
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    compare.active = false
  }

  private var colour: UIColor { ral?.colour ?? StudioScene.white }

  private func formItem() -> UIBarButtonItem {
    let item = UIBarButtonItem(
      title: form?.name ?? "Форма", image: UIImage(systemName: "chevron.up.chevron.down"),
      menu: UIMenu(title: "Форма", children: StudioForm.all.map { f in
        UIAction(
          title: f.name, subtitle: f.finishes.map(\.short).joined(separator: " · "),
          state: f == form ? .on : .off
        ) { [weak self] _ in self?.choose(form: f) }
      }))
    item.accessibilityIdentifier = "studio.form"
    item.accessibilityLabel = "Форма: \(form?.name ?? "нет")"
    return item
  }

  private func reloadScene() {
    guard let form else { return }
    compare.comparing = comparing
    compare.left.load(form, finish: leftFinish, colour: colour, shot: shot)
    if comparing { compare.right.load(form, finish: rightFinish, colour: colour, shot: shot) }
    compare.active = view.window != nil
    updateLabels()
  }
  private func updateLabels() {
    compare.setLabels(left: leftFinish.title, right: comparing ? rightFinish.title : nil)
  }
  /// Controls whose state depends on the form and compare mode.
  private func renderChrome() {
    navigationItem.rightBarButtonItem = formItem()
    formChip.text = form.map { "  \($0.name)  " }
    formChip.isHidden = form == nil
    shotControl.selectedSegmentIndex = shot == .form ? 0 : 1
    modeControl.isHidden = !(form?.comparable ?? false)
    modeControl.selectedSegmentIndex = comparing ? 0 : 1
    seamRow.alpha = comparing ? 1 : 0.35
    seamSlider.isEnabled = comparing
    renderPanel()
  }

  private func changeShot() {
    shot = shotControl.selectedSegmentIndex == 0 ? .form : .macro
    compare.left.frame(shot, animated: true)
    compare.right.frame(shot, animated: true)
  }
  private func changeMode() {
    comparing = modeControl.selectedSegmentIndex == 0
    reloadScene()
    renderChrome()
  }
  private func choose(form f: StudioForm) {
    form = f
    reset(to: f)
    reloadScene()
    renderChrome()
  }

  // MARK: Panel

  private func renderPanel() {
    panelContent.arrangedSubviews.forEach { $0.removeFromSuperview() }
    panelScroll.setContentOffset(.zero, animated: false)
    guard let form else {
      panelContent.addArrangedSubview(label("Модель недоступна в этой сборке.", 16, .regular, Palette.muted))
      return
    }
    switch panel {
    case .surface: surfacePanel(form)
    case .colour: colourPanel()
    case .structure: structurePanel()
    }
  }

  private func surfacePanel(_ form: StudioForm) {
    if comparing {
      let pair = stack(
        [finishMenu(side: "Слева", selected: leftFinish) { [weak self] f in self?.setLeft(f) },
         finishMenu(side: "Справа", selected: rightFinish) { [weak self] f in self?.setRight(f) }],
        axis: .horizontal, spacing: 10)
      pair.distribution = .fillEqually
      panelContent.addArrangedSubview(pair)
    } else {
      panelContent.addArrangedSubview(finishMenu(side: "Исполнение", selected: leftFinish) { [weak self] f in self?.setLeft(f) })
    }
    let shown = comparing ? [leftFinish, rightFinish] : [leftFinish]
    for f in shown.reduce(into: [StudioFinish](), { if !$0.contains($1) { $0.append($1) } }) {
      panelContent.addArrangedSubview(stack([label(f.title, 15, .semibold), label(MaterialFacts.short(f), 14, .regular, Palette.muted)], spacing: 3))
    }
    let finish = chosenFinish
    let open = productButton(form)
    let all = ActionButton("Все изделия: \(finish.title)", icon: "square.grid.2x2") { [weak self] in
      let catalog = CatalogController()
      var filter = CatalogFilter()
      filter.finishes = Set([CatalogFilter.Finish(rawValue: finish.rawValue)].compactMap { $0 })
      catalog.preset = filter
      self?.navigationController?.pushViewController(catalog, animated: true)
    }
    panelContent.addArrangedSubview(open)
    panelContent.addArrangedSubview(all)
    panelContent.addArrangedSubview(factsButton())
  }

  private func finishMenu(side: String, selected: StudioFinish, change: @escaping (StudioFinish) -> Void) -> UIButton {
    var c = UIButton.Configuration.filled()
    c.title = selected.short
    c.subtitle = side
    c.image = UIImage(systemName: "chevron.up.chevron.down")
    c.imagePlacement = .trailing
    c.imagePadding = 6
    c.baseBackgroundColor = .white
    c.baseForegroundColor = Palette.ink
    c.cornerStyle = .large
    c.contentInsets = .init(top: 11, leading: 14, bottom: 11, trailing: 12)
    let b = UIButton(configuration: c)
    b.menu = UIMenu(title: side, children: (form?.finishes ?? []).map { f in
      UIAction(title: f.title, state: f == selected ? .on : .off) { _ in change(f) }
    })
    b.showsMenuAsPrimaryAction = true
    b.titleLabel?.adjustsFontSizeToFitWidth = true
    b.accessibilityLabel = "\(side): \(selected.title)"
    b.accessibilityIdentifier = "studio.finish.\(side)"
    return b
  }
  private func setLeft(_ f: StudioFinish) {
    leftFinish = f
    compare.left.apply(finish: f, colour: colour)
    updateLabels()
    renderPanel()
  }
  private func setRight(_ f: StudioFinish) {
    rightFinish = f
    compare.right.apply(finish: f, colour: colour)
    updateLabels()
    renderPanel()
  }

  private func colourPanel() {
    swatches = []
    func swatch(_ c: RALColour?) -> UIButton {
      var conf = UIButton.Configuration.plain()
      conf.background.backgroundColor = c?.colour ?? StudioScene.white
      conf.background.cornerRadius = 20
      let b = UIButton(configuration: conf, primaryAction: UIAction { [weak self] _ in self?.pick(c) })
      b.widthAnchor.constraint(equalToConstant: 40).isActive = true
      b.height(40)
      b.accessibilityLabel = c.map { "RAL \($0.code), \($0.name)" } ?? "Базовый белый"
      swatches.append((c, b))
      return b
    }
    let buttons = [swatch(nil)] + RALPalette.colours.map(swatch)
    let scroll = horizontal(buttons, width: 40, height: 44)
    scroll.accessibilityIdentifier = "studio.palette"
    panelContent.addArrangedSubview(colourName)
    let row = UIView()
    row.addSubview(scroll)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: row.topAnchor), scroll.bottomAnchor.constraint(equalTo: row.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -20),
      scroll.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: 20),
    ])
    panelContent.addArrangedSubview(row)
    panelContent.addArrangedSubview(
      label("Экранное приближение RAL Classic. Salini заявляет 216 цветов палитры; доступность оттенка для исполнения и цену подтверждает менеджер.", 12, .regular, Palette.muted))
    if let form { panelContent.addArrangedSubview(productButton(form)) }
    updateSwatches()
    // Keep the chosen colour on screen once the strip has its size.
    DispatchQueue.main.async { [weak self, weak scroll] in
      guard let self, let scroll, let selected = self.swatches.first(where: { $0.0 == self.ral })?.1 else { return }
      scroll.layoutIfNeeded()
      scroll.scrollRectToVisible(selected.convert(selected.bounds, to: scroll).insetBy(dx: -60, dy: 0), animated: false)
    }
  }
  /// Selection changes in place: the strip keeps its scroll position.
  private func pick(_ c: RALColour?) {
    ral = c
    compare.left.apply(finish: leftFinish, colour: colour)
    compare.right.apply(finish: rightFinish, colour: colour)
    updateSwatches()
    UISelectionFeedbackGenerator().selectionChanged()
  }
  private func updateSwatches() {
    for (c, b) in swatches {
      let selected = c == ral
      b.configuration?.background.strokeColor = selected ? Palette.ink : Palette.line
      b.configuration?.background.strokeWidth = selected ? 3 : 1
      b.accessibilityTraits = selected ? [.button, .selected] : .button
    }
    colourName.text = ral.map { "RAL \($0.code) · \($0.name)" } ?? "Базовый белый"
    if panel == .colour, let form, let button = panelContent.arrangedSubviews.last as? UIButton {
      button.configuration?.title = productTitle(form)
    }
  }
  private var lineColour: LineColour { ral.map { .ral($0.code) } ?? .standard }
  private var chosenFinish: StudioFinish { comparing ? rightFinish : leftFinish }
  /// «Noemi · S-Stone · 790 000 ₽» — with a RAL colour the price is a base sum + colour on request.
  private func productTitle(_ form: StudioForm) -> String {
    let price = form.price(for: chosenFinish).map(rubles)
    let money = ral == nil ? price ?? "цена по запросу" : price.map { "\($0) + цвет по запросу" } ?? "цена по запросу"
    return "\(form.name) · \(chosenFinish.short) · \(money)"
  }
  /// Opens the exact execution with the studio colour, ready to add to the project.
  private func productButton(_ form: StudioForm) -> UIButton {
    let b = ActionButton(productTitle(form), icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      self.navigationController?.pushViewController(
        CatalogProductController(form.product, variantKey: form.variantKey(for: self.chosenFinish), colour: self.lineColour),
        animated: true)
    }
    b.accessibilityIdentifier = "studio.product"
    return b
  }

  private func structurePanel() {
    // Side by side; at accessibility text sizes the cards stack so nothing is cut.
    let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    let row = stack([], axis: large ? .vertical : .horizontal, spacing: 10)
    row.distribution = large ? .fill : .fillEqually
    row.alignment = .fill
    let shown = comparing ? [leftFinish, rightFinish] : [leftFinish]
    for f in shown.reduce(into: [StudioFinish](), { if !$0.contains($1) { $0.append($1) } }) {
      row.addArrangedSubview(structureCard(f))
    }
    panelContent.addArrangedSubview(row)
    panelContent.addArrangedSubview(
      label("Визуализация — иллюстрация отклика поверхности на свет по официальной 3D-модели, а не измеренная фактура или цветопроба. Схемы структуры увеличены.", 12, .regular, Palette.muted))
    panelContent.addArrangedSubview(factsButton())
  }

  private func structureCard(_ f: StudioFinish) -> UIView {
    let diagram = StructureDiagram()
    diagram.finish = f
    diagram.height(104)
    let title = label(f == .stoneMatte ? "S-Stone" : "S-Sense", 15, .semibold)
    let note = label(
      f == .stoneMatte ? "Однородно на всю толщину, без покрытия: материал и цвет — одна масса."
        : "Основа + Gelcoat 0,8 мм. Слой увеличен, масштаб условный.",
      12, .regular, Palette.muted)
    title.isAccessibilityElement = false
    note.isAccessibilityElement = false
    let card = stack([title, diagram, note], spacing: 8).inset(14)
    card.backgroundColor = .white
    card.rounded(22)
    card.isAccessibilityElement = true
    card.accessibilityLabel = diagram.accessibilityLabel
    return card
  }
  private func factsButton() -> UIView {
    let shown = comparing ? [leftFinish, rightFinish] : [leftFinish]
    let b = ActionButton("Состав, уход и гарантия", icon: "doc.text") { [weak self] in
      let facts = MaterialFactsController(finishes: shown)
      let nav = UINavigationController(rootViewController: facts)
      nav.sheetPresentationController?.detents = [.medium(), .large()]
      nav.sheetPresentationController?.prefersGrabberVisible = true
      self?.present(nav, animated: true)
    }
    b.accessibilityIdentifier = "studio.facts"
    return b
  }

  private func sliderRow(_ slider: UISlider, _ icon: String) -> UIView {
    let r = stack([symbol(icon, size: 15, color: Palette.muted), slider], axis: .horizontal, spacing: 10)
    r.alignment = .center
    r.accessibilityElements = [slider]
    return r
  }
}

/// Long material texts live in their own sheet so the studio stays one screen.
final class MaterialFactsController: ScrollController {
  private let finishes: [StudioFinish]
  init(finishes: [StudioFinish]) {
    self.finishes = finishes.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Состав и уход"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    for f in finishes {
      add(stack([label(f.title, 24, .regular, serif: true), label(MaterialFacts.composition(f), 15, .regular, Palette.muted),
                 label(MaterialFacts.care(f), 15, .regular)], spacing: 8))
    }
    add(label(MaterialFacts.never, 14, .medium, Palette.clay))
    add(label(MaterialFacts.warranty, 13, .regular, Palette.muted))
  }
}

typealias MaterialsController = MaterialStudioController

enum StudioIcons {
  static func image(_ name: String, label: String) -> UIImage {
    let image = UIImage(systemName: name) ?? UIImage()
    image.accessibilityLabel = label
    return image
  }
}
