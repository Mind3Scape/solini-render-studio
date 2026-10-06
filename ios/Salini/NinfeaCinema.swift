import MetalKit
import UIKit

/// A deterministic, scrubbable film clock; no network, timer or business-store writes.
struct NinfeaTimeline {
  static let duration: Double = 22
  static let chapterTimes: [Double] = [0.8, 7.1, 15.5]
  static let chapterNames = ["Интерьер", "Вода", "Сад"]
  private(set) var seconds: Double = 0
  var progress: Double { seconds / Self.duration }
  var chapter: Int { seconds < 1.8 ? 0 : (seconds < 7.3 ? 1 : 2) }
  var water: Float { Float(Self.ease((seconds - 1.8) / 4.8)) }
  var garden: Float { Float(min(1, max(0, (seconds - 7.3) / 6.2))) }
  var dissolve: Float { Float(Self.ease((seconds - 19.8) / 2.2)) }
  var zoom: Float { 1 + 0.035 * Float(sin(.pi * progress)) }
  mutating func advance(_ delta: Double) {
    guard delta.isFinite, delta > 0 else { return }
    seconds = (seconds + delta).truncatingRemainder(dividingBy: Self.duration)
  }
  mutating func seek(_ fraction: Double) {
    guard fraction.isFinite else { return }
    seconds = min(1, max(0, fraction)) * Self.duration
  }
  private static func ease(_ x: Double) -> Double {
    let v = min(1, max(0, x))
    return v * v * (3 - 2 * v)
  }
}

private struct CinemaUniforms {
  var time: Float
  var water: Float
  var garden: Float
  var dissolve: Float
  var aspect: Float
  var zoom: Float
  var motion: Float
  var padding: Float = 0
}

/// Shared immutable textures avoid decoding the same three full-resolution frames twice
/// when opening the full-screen presentation from the homepage.
final class NinfeaCinemaAssets {
  static let shared = NinfeaCinemaAssets()
  let device: MTLDevice?
  let queue: MTLCommandQueue?
  let pipeline: MTLRenderPipelineState?
  let textures: [MTLTexture]
  let error: String?
  static let names = ["ninfea-interior", "ninfea-water", "ninfea-garden"]
  private init() {
    let device = MTLCreateSystemDefaultDevice()
    self.device = device
    queue = device?.makeCommandQueue()
    do {
      guard let device, let library = device.makeDefaultLibrary(),
        let vertex = library.makeFunction(name: "cinemaVertex"),
        let fragment = library.makeFunction(name: "cinemaFragment")
      else { throw NSError(domain: "NinfeaCinema", code: 1) }
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertex
      descriptor.fragmentFunction = fragment
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      let preparedPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
      let loader = MTKTextureLoader(device: device)
      let preparedTextures = try Self.names.map { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
          throw NSError(domain: "NinfeaCinema", code: 2)
        }
        return try loader.newTexture(
          URL: url,
          options: [
            .SRGB: false, .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
          ])
      }
      pipeline = preparedPipeline
      textures = preparedTextures
      error = nil
    } catch {
      pipeline = nil
      textures = []
      self.error = error.localizedDescription
    }
  }
}

