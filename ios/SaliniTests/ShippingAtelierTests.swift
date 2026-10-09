import SceneKit
import XCTest

@testable import Salini

/// «Участок отгрузки» proof: deterministic demonstration, real kit resources in the bundle, the
/// Alda scale anchor, downloaded CC0 props actually in the visible scene, and the size budget.
final class ShippingAtelierTests: XCTestCase {
  private let timeline = AtelierTimeline(layout: AtelierLayout())

  func testCycleRunsThroughEveryStageInOrder() {
    var seen: [AtelierStage] = []
    for k in 0..<Int(AtelierTimeline.period * 4) {
      let stage = timeline.pose(at: Double(k) / 4).stage
      if seen.last != stage { seen.append(stage) }
    }
    XCTAssertEqual(seen, AtelierStage.allCases)
  }

  private typealias Phase = AtelierTimeline.Phase

  func testBatchWaitsRidesTheForksAndEndsInTheTruck() {
    if case .pickup = timeline.pose(at: 2).batch {} else { XCTFail("waits on the pickup square") }
    XCTAssertEqual(timeline.pose(at: 20).batch, .forks)
    XCTAssertEqual(timeline.pose(at: Phase.lower.upperBound + 0.5).batch, .slot(0))
    // While carried, the fork is raised; on the pickup and in the truck the fork is down.
    XCTAssertGreaterThan(timeline.pose(at: 20).fork, 0.2)
    XCTAssertEqual(timeline.pose(at: 0).fork, AtelierTimeline.emptyFork, accuracy: 0.001)
    XCTAssertEqual(timeline.pose(at: Phase.lower.upperBound + 0.2).fork, 0, accuracy: 0.001, "lowered onto the deck")
  }

  func testForkliftPicksUpExactlyAtThePickupAndUnloadsAtTheSlot() {
    let layout = AtelierLayout()
    let pick = timeline.pose(at: Phase.lift.lowerBound + 1)
    let forward = SIMD2<Float>(cos(pick.heading), -sin(pick.heading))
    let forks = pick.forklift + forward * AtelierTimeline.forkReach
    XCTAssertEqual(forks.x, layout.pickup.x, accuracy: 0.01)
    XCTAssertEqual(forks.y, layout.pickup.y, accuracy: 0.01)
    let drop = timeline.pose(at: Phase.lower.lowerBound + 1)
    XCTAssertEqual(drop.forklift.x + AtelierTimeline.forkReach, layout.slots[0], accuracy: 0.01)
    XCTAssertEqual(drop.forklift.y, layout.dockZ, accuracy: 0.01)
  }

  /// The forklift drives like one: the front (drive) axle never slides sideways, heading
  /// follows the path, speed, acceleration, yaw and the rear steering stay in a forklift's range.
  func testDrivingIsKinematicallyConsistent() {
    let dt = 0.1
    var prev = timeline.pose(at: 0)
    var prevSpeed: Float = 0
    for k in 1...Int(AtelierTimeline.period * 4 / dt) {
      let t = Double(k) * dt
      let p = timeline.pose(at: t)
      defer { prev = p }
      let f0 = SIMD2<Float>(cos(prev.heading), -sin(prev.heading)), f1 = SIMD2<Float>(cos(p.heading), -sin(p.heading))
      let d = (p.forklift - f1 * AtelierTimeline.frontAxle) - (prev.forklift - f0 * AtelierTimeline.frontAxle)
      let speed = simd_length(d) / Float(dt)
      defer { prevSpeed = speed }
      if simd_length(d) > 0.01 {
        let f = simd_normalize(f0 + f1)
        XCTAssertLessThan(abs(d.x * f.y - d.y * f.x) / simd_length(d), 0.01, "front axle slides sideways at \(t)")
      }
      XCTAssertLessThanOrEqual(speed, 2.0, "speed at \(t)")
      XCTAssertLessThanOrEqual(abs(speed - prevSpeed) / Float(dt), 1.0, "acceleration at \(t)")
      XCTAssertLessThanOrEqual(abs(p.steer), 65 * .pi / 180, "steering angle at \(t)")
      XCTAssertLessThanOrEqual(abs(p.steer - prev.steer) / Float(dt), 90 * .pi / 180, "steering rate at \(t)")
      var dh = p.heading - prev.heading
      while dh > .pi { dh -= 2 * .pi }
      while dh < -.pi { dh += 2 * .pi }
      XCTAssertLessThanOrEqual(abs(dh) / Float(dt), 60 * .pi / 180, "yaw rate at \(t)")
    }
  }

