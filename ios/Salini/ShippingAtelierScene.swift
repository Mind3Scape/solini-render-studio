import SceneKit
import simd

#if canImport(UIKit)
  import UIKit
  typealias AtelierColor = UIColor
#else
  import AppKit
  typealias AtelierColor = NSColor
#endif

/// «Участок отгрузки» — a small live proof of the Insight graphics level: one shipping section
/// (quality control, racking, staging, two docks, yard) built by
/// `ios/tools/insight_poc/build_atelier_kit.py` with real Poly Haven CC0 props, the Salini Alda
/// USDZ as scale anchor, and a demonstration batch that a forklift moves from quality control
/// into the truck. Everything here is a demonstration, not telemetry.
///
/// Light: the factory-yard HDRI (image-based light) + one real-time sun with shadows. The kit
/// carries a baked ambient-occlusion map on its second UV set; SceneKit applies it only to
/// ambient/IBL light, so the sun, its shadows and the highlights stay live and nothing is lit
/// twice. Night switches the same scene to a dim sky, lit fixtures and a few spot lights.

func atelierHex(_ hex: UInt, _ alpha: CGFloat = 1) -> AtelierColor {
  AtelierColor(
    red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

enum AtelierLighting: String, CaseIterable {
  case day, night
  var title: String { self == .day ? "День" : "Ночь" }
}

/// What a tap can choose.
enum AtelierSubject: Equatable {
  case batch, forklift, truck
}

/// Stages of one demonstration cycle, in order.
enum AtelierStage: Int, CaseIterable {
  case waiting, approach, lifting, moving, loading, placed, returning

  /// The batch's status line.
  var batchText: String {
    switch self {
    case .waiting: return "Контроль пройден · ждёт погрузчик"
    case .approach: return "Погрузчик подъезжает к партии"
    case .lifting: return "Партия на вилах"
    case .moving: return "Перемещение к доку 02"
    case .loading: return "Загрузка в фуру · док 02"
    case .placed, .returning: return "В фуре · док 02"
    }
  }
  var forkliftText: String {
    switch self {
    case .waiting: return "Ожидает партию у контроля"
    case .approach: return "Едет к партии"
    case .lifting: return "Поднимает партию"
    case .moving: return "Везёт партию к доку 02"
    case .loading: return "Заезжает в фуру"
    case .placed: return "Опускает партию в фуре"
    case .returning: return "Возвращается к контролю"
    }
  }
  /// Route step for the card: контроль → погрузчик → док → фура.
  var routeStep: Int {
    switch self {
    case .waiting: return 0
    case .approach, .lifting: return 1
    case .moving: return 2
    case .loading, .placed, .returning: return 3
    }
  }
}

/// Where things are, read from the kit's named anchors (single source of truth: the Blender
/// script). Defaults match the script so the logic works even without the kit (tests).
struct AtelierLayout: Equatable {
  var floor: Float = 1.2
  var pickup = SIMD2<Float>(7.4, 9.2)
  var dockZ: Float = 13.5
  var dockX: Float = 14.0
  var slots: [Float] = [26.7, 25.4, 24.1, 22.8]
  var alda: [SIMD3<Float>] = [SIMD3(3.2, 1.8, 4.2), SIMD3(7.6, 1.8, 4.2)]
  var truck = SIMD3<Float>(21.2, 1.2, 13.5)
  var nightLights: [SIMD3<Float>] = []
  /// Load space of the curtain-side trailer (x along the trailer, y deck → roof underside, z the
  /// far wall's inner face → the open curtain side) and the dock opening's clear width.
  var trailerMin = SIMD3<Float>(14.4, 1.2, 12.275)
  var trailerMax = SIMD3<Float>(27.9, 3.88, 14.775)
  var dockOpening: ClosedRange<Float> = 12.0...15.0

  init() {}
  init(anchors: [String: SIMD3<Float>]) {
    if let p = anchors["anchor_pickup"] {
      floor = p.y
      pickup = SIMD2(p.x, p.z)
    }
    if let d = anchors["anchor_dock_2"] {
      dockX = d.x
      dockZ = d.z
    }
    let s = (0..<4).compactMap { anchors["anchor_slot_\($0)"]?.x }
    if s.count == 4 { slots = s }
    let a = (1...2).compactMap { anchors["anchor_alda_\($0)"] }
    if !a.isEmpty { alda = a }
    if let t = anchors["anchor_truck"] { truck = t }
    if let a = anchors["anchor_trailer_min"], let b = anchors["anchor_trailer_max"] {
      trailerMin = a
      trailerMax = b
    }
    if let a = anchors["anchor_dock_2_left"], let b = anchors["anchor_dock_2_right"] { dockOpening = min(a.z, b.z)...max(a.z, b.z) }
    nightLights = anchors.filter { $0.key.hasPrefix("anchor_light_") }.sorted { $0.key < $1.key }.map(\.value)
  }
}

/// Where the demonstration batch is in a pose.
enum AtelierBatchPlace: Equatable {
  /// Waiting on the pickup square (opacity fades a new batch in).
  case pickup(opacity: Float)
  case forks
  case slot(Int)
}

/// The truck at dock 02: it really drives away once all four places are loaded, and an empty
/// one backs in before the next batch reaches the dock.
enum AtelierTruckState: Equatable {
  case docked, departing, away, arriving
  var text: String {
    switch self {
    case .docked: return "у дока 02"
    case .departing: return "рейс отправлен · выезжает"
    case .away: return "рейс в пути · подаётся новая фура"
    case .arriving: return "новая фура подъезжает к доку 02"
    }
  }
}

struct AtelierPose: Equatable {
  var forklift: SIMD2<Float>
  /// Rotation about +y; 0 faces +x (east).
  var heading: Float
  /// Fork lift height above the floor.
  var fork: Float
  var stage: AtelierStage
  var cycle: Int
  /// Seconds into the cycle and the share of it completed.
  var time: Double
  var progress: Double
  var batch: AtelierBatchPlace
  /// Batches already in the truck from earlier cycles.
  var loaded: Int
  var slot: Int
  /// The truck's drive along the yard (+x metres from the dock) and its visibility in the haze.
  var truck: AtelierTruckState
  var truckOffset: Float
  var truckOpacity: Float
  /// Rear-wheel steering angle (rad), mast tilt back (rad), front-axle odometer (m, signed) and
  /// signed speed (m/s) — wheels, mast and the carried load follow these.
  var steer: Float = 0
  var tilt: Float = 0
  var odometer: Float = 0
  var speed: Float = 0
  /// Batches standing in the truck right now (earlier ones plus this cycle's once placed).
  var inTruck: Int {
    if case .slot = batch { return loaded + 1 }
    return loaded
  }
  var batchNumber: Int { 214 + cycle }
}

/// The deterministic demonstration: one cycle is a function of time, so the scene, the status
/// card and the tests always agree, and pausing or speeding up never desynchronises them.
struct AtelierTimeline {
  // Vehicle and load geometry (the kit's forklift and batch; checked against the loaded meshes).
  static let forkReach: Float = 0.55
  /// Fork height with a batch (clears the floor, the dock lip and the trailer deck) and empty.
  static let carry: Float = 0.32
  static let emptyFork: Float = 0.05
  /// Forklift envelope from the fork heel.
  static let bodyBack: Float = 2.0
  static let forkLength: Float = 0.98
  static let halfWidth: Float = 0.68
  static let height: Float = 2.46
  /// Front (drive) axle behind the fork heel, and the wheelbase to the rear (steer) axle.
  static let frontAxle: Float = 0.45
  static let wheelbase: Float = 1.25
  /// Mast tilt back while carrying (rad): the load rests against the backrest.
  static let carryTilt: Float = 0.05
  /// The batch: pallet 1.0 × 1.8 m with two crates.
  static let batchSize = SIMD3<Float>(1.0, 1.48, 1.8)

  /// Route shape: the waiting point behind the pickup (m), how far west of it the forklift
  /// reverses out of the trailer (m, negative = west) and how far the two U-turns swing out.
  static var route: (home: Float, reverseTo: Float, turnOut: Float, turnHome: Float) = (2.0, -1.0, 3.0, 2.2)

  /// One cycle, in seconds. Phases (fixed windows; each drive's physical speed profile is fitted
  /// into its window — see `drives` for the natural durations).
  static let period: Double = 68
  enum Phase {
    static let approach: ClosedRange<Double> = 1.5...6.7
    static let lift: ClosedRange<Double> = 6.7...9.3
    static let backOut: ClosedRange<Double> = 9.8...13.4
    static let toDock: ClosedRange<Double> = 13.9...37.9
    static let lower: ClosedRange<Double> = 37.9...40.5
    static let reverseOut: ClosedRange<Double> = 41.1...57.3
    static let home: ClosedRange<Double> = 57.9...67.8
  }

  let layout: AtelierLayout
  let drives: [AtelierDrive]
  /// Odometer (front axle) at the start of each drive.
  private let odometerBase: [Float]
  /// When the forklift's fork tips have left the trailer on the way out (the full truck may go).
  let clearOfTrailer: Double

  init(layout: AtelierLayout) {
    self.layout = layout
    let py = layout.pickup.y, z = layout.dockZ
    let west = SIMD2<Float>(-1, 0), east = SIMD2<Float>(1, 0)
    let a = Self.frontAxle, reach = Self.forkReach
    // Heel positions → front-axle points (behind the heel along the heading).
    let homeHeel = SIMD2(layout.pickup.x + reach + Self.route.home, py)
    let pickHeel = SIMD2(layout.pickup.x + reach, py)
    let backHeel = SIMD2(layout.pickup.x + reach + 2.1, py)
    let homeAxle = homeHeel - west * a, pickAxle = pickHeel - west * a, backAxle = backHeel - west * a
    func slotAxle(_ k: Int) -> SIMD2<Float> { SIMD2(layout.slots[k] - reach, z) - east * a }
    let turnStart = backAxle, turnEnd = SIMD2(backAxle.x, z)
    let u = Self.route.turnOut, w = Self.route.turnHome
    let outAxle = SIMD2(homeAxle.x + Self.route.reverseTo, z)
    let dock = layout.dockX - 1.0
    var list: [AtelierDrive] = []
    // 0 approach: forwards west to the pallet, creeping while the forks slide in.
    let approach = AtelierPath([.line(homeAxle, pickAxle)])
    list.append(AtelierDrive(approach, from: Phase.approach.lowerBound, to: Phase.approach.upperBound, cruise: 1.2,
                             zones: [.init(range: (approach.length - 0.8)...approach.length, speed: 0.3)], align: .end))
    // 1 back out with the load, straight.
    list.append(AtelierDrive(AtelierPath([.line(pickAxle, backAxle)]), reverse: true,
                             from: Phase.backOut.lowerBound, to: Phase.backOut.upperBound, cruise: 1.0, align: .start))
    // 2…5 to the dock (one per slot): a U-turn to the east, through the dock, slow in the trailer.
    for k in 0..<layout.slots.count {
      let target = slotAxle(k)
      let path = AtelierPath([AtelierPath.turn(turnStart, west, turnEnd, east, reach: u), .line(turnEnd, target)])
      let inside = max(0, path.length - (target.x - dock))
      list.append(AtelierDrive(path, from: Phase.toDock.lowerBound, to: Phase.toDock.upperBound, cruise: 2.0,
                               zones: [.init(range: inside...path.length, speed: 1.2),
                                       .init(range: max(0, path.length - 0.6)...path.length, speed: 0.25)], align: .end))
    }
    // 6…9 reverse out of the trailer (forks first slide out of the pallet slowly).
    for k in 0..<layout.slots.count {
      let path = AtelierPath([.line(slotAxle(k), outAxle)])
      let inside = slotAxle(k).x - dock
      list.append(AtelierDrive(path, reverse: true, from: Phase.reverseOut.lowerBound, to: Phase.reverseOut.upperBound,
                               cruise: 1.8, zones: [.init(range: 0...0.9, speed: 0.3), .init(range: 0...max(0.9, inside), speed: 1.3)],
                               align: .start))
    }
    // 10 home: a U-turn back to face the pickup.
    list.append(AtelierDrive(AtelierPath([AtelierPath.turn(outAxle, east, homeAxle, west, reach: w)]),
                             from: Phase.home.lowerBound, to: Phase.home.upperBound, cruise: 1.6, align: .start))
    drives = list
    var base: [Float] = []
    var odo: Float = 0
    for d in list {
      base.append(odo)
      odo += d.path.length
    }
    odometerBase = base
    // The last load: tips out of the trailer (+0.1 m) — the truck may leave from then on.
    let last = list[6 + layout.slots.count - 1]
    var t = Phase.reverseOut.lowerBound
    while t < Phase.reverseOut.upperBound {
      let axle = last.path.sample(at: last.distance(at: t)).point
      if axle.x + a + Self.forkLength < layout.trailerMin.x - 0.1 { break }
      t += 0.05
    }
    clearOfTrailer = t
  }

  /// Which drive is active (or the last one finished) at a time in the cycle, for a slot.
  private func drive(at t: Double, slot: Int) -> Int {
    let n = layout.slots.count
    if t < Phase.backOut.lowerBound { return 0 }
    if t < Phase.toDock.lowerBound { return 1 }
    if t < Phase.reverseOut.lowerBound { return 2 + slot }
    if t < Phase.home.lowerBound { return 2 + n + slot }
    return 2 + 2 * n
  }

  /// Fork height and mast tilt over the cycle: lift then tilt back at the pallet; untilt then
  /// lower in the trailer; slide out at deck height, then raise to the travel height.
  private func forks(at t: Double) -> (Float, Float) {
    func smooth(_ x: Double) -> Float {
      let u = Float(min(1, max(0, x)))
      return u * u * (3 - 2 * u)
    }
    let e0 = Self.emptyFork, c = Self.carry, tilt = Self.carryTilt
    let lift = Phase.lift, lower = Phase.lower
    if t < lift.lowerBound { return (e0, 0) }
    if t <= lift.upperBound {
      let u = (t - lift.lowerBound) / (lift.upperBound - lift.lowerBound)
      return (e0 + (c - e0) * smooth(u / 0.7), tilt * smooth((u - 0.6) / 0.4))
    }
    if t < lower.lowerBound { return (c, tilt) }
    if t <= lower.upperBound {
      let u = (t - lower.lowerBound) / (lower.upperBound - lower.lowerBound)
      return (c * (1 - smooth((u - 0.3) / 0.7)), tilt * (1 - smooth(u / 0.3)))
    }
    return (0, 0)          // after the set-down: see `pose`, raised once the forks are out
  }

  /// Rear-wheel steering angle at a distance along a drive (rad, about the vehicle's vertical
  /// axis): the turn centre lies on the front axle line, so a left turn forwards swings the rear
  /// wheels to the right (negative).
  static func steer(_ d: AtelierDrive, at s: Float) -> Float {
    // The estimate is one-sided at the ends; a stopped vehicle starts and ends straight.
    let k = d.path.sample(at: s).curvature * min(1, s / 0.1, (d.path.length - s) / 0.1)
    return -atan(wheelbase * (d.reverse ? -k : k))
  }

  /// How far the truck drives out along the yard before it disappears into the haze.
  static let truckRun: Float = 38

  /// After the fourth batch is placed and the forklift has left the trailer the truck pulls away
  /// with its load; the next cycle an empty truck backs in long before the forklift reaches the
  /// dock.
  func truck(at t: Double, slot: Int, cycle: Int) -> (AtelierTruckState, Float, Float) {
    func smooth(_ x: Double) -> Float {
      let u = Float(min(1, max(0, x)))
      return u * u * (3 - 2 * u)
    }
    let slots = layout.slots.count
    let leave = clearOfTrailer + 0.6
    if slot == slots - 1 && t >= leave {
      let u = Float(min(1, (t - leave) / 10))
      let fade = 1 - smooth((Double(u) - 0.6) / 0.4)
      // Pull-away: gentle acceleration (distance ∝ u²), then fades into the haze.
      return (u < 1 ? .departing : .away, Self.truckRun * u * u, fade)
    }
    if slot == 0 && cycle > 0 && t < 16 {
      if t < 3 { return (.away, Self.truckRun, 0) }
      let u = Float((t - 3) / 13)
      let ease = 1 - (1 - u) * (1 - u)
      return (.arriving, Self.truckRun * (1 - ease), smooth((t - 3) / 3))
    }
    return (.docked, 0, 1)
  }

  /// Height of the batch's underside above the floor for a fork height: the forks slide under the
  /// pallet at `emptyFork`, so the batch rises only with the forks above that (no jump on pickup
  /// or placement).
  static func lift(_ fork: Float) -> Float { max(0, fork - emptyFork) }

  static func stage(at t: Double) -> AtelierStage {
    switch t {
    case ..<Phase.approach.lowerBound: return .waiting
    case ..<Phase.lift.lowerBound: return .approach
    case ..<Phase.toDock.lowerBound: return .lifting
    case ..<27: return .moving
    case ..<Phase.lower.lowerBound: return .loading
    case ..<Phase.reverseOut.lowerBound: return .placed
    default: return .returning
    }
  }

  func pose(at time: Double) -> AtelierPose {
    let total = max(0, time)
    let cycle = Int(total / Self.period)
    let t = total - Double(cycle) * Self.period
    let slot = cycle % layout.slots.count
    let i = drive(at: t, slot: slot)
    let d = drives[i]
    let s = d.distance(at: t)
    let sample = d.path.sample(at: s)
    // Heading from the travel direction (reversed when backing up).
    let dir = d.reverse ? -sample.tangent : sample.tangent
    let heading = atan2(-dir.y, dir.x)
    let heel = sample.point + dir * Self.frontAxle
    var steer = Self.steer(d, at: s)
    // Stopped between drives: the rear wheels turn (slowly) towards the next drive's first angle.
    if t > d.end {
      let n = layout.slots.count
      let order = [0, 1, 2 + slot, 2 + n + slot, 2 + 2 * n]
      let next = order.firstIndex(of: i).map { $0 + 1 < order.count ? order[$0 + 1] : 0 } ?? 0
      let nextStart = next == 0 ? drives[0].start + Self.period : drives[next].start
      let u = Float(min(1, max(0, (t - d.end) / max(0.1, nextStart - d.end))))
      let e = u * u * (3 - 2 * u)
      steer += (Self.steer(drives[next], at: 0) - steer) * e
    }
    let odometer = odometerBase[i] + s * (d.reverse ? -1 : 1)
    var (fork, tilt) = forks(at: t)
    if t >= Phase.lower.upperBound {
      // Forks slide out of the pallet at deck height, then rise to the travel height.
      let out: Float = i >= 2 + layout.slots.count && i < 2 + 2 * layout.slots.count ? s : (i == 2 + 2 * layout.slots.count ? 99 : 0)
      let u = min(1, max(0, (out - 1.1) / 0.8))
      fork = Self.emptyFork * u * u * (3 - 2 * u)
      tilt = 0
    }
    let batch: AtelierBatchPlace
    if t < Phase.lift.lowerBound {
      batch = .pickup(opacity: Float(min(1, t / 1.2)))
    } else if t < Phase.lower.upperBound {
      batch = .forks
    } else {
      batch = .slot(slot)
    }
    let truck = truck(at: t, slot: slot, cycle: cycle)
    var pose = AtelierPose(
      forklift: heel, heading: heading, fork: fork, stage: Self.stage(at: t), cycle: cycle, time: t,
      progress: t / Self.period, batch: batch, loaded: slot, slot: slot, truck: truck.0, truckOffset: truck.1,
      truckOpacity: truck.2)
    pose.steer = steer
    pose.tilt = tilt
    pose.odometer = odometer
    pose.speed = d.speed(at: t)
    return pose
  }
}

/// Fixed true-isometric orthographic camera: focus on the ground plane and a scale; pan and
/// zoom only change those two, never the angle.
struct AtelierCamera: Equatable {
  static let direction = simd_normalize(SIMD3<Float>(1, 1, 1))
  static let distance: Float = 140
  static let scaleRange: ClosedRange<Double> = 4.5...26
  static let focusMin = SIMD2<Float>(-4, -4)
  static let focusMax = SIMD2<Float>(32, 28)
  var focus = SIMD3<Float>(13.5, 1.2, 10.5)
  var scale: Double = 18

  mutating func clamp() {
    scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, scale))
    focus.x = min(Self.focusMax.x, max(Self.focusMin.x, focus.x))
    focus.z = min(Self.focusMax.y, max(Self.focusMin.y, focus.z))
  }
  func apply(to node: SCNNode) {
    node.simdPosition = focus + Self.direction * Self.distance
    node.simdLook(at: focus, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    node.camera?.orthographicScale = scale
  }
}

final class ShippingAtelierScene: NSObject, SCNSceneRendererDelegate {
  struct Resources {
    var folder: URL
    /// CatalogMedia/models: the Salini catalogue USDZ placed on the stations.
    var models: URL?
    static func bundled() -> Resources? {
      guard let folder = Bundle.main.url(forResource: "InsightAssets", withExtension: nil) else { return nil }
      let models = Bundle.main.url(forResource: "CatalogMedia", withExtension: nil)?.appendingPathComponent("models")
      return Resources(folder: folder, models: models)
    }
  }

  /// Catalogue lengths (m) of the products on the stations: the scale anchors of the scene.
  static let catalogueLengths: [String: Float] = [
    "Alda-160-70": 1.615, "Mona-170": 1.70, "Luce": 1.70, "Noemi-170": 1.705, "Sofia-150-2015-Corona-fbx": 1.50,
  ]

  let scene = SCNScene()
  let cameraNode = SCNNode()
  private(set) var layout = AtelierLayout()
  private(set) var timeline: AtelierTimeline
  private(set) var lighting: AtelierLighting = .day
  private(set) var loadedKit = false
  /// Placed catalogue products and their measured length in metres (scale anchor check).
  private(set) var productLengths: [String: Float] = [:]
  private(set) var treeCount = 0
  /// Irradiance lightmaps (day, night) applied through selfIllumination.
  private var giDay: CGImage?
  private var giNight: CGImage?
  private var giMaterials: [SCNMaterial] = []
  var hasGI: Bool { giDay != nil && !giMaterials.isEmpty }
  private(set) var propMaterials: Set<String> = []
  var camera = AtelierCamera() { didSet { camera.apply(to: cameraNode) } }

  private let forklift = SCNNode()
  private var carriage: SCNNode?
  private var batch = SCNNode()
  private var loaded: [SCNNode] = []
  private var truck: SCNNode?
  private var truckBase = SIMD3<Float>.zero
  private let ring = SCNNode()
  private let ringPlane = SCNNode()
  private let sun = SCNNode()
  private var spots: [SCNNode] = []
  private var nightMaterials: [(SCNMaterial, AtelierColor, CGFloat, CGFloat)] = []
  private var windowMaterials: [SCNMaterial] = []
  private(set) var selected: AtelierSubject?

  /// Demonstration clock, advanced by the renderer; paused and speed are honoured exactly.
  private let lock = NSLock()
  private var demoTime: Double = 0
  private var lastFrame: TimeInterval?
  private var _paused = false
  private var _pose: AtelierPose
  var speed: Double = 1
  var paused: Bool {
    get { lock.withLock { _paused } }
    set { lock.withLock { _paused = newValue; lastFrame = nil } }
  }
  /// The pose last shown (read from the main thread by the status card).
  var pose: AtelierPose { lock.withLock { _pose } }

  init(resources: Resources?) {
    timeline = AtelierTimeline(layout: AtelierLayout())
    _pose = timeline.pose(at: 0)
    super.init()
    let cam = SCNCamera()
    cam.usesOrthographicProjection = true
    cam.zNear = 20
    cam.zFar = 320
    // Linear HDR is mapped once by the app's PBR Neutral technique (see `technique`), as in the
    // material studio: no SceneKit filmic curve on top, no bloom.
    cam.wantsHDR = false
    cameraNode.camera = cam
    scene.rootNode.addChildNode(cameraNode)
    camera.apply(to: cameraNode)
    if let resources { load(resources) }
    setupLights()
    setupGround()
    setupRing()
    setLighting(.day, animated: false)
    apply(timeline.pose(at: 0))
  }

  // MARK: Loading

  private func load(_ r: Resources) {
    let kitURL = r.folder.appendingPathComponent("atelier_kit.usdc")
    guard let kit = try? SCNScene(url: kitURL, options: [.checkConsistency: false]) else { return }
    loadedKit = true
    var anchors: [String: SIMD3<Float>] = [:]
    var transforms: [String: simd_float4x4] = [:]
    kit.rootNode.enumerateHierarchy { node, _ in
      if let name = node.name, name.hasPrefix("anchor_") {
        anchors[name] = node.simdWorldPosition
        transforms[name] = node.simdWorldTransform
      }
    }
    layout = AtelierLayout(anchors: anchors)
    timeline = AtelierTimeline(layout: layout)
    let materials = AtelierMaterials(folder: r.folder)
    let ao = r.folder.appendingPathComponent("atelier_ao.png")
    let hasAO = FileManager.default.fileExists(atPath: ao.path)
    func take(_ name: String) -> SCNNode? {
      guard let n = kit.rootNode.childNode(withName: name, recursively: true) else { return nil }
      // Keep the USD stage's up-axis conversion that lives on the parents.
      let world = n.simdWorldTransform
      n.removeFromParentNode()
      n.simdTransform = world
      return n
    }
    giDay = materials.lightmap(.day)
    giNight = materials.lightmap(.night)
    // «Static» carries lightmap texels (baked light); «StaticProps» has none, so the live night
    // spots light it instead — each surface has exactly one owner of its lamp light.
    for (name, live) in [("Static", false), ("StaticOutside", false), ("StaticProps", true), ("StaticPropsOutside", true)] {
      guard let stat = take(name) else { continue }
      stat.enumerateHierarchy { node, _ in
        if live { node.categoryBitMask |= Self.moverMask }
        guard let g = node.geometry else { return }
        let (uv0, channel) = AtelierMaterials.channels(of: g)
        for m in g.materials {
          materials.apply(to: m, uv0: uv0)
          if hasAO, let channel {
            // With selfIllumination the AO map only occludes specular IBL (measured), so the
            // baked sky occlusion is never applied twice.
            m.ambientOcclusion.contents = ao
            m.ambientOcclusion.mappingChannel = channel
            m.ambientOcclusion.intensity = 1
          }
          if let channel, giDay != nil, materials.lightmapped.contains(m.name ?? "") {
            m.selfIllumination.mappingChannel = channel
            m.selfIllumination.intensity = 1
            giMaterials.append(m)
          }
          if m.name == "M_Window" { windowMaterials.append(m) }
          if let night = AtelierMaterials.nightEmission[m.name ?? ""] {
            nightMaterials.append((m, night.0, night.1, night.2))
          }
        }
        node.castsShadow = true
      }
      scene.rootNode.addChildNode(stat)
    }
    propMaterials = materials.applied
    // Vegetation prototypes (Poly Haven tree and shrubs), instanced with shared geometry at
    // anchor_inst_<Proto>_<k>.
    for protoName in ["Tree", "Shrub2", "Shrub3", "Shrub4"] {
      guard let proto = take(protoName) else { continue }
      materials.applyAll(proto)
      for (name, t) in transforms.sorted(by: { $0.key < $1.key }) where name.hasPrefix("anchor_inst_\(protoName)_") {
        let plant = proto.clone()
        plant.name = protoName
        plant.simdTransform = t
        plant.castsShadow = true
        plant.enumerateHierarchy { n, _ in n.categoryBitMask |= Self.moverMask }
        scene.rootNode.addChildNode(plant)
        treeCount += 1
      }
    }
    if let fork = take("Forklift") {
      forklift.addChildNode(fork)
      carriage = fork.childNode(withName: "Forklift_Carriage", recursively: true)
      materials.applyAll(fork)
      fork.enumerateHierarchy { n, _ in
        n.geometry?.materials.forEach { m in
          if let night = AtelierMaterials.nightEmission[m.name ?? ""] { nightMaterials.append((m, night.0, night.1, night.2)) }
        }
      }
    }
    forklift.name = "Forklift"
    scene.rootNode.addChildNode(forklift)
    forklift.addChildNode(blob(width: 1.7, length: 3.0, offsetX: -1.0))
    if let t = take("Truck") {
      materials.applyAll(t)
      t.name = "Truck"
      scene.rootNode.addChildNode(t)
      t.addChildNode(blob(width: 3.2, length: 18.5, offsetX: 23.4, z: layout.dockZ, y: 0.02))
      truck = t
      truckBase = t.simdPosition
    }
    if let proto = take("Batch") {
      materials.applyAll(proto)
      // The clone keeps the USD up-axis conversion in its own transform; the demo poses only
      // the holder (setting the clone's Euler angles would undo the conversion and stand the
      // pallet on its edge — the clipping seen in build 10).
      func holder(_ name: String) -> SCNNode {
        let h = SCNNode()
        h.name = name
        h.addChildNode(proto.clone())
        return h
      }
      batch = holder("BatchCurrent")
      scene.rootNode.addChildNode(batch)
      for k in 0..<layout.slots.count {
        let c = holder("BatchLoaded")
        c.simdPosition = SIMD3(layout.slots[k], layout.floor, layout.dockZ)
        scene.rootNode.addChildNode(c)
        loaded.append(c)
      }
    }
    if let models = r.models {
      for (name, position) in anchors.sorted(by: { $0.key < $1.key }) where name.hasPrefix("anchor_product_") {
        // USD prim names turn «-» into «_»: map the anchor back to the catalogue file name.
        let key = String(name.dropFirst("anchor_product_".count))
        let file = Self.catalogueLengths.keys.first { $0.replacingOccurrences(of: "-", with: "_") == key } ?? key
        guard let product = try? SCNScene(url: models.appendingPathComponent(file + ".usdz"), options: nil) else { continue }
        let model = SCNNode()
        for child in product.rootNode.childNodes { model.addChildNode(child) }
        let (lo, hi) = model.boundingBox
        let size = SIMD3<Float>(Float(hi.x - lo.x), Float(hi.y - lo.y), Float(hi.z - lo.z))
        // SceneKit ignores the USDZ's metersPerUnit (the catalogue files are in millimetres):
        // pick the file's unit, then check it against the catalogue length.
        let expected = Self.catalogueLengths[file] ?? 1.7
        let longest = max(size.x, size.z)
        var unit: Float = longest > 100 ? 0.001 : longest > 10 ? 0.01 : 1
        if abs(longest * unit - expected) > 0.15 { unit = expected / max(0.001, longest) }
        productLengths[file] = longest * unit
        let centred = SCNNode()
        centred.addChildNode(model)
        model.simdPosition = SIMD3(-Float(lo.x + hi.x) / 2, -Float(lo.y), -Float(lo.z + hi.z) / 2)
        centred.simdScale = SIMD3(repeating: unit)
        // Long side along the table (x); bottom on the table top.
        if size.z > size.x { centred.simdEulerAngles.y = .pi / 2 }
        let holder = SCNNode()
        holder.name = "Product"
        holder.simdPosition = position
        holder.addChildNode(centred)
        holder.enumerateHierarchy { n, _ in
          n.castsShadow = true
          n.categoryBitMask |= Self.moverMask
          // Salini gelcoat white, as in the material studio's base: glossy, non-metallic.
          n.geometry?.materials.forEach { m in
            m.lightingModel = .physicallyBased
            m.diffuse.contents = atelierHex(0xF3F2EE)
            m.roughness.contents = 0.22
            m.metalness.contents = 0
            m.normal.contents = nil
            m.isDoubleSided = true
          }
        }
        scene.rootNode.addChildNode(holder)
      }
    }
    if let env = AtelierMaterials.environment(folder: r.folder) {
      scene.lightingEnvironment.contents = env
    }
    for mover in [forklift, batch, truck].compactMap({ $0 }) + loaded {
      mover.enumerateHierarchy { n, _ in n.categoryBitMask |= Self.moverMask }
    }
  }

  /// Night spots light what has no baked lamp light: movers, catalogue products, trees and the
  /// unlightmapped props («StaticProps»). The lightmapped static geometry has them baked in.
  static let moverMask = 2

  /// A soft contact shadow (ambient occlusion of a mover on the floor), real-time sun shadows do
  /// the rest.
  private func blob(width: Float, length: Float, offsetX: Float, z: Float = 0, y: Float = 0.015) -> SCNNode {
    let plane = SCNPlane(width: CGFloat(length), height: CGFloat(width))
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = AtelierMaterials.blobImage
    m.transparent.contents = AtelierMaterials.blobImage
    m.transparencyMode = .rgbZero
    m.blendMode = .multiply
    m.writesToDepthBuffer = false
    plane.materials = [m]
    let n = SCNNode(geometry: plane)
    n.name = "ContactShadow"
    n.simdEulerAngles.x = -.pi / 2
    n.simdPosition = SIMD3(offsetX, y, z)
    n.castsShadow = false
    n.renderingOrder = -1
    return n
  }

  private func setupGround() {
    // The site continues beyond the kit: plain paving into the fog.
    let floor = SCNFloor()
    floor.reflectivity = 0
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = atelierHex(0xA8A49C)
    m.roughness.contents = 0.95
    floor.materials = [m]
    let n = SCNNode(geometry: floor)
    n.simdPosition.y = -0.01
    n.castsShadow = false
    scene.rootNode.addChildNode(n)
  }

  /// Selection: a thin amber outline on the ground sized to the subject (concept 01's accent),
  /// not a glowing tube — at night it stays a painted-looking line, not an LED.
  private func setupRing() {
    ring.castsShadow = false
    ring.opacity = 0
    ring.name = "SelectionRing"
    ringPlane.simdEulerAngles.x = -.pi / 2          // lies on the ground; the parent only yaws
    ringPlane.renderingOrder = 5
    ringPlane.castsShadow = false
    ring.addChildNode(ringPlane)
    scene.rootNode.addChildNode(ring)
  }

  private static func outline(width: Float, length: Float) -> SCNGeometry {
    let ppm: Float = 48
    let w = Int(width * ppm), h = Int(length * ppm)
    let plane = SCNPlane(width: CGFloat(width), height: CGFloat(length))
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.blendMode = .alpha
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    if let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    {
      let line = CGFloat(0.09 * ppm)
      let rect = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: line, dy: line)
      let path = CGPath(roundedRect: rect, cornerWidth: CGFloat(0.35 * ppm), cornerHeight: CGFloat(0.35 * ppm), transform: nil)
      ctx.setFillColor(red: 0.94, green: 0.66, blue: 0.22, alpha: 0.14)
      ctx.addPath(path)
      ctx.fillPath()
      ctx.setStrokeColor(red: 0.96, green: 0.68, blue: 0.24, alpha: 1)
      ctx.setLineWidth(line)
      ctx.addPath(path)
      ctx.strokePath()
      m.diffuse.contents = ctx.makeImage()
    }
    plane.materials = [m]
    return plane
  }
  private lazy var outlines: [AtelierSubject: SCNGeometry] = [
    .batch: Self.outline(width: 1.5, length: 2.3),
    .forklift: Self.outline(width: 1.8, length: 4.2),
    .truck: Self.outline(width: 3.4, length: 18.8),
  ]

  /// Soft bounce for everything without lightmap texels (products, props, plants, movers): the
  /// hall floor and walls return light from below; without it gelcoat undersides read black under
  /// the outdoor IBL. Ambient, category 2 only, so lightmapped static is never lit twice.
  private let bounce = SCNNode()

  private func setupLights() {
    let fill = SCNLight()
    fill.type = .ambient
    fill.categoryBitMask = Self.moverMask
    fill.color = atelierHex(0xEEEBE6)
    bounce.light = fill
    scene.rootNode.addChildNode(bounce)
    let light = SCNLight()
    light.type = .directional
    light.castsShadow = true
    light.shadowMode = .forward
    light.shadowMapSize = CGSize(width: 4096, height: 4096)
    light.automaticallyAdjustsShadowProjection = false
    light.orthographicScale = 30
    light.zNear = 1
    light.zFar = 260
    // Soft architectural daylight: a 3° sun gives 15–30 cm penumbrae at hall heights; PCF over
    // ~12 texels of the 4096 map (1.5 cm each) approximates it (the bake carries the sky light).
    light.shadowBias = 0.8
    light.shadowRadius = 12
    light.shadowSampleCount = 32
    // Physically dark sun shadows: the baked sky (selfIllumination) is what fills them.
    light.shadowColor = atelierHex(0x000000, 1)
    sun.light = light
    let target = SIMD3<Float>(14, 0, 11)
    let toSun = simd_normalize(SIMD3<Float>(0.6, 0.78, -0.4))   // = SUN_TO in the kit script
    sun.simdPosition = target + toSun * 120
    sun.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    scene.rootNode.addChildNode(sun)
    for p in layout.nightLights {
      let l = SCNLight()
      l.type = .spot
      l.spotInnerAngle = 20
      l.spotOuterAngle = 88
      l.attenuationStartDistance = 1
      l.attenuationEndDistance = 11
      l.attenuationFalloffExponent = 2
      l.color = atelierHex(0xFFE2B8)
      l.intensity = 0
      l.castsShadow = false
      l.categoryBitMask = Self.moverMask
      let n = SCNNode()
      n.light = l
      n.simdPosition = p
      n.simdEulerAngles.x = -.pi / 2
      scene.rootNode.addChildNode(n)
      spots.append(n)
    }
  }

  // MARK: Lighting

  func setLighting(_ mode: AtelierLighting, animated: Bool) {
    lighting = mode
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated ? 1.2 : 0
    let night = mode == .night
    let background = night ? atelierHex(0x0C1217) : atelierHex(0xE4E7EA)
    scene.background.contents = background
    scene.fogColor = background
    scene.fogStartDistance = 150
    scene.fogEndDistance = 215
    scene.fogDensityExponent = 1.3
    // Sun ≈ sky (1250 vs 1.25 × the normalised, desaturated sky), neutral white.
    scene.lightingEnvironment.intensity = night ? 0.035 : 1.25
    sun.light?.intensity = night ? 60 : 1250
    sun.light?.color = night ? atelierHex(0x9DB2D6) : atelierHex(0xFFFAF3)
    for (k, s) in spots.enumerated() {
      // Live spots light the movers only (category 2); the hall and yard have them baked.
      s.light?.intensity = night ? (k < 2 ? 260 : 220) : 0
    }
    for m in giMaterials {
      m.selfIllumination.contents = night ? giNight ?? giDay : giDay
    }
    bounce.light?.intensity = night ? 30 : 260
    for (m, color, day, nightValue) in nightMaterials {
      m.emission.contents = color
      m.emission.intensity = night ? nightValue : day
    }
    for m in windowMaterials {
      m.diffuse.contents = night ? atelierHex(0x1C2731) : atelierHex(0x9FB2BE)
    }
    SCNTransaction.commit()
  }

  /// Exposure in stops for the PBR Neutral mapping of each lighting state.
  static var dayExposure: Float = -0.55
  static var nightExposure: Float = 0.35
  /// The tone-mapping technique for a lighting state (set on the SCNView / renderer).
  func technique(for mode: AtelierLighting) -> SCNTechnique? {
    StudioToneMapping.technique(exposure: mode == .day ? Self.dayExposure : Self.nightExposure)
  }

  // MARK: Demonstration

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    lock.lock()
    let dt = lastFrame.map { min(0.1, time - $0) } ?? 0
    lastFrame = time
    if !_paused { demoTime += dt * speed }
    let t = demoTime
    lock.unlock()
    apply(timeline.pose(at: t))
  }

  /// Forget the last frame time: the next frame advances by zero (after a pause, a hidden screen
  /// or the background), so the demonstration never jumps.
  func resetClock() {
    lock.withLock { lastFrame = nil }
  }

  /// Jumps the demonstration to a time (tests, QA stills).
  func show(time: Double) {
    lock.withLock { demoTime = time }
    apply(timeline.pose(at: time))
  }

  func apply(_ p: AtelierPose) {
    lock.withLock { _pose = p }
    forklift.simdPosition = SIMD3(p.forklift.x, layout.floor, p.forklift.y)
    forklift.simdEulerAngles = SIMD3(0, p.heading, 0)
    carriage?.simdPosition = SIMD3(0, p.fork, 0)
    switch p.batch {
    case .pickup(let opacity):
      batch.simdPosition = SIMD3(layout.pickup.x, layout.floor, layout.pickup.y)
      batch.simdEulerAngles = .zero
      batch.opacity = CGFloat(opacity)
    case .forks:
      let forward = SIMD3<Float>(cos(p.heading), 0, -sin(p.heading))
      let heel = SIMD3(p.forklift.x, layout.floor, p.forklift.y)
      batch.simdPosition = heel + forward * AtelierTimeline.forkReach + SIMD3(0, AtelierTimeline.lift(p.fork), 0)
      batch.simdEulerAngles = SIMD3(0, p.heading - .pi, 0)
      batch.opacity = 1
    case .slot(let k):
      batch.simdPosition = SIMD3(layout.slots[k] + p.truckOffset, layout.floor, layout.dockZ)
      batch.simdEulerAngles = .zero
      batch.opacity = CGFloat(p.truckOpacity)
    }
    for (k, node) in loaded.enumerated() {
      node.isHidden = k >= p.loaded
      node.simdPosition = SIMD3(layout.slots[k] + p.truckOffset, layout.floor, layout.dockZ)
      node.opacity = CGFloat(p.truckOpacity)
    }
    if let truck {
      truck.simdPosition = truckBase + SIMD3(p.truckOffset, 0, 0)
      truck.opacity = CGFloat(p.truckOpacity)
      truck.isHidden = p.truckOpacity < 0.01
    }
    if let selected { placeRing(on: selected, pose: p) }
  }

  // MARK: Selection

  func subject(of node: SCNNode) -> AtelierSubject? {
    var n: SCNNode? = node
    while let current = n {
      switch current.name {
      case "BatchCurrent": return .batch
      case "Forklift": return .forklift
      case "Truck", "BatchLoaded": return .truck
      default: n = current.parent
      }
    }
    return nil
  }

  func select(_ subject: AtelierSubject?, animated: Bool = true) {
    selected = subject
    SCNTransaction.begin()
    SCNTransaction.animationDuration = animated ? 0.25 : 0
    ring.opacity = subject == nil ? 0 : 0.9
    SCNTransaction.commit()
    if let subject { placeRing(on: subject, pose: pose) }
  }

  private func placeRing(on subject: AtelierSubject, pose p: AtelierPose) {
    if ringPlane.geometry !== outlines[subject] { ringPlane.geometry = outlines[subject] }
    switch subject {
    case .batch:
      // The plane's height runs along the pallet's long side (z); it turns with the forks.
      ring.simdPosition = SIMD3(batch.simdPosition.x, batch.simdPosition.y + 0.03, batch.simdPosition.z)
      ring.simdEulerAngles = SIMD3(0, batch.simdEulerAngles.y, 0)
    case .forklift:
      let forward = SIMD3<Float>(cos(p.heading), 0, -sin(p.heading))
      ring.simdPosition = SIMD3(p.forklift.x, layout.floor + 0.03, p.forklift.y) - forward * 0.75
      ring.simdEulerAngles = SIMD3(0, p.heading + .pi / 2, 0)
    case .truck:
      ring.simdPosition = SIMD3(layout.truck.x + 2.2 + p.truckOffset, 0.03, layout.truck.z)
      ring.simdEulerAngles = SIMD3(0, .pi / 2, 0)
    }
  }

  /// Real extent of a mover's loaded geometry in its own frame (forklift: fork heel at the
  /// origin, +x forward; batch: centred on its position) — checked against the safety envelope
  /// the timeline uses, so the clearance tests cover the actual kit, not declared numbers.
  func envelope(of subject: AtelierSubject) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
    let root: SCNNode
    switch subject {
    case .forklift: root = forklift
    case .batch: root = batch
    case .truck: return nil
    }
    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
    root.enumerateHierarchy { n, _ in
      guard n.geometry != nil, n.name != "ContactShadow" else { return }
      let (a, b) = n.boundingBox
      for i in 0..<8 {
        let c = SIMD3<Float>(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z))
        let w = n.simdConvertPosition(c, to: nil)
        let local: SIMD3<Float>
        if subject == .forklift {
          local = forklift.simdConvertPosition(w, from: nil)
        } else {
          local = w - SIMD3(batch.simdWorldPosition.x, layout.floor, batch.simdWorldPosition.z)
        }
        lo = simd_min(lo, local)
        hi = simd_max(hi, local)
      }
    }
    return lo.x <= hi.x ? (lo, hi) : nil
  }

  /// World position on screen of a subject (for the card's anchor line).
  func focusPoint(of subject: AtelierSubject) -> SIMD3<Float> {
    switch subject {
    case .batch: return batch.simdPosition
    case .forklift: return forklift.simdPosition
    case .truck: return layout.truck + SIMD3(pose.truckOffset, 0, 0)
    }
  }
}

