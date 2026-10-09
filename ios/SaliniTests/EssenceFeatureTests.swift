import XCTest

@testable import Salini

/// The home material block «Камень изнутри»: the CTA hands the studio a form that really sells
/// the chosen finish, selection and accessibility follow the finish, the six fragments ship and
/// the illustration is labelled as such.
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
    XCTAssertTrue(text.contains("визуализация"), text)
    XCTAssertTrue(text.contains("Gelcoat"), text)
    XCTAssertTrue(text.contains("условны"), text)
    XCTAssertFalse(text.contains("боксит") || text.contains("мрамор "), text)
    XCTAssertEqual(stage.accessibilityValue, StudioFinish.senseGloss.title)
  }

  /// The six generated fragments ship in the bundle with transparency, matte / gloss pairs have
  /// the same canvas, and the feature shows the illustrated stage.
  func testAllSixFragmentsShipAndTheStageIsShown() throws {
    let layers = EssenceLayers.manifest()
    XCTAssertTrue(EssenceLayers.available(layers), "missing EssenceAssets in the bundle")
    for name in ["essence-stone-mass", "essence-stone-fragment", "essence-sense-core-gloss", "essence-sense-core-matte",
                 "essence-sense-cap-gloss", "essence-sense-cap-matte"] {
      let image = try XCTUnwrap(EssenceLayers.image(name), name)
      let alpha = image.cgImage?.alphaInfo ?? .none
      XCTAssertTrue([.first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha), "\(name) has no alpha")
    }
    for part in ["core", "cap"] {
      XCTAssertEqual(EssenceLayers.image("essence-sense-\(part)-matte")?.size, EssenceLayers.image("essence-sense-\(part)-gloss")?.size)
    }
    XCTAssertTrue(EssenceFeatureView { _, _ in }.illustrated)
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
