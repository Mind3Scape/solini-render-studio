import AVFoundation
import UIKit

/// A bounded clock matching the offline-rendered film. The final garden holds;
/// replay is deliberate, with no dissolve back into the empty pavilion.
struct NinfeaTimeline {
  static let duration: Double = 30
  static let chapterTimes: [Double] = [0.8, 9.5, 27]
  static let chapterNames = ["Интерьер", "Вода", "Сад"]
  private(set) var seconds: Double = 0
  var progress: Double { seconds / Self.duration }
  var chapter: Int { seconds < 2 ? 0 : (seconds < 10.5 ? 1 : 2) }
  var ended: Bool { seconds >= Self.duration }
  mutating func advance(_ delta: Double) {
    guard delta.isFinite, delta > 0 else { return }
    seconds = min(Self.duration, seconds + delta)
  }
  mutating func seek(_ fraction: Double) {
    guard fraction.isFinite else { return }
    seconds = min(1, max(0, fraction)) * Self.duration
  }
}

enum NinfeaCinemaAssets {
  static let filmURL = Bundle.main.url(forResource: "ninfea-film-v2", withExtension: "mp4")
  static let posterName = "ninfea-poster-v2.png"
}

private final class CinemaPlayerSurface: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// The expensive botanical composition and neural interpolation happen on the Mac.
/// iOS decodes one bundled silent movie, with a single clock for home and fullscreen.
final class NinfeaCinemaView: UIView {
  private let player = AVPlayer()
  private let surface = CinemaPlayerSurface()
  private let poster = UIImageView()
  private var observers: [NSObjectProtocol] = []
  private var itemObservation: NSKeyValueObservation?
  private var displayObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var pendingSeek = true
  private var seeking = false
  private var seekGeneration = 0
  private(set) var timeline = NinfeaTimeline()
  private(set) var userPaused = false
  var active = false { didSet { if active != oldValue { updatePlayback() } } }
  var onFrame: ((NinfeaTimeline, Bool) -> Void)?
  var isPlaying: Bool { player.rate > 0 }
  var available: Bool {
    NinfeaCinemaAssets.filmURL != nil && player.currentItem?.status != .failed
  }
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  init(progress: Double = 0, paused: Bool = false) {
    super.init(frame: .zero)
    timeline.seek(progress)
    userPaused = paused
    if reduceMotion { timeline.seek(1) }
    clipsToBounds = true
    backgroundColor = UIColor(hex: 0x172923)
    poster.image = UIImage(named: reduceMotion ? NinfeaCinemaAssets.posterName : "ninfea-interior.png")
    poster.contentMode = .scaleAspectFill
    surface.playerLayer.player = player
    surface.playerLayer.videoGravity = .resizeAspectFill
    pin(surface)
    pin(poster)
    player.isMuted = true
    player.actionAtItemEnd = .pause
    player.preventsDisplaySleepDuringVideoPlayback = false
    if let url = NinfeaCinemaAssets.filmURL {
      let item = AVPlayerItem(url: url)
      player.replaceCurrentItem(with: item)
      itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
        DispatchQueue.main.async { self?.performPendingSeek(); self?.updatePlayback() }
      }
      observers.append(NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        guard let self, !self.seeking, !self.pendingSeek else { return }
        self.timeline.seek(1)
        self.userPaused = true
        self.updatePlayback()
      })
    }
    displayObservation = surface.playerLayer.observe(\.isReadyForDisplay, options: [.new]) {
      [weak self] layer, _ in
      DispatchQueue.main.async { self?.poster.isHidden = layer.isReadyForDisplay }
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 30), queue: .main
    ) { [weak self] time in
      guard let self, !self.pendingSeek, !self.seeking, !self.timeline.ended else { return }
      self.timeline.seek(time.seconds / NinfeaTimeline.duration)
      self.onFrame?(self.timeline, self.isPlaying)
    }
    isAccessibilityElement = true
    accessibilityLabel = "Ninfea. Изумрудная ванна в архитектуре водного сада"
    for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
                 UIAccessibility.reduceMotionStatusDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] notification in
        guard let self else { return }
        if notification.name == UIApplication.willResignActiveNotification {
          self.player.pause()
          self.onFrame?(self.timeline, false)
        } else if notification.name == UIAccessibility.reduceMotionStatusDidChangeNotification,
                  self.reduceMotion {
          self.seek(1)
        } else {
          self.updatePlayback()
        }
      })
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit {
    player.pause()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    observers.forEach(NotificationCenter.default.removeObserver)
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlayback()
  }
  func togglePlayback() {
    guard !reduceMotion else { return }
    if timeline.ended { replay(); return }
    userPaused.toggle()
    updatePlayback()
  }
  func replay() { restore(progress: 0, paused: false) }
  func restore(progress: Double, paused: Bool) {
    timeline.seek(reduceMotion ? 1 : progress)
    userPaused = paused
    requestSeek()
  }
  func seek(_ progress: Double, pause: Bool = true) {
    timeline.seek(progress)
    if pause { userPaused = true }
    requestSeek()
  }
  func chapter(_ index: Int) {
    guard NinfeaTimeline.chapterTimes.indices.contains(index) else { return }
    seek(NinfeaTimeline.chapterTimes[index] / NinfeaTimeline.duration)
  }
  private func requestSeek() {
    player.pause()
    pendingSeek = true
    seekGeneration += 1
    performPendingSeek()
    onFrame?(timeline, false)
  }
  private func performPendingSeek() {
    guard pendingSeek, player.currentItem?.status == .readyToPlay else { return }
    pendingSeek = false
    seeking = true
    let generation = seekGeneration
    // The exact end timestamp has no frame. Hold the last encoded frame instead.
    let seconds = min(timeline.seconds, NinfeaTimeline.duration - 1.0 / 30)
    player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, generation == self.seekGeneration else { return }
        self.seeking = false
        self.updatePlayback()
      }
    }
  }
  private func updatePlayback() {
    let run = active && window != nil && UIApplication.shared.applicationState == .active
      && !userPaused && !reduceMotion && available && !timeline.ended
      && !pendingSeek && !seeking && player.currentItem?.status == .readyToPlay
    if run { player.play() } else { player.pause() }
    onFrame?(timeline, run)
  }
}

/// Deliberately small controls: the scene, not a transport toolbar, leads the page.
final class NinfeaCinemaControls: UIView {
  private weak var cinema: NinfeaCinemaView?
  private let play = UIButton(type: .system)
  private let progress = UIProgressView(progressViewStyle: .bar)
  private let phase = label("Интерьер", 11, .medium, .white)
  private var lastPlaying: Bool?
  private var lastEnded: Bool?
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
    let image = playing ? "pause.fill" : (timeline.ended ? "arrow.counterclockwise" : "play.fill")
    if lastPlaying != playing || lastEnded != timeline.ended {
      lastPlaying = playing
      lastEnded = timeline.ended
      play.configuration?.image = UIImage(
        systemName: image,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
      play.accessibilityLabel =
        playing ? "Приостановить историю Ninfea"
        : (timeline.ended ? "Смотреть Ninfea с начала" : "Продолжить историю Ninfea")
    }
    phase.text =
      reduced
      ? "Форма, вдохновлённая природой"
      : "0\(timeline.chapter + 1)   \(NinfeaTimeline.chapterNames[timeline.chapter])"
    progress.progress = Float(timeline.progress)
    progress.isHidden = reduced
  }
}
