import UIKit

/// «Камень изнутри» as a layered 2.5D composition: transparent PNG fragments (stone halves,
/// slices, raw minerals) over a soft card, assembled and then parted along their cut, floating
/// with depth parallax, the hero layers rising past the card's top and side edges into the
/// stage's own reserved margins. Full 3D stays in the material studio.
///
/// Art is described by a manifest: `EssenceLayers.json` in the bundle if present, otherwise the
/// built-in default below. Every layer names its image (asset catalogue name or bundled file),
/// the group it belongs to and where it rests/flies in card coordinates. The stage is used
/// only when every image of the manifest resolves; otherwise the feature falls back to the
/// procedural SceneKit stage.
struct EssenceLayer: Codable, Equatable {
  enum Group: String, Codable { case stone, sense, raw }
  var id: String
  /// Image name (asset catalogue or bundle file, with or without «.png»).
  var image: String
  /// Optional per-finish images for the same fragment (matte / gloss Gelcoat); keys are
  /// `StudioFinish.rawValue` (`stoneMatte` uses `image`). Cross-fades when the finish changes.
  var finishImages: [String: String]?
  var group: Group
  /// Centre at rest (opened), in card units: x 0…1 left → right, y 0…1 top → bottom; values
  /// outside 0…1 place the fragment beyond the card edge (within the stage's margins).
  var x: Double
  var y: Double
  /// Width as a share of the card width; the height follows the image's aspect ratio.
  var width: Double
  /// Rotation at rest, degrees.
  var rotation: Double = 0
  /// The pose when the other material is chosen (smaller, behind); nil = same as above. The
  /// chosen material's layers use x / y / width / rotation, the other's these.
  var backX: Double?
  var backY: Double?
  var backWidth: Double?
  var backRotation: Double?
  /// Offset of the closed (assembled) state from the rest pose, card units, and its rotation.
  var closedDX: Double = 0
  var closedDY: Double = 0
  var closedRotation: Double = 0
  /// Depth 0 (far) … 1 (near): parallax amount, float amplitude and the shadow's spread.
  var depth: Double = 0.5
  /// Draw order (higher above).
  var z: Double = 0
  /// Height above the card (card units) for its contact shadow; 0 = no shadow.
  var lift: Double = 0.06
  /// Callouts on this fragment.
  var labels: [EssenceLabel]?
}

/// A callout: the text key («stone», «coat», «core»), the point it marks in the image (0…1 from
/// the top left) and whether the text sits above or below that point.
struct EssenceLabel: Codable, Equatable {
  var key: String
  var x: Double
  var y: Double
  var above: Bool = false
}

enum EssenceLayers {
  /// Default art direction for the six generated fragments (ios/Salini/EssenceAssets): the chosen
  /// material is the hero in the middle of the card, its loose piece flying past the card's top
  /// edge; the other material waits smaller, higher and behind. Choosing swaps them with one
  /// continuous focus move. Positions are in card units (see `EssenceLayer`).
  static let fallbackManifest: [EssenceLayer] = [
    EssenceLayer(id: "stone-mass", image: "essence-stone-mass", group: .stone,
                 x: 0.46, y: 0.35, width: 0.86, rotation: -3,
                 backX: 0.18, backY: 0.12, backWidth: 0.34, backRotation: -12,
                 depth: 0.6, z: 2, lift: 0.05,
                 labels: [EssenceLabel(key: "stone", x: 0.42, y: 0.42)]),
    EssenceLayer(id: "stone-fragment", image: "essence-stone-fragment", group: .stone,
                 x: 0.86, y: -0.08, width: 0.32, rotation: 16,
                 backX: 0.36, backY: -0.06, backWidth: 0.16, backRotation: 24,
                 closedDX: -0.24, closedDY: 0.34, closedRotation: -16, depth: 0.9, z: 3, lift: 0.22),
    EssenceLayer(id: "sense-core", image: "essence-sense-core-matte",
                 finishImages: ["senseMatte": "essence-sense-core-matte", "senseGloss": "essence-sense-core-gloss"],
                 group: .sense, x: 0.5, y: 0.4, width: 0.82, rotation: 2,
                 backX: 0.82, backY: 0.14, backWidth: 0.32, backRotation: 10,
                 depth: 0.6, z: 2, lift: 0.05,
                 labels: [EssenceLabel(key: "core", x: 0.45, y: 0.5), EssenceLabel(key: "coat", x: 0.3, y: 0.12, above: true)]),
    EssenceLayer(id: "sense-cap", image: "essence-sense-cap-matte",
                 finishImages: ["senseMatte": "essence-sense-cap-matte", "senseGloss": "essence-sense-cap-gloss"],
                 group: .sense, x: 0.16, y: -0.06, width: 0.36, rotation: -14,
                 backX: 0.66, backY: -0.04, backWidth: 0.16, backRotation: -20,
                 closedDX: 0.26, closedDY: 0.36, closedRotation: 14, depth: 0.9, z: 3, lift: 0.22),
  ]

