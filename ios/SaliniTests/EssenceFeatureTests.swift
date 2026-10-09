import SceneKit
import XCTest

@testable import Salini

/// The home material block «Камень изнутри»: the CTA hands the studio a form that really sells
/// the chosen finish, selection and accessibility follow the finish, and the scene is honest
/// (labelled schematic, static pose when motion is off).
@MainActor
final class EssenceFeatureTests: XCTestCase {
  func testEveryFinishOpensAFormThatSellsIt() {
    for f in StudioFinish.allCases {
      guard let form = EssenceFeatureView.form(for: f) else { continue }   // catalogue without models
      XCTAssertTrue(form.finishes.contains(f), "\(f) → \(form.name)")
    }
    if let noemi = StudioForm.noemi, let first = noemi.finishes.first {
      XCTAssertEqual(EssenceFeatureView.form(for: first)?.name, noemi.name, "Noemi first, like the studio")
    }
  }

  func testCallToActionCarriesTheSelectedFinish() throws {
    var opened: (StudioForm?, StudioFinish)?
    let view = EssenceFeatureView { form, finish in opened = (form, finish) }
    view.frame = CGRect(x: 0, y: 0, width: 342, height: 1100)
    view.layoutIfNeeded()
    for f in StudioFinish.allCases {
      view.select(f, animated: false)
      XCTAssertEqual(view.finish, f)
      let chip = try XCTUnwrap(find(view, "essence.\(f.rawValue)") as? UIButton)
      XCTAssertTrue(chip.accessibilityTraits.contains(.selected))
      let cta = try XCTUnwrap(find(view, "essence.explore") as? UIButton)
      cta.sendActions(for: .touchUpInside)
      XCTAssertEqual(opened?.1, f)
      if let form = opened?.0 { XCTAssertTrue(form.finishes.contains(f)) }
    }
  }

  func testStageDescribesTheIllustrationHonestly() throws {
    let view = EssenceFeatureView { _, _ in }
    view.select(.senseGloss, animated: false)
    let stage = try XCTUnwrap(find(view, "essence.stage"))
    let text = stage.accessibilityLabel ?? ""
    XCTAssertTrue(text.contains("схема"), text)
    XCTAssertTrue(text.contains("Gelcoat 0,8"), text)
    XCTAssertTrue(text.contains("условна"), text)
    XCTAssertEqual(stage.accessibilityValue, StudioFinish.senseGloss.title)
  }

  func testSceneBuildsAndHoldsAStaticPoseWithoutMotion() {
    let scene = EssenceScene()
    let anchors = scene.anchors()
    for key in ["stone", "coat", "core"] {
      let p = try? XCTUnwrap(anchors[key])
      XCTAssertNotNil(p, key)
      if let p { XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, key) }
    }
    scene.pose(time: 3.7, opening: 1, emphasis: 1, motion: false)
    let a = scene.anchors()
    scene.pose(time: 11.2, opening: 1, emphasis: 1, motion: false)
    let b = scene.anchors()
    for (k, v) in a { XCTAssertEqual(simd_distance(v, b[k]!), 0, accuracy: 1e-5, "\(k) moved without motion") }
    // Opening parts the halves: the cut (and its Gelcoat band) turns and moves into view.
    scene.pose(time: 0, opening: 0, emphasis: 1, motion: false)
    let closed = scene.anchors()["coat"]!
    scene.pose(time: 0, opening: 1, emphasis: 1, motion: false)
    XCTAssertGreaterThan(simd_distance(scene.anchors()["coat"]!, closed), 0.05)
  }

  /// The manifest round-trips through JSON (the art-direction file format), keeps the six
  /// generated fragment names, never the old raw-stone placeholders, and every finish of S-Sense
  /// switches to its own matching asset.
  func testManifestNamesTheSixFragmentsAndRoundTrips() throws {
    let layers = EssenceLayers.fallbackManifest
    let names = Set(layers.flatMap { [$0.image] + Array(($0.finishImages ?? [:]).values) })
    XCTAssertEqual(names, ["essence-stone-mass", "essence-stone-fragment", "essence-sense-core-gloss", "essence-sense-core-matte",
                           "essence-sense-cap-gloss", "essence-sense-cap-matte"])
    for l in layers where l.group == .sense {
      XCTAssertNotEqual(l.finishImages?["senseMatte"], l.finishImages?["senseGloss"], l.id)
    }
    let data = try JSONEncoder().encode(layers)
    XCTAssertEqual(try JSONDecoder().decode([EssenceLayer].self, from: data), layers)
    // A loose piece of each material flies past the card's top edge (y < 0) in its hero pose.
    XCTAssertTrue(layers.contains { $0.group == .stone && $0.y < 0 })
    XCTAssertTrue(layers.contains { $0.group == .sense && $0.y < 0 })
  }

  /// Only delivered images are shown; a missing finish variant falls back to one that exists.
  func testResolvedSkipsMissingImages() {
    let missing = EssenceLayer(id: "x", image: "essence-does-not-exist", group: .stone, x: 0.5, y: 0.5, width: 0.5)
    XCTAssertTrue(EssenceLayers.resolved([missing]).isEmpty)
    XCTAssertFalse(EssenceLayers.available([missing]))
  }

  /// The host activates the block by `animationBounds`: the stage rect including the reserved
  /// overflow margin above the card.
  func testAnimationBoundsCoverTheStage() {
    let view = EssenceFeatureView { _, _ in }
    view.frame = CGRect(x: 0, y: 0, width: 342, height: 1200)
    view.setNeedsLayout()
    view.layoutIfNeeded()
    let r = view.animationBounds
    XCTAssertGreaterThanOrEqual(r.height, 440)
    XCTAssertEqual(r.width, 342, accuracy: 0.5)
    XCTAssertTrue(view.bounds.contains(r))
  }

  private func find(_ root: UIView, _ id: String) -> UIView? {
    if root.accessibilityIdentifier == id { return root }
    for v in root.subviews { if let f = find(v, id) { return f } }
    return nil
  }
}