/// Material library of the kit: our own PBR for the procedural parts (by `M_*` name), the Poly
/// Haven textures for the downloaded props (atelier_materials.json), tiled ground textures.
final class AtelierMaterials {
  struct Spec {
    var color: UInt
    var rough: CGFloat
    var metal: CGFloat = 0
    var transparency: CGFloat = 1
    /// Micro relief from the concrete scan (normal intensity; 0 = smooth).
    var relief: CGFloat = 0
    /// Profiled sheet: horizontal ribs every 10 cm (procedural normal map, intensity).
    var ribs: CGFloat = 0
  }
  static let specs: [String: Spec] = [
    // Architecture: porcelain white / light grey, with real relief from the concrete scan.
    "M_Panel": Spec(color: 0xE9EBEB, rough: 0.42, ribs: 0.55), "M_Plinth": Spec(color: 0xD4D2CC, rough: 0.82, relief: 0.6),
    "M_Section": Spec(color: 0x84837F, rough: 0.9, relief: 0.5), "M_Floor": Spec(color: 0xC8CAC8, rough: 0.3),
    "M_Slab": Spec(color: 0xC9C6BF, rough: 0.88, relief: 0.7), "M_Asphalt": Spec(color: 0x55595C, rough: 0.9),
    "M_Paving": Spec(color: 0xCCC9C1, rough: 0.9, relief: 0.7), "M_Curb": Spec(color: 0xE0DED7, rough: 0.8, relief: 0.6),
    "M_Grass": Spec(color: 0x7D9068, rough: 0.97), "M_LineWhite": Spec(color: 0xE6E6E1, rough: 0.75),
    "M_LineYellow": Spec(color: 0xD9A23A, rough: 0.6),
    // Engineering: blue-grey steel, galvanised silver; amber only as accents.
    "M_Steel": Spec(color: 0x5D7184, rough: 0.42, metal: 0.55), "M_Galv": Spec(color: 0xC3C7CA, rough: 0.35, metal: 0.9),
    "M_RackUpright": Spec(color: 0x3E5E80, rough: 0.42, metal: 0.4), "M_RackBeam": Spec(color: 0xD99A3A, rough: 0.5, metal: 0.2),
    "M_Timber": Spec(color: 0xC2A27A, rough: 0.85), "M_Carton": Spec(color: 0xC4A27A, rough: 0.9),
    "M_Wrap": Spec(color: 0xF4F4F1, rough: 0.3), "M_Rubber": Spec(color: 0x24272A, rough: 0.8),
    "M_Bollard": Spec(color: 0xE0A33A, rough: 0.45), "M_Lamp": Spec(color: 0xF4F2EA, rough: 0.3),
    "M_Desk": Spec(color: 0xE2DFD8, rough: 0.55), "M_Screen": Spec(color: 0x0E1318, rough: 0.15),
    "M_Foliage": Spec(color: 0x4F7A4A, rough: 0.9), "M_Bark": Spec(color: 0x5A4A3C, rough: 0.9),
    "M_Mat": Spec(color: 0x67727C, rough: 0.85), "M_Leveler": Spec(color: 0x8E9398, rough: 0.5, metal: 0.7),
    "M_TruckCab": Spec(color: 0xF2F2F0, rough: 0.28), "M_Trailer": Spec(color: 0xE6E8E9, rough: 0.45, metal: 0.2),
    "M_Glass": Spec(color: 0x1A2229, rough: 0.06), "M_Forklift": Spec(color: 0xE0A033, rough: 0.4),
    "M_Beacon": Spec(color: 0xFF9A2E, rough: 0.3), "M_Toolbox": Spec(color: 0xD9922E, rough: 0.45),
    "M_Window": Spec(color: 0x9FB2BE, rough: 0.07, metal: 0.25), "M_BoothFrame": Spec(color: 0xEDEDEB, rough: 0.35, metal: 0.5),
    "M_GlassClear": Spec(color: 0xCFDDE4, rough: 0.04, transparency: 0.22),
    "M_Coat": Spec(color: 0xF1F1EE, rough: 0.8), "M_Vest": Spec(color: 0xE39A2C, rough: 0.7),
    "M_Trousers": Spec(color: 0x2E3540, rough: 0.85), "M_Skin": Spec(color: 0xC99A80, rough: 0.7),
    "M_Hair": Spec(color: 0x2A2522, rough: 0.8), "M_Workwear": Spec(color: 0x34506E, rough: 0.8),
    "M_Ceramic": Spec(color: 0xF6F6F3, rough: 0.12),
    "M_Coping": Spec(color: 0x454C54, rough: 0.5, metal: 0.4),
    "M_Frame": Spec(color: 0x7F888F, rough: 0.36, metal: 0.75), "M_LampHousing": Spec(color: 0xE9EAEA, rough: 0.4, metal: 0.3), "M_Joint": Spec(color: 0x7C7F80, rough: 0.8),
    "M_Roof": Spec(color: 0x6B6F72, rough: 0.95, relief: 1.0), "M_Facade": Spec(color: 0xD7DADC, rough: 0.45, ribs: 0.4),
    "M_Curtain": Spec(color: 0xA8B0B8, rough: 0.8), "M_Chassis": Spec(color: 0x23272B, rough: 0.5, metal: 0.4),
    "M_TrailerRoof": Spec(color: 0xD9DCDE, rough: 0.5), "M_Grille": Spec(color: 0x15181B, rough: 0.4, metal: 0.5),
    "M_Headlight": Spec(color: 0xF2F2EE, rough: 0.1), "M_TailLight": Spec(color: 0x8A1C14, rough: 0.2),
    // Services: powder-coated cabinets (RAL 7035), blue water line.
    "M_Cabinet": Spec(color: 0xD3D5D0, rough: 0.5, metal: 0.1), "M_Strap": Spec(color: 0x2B3036, rough: 0.65), "M_PipeWater": Spec(color: 0x3F6D8C, rough: 0.38, metal: 0.3),
  ]
  /// Emission per material: colour, day intensity, night intensity.
  static let nightEmission: [String: (AtelierColor, CGFloat, CGFloat)] = [
    "M_Lamp": (atelierHex(0xFFF1D8), 0.15, 1.6),
    "M_Screen": (atelierHex(0x7FB7E6), 0.25, 0.9),
    "M_Beacon": (atelierHex(0xFF9A2E), 0.4, 2.2),
  ]

