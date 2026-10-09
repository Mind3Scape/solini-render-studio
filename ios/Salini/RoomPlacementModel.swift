import SceneKit
import UIKit
import simd

/// The showroom framing is deliberately independent of the physical, catalogue-sized AR asset.
struct RoomProduct {
  let form: StudioForm
  let finish: StudioFinish
  let ral: RALColour?
  let metres: SIMD3<Float> // longest horizontal side, height, shorter horizontal side

  init?(form: StudioForm, finish: StudioFinish? = nil, ral: RALColour? = nil) {
    let d = form.product.dimensions
    guard let length = d.length?.exact, let width = (d.width ?? d.depth)?.exact,
      let height = d.height?.exact,
      [length, width, height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
    self.form = form
    let selected = finish.flatMap { form.finishes.contains($0) ? $0 : nil } ?? form.finishes.first ?? .stoneMatte
    self.finish = selected
    let variant = form.product.variant(key: form.variantKey(for: selected))
    self.ral = variant?.allowsRAL == true ? ral : nil
    metres = SIMD3(Float(max(length, width)), Float(height), Float(min(length, width))) / 1000
  }

  static func selection(_ product: CatalogProduct, variant: CatalogVariant?, colour: LineColour) -> RoomProduct? {
    guard let form = StudioForm.all.first(where: { $0.product.id == product.id }) else { return nil }
    let ral: RALColour?
    if case .ral(let code) = colour { ral = RALPalette.colours.first { $0.code == code } } else { ral = nil }
    return RoomProduct(form: form, finish: StudioFinish(material: variant?.material, finish: variant?.finish), ral: ral)
  }

  var subtitle: String {
    [finish.title, ral.map { "RAL \($0.code)" } ?? "Базовый белый"].joined(separator: " · ")
  }
}

enum RoomAssetError: Error { case unreadable, invalidGeometry, dimensionsMismatch }

enum RoomAssetBuilder {
  /// Retains the official mesh and its import/up-axis hierarchy. First validate its proportions;
  /// small CAD/catalogue discrepancies (up to 5%, e.g. feet/rim envelopes) are then calibrated
  /// per axis to the published dimensions. A gross mismatch is an error, never a substitute mesh.
  static func build(_ product: RoomProduct) throws -> SCNNode {
    guard let studio = StudioScene(modelURL: product.form.modelURL, finish: product.finish,
                                   colour: product.ral?.colour ?? StudioScene.white) else {
      throw RoomAssetError.unreadable
    }
    let orientation = SCNNode()
    studio.model.removeFromParentNode()
    orientation.addChildNode(studio.model)
    // Parent bounds include the studio model's own rotation, unlike its local boundingBox.
    let (lo, hi) = orientation.boundingBox
    if hi.z - lo.z > hi.x - lo.x {
      let turn = SCNNode()
      orientation.eulerAngles.y = .pi / 2
      turn.addChildNode(orientation)
      return try calibrated(turn, product: product)
    }
    return try calibrated(orientation, product: product)
  }

  private static func calibrated(_ mesh: SCNNode, product: RoomProduct) throws -> SCNNode {
    let (lo, hi) = mesh.boundingBox
    let extent = SIMD3<Float>(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    guard extent.x > 0, extent.y > 0, extent.z > 0,
      [extent.x, extent.y, extent.z].allSatisfy(\.isFinite) else { throw RoomAssetError.invalidGeometry }
    let scale = product.metres.x / extent.x
    let expected = product.metres
    let actual = extent * scale
    // CAD product envelopes can include a few mm of fittings. Larger discrepancies are not hidden.
    guard abs(actual.y - expected.y) <= max(0.025, expected.y * 0.05),
      abs(actual.z - expected.z) <= max(0.025, expected.z * 0.05) else { throw RoomAssetError.dimensionsMismatch }
    let calibration = expected / extent
    mesh.simdScale = calibration
    mesh.simdPosition = SIMD3(-(lo.x + hi.x) / 2, -lo.y, -(lo.z + hi.z) / 2) * calibration
    let root = SCNNode()
    root.name = "Salini.RoomProduct"
    root.addChildNode(mesh)
    return root
  }
}

enum RoomPlacementMath {
  /// Dragging is constrained to the established floor, so a wall/table can't lift the bathtub.
  static func floorPoint(near: SIMD3<Float>, far: SIMD3<Float>, floorY: Float) -> SIMD3<Float>? {
    let direction = far - near
    guard abs(direction.y) > 0.0001 else { return nil }
    let t = (floorY - near.y) / direction.y
    let point = near + direction * t
    guard t >= 0, point.x.isFinite, point.z.isFinite, simd_distance(point, near) <= 7 else { return nil }
    return point
  }
  static func normalizedAngle(_ angle: Float) -> Float {
    atan2(sin(angle), cos(angle))
  }
}

enum RoomStage: Equatable {
  case introduction, unavailable, denied, loading, searching, ready, placed, interrupted, failed(String)
  var canPlace: Bool { self == .ready }
  var canManipulate: Bool { self == .placed }
}
