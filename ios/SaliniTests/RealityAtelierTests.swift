import RealityKit
import XCTest

@testable import Salini

/// RealityKit «Отгрузка»: the loaded entities really stand where the demonstration timeline
/// says, with their true dimensions (up axis kept), inside the truck when loaded, and the truck
/// really drives away. Uses the bundled kit.
@MainActor
final class RealityAtelierTests: XCTestCase {
  private static var shared: RealityAtelierScene?

  private func scene() async throws -> RealityAtelierScene {
    if let s = Self.shared { return s }
    let folder = try XCTUnwrap(Bundle.main.url(forResource: "InsightAssets", withExtension: nil))
    let models = Bundle.main.url(forResource: "CatalogMedia", withExtension: nil)?.appendingPathComponent("models")
    let s = RealityAtelierScene(folder: folder, models: models)
    try await s.load()
    Self.shared = s
    return s
  }

  func testLightingLoadsWithLightmapAndProbes() async throws {
    let s = try await scene()
    XCTAssertTrue(s.report.contains { $0.hasPrefix("lightmap ") && $0.contains("entities") }, "\(s.report)")
    XCTAssertFalse(s.report.contains { $0.contains("FAILED") }, "\(s.report)")
    XCTAssertFalse(s.diagnostics.skyEverywhere, "the sky light stays outside (it suppresses the hall probe)")
  }

  func testForkliftAndBatchFollowTheTimelineWithTrueDimensions() async throws {
    let s = try await scene()
    let p = s.timeline.pose(at: 20)                         // carrying, turning towards the dock
    s.apply(p)
    XCTAssertEqual(s.forklift.position.x, p.forklift.x, accuracy: 0.001)
    XCTAssertEqual(s.forklift.position.z, p.forklift.y, accuracy: 0.001)
    let b = s.batch.visualBounds(relativeTo: nil)
    XCTAssertEqual(b.extents.y, AtelierTimeline.batchSize.y, accuracy: 0.05, "pallet lies flat (up axis kept)")
    XCTAssertGreaterThanOrEqual(b.min.y, s.layout.floor + 0.15, "carried above the floor")
    let f = s.forklift.visualBounds(relativeTo: nil)
    XCTAssertLessThanOrEqual(f.max.y - s.layout.floor, AtelierTimeline.height + AtelierTimeline.carry + 0.05)
  }

  func testPlacedBatchIsInsideTheTrailerAndTheFullTruckDrivesAway() async throws {
    let s = try await scene()
    let placed = s.timeline.pose(at: 36)                    // first batch set down in slot 0
    s.apply(placed)
    let b = s.batch.visualBounds(relativeTo: nil)
    XCTAssertGreaterThanOrEqual(b.min.x, s.layout.trailerMin.x)
    XCTAssertLessThanOrEqual(b.max.x, s.layout.trailerMax.x)
    XCTAssertGreaterThanOrEqual(b.min.z, s.layout.trailerMin.z)
    XCTAssertLessThanOrEqual(b.max.z, s.layout.trailerMax.z)
    XCTAssertLessThanOrEqual(b.max.y, s.layout.trailerMax.y, "under the trailer roof")
    XCTAssertEqual(b.min.y, s.layout.floor, accuracy: 0.03, "standing on the deck")
    let truck = try XCTUnwrap(s.truck)
    let docked = truck.position.x
    let leaving = s.timeline.pose(at: AtelierTimeline.period * 3 + 45)
    s.apply(leaving)
    XCTAssertEqual(truck.position.x - docked, leaving.truckOffset, accuracy: 0.01)
    XCTAssertGreaterThan(leaving.truckOffset, 5)
    XCTAssertEqual(s.loaded.filter(\.isEnabled).count, leaving.loaded, "earlier batches ride with the truck")
    for e in s.loaded where e.isEnabled {
      XCTAssertGreaterThan(e.position.x, s.layout.slots.min()! + 5, "loaded batches moved with the truck")
    }
  }