  let folder: URL
  private let map: [String: [String: Any]]
  /// Materials with real texels in the lightmap atlas (they receive the baked GI).
  let lightmapped: Set<String>
  private let gi: [String: Any]?
  private(set) var applied: Set<String> = []

  init(folder: URL) {
    self.folder = folder
    let url = folder.appendingPathComponent("atelier_materials.json")
    if let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let materials = json["materials"] as? [String: [String: Any]]
    {
      map = materials
      lightmapped = Set(json["lightmapped"] as? [String] ?? [])
      gi = json["gi"] as? [String: Any]
    } else {
      map = [:]
      lightmapped = []
      gi = nil
    }
  }

  /// Texture-coordinate channels of a kit mesh. SceneKit does not keep USD primvar names and
  /// its order is not the export order (measured: «Lightmap» arrives first), so the baked set is
  /// recognised by its data: the only set that stays inside 0…1 (UV0 is a world-scale projection).
  static func channels(of geometry: SCNGeometry) -> (uv0: Int, lightmap: Int?) {
    let sets = geometry.sources(for: .texcoord)
    guard sets.count >= 2 else { return (0, nil) }
    func inUnitSquare(_ src: SCNGeometrySource) -> Bool {
      guard src.usesFloatComponents, src.bytesPerComponent == 4 else { return false }
      return src.data.withUnsafeBytes { raw -> Bool in
        let step = max(1, src.vectorCount / 4000)
        for k in stride(from: 0, to: src.vectorCount, by: step) {
          for c in 0..<2 {
            let v = raw.load(fromByteOffset: src.dataOffset + k * src.dataStride + c * 4, as: Float.self)
            if v < -0.001 || v > 1.001 { return false }
          }
        }
        return true
      }
    }
    let unit = sets.indices.filter { inUnitSquare(sets[$0]) }
    let lightmap = unit.count == 1 ? unit[0] : 0
    return (lightmap == 0 ? 1 : 0, lightmap)
  }

