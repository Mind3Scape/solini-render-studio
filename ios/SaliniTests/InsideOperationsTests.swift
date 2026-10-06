import SceneKit
import XCTest

@testable import Salini

final class InsideOperationsTests: XCTestCase {
  func testForecastSchedulesEveryBathWithoutOverlappingPostWork() {
    let main = forecastAria(at: 900, plan: .mainQueue)
    let reserve = forecastAria(at: 900, plan: .reserve)
    XCTAssertEqual(main.readyTime, "17:20")
    XCTAssertEqual(reserve.readyTime, "16:45")
    XCTAssertEqual(reserve.reserveQuantity, 3)
    XCTAssertEqual(reserve.reserveMinutes, 45)
    for forecast in [main, reserve] {
      XCTAssertEqual(forecast.assignments.count, 4)
      for group in Dictionary(grouping: forecast.assignments, by: \.post).values {
        let sorted = group.sorted { $0.starts < $1.starts }
        for (a, b) in zip(sorted, sorted.dropFirst()) { XCTAssertLessThanOrEqual(a.ends, b.starts) }
      }
      XCTAssertEqual(forecast.readyMinute - forecast.processingEnds, 40)
    }
    XCTAssertGreaterThan(forecastAria(at: 940, plan: .reserve).readyMinute, reserve.readyMinute)
  }
  func testReserveUsesForecastForCompletionAndChangesAllViewsOfOrder() throws {
    let s = FactorySimulation()
    XCTAssertTrue(s.activateReserve())
    XCTAssertFalse(s.activateReserve())
    XCTAssertEqual(s.reserve, .preparing)
    for _ in 0..<3 { s.advance() }
    XCTAssertEqual(s.reserve, .preparing)
    s.advance()
    XCTAssertEqual(s.reserve, .processing)
    XCTAssertEqual(s.load(.finishing), 72)
    for _ in 0..<22 { s.advance() }
    XCTAssertTrue(s.ariaCompleted)
    XCTAssertEqual(s.reserve, .finished)
    XCTAssertEqual(s.minute, try XCTUnwrap(s.ariaAssignments).processingEnds)
    XCTAssertEqual(s.zone(for: .aria), .quality)
    XCTAssertEqual(s.count(.finishing), 14)
    XCTAssertEqual(s.count(.quality), 20)
    XCTAssertEqual(s.completed, 42, "Processing is not quality acceptance")
  }
  func testMainQueueIsARealAlternativeAndClosesReserveWindow() {
    let s = FactorySimulation()
    XCTAssertTrue(s.keepMainQueue())
    XCTAssertFalse(s.keepMainQueue())
    XCTAssertEqual(s.ariaForecast, "17:20")
    for _ in 0..<20 { s.advance() }
    XCTAssertEqual(s.clockTime, "15:50")
    XCTAssertFalse(s.canActivateReserve)
    XCTAssertFalse(s.activateReserve())
    for _ in 0..<20 { s.advance() }
    XCTAssertTrue(s.ariaCompleted)
    XCTAssertEqual(s.clockTime, "16:40")
    XCTAssertFalse(s.needsAttention(.aria))
  }
  func testMainQueueCanBeReplannedBeforeAnyBathStarts() {
    let s = FactorySimulation()
    s.keepMainQueue()
    for _ in 0..<4 { s.advance() }
    XCTAssertTrue(s.activateReserve())
    XCTAssertEqual(s.ariaPlan, .reserve)
    XCTAssertEqual(s.ariaForecast, forecastAria(at: 910, plan: .reserve).readyTime)
  }
  func testDispatchRequiresQualityThenPackingThenLoadingAndCannotRepeat() {
    let s = FactorySimulation()
    XCTAssertFalse(s.releaseMareaDispatch())
    XCTAssertTrue(s.startQualityCheck())
    XCTAssertFalse(s.startQualityCheck())
    for _ in 0..<11 { s.advance() }
    XCTAssertEqual(s.quality, .checking)
    XCTAssertEqual(s.completed, 42)
    s.advance()
    XCTAssertEqual(s.quality, .packing)
    XCTAssertEqual(s.completed, 54)
    XCTAssertEqual(s.zone(for: .marea), .packing)
    XCTAssertEqual(s.count(.packing), 24)
    XCTAssertFalse(s.releaseMareaDispatch())
    for _ in 0..<6 { s.advance() }
    XCTAssertEqual(s.quality, .loading)
    XCTAssertEqual(s.zone(for: .marea), .dispatch)
    XCTAssertFalse(s.releaseMareaDispatch())
    for _ in 0..<4 { s.advance() }
    XCTAssertEqual(s.quality, .ready)
    XCTAssertEqual(s.clockTime, "15:55")
    XCTAssertTrue(s.releaseMareaDispatch())
    let history = s.journal.count
    XCTAssertFalse(s.releaseMareaDispatch())
    XCTAssertEqual(s.journal.count, history)
    XCTAssertTrue(s.status(.marea).contains("в пути"))
    XCTAssertTrue(s.status(.domino).contains("в пути"))
    XCTAssertEqual(s.completed, 54)
  }
  func testPauseFreezesBothProcessesAndClockRestsAtDecisionPoints() {
    let s = FactorySimulation()
    for _ in 0..<30 { s.advance() }
    XCTAssertEqual(
      s.clockTime, "15:00", "Reading the scene must not silently consume the decision window")
    s.activateReserve()
    s.startQualityCheck()
    for _ in 0..<3 { s.advance() }
    s.paused = true
    let minute = s.minute
    let tick = s.tick
    for _ in 0..<100 { s.advance() }
    XCTAssertEqual(s.minute, minute)
    XCTAssertEqual(s.tick, tick)
    s.paused = false
    for _ in 0..<30 { s.advance() }
    XCTAssertTrue(s.ariaCompleted)
    XCTAssertEqual(s.quality, .ready)
    let stopped = s.minute
    for _ in 0..<50 { s.advance() }
    XCTAssertEqual(s.minute, stopped)
    XCTAssertEqual(s.completed, 54)
  }
  func testFurnitureSkipsMineralCastingAndMareaUsesDirectDispatch() {
    XCTAssertFalse(InsideOrderID.domino.route.contains(.casting))
    XCTAssertFalse(InsideOrderID.mirrors.route.contains(.materials))
    XCTAssertFalse(InsideOrderID.marea.route.contains(.warehouse))
    XCTAssertTrue(InsideOrderID.aria.route.contains(.warehouse))
  }
  @MainActor func testAllOperationsPanelsLoadAcrossStateTransitions() {
    let s = FactorySimulation()
    let destinations: [InsideDestination] =
      [.briefing, .orders, .dispatch, .events] + FactoryZone.allCases.map { .zone($0) }
      + InsideOrderID.allCases.map { .order($0) } + [
        .station(.finishing, "F-04"), .station(.quality, "Q-02"),
      ]
    for state in 0..<4 {
      if state == 1 {
        s.activateReserve()
        s.startQualityCheck()
      }
      if state == 2 { for _ in 0..<18 { s.advance() } }
      if state == 3 {
        for _ in 0..<20 { s.advance() }
        s.releaseMareaDispatch()
      }
      for destination in destinations {
        let panel = InsidePanelController(destination, simulation: s) { _, _ in }
        panel.loadViewIfNeeded()
        XCTAssertGreaterThan(panel.content.arrangedSubviews.count, 1)
      }
    }
  }
  @MainActor func testSceneLensesAndBothDeparturesPreserveCameraIsometry() throws {
    let s = FactorySimulation()
    let scene = FactorySceneView()
    scene.frame = CGRect(x: 0, y: 0, width: 402, height: 520)
    scene.layoutIfNeeded()
    let orientation = try XCTUnwrap(scene.pointOfView).orientation
    for lens in CampusLens.allCases {
      scene.apply(s, lens: lens, tracked: .aria)
      scene.showOrderRoute(InsideOrderID.aria.route)
      scene.focusOn(.finishing, animated: false)
      XCTAssertEqual(scene.pointOfView!.orientation.x, orientation.x, accuracy: 0.0001)
    }
    s.startQualityCheck()
    for _ in 0..<22 { s.advance() }
    s.releaseMareaDispatch()
    s.releaseDispatch()
    scene.apply(s, lens: .orders, tracked: .marea)
    scene.apply(s, lens: .orders, tracked: .marea)
    scene.setPaused(true)
    XCTAssertEqual(scene.pointOfView!.orientation.w, orientation.w, accuracy: 0.0001)
  }
  @MainActor func testMapFocusStaysInUsableViewportAboveGlass() throws {
    let scene = FactorySceneView()
    scene.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    for insets in [
      UIEdgeInsets(top: 238, left: 0, bottom: 220, right: 0),
      UIEdgeInsets(top: 135, left: 0, bottom: 180, right: 0),
      UIEdgeInsets(top: 135, left: 35, bottom: 330, right: 5),
    ] {
      scene.mapContentInsets = insets
      scene.layoutIfNeeded()
      scene.focusOn(.finishing, animated: false)
      // An offscreen SCNView does not advance its presentation tree without a render.
      SCNTransaction.flush()
      _ = scene.snapshot()
      let visible = scene.bounds.inset(by: insets)
      let projected = scene.projectPoint(scene.mapCamera.focus)
      XCTAssertEqual(CGFloat(projected.x), visible.midX, accuracy: 1)
      XCTAssertEqual(CGFloat(projected.y), visible.midY, accuracy: 1)
      let orientation = try XCTUnwrap(scene.pointOfView).orientation
      scene.stepZoom(true)
      XCTAssertEqual(scene.pointOfView!.orientation.w, orientation.w, accuracy: 0.0001)
    }
  }

}