  /// The manifest in use: `EssenceLayers.json` from the bundle, else the default.
  static func manifest(bundle: Bundle = .main) -> [EssenceLayer] {
    if let url = bundle.url(forResource: "EssenceLayers", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let layers = try? JSONDecoder().decode([EssenceLayer].self, from: data), !layers.isEmpty
    {
      return layers
    }
    return fallbackManifest
  }

  /// Asset catalogue name, or a PNG at the bundle root or in its «EssenceAssets» folder.
  static func image(_ name: String, bundle: Bundle = .main) -> UIImage? {
    if let i = UIImage(named: name, in: bundle, compatibleWith: nil) { return i }
    let base = name.hasSuffix(".png") ? String(name.dropLast(4)) : name
    for dir in [nil, "EssenceAssets"] {
      if let url = bundle.url(forResource: base, withExtension: "png", subdirectory: dir) { return UIImage(contentsOfFile: url.path) }
    }
    return nil
  }

  /// The layers whose main image resolves (a missing finish variant falls back to the main
  /// image); the layered stage shows these. Empty → the procedural fallback stage.
  static func resolved(_ layers: [EssenceLayer], bundle: Bundle = .main) -> [EssenceLayer] {
    layers.compactMap { l in
      if image(l.image, bundle: bundle) != nil { return l }
      // The main name may itself be a variant that is not delivered yet: take any variant present.
      guard let v = l.finishImages?.values.sorted().first(where: { image($0, bundle: bundle) != nil }) else { return nil }
      var copy = l
      copy.image = v
      return copy
    }
  }

  /// True when every image of the manifest (and of its finish variants) is in the bundle.
  static func available(_ layers: [EssenceLayer], bundle: Bundle = .main) -> Bool {
    !layers.isEmpty && layers.allSatisfy { l in
      image(l.image, bundle: bundle) != nil && (l.finishImages ?? [:]).values.allSatisfy { image($0, bundle: bundle) != nil }
    }
  }
}

/// The stages the feature can show (layered 2.5D or the procedural SceneKit fallback).
@MainActor
protocol EssenceStage: UIView {
  var onSelect: ((StudioFinish) -> Void)? { get set }
  func show(_ f: StudioFinish, animated: Bool)
  func setRunning(_ on: Bool)
}

extension EssenceStageView: EssenceStage {}

// MARK: - Layered stage

final class EssenceLayerStage: UIView, EssenceStage {
  /// Margins of the stage around the card where fragments may fly (part of this view's bounds,
  /// never over the copy or neighbouring cards).
  static let overflowTop: CGFloat = 84
  static let overflowSide: CGFloat = 0
  static let cardInset: CGFloat = 0
  var onSelect: ((StudioFinish) -> Void)?

  private struct Piece {
    let spec: EssenceLayer
    let view: UIImageView
    let shadow: UIImageView
    var aspect: CGFloat
  }