  private func url(_ key: String, _ entry: [String: Any]) -> URL? {
    (entry[key] as? String).map { folder.appendingPathComponent($0) }
  }

  func apply(to m: SCNMaterial, uv0: Int = 0) {
    let name = m.name ?? ""
    defer {
      for p in [m.diffuse, m.roughness, m.metalness, m.normal] { p.mappingChannel = uv0 }
    }
    m.lightingModel = .physicallyBased
    if let spec = Self.specs[name] {
      m.diffuse.contents = atelierHex(spec.color)
      m.roughness.contents = spec.rough
      m.metalness.contents = spec.metal
      m.normal.contents = nil
      if spec.relief > 0, let floor = map["M_Floor"], let normal = url("normal", floor) {
        // World-scale relief (UV0 is a 2 m cube projection): 1.5 m tiles, no visible repeat.
        let t = SCNMatrix4MakeScale(1.33, 1.33, 1)
        m.normal.contents = normal
        m.normal.intensity = spec.relief
        m.normal.contentsTransform = t
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        if spec.rough > 0.7, let rough = url("rough", floor) {
          m.roughness.contents = rough
          m.roughness.textureComponents = .red
          m.roughness.contentsTransform = t
          m.roughness.wrapS = .repeat
          m.roughness.wrapT = .repeat
        }
      }
      if spec.ribs > 0, let ribs = Self.ribNormal {
        // UV0 is a 2 m cube projection (V = height on walls): 20 ribs per UV unit.
        m.normal.contents = ribs
        m.normal.intensity = spec.ribs
        m.normal.contentsTransform = SCNMatrix4MakeScale(1, 5, 1)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
      }
      if spec.transparency < 1 {
        m.transparency = spec.transparency
        m.transparencyMode = .dualLayer
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
      }
    }
    guard let entry = map[name] else { return }
    applied.insert(name)
    // Kit textures (downloaded props and the generated surfaces) are authored per UV0 unit.
    for p in [m.diffuse, m.roughness, m.normal] { p.contentsTransform = SCNMatrix4Identity }
    if let base = url("base", entry) {
      m.diffuse.contents = base
      m.diffuse.wrapS = .repeat
      m.diffuse.wrapT = .repeat
    }
    if let arm = url("arm", entry) {
      m.roughness.contents = arm
      m.roughness.textureComponents = .green
      m.metalness.contents = arm
      m.metalness.textureComponents = .blue
    }
    if let rough = url("rough", entry) {
      m.roughness.contents = rough
      m.roughness.textureComponents = .red
    }
    if let normal = url("normal", entry) {
      m.normal.contents = normal
      // Generated surface maps carry their intended strength; scanned props are softened.
      m.normal.intensity = (entry["asset"] as? String) == "generated" ? 1.0 : 0.8
    }
    if (entry["foliage"] as? Bool) == true {
      m.isDoubleSided = true
    }
    if (entry["grille"] as? Bool) == true {
      m.diffuse.contents = atelierHex(0x2A2D30)
      m.roughness.contents = 0.6
      m.metalness.contents = 0.6
    }
    if let tile = entry["tile"] as? Double {
      // Ground UV0 is a cube projection of 2 m; the texture repeats every `tile` metres.
      let s = Float(2 / tile)
      let t = SCNMatrix4MakeScale(.init(s), .init(s), 1)
      for p in [m.diffuse, m.roughness, m.normal] {
        p.contentsTransform = t
        p.wrapS = .repeat
        p.wrapT = .repeat
      }
    }
  }