  /// A load is lifted, tilted and lowered only while the forklift stands still; it sits still on
  /// the pickup square until the forks rise and in the trailer once set down; the forks enter
  /// the pallet straight, below its deck.
  func testLoadIsHandledOnlyAtStandstill() {
    var prev = timeline.pose(at: 0)
    for k in 1...Int(AtelierTimeline.period * 4 * 30) {
      let p = timeline.pose(at: Double(k) / 30)
      defer { prev = p }
      let loaded = p.batch == .forks || prev.batch == .forks
      if loaded && (abs(p.fork - prev.fork) > 1e-5 || abs(p.tilt - prev.tilt) > 1e-5) {
        XCTAssertLessThan(abs(p.speed), 0.01, "load moved on the mast while driving, t=\(p.time)")
        XCTAssertLessThan(simd_distance(p.forklift, prev.forklift), 1e-4, "t=\(p.time)")
      }
      if case .pickup = p.batch, p.time > Phase.approach.lowerBound {
        // Approach: forks under the deck, heel on the pallet's axis.
        XCTAssertLessThanOrEqual(p.fork, AtelierTimeline.emptyFork + 1e-4)
        XCTAssertEqual(p.forklift.y, AtelierLayout().pickup.y, accuracy: 0.002)
      }
    }
  }

  /// Every hall obstacle near the route (from the kit script) keeps ≥ 0.4 m from the forklift
  /// and its load: columns, the east wall, the dock-1 staging, the packing area and the QC
  /// station beside the pickup.
  func testRouteClearsTheHallObstacles() {
    let obstacles: [(String, SIMD2<Float>, SIMD2<Float>)] = [
      ("crane column", SIMD2(9.05, 7.45), SIMD2(9.35, 7.75)), ("crane column east", SIMD2(13.45, 7.45), SIMD2(13.75, 7.75)),
      ("wall column", SIMD2(13.43, 9.85), SIMD2(13.73, 10.15)), ("dock-1 staging", SIMD2(12.4, 5.8), SIMD2(13.4, 7.6)),
      ("east wall", SIMD2(13.72, 8.0), SIMD2(14.0, 12.0)), ("east wall south", SIMD2(13.72, 15.0), SIMD2(14.0, 20.0)),
      ("packing table", SIMD2(3.95, 8.9), SIMD2(5.95, 9.85)), ("racking", SIMD2(3.35, 10.9), SIMD2(4.55, 19.0)),
      ("QC 04 frame", SIMD2(8.2, 7.6), SIMD2(8.3, 7.7)), ("QC 04 trolley", SIMD2(7.45, 7.18), SIMD2(8.05, 7.58)),
    ]
    for p in samples(cycles: 4) {
      let f = SIMD2<Float>(cos(p.heading), -sin(p.heading)), side = SIMD2<Float>(-f.y, f.x)
      var points: [SIMD2<Float>] = []
      for a in stride(from: -AtelierTimeline.bodyBack, through: AtelierTimeline.forkLength, by: 0.1) {
        for b in stride(from: -AtelierTimeline.halfWidth, through: AtelierTimeline.halfWidth, by: 0.1) { points.append(p.forklift + f * a + side * b) }
      }
      if p.batch == .forks {
        let c = p.forklift + f * AtelierTimeline.forkReach
        for a in stride(from: Float(-0.5), through: 0.5, by: 0.1) {
          for b in stride(from: Float(-0.9), through: 0.9, by: 0.1) { points.append(c + f * a + side * b) }
        }
      }
      for (name, lo, hi) in obstacles {
        for q in points {
          let dx = max(lo.x - q.x, 0, q.x - hi.x), dz = max(lo.y - q.y, 0, q.y - hi.y)
          XCTAssertGreaterThanOrEqual((dx * dx + dz * dz).squareRoot(), 0.4, "\(name) at t=\(p.cycle):\(p.time)")
        }
      }
    }
  }