final class NinfeaCinemaView: UIView, MTKViewDelegate {
  private let assets = NinfeaCinemaAssets.shared
  private let metal: MTKView
  private let poster = UIImageView(image: UIImage(named: "ninfea-garden.png"))
  private var observers: [NSObjectProtocol] = []
  private var lastTime: CFTimeInterval?
  private(set) var timeline = NinfeaTimeline()
  private(set) var userPaused = false
  var active = false { didSet { if active != oldValue { updatePlayback() } } }
  var onFrame: ((NinfeaTimeline, Bool) -> Void)?
  var isPlaying: Bool { !metal.isPaused }
  var available: Bool { assets.error == nil }
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  init(progress: Double = 0, paused: Bool = false) {
    metal = MTKView(frame: .zero, device: assets.device)
    super.init(frame: .zero)
    timeline.seek(progress)
    userPaused = paused
    if reduceMotion { timeline.seek(NinfeaTimeline.chapterTimes[2] / NinfeaTimeline.duration) }
    clipsToBounds = true
    backgroundColor = UIColor(hex: 0x172923)
    poster.contentMode = .scaleAspectFill
    pin(poster)
    metal.colorPixelFormat = .bgra8Unorm
    metal.framebufferOnly = true
    metal.preferredFramesPerSecond = 30
    metal.isPaused = true
    metal.enableSetNeedsDisplay = false
    metal.delegate = self
    pin(metal)
    metal.isHidden = !available
    isAccessibilityElement = true
    accessibilityLabel = "Ninfea. Изумрудная ванна в архитектуре водного сада"
    for name in [
      UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
      UIAccessibility.reduceMotionStatusDidChangeNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(
          forName: name, object: nil, queue: .main
        ) { [weak self] notification in
          guard let self else { return }
          if notification.name == UIApplication.willResignActiveNotification {
            self.metal.isPaused = true
            self.lastTime = nil
          } else {
            if notification.name == UIAccessibility.reduceMotionStatusDidChangeNotification,
              self.reduceMotion
            {
              self.timeline.seek(NinfeaTimeline.chapterTimes[2] / NinfeaTimeline.duration)
            }
            self.updatePlayback()
          }
        })
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlayback()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    // Cap the hero at 2×. 30 fps is ample for this quiet film and keeps GPU cost bounded.
    metal.drawableSize = CGSize(width: bounds.width * 2, height: bounds.height * 2)
    if metal.isPaused { metal.draw() }
  }
  func togglePlayback() {
    guard !reduceMotion else { return }
    userPaused.toggle()
    updatePlayback()
  }
  func replay() {
    timeline.seek(0)
    userPaused = false
    updatePlayback()
  }
  func restore(progress: Double, paused: Bool) {
    timeline.seek(progress)
    userPaused = paused
    updatePlayback()
  }
  func seek(_ progress: Double, pause: Bool = true) {
    timeline.seek(progress)
    if pause { userPaused = true }
    updatePlayback()
  }
  func chapter(_ index: Int) {
    guard NinfeaTimeline.chapterTimes.indices.contains(index) else { return }
    seek(NinfeaTimeline.chapterTimes[index] / NinfeaTimeline.duration)
  }
  private func updatePlayback() {
    let run =
      active && window != nil && UIApplication.shared.applicationState == .active
      && !userPaused && !reduceMotion && available
    metal.isPaused = !run
    lastTime = nil
    if !run { metal.draw() }
    onFrame?(timeline, run)
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  func draw(in view: MTKView) {
    guard available, bounds.width > 0, bounds.height > 0,
      let pipeline = assets.pipeline, let drawable = view.currentDrawable,
      let descriptor = view.currentRenderPassDescriptor,
      let command = assets.queue?.makeCommandBuffer(),
      let encoder = command.makeRenderCommandEncoder(descriptor: descriptor)
    else { return }
    let now = CACurrentMediaTime()
    if !view.isPaused, let lastTime { timeline.advance(min(0.2, now - lastTime)) }
    lastTime = view.isPaused ? nil : now
    var uniforms = CinemaUniforms(
      time: Float(timeline.seconds), water: timeline.water, garden: timeline.garden,
      dissolve: timeline.dissolve, aspect: Float(bounds.width / bounds.height),
      zoom: reduceMotion ? 1 : timeline.zoom, motion: reduceMotion ? 0 : 1)
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CinemaUniforms>.stride, index: 0)
    for (index, texture) in assets.textures.enumerated() {
      encoder.setFragmentTexture(texture, index: index)
    }
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.present(drawable)
    command.commit()
    onFrame?(timeline, !view.isPaused)
  }
}

/// Deliberately small controls: the scene, not a transport toolbar, leads the page.
final class NinfeaCinemaControls: UIView {
  private weak var cinema: NinfeaCinemaView?
  private let play = UIButton(type: .system)
  private let progress = UIProgressView(progressViewStyle: .bar)
  private let phase = label("Интерьер", 11, .medium, .white)
  private var lastPlaying: Bool?
  init(cinema: NinfeaCinemaView, expand: (() -> Void)? = nil) {
    self.cinema = cinema
    super.init(frame: .zero)
    var config = UIButton.Configuration.glass()
    config.baseForegroundColor = .white
    config.cornerStyle = .capsule
    config.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
    play.configuration = config
    play.widthAnchor.constraint(equalToConstant: 44).isActive = true
    play.height(44)
    play.accessibilityIdentifier = "ninfea.play"
    play.addAction(UIAction { [weak cinema] _ in cinema?.togglePlayback() }, for: .touchUpInside)
    progress.progressTintColor = .white.withAlphaComponent(0.9)
    progress.trackTintColor = .white.withAlphaComponent(0.23)
    progress.isAccessibilityElement = false
    let text = stack([phase, progress], spacing: 9)
    let row = stack([play, text], axis: .horizontal, spacing: 13)
    row.alignment = .center
    if let expand {
      let button = ActionButton("", icon: "arrow.up.left.and.arrow.down.right", action: expand)
      button.configuration?.baseForegroundColor = .white
      button.configuration?.contentInsets = config.contentInsets
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.height(44)
      button.accessibilityLabel = "Открыть историю Ninfea на весь экран"
      button.accessibilityIdentifier = "hero.open.ninfea"
      row.addArrangedSubview(button)
    }
    pin(row)
    cinema.onFrame = { [weak self] timeline, playing in self?.update(timeline, playing: playing) }
    update(cinema.timeline, playing: cinema.isPlaying)
  }
  required init?(coder: NSCoder) { fatalError() }
  private func update(_ timeline: NinfeaTimeline, playing: Bool) {
    let reduced = UIAccessibility.isReduceMotionEnabled
    play.isHidden = reduced || cinema?.available == false
    let image = playing ? "pause.fill" : "play.fill"
    if lastPlaying != playing {
      lastPlaying = playing
      play.configuration?.image = UIImage(
        systemName: image,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
      play.accessibilityLabel =
        playing ? "Приостановить историю Ninfea" : "Продолжить историю Ninfea"
    }
    phase.text =
      reduced
      ? "Форма, вдохновлённая природой"
      : "0\(timeline.chapter + 1)   \(NinfeaTimeline.chapterNames[timeline.chapter])"
    progress.progress = Float(timeline.progress)
    progress.isHidden = reduced
  }
}