  func applyAll(_ node: SCNNode) {
    node.enumerateHierarchy { n, _ in
      n.geometry?.materials.forEach { apply(to: $0) }
    }
  }

  /// The factory-yard HDRI as a linear half-float image (normalised to mean luminance 1).
  static func environment(folder: URL) -> CGImage? {
    let url = folder.appendingPathComponent("factory_yard_1k.hdr")
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let hdr = RadianceImage(data: data) else {
      return nil
    }
    let mean = hdr.meanLuminance
    guard mean.isFinite, mean > 0 else { return nil }
    // The HDRI's own sun disc is clamped and the sky desaturated 85 % (as in the bake): the
    // real-time sun replaces the disc, and the yard's warm-green cast does not tint the scene.
    var px = hdr.pixels
    let limit = 6 * mean
    for i in stride(from: 0, to: px.count, by: 3) {
      var l = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]
      if l > limit {
        let k = limit / l
        px[i] *= k
        px[i + 1] *= k
        px[i + 2] *= k
        l = limit
      }
      for c in 0..<3 { px[i + c] = px[i + c] * 0.15 + l * 0.85 }
    }
    return RadianceImage(width: hdr.width, height: hdr.height, pixels: px).cgImage(scale: 1 / mean)
  }

  /// A baked irradiance lightmap as a linear half-float image. The kit stores it as an 8-bit PNG
  /// with gamma 2.2 over 0…range (atelier_materials.json «gi»); decoded here back to linear.
  func lightmap(_ mode: AtelierLighting, scale: Float = 1) -> CGImage? {
    guard let gi = gi, let file = gi[mode == .day ? "day" : "night"] as? String else { return nil }
    let range = Float(gi["range"] as? Double ?? 4), gamma = Float(gi["gamma"] as? Double ?? 2.2)
    let url = folder.appendingPathComponent(file)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
      guard let ctx = CGContext(
        data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { return false }
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard drawn else { return nil }
    var table = [Float](repeating: 0, count: 256)
    for i in 0..<256 { table[i] = pow(Float(i) / 255, gamma) * range * scale }
    var pixels = [Float](repeating: 0, count: w * h * 3)
    for i in 0..<(w * h) {
      pixels[i * 3] = table[Int(bytes[i * 4])]
      pixels[i * 3 + 1] = table[Int(bytes[i * 4 + 1])]
      pixels[i * 3 + 2] = table[Int(bytes[i * 4 + 2])]
    }
    return RadianceImage(width: w, height: h, pixels: pixels).cgImage(scale: 1)
  }

  /// Tangent-space normal map of a profiled sheet: 4 trapezoid ribs across V (RGBA 8-bit).
  static let ribNormal: CGImage? = {
    let w = 8, h = 128
    guard let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    for y in 0..<h {
      let u = Double(y % 32) / 32                     // one rib = 32 px
      // Slope of a trapezoid profile: rising flank, flat crest, falling flank, flat valley.
      let slope: Double = u < 0.15 ? 1 : u < 0.5 ? 0 : u < 0.65 ? -1 : 0
      let n = simd_normalize(SIMD3<Double>(0, -slope * 0.8, 1))
      ctx.setFillColor(red: 0.5, green: CGFloat(n.y * 0.5 + 0.5), blue: CGFloat(n.z * 0.5 + 0.5), alpha: 1)
      ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
    }
    return ctx.makeImage()
  }()

  /// Radial falloff used by contact shadows (white = no darkening).
  static let blobImage: CGImage? = {
    // RGBA 8-bit: a single-channel image becomes R8Unorm_sRGB, which Metal rejects in the
    // simulator (SIGABRT in SCNMTLResourceManager).
    let w = 64, h = 64
    guard let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    for y in 0..<h {
      for x in 0..<w {
        let dx = (Double(x) + 0.5) / Double(w) * 2 - 1
        let dy = (Double(y) + 0.5) / Double(h) * 2 - 1
        let d = min(1, (dx * dx * dx * dx + dy * dy * dy * dy).squareRoot().squareRoot())
        let v = 1 - 0.55 * (1 - d * d) * (1 - d * d)
        ctx.setFillColor(red: v, green: v, blue: v, alpha: 1)
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    return ctx.makeImage()
  }()
}