  func testSlotsFillOneByOneAndTheFullTruckLeaves() {
    let p = AtelierTimeline.period
    XCTAssertEqual(timeline.pose(at: p * 1 + Phase.lower.upperBound + 0.5).batch, .slot(1))
    XCTAssertEqual(timeline.pose(at: p * 2 + 10).loaded, 2)
    // The full truck really drives away with its four batches, an empty one backs in before
    // the forklift reaches the dock, and the card's count follows.
    let leaving = timeline.pose(at: p * 3 + timeline.clearOfTrailer + 6)
    XCTAssertEqual(leaving.truck, .departing)
    XCTAssertGreaterThan(leaving.truckOffset, 5)
    XCTAssertEqual(leaving.inTruck, 4)
    XCTAssertEqual(timeline.pose(at: p * 3 + timeline.clearOfTrailer).truckOffset, 0, "stays docked until the forklift is out")
    XCTAssertEqual(timeline.pose(at: p * 4 + 1).truck, .away)
    XCTAssertEqual(timeline.pose(at: p * 4 + 1).loaded, 0, "a new truck starts empty")
    XCTAssertEqual(timeline.pose(at: p * 4 + 8).truck, .arriving)
    let docked = timeline.pose(at: p * 4 + 16.5)
    XCTAssertEqual(docked.truck, .docked)
    XCTAssertEqual(docked.truckOffset, 0)
    XCTAssertEqual(docked.truckOpacity, 1)
    XCTAssertEqual(timeline.pose(at: 5).truck, .docked, "the very first truck is already at the dock")
    XCTAssertEqual(timeline.pose(at: p * 4 + 1).batchNumber, 218)
  }

  func testMotionIsContinuousWithoutJumps() {
    var last = timeline.pose(at: 0)
    for k in 1...Int(AtelierTimeline.period * 5 * 30) {
      let p = timeline.pose(at: Double(k) / 30)
      XCTAssertLessThan(simd_distance(p.forklift, last.forklift), 0.25, "at \(Double(k) / 30) s")
      // The truck jumps only while invisible (from far away back to the far start).
      if p.truckOpacity > 0.01 && last.truckOpacity > 0.01 {
        XCTAssertLessThan(abs(p.truckOffset - last.truckOffset), 0.5, "truck at \(Double(k) / 30) s")
      }
      last = p
    }
  }

  // MARK: Loading mechanics — clearances along the whole route (several cycles, 30 samples/s)

  private struct Rect {
    var corners: [SIMD2<Float>]
    func minX() -> Float { corners.map(\.x).min()! }
    func maxX() -> Float { corners.map(\.x).max()! }
    func minZ() -> Float { corners.map(\.y).min()! }
    func maxZ() -> Float { corners.map(\.y).max()! }
  }
  /// A footprint rectangle from `back` behind to `front` ahead of `origin` along `heading`.
  private func footprint(_ origin: SIMD2<Float>, _ heading: Float, back: Float, front: Float, half: Float) -> Rect {
    let f = SIMD2<Float>(cos(heading), -sin(heading)), s = SIMD2<Float>(-f.y, f.x)
    return Rect(corners: [origin - f * back - s * half, origin - f * back + s * half,
                          origin + f * front - s * half, origin + f * front + s * half])
  }
  private func forkliftRect(_ p: AtelierPose) -> Rect {
    footprint(p.forklift, p.heading, back: AtelierTimeline.bodyBack, front: AtelierTimeline.forkLength,
              half: AtelierTimeline.halfWidth)
  }
  private func batchRect(_ p: AtelierPose) -> Rect {
    let c = p.forklift + SIMD2(cos(p.heading), -sin(p.heading)) * AtelierTimeline.forkReach
    let size = AtelierTimeline.batchSize
    return footprint(c, p.heading, back: size.x / 2, front: size.x / 2, half: size.z / 2)
  }
  private func slotRect(_ x: Float, _ layout: AtelierLayout) -> Rect {
    let size = AtelierTimeline.batchSize
    return footprint(SIMD2(x, layout.dockZ), 0, back: size.x / 2, front: size.x / 2, half: size.z / 2)
  }
  /// Gap between two rectangles along x or z (negative = overlap); good enough for the
  /// axis-aligned trailer slots and a forklift driving along the trailer axis.
  private func gap(_ a: Rect, _ b: Rect) -> Float {
    max(b.minX() - a.maxX(), a.minX() - b.maxX(), b.minZ() - a.maxZ(), a.minZ() - b.maxZ())
  }
  private func samples(cycles: Int = 5, layout: AtelierLayout = AtelierLayout()) -> [AtelierPose] {
    let timeline = AtelierTimeline(layout: layout)
    return (0..<Int(AtelierTimeline.period * Double(cycles) * 30)).map { timeline.pose(at: Double($0) / 30) }
  }

