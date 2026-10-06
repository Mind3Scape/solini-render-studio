import AVFoundation
import UIKit

/// One visit, one uninterrupted scene. No transport state is carried across visits.
struct NinfeaPlaybackState {
  private(set) var visit = 0
  private(set) var seconds: Double = 0
  private(set) var finished = false
  mutating func beginVisit() {
    visit += 1
    seconds = 0
    finished = false
  }
  mutating func update(seconds: Double) {
    guard seconds.isFinite, seconds >= 0, !finished else { return }
    self.seconds = seconds
  }
  mutating func finish() { finished = true }
}

enum NinfeaCinemaAssets {
  // Never silently fall back to the rejected layer-warp V2 movie.
  static let filmURL = Bundle.main.url(forResource: "ninfea-film-v3", withExtension: "mp4")
  static let posterName = "ninfea-poster-v3.png"
}

private final class CinemaPlayerSurface: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Ambient product artwork: automatic entrance, final hold, no player chrome.
final class NinfeaCinemaView: UIView {
  private let player = AVPlayer()
  private let surface = CinemaPlayerSurface()
  private let poster = UIImageView()
  private var observers: [NSObjectProtocol] = []
  private var itemObservation: NSKeyValueObservation?
  private var displayObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var pendingStart = false
  private var seeking = false
  private var seekGeneration = 0
  private(set) var playback = NinfeaPlaybackState()
  var active = false {
    didSet {
      guard active != oldValue else { return }
      if active { beginVisit() } else { updatePlayback() }
    }
  }
  var isPlaying: Bool { player.rate > 0 }
  var available: Bool {
    NinfeaCinemaAssets.filmURL != nil && player.currentItem?.status != .failed
  }
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  init() {
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = UIColor(hex: 0x172923)
    poster.contentMode = .scaleAspectFill
    poster.image = UIImage(named: NinfeaCinemaAssets.posterName)
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
        DispatchQueue.main.async { self?.performPendingStart(); self?.updatePlayback() }
      }
      observers.append(NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        guard let self, !self.seeking, !self.pendingStart else { return }
        self.playback.finish()
        self.player.pause()
        // Keep the actual final decoded image. Do not dissolve or jump to a poster.
      })
    }
    displayObservation = surface.playerLayer.observe(\.isReadyForDisplay, options: [.new]) {
      [weak self] _, _ in
      DispatchQueue.main.async { self?.revealReadyFrame() }
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 10), queue: .main
    ) { [weak self] time in
      guard let self, !self.pendingStart, !self.seeking else { return }
      self.playback.update(seconds: time.seconds)
    }
    isAccessibilityElement = true
    accessibilityLabel = "Ninfea. Природа обретает форму"
    for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
                 UIAccessibility.reduceMotionStatusDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] notification in
        guard let self else { return }
        if notification.name == UIApplication.willResignActiveNotification {
          self.player.pause()
        } else if self.active {
          self.beginVisit()
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
    performPendingStart()
    updatePlayback()
  }
  private func beginVisit() {
    player.pause()
    playback.beginVisit()
    seekGeneration += 1
    pendingStart = available && !reduceMotion
    seeking = false
    poster.image = UIImage(named: pendingStart ? "ninfea-interior.png" : NinfeaCinemaAssets.posterName)
    poster.isHidden = false
    surface.isHidden = reduceMotion || !available
    performPendingStart()
    updatePlayback()
  }
  private func performPendingStart() {
    guard pendingStart, player.currentItem?.status == .readyToPlay else { return }
    pendingStart = false
    seeking = true
    let generation = seekGeneration
    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, generation == self.seekGeneration else { return }
        self.seeking = false
        self.revealReadyFrame()
        self.updatePlayback()
      }
    }
  }
  private func revealReadyFrame() {
    if available && !reduceMotion && !pendingStart && !seeking && surface.playerLayer.isReadyForDisplay {
      poster.isHidden = true
    }
  }
  private func updatePlayback() {
    let run = active && window != nil && UIApplication.shared.applicationState == .active
      && !reduceMotion && available && !playback.finished
      && !pendingStart && !seeking && player.currentItem?.status == .readyToPlay
    if run { player.play() } else { player.pause() }
  }
}
