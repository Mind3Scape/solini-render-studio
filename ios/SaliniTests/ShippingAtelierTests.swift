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

  func testBatchWaitsRidesTheForksAndEndsInTheTruck() {
    if case .pickup = timeline.pose(at: 2).batch {} else { XCTFail("waits on the pickup square") }
    XCTAssertEqual(timeline.pose(at: 18).batch, .forks)
    XCTAssertEqual(timeline.pose(at: 36).batch, .slot(0))
    // While carried, the fork is raised; on the pickup and in the truck the fork is down.
    XCTAssertGreaterThan(timeline.pose(at: 18).fork, 0.2)
    XCTAssertEqual(timeline.pose(at: 0).fork, 0, accuracy: 0.001)
    XCTAssertEqual(timeline.pose(at: 34).fork, 0, accuracy: 0.001)
  }

  func testForkliftPicksUpExactlyAtThePickupAndUnloadsAtTheSlot() {
    let layout = AtelierLayout()
    let pick = timeline.pose(at: 9)
    let forward = SIMD2<Float>(cos(pick.heading), -sin(pick.heading))
    let forks = pick.forklift + forward * AtelierTimeline.forkReach
    XCTAssertEqual(forks.x, layout.pickup.x, accuracy: 0.05)
    XCTAssertEqual(forks.y, layout.pickup.y, accuracy: 0.05)
    let drop = timeline.pose(at: 32)
    XCTAssertEqual(drop.forklift.x + AtelierTimeline.forkReach, layout.slots[0], accuracy: 0.05)
    XCTAssertEqual(drop.forklift.y, layout.dockZ, accuracy: 0.05)
  }

  func testSlotsFillOneByOneAndTheFullTruckLeaves() {
    let p = AtelierTimeline.period
    XCTAssertEqual(timeline.pose(at: p * 1 + 36).batch, .slot(1))
    XCTAssertEqual(timeline.pose(at: p * 2 + 10).loaded, 2)
    // The full truck really drives away with its four batches, an empty one backs in before
    // the forklift reaches the dock, and the card's count follows.
    let leaving = timeline.pose(at: p * 3 + 45)
    XCTAssertEqual(leaving.truck, .departing)
    XCTAssertGreaterThan(leaving.truckOffset, 5)
    XCTAssertEqual(leaving.inTruck, 4)
    XCTAssertEqual(timeline.pose(at: p * 3 + 40).truckOffset, 0, "stays docked until the forklift is out")
    XCTAssertEqual(timeline.pose(at: p * 4 + 1).truck, .away)
    XCTAssertEqual(timeline.pose(at: p * 4 + 1).loaded, 0, "a new truck starts empty")
    XCTAssertEqual(timeline.pose(at: p * 4 + 8).truck, .arriving)
    let docked = timeline.pose(at: p * 4 + 14)
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
    XCTAssertLessThan(bytes, 40 * 1024 * 1024, "proof resources stay under the agreed 40 MB")
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
