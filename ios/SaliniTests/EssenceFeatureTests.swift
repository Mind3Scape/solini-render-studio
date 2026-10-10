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
    // The paired composition reserves top space but opens cuts locally, not across the card.
    for fragment in layers where fragment.closedDY != 0 {
      XCTAssertLessThan(hypot(fragment.closedDX * 440, fragment.closedDY * 338), 24)
    }
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
    XCTAssertGreaterThanOrEqual(r.height, 360)
    XCTAssertEqual(r.width, 342, accuracy: 0.5)
    XCTAssertTrue(view.bounds.contains(r))
  }

  func testFragmentsStayCloseDuringRevealAndFinishChanges() throws {
    try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Animation disabled by system accessibility")
    let stage = EssenceLayerStage(layers: EssenceLayers.manifest())
    stage.frame = CGRect(x: 0, y: 0, width: 362, height: 396)
    stage.layoutIfNeeded()
    let ids = EssenceLayers.manifest().map { "essence.fragment.\($0.id)" }
    let views = try ids.map { try XCTUnwrap(find(stage, $0)) }
    let initial = views.map(\.center)
    stage.setRunning(true)
    for _ in 0..<45 { stage.advance(by: 0.05) }
    for (view, start) in zip(views, initial) {
      XCTAssertLessThan(hypot(view.center.x - start.x, view.center.y - start.y), 25)
    }
    let beforeSelection = views.map(\.center)
    let sizes = views.map { $0.bounds.width }
    stage.show(.senseGloss, animated: true)
    for _ in 0..<45 { stage.advance(by: 0.05) }
    for (i, view) in views.enumerated() {
      XCTAssertLessThan(hypot(view.center.x - beforeSelection[i].x, view.center.y - beforeSelection[i].y), 25)
      XCTAssertTrue((0.85...1.15).contains(view.bounds.width / sizes[i]))
    }
    stage.setRunning(false)
  }

  func testPauseAndRepeatedVisibilityUpdatesPreserveAnimationProgress() throws {
    try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Animation disabled by system accessibility")
    let stage = EssenceLayerStage(layers: EssenceLayers.manifest())
    stage.frame = CGRect(x: 0, y: 0, width: 362, height: 396)
    stage.layoutIfNeeded()
    stage.setRunning(true)
    stage.advance(by: 0.05)
    XCTAssertGreaterThan(stage.opening, 0, "Motion starts on entry, without a delayed reveal")
    for _ in 0..<10 { stage.advance(by: 0.05) }
    let progress = stage.opening
    let time = stage.clock
    let fragment = try XCTUnwrap(find(stage, "essence.fragment.stone-fragment"))
    let frame = fragment.frame
    for _ in 0..<20 { stage.setRunning(true) }
    XCTAssertEqual(stage.clock, time)
    stage.setRunning(false)
    stage.advance(by: 1)
    XCTAssertFalse(stage.isAnimating)
    XCTAssertEqual(stage.opening, progress)
    XCTAssertEqual(stage.clock, time)
    XCTAssertEqual(fragment.frame, frame, "Pausing must not jump to the final pose")
    stage.setRunning(true)
    XCTAssertEqual(fragment.frame, frame)
    stage.advance(by: 0.05)
    XCTAssertGreaterThan(stage.opening, progress)
    stage.setRunning(false)
  }

  func testTabletUsesBoundedArtworkRatherThanScalingBeyondTheStage() throws {
    let stage = EssenceLayerStage(layers: EssenceLayers.manifest())
    stage.frame = CGRect(x: 0, y: 0, width: 1024, height: 396)
    stage.layoutIfNeeded()
    for layer in EssenceLayers.manifest() {
      let fragment = try XCTUnwrap(find(stage, "essence.fragment.\(layer.id)"))
      XCTAssertLessThanOrEqual(fragment.bounds.width, 440 * 0.64)
      XCTAssertTrue(stage.bounds.insetBy(dx: -12, dy: -12).contains(fragment.frame), layer.id)
    }
  }

  private func find(_ root: UIView, _ id: String) -> UIView? {
    if root.accessibilityIdentifier == id { return root }
    for v in root.subviews { if let f = find(v, id) { return f } }
    return nil
  }
}