  private let card = UIView()
  private let gradient = CAGradientLayer()
  private let shadows = UIView()          // contact shadows, clipped to the card
  private let fragments = UIView()        // the fragments, not clipped
  private var pieces: [Piece] = []
  private var callouts: [String: EssenceCallout] = [:]
  private var finish: StudioFinish = .stoneMatte
  private var link: CADisplayLink?
  private var running = false
  private var opened = false
  // Animated state.
  private var opening: CGFloat = 0
  private var openStart: CFTimeInterval?
  private var emphasis: CGFloat = 0
  private var emphasisTarget: CGFloat = 0
  private var clock: CFTimeInterval = 0
  private var lastTick: CFTimeInterval?
  static let openDelay: CFTimeInterval = 0.3
  static let openDuration: CFTimeInterval = 2.0
  /// A soft elliptical contact shadow (radial falloff), drawn once and stretched per fragment.
  static let softShadow: UIImage = {
    let size = CGSize(width: 128, height: 128)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let colours = [UIColor(white: 0, alpha: 0.5).cgColor, UIColor(white: 0, alpha: 0.18).cgColor, UIColor(white: 0, alpha: 0).cgColor]
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 0.45, 1])!
      ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                                       endRadius: 64, options: [])
    }
  }()

  init(layers: [EssenceLayer]) {
    super.init(frame: .zero)
    height(460)
    card.layer.cornerRadius = 30
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    gradient.colors = [UIColor(hex: 0xEEECE7).cgColor, UIColor(hex: 0xE0DDD6).cgColor]
    gradient.startPoint = CGPoint(x: 0.2, y: 0)
    gradient.endPoint = CGPoint(x: 0.8, y: 1)
    card.layer.addSublayer(gradient)
    card.addSubview(shadows)
    shadows.isUserInteractionEnabled = false
    addSubview(card)
    addSubview(fragments)
    fragments.isUserInteractionEnabled = false
    for spec in layers.sorted(by: { $0.z < $1.z }) {
      let image = EssenceLayers.image(spec.image)
      let v = UIImageView(image: image)
      v.contentMode = .scaleAspectFit
      v.isAccessibilityElement = false
      v.layer.minificationFilter = .trilinear
      let s = UIImageView(image: Self.softShadow)
      s.isUserInteractionEnabled = false
      shadows.addSubview(s)
      fragments.addSubview(v)
      let size = image?.size ?? CGSize(width: 1, height: 1)
      pieces.append(Piece(spec: spec, view: v, shadow: s, aspect: size.height / max(1, size.width)))
    }
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
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
  }
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    card.frame = CGRect(x: Self.cardInset, y: Self.overflowTop, width: bounds.width - 2 * Self.cardInset,
                        height: bounds.height - Self.overflowTop)
    gradient.frame = card.bounds
    shadows.frame = card.bounds
    fragments.frame = bounds
    apply()
  }

  // MARK: State

  func setRunning(_ on: Bool) {
    running = on
    let reduce = UIAccessibility.isReduceMotionEnabled
    if on && !opened {
      opened = true
      if reduce { opening = 1 } else { openStart = nil }
    }
    if reduce || !on { settle() }
    if on && !reduce {
      if link == nil {
        let l = CADisplayLink(target: EssenceTicker(self), selector: #selector(EssenceTicker.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
      }
      lastTick = nil
    } else {
      link?.invalidate()
      link = nil
    }
    apply()
  }

  func show(_ f: StudioFinish, animated: Bool) {
    let previous = finish
    finish = f
    emphasisTarget = f == .stoneMatte ? 0 : 1
    if !animated || link == nil { emphasis = emphasisTarget }
    accessibilityLabel = EssenceStageView.description(f)
    accessibilityValue = f.title
    for p in pieces {
      guard let variants = p.spec.finishImages else { continue }
      let name = variants[f.rawValue] ?? p.spec.image
      guard name != (variants[previous.rawValue] ?? p.spec.image), let image = EssenceLayers.image(name) ?? EssenceLayers.image(p.spec.image)
      else { continue }
      if animated {
        UIView.transition(with: p.view, duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.45,
                          options: [.transitionCrossDissolve, .allowUserInteraction]) { p.view.image = image }
      } else {
        p.view.image = image
      }
    }
    apply()
    UIView.animate(withDuration: animated ? 0.3 : 0) { self.updateCalloutAlpha() }
  }

  /// Targets reached, no float (paused, offscreen, Reduce Motion).
  private func settle() {
    if opened { opening = 1 }
    openStart = nil
    emphasis = emphasisTarget
  }

  fileprivate func tick(_ link: CADisplayLink) {
    let now = link.targetTimestamp
    let dt = min(0.05, max(0, now - (lastTick ?? now)))
    lastTick = now
    clock += dt
    if opened && opening < 1 {
      if openStart == nil { openStart = clock + Self.openDelay }
      let u = max(0, min(1, (clock - (openStart ?? clock)) / Self.openDuration))
      opening = u * u * u * (u * (u * 6 - 15) + 10)
    }
    emphasis += (emphasisTarget - emphasis) * (1 - exp(-dt / 0.22))
    apply()
  }

  // MARK: Pose

  /// Places every fragment: closed → rest by `opening`, the selected group forward by
  /// `emphasis`, a slow float and a parallax from the stage's position on screen.
  private func apply() {
    guard card.bounds.width > 0 else { return }
    let w = card.bounds.width, h = card.bounds.height, origin = card.frame.origin
    let motion = link != nil
    // Scroll parallax: −1 (stage near the top of the window) … 1 (near the bottom).
    var scroll: CGFloat = 0
    if let window {
      let mid = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window).y
      scroll = max(-1, min(1, (mid - window.bounds.midY) / max(1, window.bounds.height / 2)))
    }
    let o = opening
    for p in pieces {
      let s = p.spec
      // 1 = this layer's material is the chosen one (hero pose), 0 = it waits behind.
      let focus: CGFloat = s.group == .stone ? 1 - emphasis : s.group == .sense ? emphasis : 1
      let f = Double(focus * focus * (3 - 2 * focus))
      func mix(_ hero: Double, _ back: Double?) -> Double { (back ?? hero) + (hero - (back ?? hero)) * f }
      let d = CGFloat(s.depth)
      let phase = CGFloat(abs(s.id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } % 628)) / 100
      let float: CGFloat = motion ? sin(CGFloat(clock) * 0.7 + phase) * (2 + 4 * d) : 0
      let sway: CGFloat = motion ? sin(CGFloat(clock) * 0.37 + phase) * 1.2 : 0
      // A loose piece rejoins its body while closed (only for the chosen material).
      let closed = Double(1 - o) * f
      let cx = origin.x + w * CGFloat(mix(s.x, s.backX) + s.closedDX * closed)
      let cy = origin.y + h * CGFloat(mix(s.y, s.backY) + s.closedDY * closed) + float - scroll * 14 * d
      let width = w * CGFloat(mix(s.width, s.backWidth))
      let size = CGSize(width: width, height: width * p.aspect)
      let angle = CGFloat(mix(s.rotation, s.backRotation) + s.closedRotation * closed) * .pi / 180 + sway * .pi / 180
      p.view.bounds = CGRect(origin: .zero, size: size)
      p.view.center = CGPoint(x: cx, y: cy)
      p.view.transform = CGAffineTransform(rotationAngle: angle)
      p.view.alpha = 0.62 + 0.38 * CGFloat(f)
      p.view.layer.zPosition = CGFloat(s.z) + 10 * CGFloat(f)
      // Contact shadow on the card: below the fragment by its lift, wider and lighter when high.
      let lift = CGFloat(s.lift) * h
      if lift > 0 {
        // Soft ellipse on the card below the fragment, offset away from the key light (upper
        // left); higher fragments cast wider, fainter shadows.
        let spread = 1 + CGFloat(s.lift) * 3
        let sw = size.width * 0.95 * spread
        let sh = max(14, size.width * 0.24 * spread)
        let bottom = cy + size.height * 0.36
        p.shadow.bounds = CGRect(x: 0, y: 0, width: sw, height: sh)
        p.shadow.center = CGPoint(x: cx + lift * 0.5 - origin.x, y: bottom + lift * 0.8 - origin.y)
        p.shadow.alpha = 0.55 / spread
        p.shadow.isHidden = false
      } else {
        p.shadow.isHidden = true
      }
    }
    placeCallouts()
  }

  private func placeCallouts() {
    for p in pieces {
      for l in p.spec.labels ?? [] {
        guard let c = callouts[l.key] else { continue }
        let point = p.view.convert(CGPoint(x: p.view.bounds.width * CGFloat(l.x), y: p.view.bounds.height * CGFloat(l.y)), to: self)
        c.place(at: point, in: bounds, above: l.above)
      }
    }
    updateCalloutAlpha()
  }
  private func updateCalloutAlpha() {
    let open = opening > 0.7
    let sense = emphasisTarget > 0.5
    callouts["stone"]?.alpha = open && !sense ? 1 : 0
    callouts["core"]?.alpha = open && sense ? 1 : 0
    callouts["coat"]?.alpha = open && sense ? 1 : 0
  }

  // MARK: Interaction

  @objc private func tap(_ g: UITapGestureRecognizer) {
    let p = g.location(in: self)
    // The nearest fragment whose box contains the tap, front first.
    for piece in pieces.sorted(by: { $0.view.layer.zPosition > $1.view.layer.zPosition })
    where piece.view.frame.contains(p) {
      switch piece.spec.group {
      case .stone: onSelect?(.stoneMatte)
      case .sense: onSelect?(finish == .stoneMatte ? .senseGloss : finish)
      case .raw: continue
      }
      return
    }
  }
  override func accessibilityIncrement() { step(1) }
  override func accessibilityDecrement() { step(-1) }
  private func step(_ d: Int) {
    let all = StudioFinish.allCases
    guard let i = all.firstIndex(of: finish) else { return }
    onSelect?(all[(i + d + all.count) % all.count])
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { link?.invalidate(); link = nil }
  }
  deinit { MainActor.assumeIsolated { link?.invalidate() } }
}

/// Breaks the display link's strong reference to the stage.
private final class EssenceTicker: NSObject {
  weak var stage: EssenceLayerStage?
  init(_ s: EssenceLayerStage) { stage = s }
  @objc func tick(_ l: CADisplayLink) {
    guard let stage else { return l.invalidate() }
    MainActor.assumeIsolated { stage.tick(l) }
  }
}