  func testForkliftAndBatchStayInsideTheTrailerAndDockOpening() {
    checkInsideTrailer(AtelierLayout())
  }
  private func checkInsideTrailer(_ layout: AtelierLayout) {
    let wallMargin: Float = 0.1
    var worstSide = Float.greatestFiniteMagnitude
    for p in samples(layout: layout) {
      var shapes = [forkliftRect(p)]
      if p.batch == .forks { shapes.append(batchRect(p)) }
      for r in shapes {
        for c in r.corners {
          if c.x > layout.trailerMin.x {                       // inside the trailer: between its walls
            let side = min(c.y - layout.trailerMin.z, layout.trailerMax.z - c.y)
            worstSide = min(worstSide, side)
            XCTAssertGreaterThanOrEqual(side, wallMargin, "side wall at t=\(p.cycle):\(p.time)")
            XCTAssertLessThanOrEqual(c.x, layout.trailerMax.x - wallMargin, "front wall at t=\(p.time)")
          } else if c.x > layout.dockX - 0.4 {                 // through the dock opening (jambs)
            XCTAssertGreaterThanOrEqual(c.y, layout.dockOpening.lowerBound + wallMargin, "jamb at t=\(p.time)")
            XCTAssertLessThanOrEqual(c.y, layout.dockOpening.upperBound - wallMargin, "jamb at t=\(p.time)")
          }
        }
      }
    }
    XCTAssertGreaterThan(worstSide, 0.2, "the narrowest side clearance in the trailer")
  }

  func testHeightsClearTheTrailerRoofAndTheForksCarryAboveTheFloor() {
    let layout = AtelierLayout()
    let roofGap = layout.trailerMax.y - layout.trailerMin.y - AtelierTimeline.height
    XCTAssertGreaterThanOrEqual(roofGap, 0.2, "forklift under the trailer roof")
    let batchTop = AtelierTimeline.lift(AtelierTimeline.carry) + AtelierTimeline.batchSize.y
    XCTAssertGreaterThanOrEqual(layout.trailerMax.y - layout.trailerMin.y - batchTop, 0.5, "carried batch under the roof")
    var last: AtelierPose?
    for p in samples(cycles: 2) {
      defer { last = p }
      guard let l = last, p.batch == .forks, l.batch == .forks else { continue }
      let moving = simd_distance(p.forklift, l.forklift) > 0.0005
      if moving {
        XCTAssertGreaterThanOrEqual(AtelierTimeline.lift(p.fork), 0.15, "batch above the floor while driving, t=\(p.time)")
      }
    }
  }

  func testNothingPassesThroughEarlierLoadsAndTheTruckOnlyMovesWhenTheForkliftIsOut() {
    checkLoads(AtelierLayout())
  }
  private func checkLoads(_ layout: AtelierLayout) {
    for p in samples(layout: layout) {
      let fork = forkliftRect(p)
      for k in 0..<p.loaded {
        let other = slotRect(layout.slots[k] + p.truckOffset, layout)
        XCTAssertGreaterThanOrEqual(gap(fork, other), 0.1, "forklift vs slot \(k) at t=\(p.time)")
        if p.batch == .forks { XCTAssertGreaterThanOrEqual(gap(batchRect(p), other), 0.15, "batch vs slot \(k)") }
      }
      if p.truckOffset > 0 || p.truck != .docked {
        XCTAssertLessThan(fork.maxX(), layout.trailerMin.x - 0.1, "forklift out before the truck moves, t=\(p.time)")
      }
      if case .slot(let k) = p.batch {
        let r = slotRect(layout.slots[k], layout)
        XCTAssertGreaterThanOrEqual(r.minZ() - layout.trailerMin.z, 0.1)
        XCTAssertGreaterThanOrEqual(layout.trailerMax.z - r.maxZ(), 0.1)
      }
    }
  }

