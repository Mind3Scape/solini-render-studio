import SceneKit
import XCTest
@testable import Salini

final class RoomPlacementTests: XCTestCase {
  func testEveryBundledProductHasVerifiedMetreScaleAndRestsOnFloor() throws {
    XCTAssertEqual(StudioForm.all.count, 13)
    for form in StudioForm.all {
      let product = try XCTUnwrap(RoomProduct(form: form), form.name)
      let node: SCNNode
      do { node = try RoomAssetBuilder.build(product) }
      catch { XCTFail("\(form.name): \(error)"); continue }
      let (lo, hi) = node.boundingBox
      XCTAssertEqual(hi.x - lo.x, product.metres.x, accuracy: 0.001, form.name)
      XCTAssertEqual(hi.z - lo.z, product.metres.z, accuracy: 0.001, form.name)
      XCTAssertEqual(hi.y - lo.y, product.metres.y, accuracy: 0.001, form.name)
      XCTAssertEqual(lo.y, 0, accuracy: 0.0001, "\(form.name) must sit on the detected floor")
      XCTAssertEqual(lo.x + hi.x, 0, accuracy: 0.0001, form.name)
      XCTAssertEqual(lo.z + hi.z, 0, accuracy: 0.0001, form.name)
      XCTAssertEqual(node.scale.x, 1, accuracy: 0.0001)
      var vertexCount = 0
      node.enumerateChildNodes { n, _ in vertexCount += n.geometry?.sources(for: .vertex).first?.vectorCount ?? 0 }
      XCTAssertGreaterThan(vertexCount, 1000, "The real product mesh must be present")
    }
  }

  func testSelectionKeepsExactProductFinishAndAllowedRAL() throws {
    let form = try XCTUnwrap(StudioForm.noemi)
    let variant = try XCTUnwrap(form.product.variants.first { $0.material == "sStone" })
    let selection = try XCTUnwrap(RoomProduct.selection(form.product, variant: variant, colour: .ral("7016")))
    XCTAssertEqual(selection.form.product.id, form.product.id)
    XCTAssertEqual(selection.finish, .stoneMatte)
    XCTAssertEqual(selection.ral?.code, "7016")
    XCTAssertEqual(selection.metres.x, 1.705, accuracy: 0.0001)
    XCTAssertEqual(selection.metres.z, 0.755, accuracy: 0.0001)
    XCTAssertEqual(selection.metres.y, 0.690, accuracy: 0.0001)
    let unmodelled = try XCTUnwrap(Catalog.shared.products.first { $0.model == nil })
    XCTAssertNil(RoomProduct.selection(unmodelled, variant: unmodelled.variants.first, colour: .standard),
                 "Never substitute another product's mesh")
  }

  func testDragStaysOnEstablishedFloorAndRejectsHorizonOrDistantHits() throws {
    let p = try XCTUnwrap(RoomPlacementMath.floorPoint(near: SIMD3(0, 1.5, 0), far: SIMD3(2, -1.5, -4), floorY: 0.1))
    XCTAssertEqual(p.y, 0.1, accuracy: 0.0001)
    XCTAssertEqual(p.x, 0.933333, accuracy: 0.0001)
    XCTAssertEqual(p.z, -1.866667, accuracy: 0.0001)
    XCTAssertNil(RoomPlacementMath.floorPoint(near: SIMD3(0, 1, 0), far: SIMD3(4, 1, 0), floorY: 0))
    XCTAssertNil(RoomPlacementMath.floorPoint(near: SIMD3(0, 1, 0), far: SIMD3(0, 2, -1), floorY: 0))
    XCTAssertNil(RoomPlacementMath.floorPoint(near: SIMD3(0, 1, 0), far: SIMD3(100, 0, 0), floorY: 0))
    XCTAssertEqual(RoomPlacementMath.normalizedAngle(4 * .pi + 0.4), 0.4, accuracy: 0.0001)
  }

  @MainActor func testSimulatorExplainsCameraAvailabilityAndIncludesStudioEscape() throws {
    let form = try XCTUnwrap(StudioForm.noemi)
    let controller = RoomPlacementController(product: try XCTUnwrap(RoomProduct(form: form)))
    controller.loadViewIfNeeded()
    #if targetEnvironment(simulator)
    XCTAssertEqual(controller.stage, .unavailable)
    #endif
    XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription"))
    func find(_ v: UIView, _ id: String) -> UIView? {
      if v.accessibilityIdentifier == id { return v }
      return v.subviews.lazy.compactMap { find($0, id) }.first
    }
    XCTAssertNotNil(find(controller.view, "room.close"))
    let button = try XCTUnwrap(find(controller.view, "room.primary") as? UIButton)
    #if targetEnvironment(simulator)
    XCTAssertEqual(button.configuration?.title, "Открыть 3D-студию")
    #endif
    XCTAssertTrue(button.isEnabled)
    let size = try XCTUnwrap(find(controller.view, "room.dimensions") as? UILabel)
    XCTAssertTrue(size.text?.contains("1705 × 755 × 690") == true)
  }
}
