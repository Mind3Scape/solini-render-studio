import AVFoundation
import UIKit

/// The reveal plays once per visit; only the living ending repeats.
struct NinfeaPlaybackState {
  private(set) var visit = 0
  private(set) var seconds: Double = 0
  private(set) var finished = false
  private(set) var ambientCycles = 0
  mutating func beginVisit() {
    visit += 1
    seconds = 0
    finished = false
    ambientCycles = 0
  }
  mutating func update(seconds: Double) {
    guard seconds.isFinite, seconds >= 0, !finished else { return }
    self.seconds = seconds
  }
  mutating func finish() { finished = true }
  mutating func completeAmbientCycle() { ambientCycles += 1 }
}

enum CollectionCinemaAssets: String, CaseIterable {
  case ninfea, aria, opera, greca
  var name: String { rawValue.capitalized }
  var introName: String { self == .ninfea ? "ninfea-film-v3" : "\(rawValue)-film-v1" }
  var loopName: String { "\(rawValue)-loop-v1" }
  var startPoster: String { self == .ninfea ? "ninfea-interior.png" : "\(rawValue)-start-v1.png" }
  var finalPoster: String { self == .ninfea ? "ninfea-poster-v3.png" : "\(rawValue)-final-v1.png" }
  var fallbackPoster: String {
    switch self {
    case .ninfea: return "ninfea-poster-v3.png"
    case .greca: return "greca-editorial.jpg"
    default: return "\(rawValue).jpg"
    }
  }
  var introURL: URL? { Bundle.main.url(forResource: introName, withExtension: "mp4") }
  var loopURL: URL? { Bundle.main.url(forResource: loopName, withExtension: "mp4") }
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

/// One video surface, a queued reveal, then an AVPlayerLooper. No fades, seeks at
/// the loop boundary, reverse playback or transport controls. Offscreen pages
/// release their decoders; Reduce Motion shows the finished composition.
final class NinfeaCinemaView: UIView {
  let collection: CollectionCinemaAssets
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var loadingTask: Task<Void, Never>?
  private let surface = CinemaPlayerSurface()
  private let poster = UIImageView()
  private var observers: [NSObjectProtocol] = []
  private var itemObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var displayObservation: NSKeyValueObservation?
  private var loopObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var visitGeneration = 0
  private var introItem: AVPlayerItem?
  private var needsPreparation = true
  private(set) var playback = NinfeaPlaybackState()
  var active = false {
    didSet {
      guard active != oldValue else { return }
      if active { beginVisit() } else { releasePlayback() }
    }
  }
  var isPlaying: Bool { (player?.rate ?? 0) > 0 }
  /// Position inside the current item (reveal or one loop replica); NaN without a player.
  var playheadSeconds: Double { player?.currentTime().seconds ?? .nan }
  var available: Bool {
    collection.introURL != nil && collection.loopURL != nil
  }
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  init(collection: CollectionCinemaAssets = .ninfea) {
    self.collection = collection
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = UIColor(hex: 0x172923)
    poster.contentMode = .scaleAspectFill
    poster.image = UIImage(named: collection.finalPoster) ?? UIImage(named: collection.fallbackPoster)
    surface.playerLayer.videoGravity = .resizeAspectFill
    pin(surface)
    pin(poster)
    displayObservation = surface.playerLayer.observe(\.isReadyForDisplay, options: [.new]) {
      [weak self] _, _ in
      DispatchQueue.main.async { self?.revealReadyFrame() }
    }
    isAccessibilityElement = true
    accessibilityLabel = "\(collection.name). Живая коллекция"
    for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
                 UIAccessibility.reduceMotionStatusDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] notification in
        guard let self else { return }
        if notification.name == UIApplication.willResignActiveNotification {
          self.player?.pause()
        } else if self.active {
          // Returning from Control Center or a system alert is not a new visit: the living
          // ending resumes where it was. Only a released/failed player restarts the reveal.
          if notification.name == UIApplication.didBecomeActiveNotification, self.player != nil,
             self.player?.currentItem?.status != .failed {
            self.updatePlayback()
          } else {
            self.beginVisit()
          }
        }
      })
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit {
    loadingTask?.cancel()
    player?.pause()
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    observers.forEach(NotificationCenter.default.removeObserver)
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { releasePlayback() }
    else if active { preparePlaybackIfNeeded(); updatePlayback() }
  }
  private func beginVisit() {
    releasePlayback()
    playback.beginVisit()
    let posterName = available && !reduceMotion ? collection.startPoster : collection.finalPoster
    poster.image = UIImage(named: posterName) ?? UIImage(named: collection.fallbackPoster)
    poster.isHidden = false
    surface.isHidden = reduceMotion || !available
    preparePlaybackIfNeeded()
  }
  private func preparePlaybackIfNeeded() {
    guard needsPreparation, active, window != nil, !reduceMotion,
          let introURL = collection.introURL, let loopURL = collection.loopURL else { return }
    needsPreparation = false
    let generation = visitGeneration
    loadingTask = Task { @MainActor [weak self] in
      let introAsset = AVURLAsset(url: introURL)
      let loopAsset = AVURLAsset(url: loopURL)
      do {
        async let introDuration = introAsset.load(.duration)
        async let loopDuration = loopAsset.load(.duration)
        let durations = try await (introDuration, loopDuration)
        guard !Task.isCancelled, let self, self.visitGeneration == generation,
              durations.0.seconds > 0, durations.1.seconds > 0 else { return }
        let intro = AVPlayerItem(asset: introAsset)
        let ambient = AVPlayerItem(asset: loopAsset)
        let queue = AVQueuePlayer(items: [intro])
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.automaticallyWaitsToMinimizeStalling = true
        self.player = queue
        self.introItem = intro
        self.looper = AVPlayerLooper(player: queue, templateItem: ambient,
          timeRange: .invalid, existingItemsOrdering: .loopingItemsFollowExistingItems)
        self.surface.playerLayer.player = queue
        self.itemObservation = queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
          DispatchQueue.main.async {
            guard let self, self.visitGeneration == generation else { return }
            if let item = self.player?.currentItem, item !== self.introItem {
              self.playback.finish()
            }
            self.observeCurrentItem(generation: generation)
          }
        }
        self.timeObserver = queue.addPeriodicTimeObserver(
          forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
          guard let self, self.visitGeneration == generation else { return }
          self.playback.update(seconds: time.seconds)
        }
        self.loopObservation = self.looper?.observe(\.loopCount, options: [.new]) { [weak self] _, _ in
          DispatchQueue.main.async {
            guard let self, self.visitGeneration == generation else { return }
            self.playback.completeAmbientCycle()
          }
        }
        self.updatePlayback()
      } catch {
        guard let self, self.visitGeneration == generation else { return }
        self.poster.image = UIImage(named: self.collection.finalPoster)
          ?? UIImage(named: self.collection.fallbackPoster)
        self.poster.isHidden = false
      }
    }
  }
  private func observeCurrentItem(generation: Int) {
    statusObservation = player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        guard let self, self.visitGeneration == generation else { return }
        if self.player?.currentItem?.status == .failed {
          self.releasePlayback()
          self.poster.image = UIImage(named: self.collection.finalPoster)
            ?? UIImage(named: self.collection.fallbackPoster)
          self.surface.isHidden = true
          return
        }
        self.revealReadyFrame()
        self.updatePlayback()
      }
    }
  }
  private func releasePlayback() {
    visitGeneration += 1
    loadingTask?.cancel()
    loadingTask = nil
    player?.pause()
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
    itemObservation = nil
    statusObservation = nil
    loopObservation = nil
    looper?.disableLooping()
    looper = nil
    player?.removeAllItems()
    surface.playerLayer.player = nil
    player = nil
    introItem = nil
    needsPreparation = true
    poster.isHidden = false
  }
  private func revealReadyFrame() {
    if active && !reduceMotion && player?.currentItem?.status == .readyToPlay
        && surface.playerLayer.isReadyForDisplay {
      poster.isHidden = true
    }
  }
  private func updatePlayback() {
    // A queued loop replica can initially have `.unknown` status. Keep playback intent
    // across that transition and let AVPlayer wait for media instead of adding a pause.
    let run = active && window != nil && UIApplication.shared.applicationState == .active
      && !reduceMotion && available && player != nil && player?.currentItem?.status != .failed
    if run { player?.play() } else { player?.pause() }
  }
}