  func testBatchIsCarriedUntilItIsSetDownInItsSlot() {
    let timeline = AtelierTimeline(layout: AtelierLayout())
    // Still on the forks while lowering; placed only once the forks are at the deck.
    XCTAssertEqual(timeline.pose(at: Phase.lower.upperBound - 0.6).batch, .forks)
    XCTAssertLessThan(AtelierTimeline.lift(timeline.pose(at: Phase.lower.upperBound - 0.01).fork), 0.01)
    XCTAssertEqual(timeline.pose(at: Phase.lower.upperBound + 0.1).batch, .slot(0))
    // Picked up only once the forks start rising from under the pallet.
    if case .pickup = timeline.pose(at: Phase.lift.lowerBound - 0.1).batch {} else { XCTFail("still on the pickup square") }
    XCTAssertEqual(AtelierTimeline.lift(timeline.pose(at: Phase.lift.lowerBound).fork), 0, accuracy: 0.001)
  }

  /// The real kit: the loaded forklift (body, mast, carriage, driver) and batch fit the envelope
  /// the clearance tests use, and the route is checked on the bundle's own trailer/dock anchors.
  func testLoadedGeometryFitsTheSafetyEnvelopeAndTheRouteClearsTheBundledTruck() throws {
    let scene = ShippingAtelierScene(resources: try XCTUnwrap(ShippingAtelierScene.Resources.bundled()))
    scene.show(time: 0)                               // forklift at home, batch on the pickup square
    let fork = try XCTUnwrap(scene.envelope(of: .forklift))
    XCTAssertGreaterThanOrEqual(fork.min.x, -AtelierTimeline.bodyBack - 0.01, "body behind the heel")
    XCTAssertLessThanOrEqual(fork.max.x, AtelierTimeline.forkLength + 0.01, "fork tips")
    XCTAssertLessThanOrEqual(max(-fork.min.z, fork.max.z), AtelierTimeline.halfWidth + 0.01, "width")
    XCTAssertLessThanOrEqual(fork.max.y, AtelierTimeline.height + AtelierTimeline.emptyFork + 0.01, "mast / guard height")
    XCTAssertGreaterThanOrEqual(fork.min.y, -0.02, "wheels on the floor")
    let batch = try XCTUnwrap(scene.envelope(of: .batch))
    let size = batch.max - batch.min
    XCTAssertLessThanOrEqual(size.x, AtelierTimeline.batchSize.x + 0.02)
    XCTAssertLessThanOrEqual(size.y, AtelierTimeline.batchSize.y + 0.02)
    XCTAssertLessThanOrEqual(size.z, AtelierTimeline.batchSize.z + 0.02)
    // The bundle's anchors, not the defaults: a real roof, the dock jambs, the slots.
    let layout = scene.layout
    XCTAssertGreaterThan(layout.trailerMax.y - layout.trailerMin.y, AtelierTimeline.height + 0.2, "trailer roof clearance")
    XCTAssertEqual(layout.dockOpening.upperBound - layout.dockOpening.lowerBound, 3.0, accuracy: 0.05)
    checkInsideTrailer(layout)
    checkLoads(layout)
  }

