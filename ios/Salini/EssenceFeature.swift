import UIKit

/// Home feature «Камень изнутри»: the two Salini materials as an illustrative mineral composition
/// — S-Stone a homogeneous mass, S-Sense a mineral core under a Gelcoat skin — drawn from six
/// generated transparent fragments (ios/Salini/EssenceAssets) in a layered 2.5D stage whose
/// pieces rise past the card into the block's own reserved margin. Full 3D stays in the studio;
/// the CTA opens it on a form that sells the chosen finish.
///
/// Integration (Codex): `EssenceFeatureView(open:)` replaces `MaterialFeatureView` on Home; create
/// it with `active = false` and switch `active` while `animationBounds` is in the viewport. The
/// view also pauses itself off-window, in the background and with Reduce Motion. If the bundled
/// fragments are missing (never expected; covered by a test), the stage is omitted and the block
/// stays a quiet text + studio link.
final class EssenceFeatureView: UIView {
  private(set) var finish: StudioFinish = .stoneMatte
  /// The host's visibility: when false nothing animates and no frames are drawn.
  var active = true {
    didSet { updatePlaying() }
  }
  /// The layered stage, nil if its fragments are not in the bundle.
  private let stage: EssenceLayerStage? = {
    let layers = EssenceLayers.manifest()
    return EssenceLayers.available(layers) ? EssenceLayerStage(layers: layers) : nil
  }()
  /// Whether the illustration is shown (tests, diagnostics).
  var illustrated: Bool { stage != nil }
  /// The stage (with its reserved overflow margin) in this view's coordinates: the host turns
  /// `active` on only while this rect is in the viewport. `.zero` without a stage.
  var animationBounds: CGRect { stage.map { $0.convert($0.bounds, to: self) } ?? .zero }
  private var chips: [(StudioFinish, UIButton)] = []
  private let caption = label("", 15, .regular, Palette.muted)
  private let open: (StudioForm?, StudioFinish) -> Void
  private var observers: [NSObjectProtocol] = []

  init(open: @escaping (StudioForm?, StudioFinish) -> Void) {
    self.open = open
    super.init(frame: .zero)
    let title = label("Камень изнутри.", 40, .regular, serif: true)
    let lead = label("Однородный S-Stone. Минеральное ядро под тонким слоем Gelcoat — S-Sense.", 16, .regular, Palette.muted)
    stage?.accessibilityIdentifier = "essence.stage"
    stage?.onSelect = { [weak self] f in self?.select(f) }
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
    let note = label("Художественная визуализация состава. Форма и толщина слоёв условны.", 12, .regular, Palette.muted)
    let more = ActionButton("Студия материалов", icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      self.open(Self.form(for: self.finish), self.finish)
    }
    more.accessibilityIdentifier = "essence.explore"
    more.accessibilityHint = "Открывает студию: формы Salini, сравнение исполнений и цвет"
    let body = stack([eyebrow("МАТЕРИАЛЫ SALINI"), title, lead] + [stage].compactMap { $0 } + [tabs, caption, note, more],
                     spacing: 14)
    body.setCustomSpacing(4, after: lead)
    if let stage { body.setCustomSpacing(16, after: stage) }
    body.setCustomSpacing(18, after: note)
    pin(body)
    select(.stoneMatte, animated: false)
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
    // Resume on didBecomeActive: at willEnterForeground the state can still read .background.
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
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
    stage?.show(f, animated: animated && !UIAccessibility.isReduceMotionEnabled)
    if animated && changed { UISelectionFeedbackGenerator().selectionChanged() }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlaying()
  }
  private func updatePlaying() {
    let visible = active && window != nil && UIApplication.shared.applicationState != .background
    stage?.setRunning(visible)
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