  /// Framing: the fitted truck (the whole docked truck at t = 30) lies inside the free band of a
  /// phone screen, between the header (top 17 %) and the card (bottom 22 %).
  func testFittedTruckLiesInsideTheFreeBand() async throws {
    let s = try await scene()
    let (aspect, top, bottom): (Float, Float, Float) = (0.46, 0.17, 0.22)
    s.azimuth = 0
    s.apply(s.timeline.pose(at: 30))
    s.scale = s.fitScale(.truck, aspect: aspect, top: top, bottom: bottom)
    s.focus = s.followFocus(.truck, top: top, bottom: bottom)
    let m = s.camera.transformMatrix(relativeTo: nil)
    let right = simd_normalize(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z))
    let up = simd_normalize(SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z))
    let b = s.followBounds(.truck)
    XCTAssertGreaterThan(b.extents.x, 12, "the whole truck, cab included")
    for i in 0..<8 {
      let c = SIMD3(i & 1 == 0 ? b.min.x : b.max.x, i & 2 == 0 ? b.min.y : b.max.y, i & 4 == 0 ? b.min.z : b.max.z)
      let o = c - s.focus
      XCTAssertLessThanOrEqual(abs(simd_dot(o, right)), s.scale * aspect + 0.01, "inside the width")
      XCTAssertLessThanOrEqual(simd_dot(o, up), s.scale * (1 - 2 * top) + 0.01, "below the header")
      XCTAssertGreaterThanOrEqual(simd_dot(o, up), -s.scale * (1 - 2 * bottom) - 0.01, "above the card")
    }
  }

  /// A leaving truck is followed by its visible part (it never drags the camera off the site);
  /// once the loaded truck has pulled out, the followed batch is the next one at the pickup.
  func testFollowTargetsStayOnTheSite() async throws {
    let s = try await scene()
    s.apply(s.timeline.pose(at: AtelierTimeline.period * 3 + 45))
    XCTAssertLessThanOrEqual(s.followBounds(.truck).max.x, RealityAtelierScene.siteLimitX)
    s.apply(s.timeline.pose(at: AtelierTimeline.period * 3 + 47.2))
    XCTAssertLessThan(s.pose.truckOpacity, 0.5)
    let c = s.followBounds(.batch).center
    XCTAssertEqual(c.x, s.layout.pickup.x, accuracy: 0.01)
    XCTAssertEqual(c.z, s.layout.pickup.y, accuracy: 0.01)
  }

  /// Following keeps the hall around the batch and the forklift (no close-up of one machine).
  func testFollowFramingKeepsContext() async throws {
    let s = try await scene()
    s.apply(s.timeline.pose(at: 19))
    for subject in [AtelierSubject.batch, .forklift] {
      XCTAssertGreaterThanOrEqual(s.fitScale(subject, aspect: 0.46, top: 0.17, bottom: 0.22), 8)
    }
  }

  /// The roof is cut only while the batch is inside the docked trailer, and restored otherwise.
  func testTrailerCutOnlyWhileTheBatchIsInside() async throws {
    let s = try await scene()
    s.apply(s.timeline.pose(at: 34))                        // set down in slot 0, under the roof
    XCTAssertTrue(s.batchInTrailer)
    s.setTrailerCut(true)
    XCTAssertEqual(s.roofOpacity, RealityAtelierScene.cutOpacity, accuracy: 0.001)
    s.apply(s.timeline.pose(at: 19))                        // on the forks in the hall
    XCTAssertFalse(s.batchInTrailer)
    s.setTrailerCut(false)
    XCTAssertEqual(s.roofOpacity, 1)
    s.apply(s.timeline.pose(at: AtelierTimeline.period * 3 + 44))   // the loaded truck is leaving
    XCTAssertFalse(s.batchInTrailer, "a moving truck keeps its roof")
  }

  /// Night swaps the light owners (night atlas, night panoramas, moon, fixtures) and back.
  func testNightAndDayLighting() async throws {
    let s = try await scene()
    await s.setLighting(.night)
    XCTAssertEqual(s.lighting, .night)
    XCTAssertFalse(s.report.contains { $0.contains("FAILED") || $0.contains("missing") }, "\(s.report)")
    await s.setLighting(.day)
    XCTAssertEqual(s.lighting, .day)
  }

  func testTappedChildrenResolveToTheirSubject() async throws {
    let s = try await scene()
    let child = try XCTUnwrap(s.forklift.children.first)
    XCTAssertEqual(s.subject(of: child), .forklift)
    XCTAssertEqual(s.subject(of: s.batch.children.first ?? s.batch), .batch)
    XCTAssertNil(s.subject(of: s.root))
  }
}