  func testBundledKitLoadsWithAnchorsAldaAndDownloadedProps() throws {
    let resources = try XCTUnwrap(ShippingAtelierScene.Resources.bundled(), "InsightAssets in the bundle")
    let scene = ShippingAtelierScene(resources: resources)
    XCTAssertTrue(scene.loadedKit)
    XCTAssertEqual(scene.layout.pickup.x, 7.4, accuracy: 0.01, "anchors come from the kit")
    XCTAssertEqual(scene.layout.slots.count, 4)
    XCTAssertGreaterThanOrEqual(scene.layout.nightLights.count, 6)
    // Salini catalogue products on the stations, each at its catalogue length (scale anchors).
    XCTAssertGreaterThanOrEqual(scene.productLengths.count, 4, "\(scene.productLengths)")
    for (file, length) in scene.productLengths {
      let expected = try XCTUnwrap(ShippingAtelierScene.catalogueLengths[file], file)
      XCTAssertEqual(length, expected, accuracy: 0.06, file)
    }
    XCTAssertEqual(scene.productLengths["Alda-160-70"] ?? 0, 1.615, accuracy: 0.06)
    XCTAssertGreaterThanOrEqual(scene.treeCount, 2, "the Poly Haven tree is instanced")
    XCTAssertTrue(scene.hasGI, "baked day/night irradiance is applied through selfIllumination")
    // At least four real downloaded Poly Haven props are textured in the visible static mesh.
    let props = scene.propMaterials.filter { !$0.hasPrefix("M_") }
    let assets = Set(props.map { $0.components(separatedBy: "_0").first ?? $0 })
    XCTAssertGreaterThanOrEqual(assets.count, 4, "props: \(props.sorted())")
    for node in ["Forklift", "Truck", "BatchCurrent"] {
      XCTAssertNotNil(scene.scene.rootNode.childNode(withName: node, recursively: true), node)
    }
  }

  func testAssetManifestListsWhatShipsAndBudgetHolds() throws {
    let folder = try XCTUnwrap(Bundle.main.url(forResource: "InsightAssets", withExtension: nil))
    let data = try Data(contentsOf: folder.appendingPathComponent("ASSETS.json"))
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let assets = try XCTUnwrap(json["assets"] as? [[String: Any]])
    XCTAssertGreaterThanOrEqual(assets.count, 8)
    for a in assets {
      let name = try XCTUnwrap(a["asset"] as? String)
      XCTAssertNotNil(a["source"] as? String, name)
      if name.hasPrefix("salini-") {
        // Salini's own product geometry: rights retained, recorded separately (not CC0).
        XCTAssertNotNil(a["rights"] as? String, name)
      } else {
        XCTAssertEqual(a["license"] as? String, "CC0-1.0", name)
      }
    }
    var bytes = 0
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
    while let url = files?.nextObject() as? URL {
      bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    XCTAssertLessThan(bytes, 80 * 1024 * 1024, "proof resources stay under the agreed 80 MB (quality pass)")
  }

  func testSelectionResolvesSubjectsFromChildNodes() throws {
    let scene = ShippingAtelierScene(resources: ShippingAtelierScene.Resources.bundled())
    let root = scene.scene.rootNode
    let fork = try XCTUnwrap(root.childNode(withName: "Forklift", recursively: true))
    let anyChild = fork.childNodes.first.flatMap { $0.childNodes.first ?? $0 } ?? fork
    XCTAssertEqual(scene.subject(of: anyChild), .forklift)
    let batch = try XCTUnwrap(root.childNode(withName: "BatchCurrent", recursively: true))
    XCTAssertEqual(scene.subject(of: batch.childNodes.first ?? batch), .batch)
    XCTAssertNil(scene.subject(of: root))
  }

  func testDayNightSwitchesTheSameScene() {
    let scene = ShippingAtelierScene(resources: ShippingAtelierScene.Resources.bundled())
    let nodes = scene.scene.rootNode.childNodes.count
    XCTAssertNotNil(scene.technique(for: .day), "PBR Neutral tone mapping compiles")
    scene.setLighting(.night, animated: false)
    XCTAssertEqual(scene.lighting, .night)
    XCTAssertLessThan(scene.scene.lightingEnvironment.intensity, 0.1)
    // Night spots light only the movers; the hall's lamps are baked into the night lightmap.
    let spots = scene.scene.rootNode.childNodes.compactMap(\.light).filter { $0.type == .spot }
    XCTAssertFalse(spots.isEmpty)
    XCTAssertTrue(spots.allSatisfy { $0.categoryBitMask == ShippingAtelierScene.moverMask })
    scene.setLighting(.day, animated: false)
    XCTAssertEqual(scene.scene.rootNode.childNodes.count, nodes, "no geometry is swapped for night")
  }
}
