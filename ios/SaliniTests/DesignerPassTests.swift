import UIKit
import XCTest

@testable import Salini

/// Designer pass: the object path, honest proposal state, tab glyphs, app icon sources and the club.
final class DesignerPassTests: XCTestCase {
  private func tempStore() throws -> (ProjectStore, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("designer-\(UUID()).json")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "Salini.designer.\(UUID())"))
    return (ProjectStore(fileURL: url, defaults: defaults), url)
  }

  func testEmptyObjectIsNeverPresentedAsReady() throws {
    let (store, url) = try tempStore()
    defer { try? FileManager.default.removeItem(at: url) }
    store.newProject(name: "Квартира на Патриарших")
    let j = DesignerJourney(project: store.current)
    XCTAssertTrue(j.isEmpty)
    XCTAssertEqual(j.next, .chooseProducts, "An empty object starts with products, not a proposal")
    XCTAssertEqual(j.state(.object), .done, "The object exists; the client is optional")
    XCTAssertEqual(j.state(.selection), .next)
    XCTAssertEqual(j.files, .none)
    XCTAssertEqual(j.state(.technical), .open)
    XCTAssertEqual(j.state(.proposal), .open)
    for step in DesignerJourney.Step.allCases {
      XCTAssertFalse(j.detail(step).contains("₽"), "No «0 ₽» for an empty object")
      XCTAssertFalse(j.detail(step).lowercased().contains("готов"), "\(step): never «ready» when empty")
    }
    XCTAssertEqual(j.detail(.proposal), "Без изделий не собирается")
  }

  func testClientIsOptionalAndNeverGatesTheProposal() throws {
    let (store, url) = try tempStore()
    defer { try? FileManager.default.removeItem(at: url) }
    store.newProject(name: "Вилла у моря")
    // An execution that no longer exists needs clarification first.
    var p = store.current
    p.lines.append(ProjectLine(productId: "aria", variantKey: "missing-key"))
    store.current = p
    XCTAssertEqual(DesignerJourney(project: store.current).next, .resolveExecutions(1))
    p = store.current
    p.lines.removeAll()
    store.current = p
    let noemi = try XCTUnwrap(StudioForm.noemi?.product)
    store.add(noemi, variantKey: noemi.variants.first?.key, quantity: 2)
    let j = DesignerJourney(project: store.current)
    XCTAssertFalse(j.hasClient)
    XCTAssertEqual(j.next, .prepareProposal, "No client: the proposal is still the next step")
    XCTAssertEqual(j.state(.object), .done)
    XCTAssertEqual(j.state(.selection), .done)
    XCTAssertEqual(j.state(.proposal), .next)
    XCTAssertEqual(j.detail(.object), "Клиент не указан — по желанию")
  }

  /// A product with no official model and no drawing/passport on its card.
  private func productWithoutFiles() throws -> CatalogProduct {
    let models = Set(StudioForm.all.map(\.product.id))
    return try XCTUnwrap(Catalog.shared.products.first { p in
      !models.contains(p.id) && !p.variants.isEmpty
        && !p.documents.contains { $0.kind == "drawing" || $0.kind == "passport" }
    }, "The catalogue has products without published files")
  }

  func testTechnicalPackageIsNeverDoneWithoutFiles() throws {
    let (store, url) = try tempStore()
    defer { try? FileManager.default.removeItem(at: url) }
    store.newProject(name: "Без файлов")
    let bare = try productWithoutFiles()
    store.add(bare, variantKey: bare.variants.first?.key)
    var j = DesignerJourney(project: store.current)
    XCTAssertEqual(j.state(.selection), .done, "Choosing products is not the package")
    XCTAssertEqual(j.files, .byRequest)
    XCTAssertEqual(j.state(.technical), .open, "Zero files is never done")
    XCTAssertTrue(j.detail(.technical).contains("по запросу"))
    // One product with a model next to it: partial, still not done.
    let noemi = try XCTUnwrap(StudioForm.noemi?.product)
    store.add(noemi, variantKey: noemi.variants.first?.key)
    j = DesignerJourney(project: store.current)
    XCTAssertEqual(j.files, .partial)
    XCTAssertEqual(j.state(.technical), .partial)
    XCTAssertEqual(j.withModel, 1)
    // Only products with files: available.
    do {
      var only = store.current
      only.lines.removeAll { $0.productId == bare.id }
      store.current = only
    }
    XCTAssertEqual(DesignerJourney(project: store.current).state(.technical), .done)
  }

  @MainActor func testEveryExecutionAndColourIsKeptAndTheStudioGetsTheRAL() throws {
    let noemi = try XCTUnwrap(StudioForm.noemi)
    let stone = try XCTUnwrap(noemi.product.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == .stoneMatte })
    let gloss = try XCTUnwrap(noemi.product.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == .senseGloss })
    let white = ProjectLine(productId: noemi.product.id, variantKey: stone.key)
    let glossWhite = ProjectLine(productId: noemi.product.id, variantKey: gloss.key)
    let glossRAL = ProjectLine(productId: noemi.product.id, variantKey: gloss.key, colour: .ral("7016"))
    XCTAssertEqual(DesignerWorkspace.studioView(for: white), .open(noemi, .stoneMatte, nil), "Base white is shown as white")
    XCTAssertEqual(DesignerWorkspace.studioView(for: glossWhite), .open(noemi, .senseGloss, nil))
    let ral = try XCTUnwrap(RALPalette.colour("7016"))
    XCTAssertEqual(DesignerWorkspace.studioView(for: glossRAL), .open(noemi, .senseGloss, ral), "The chosen RAL goes to the studio")
    let controller = MaterialStudioController(form: noemi, finish: .senseGloss, ral: ral)
    XCTAssertEqual(controller.ral, ral, "The studio opens on that colour, not on white")
    let bare = try productWithoutFiles()
    XCTAssertEqual(DesignerWorkspace.studioView(for: ProjectLine(productId: bare.id, variantKey: bare.variants.first?.key)), .noModel)
  }

  func testProposalStaysCurrentUntilTheObjectChanges() throws {
    let (store, url) = try tempStore()
    defer { try? FileManager.default.removeItem(at: url) }
    store.newProject(name: "Пентхаус", client: "Анна")
    let noemi = try XCTUnwrap(StudioForm.noemi?.product)
    store.add(noemi, variantKey: noemi.variants.first?.key)
    let built = store.current
    store.recordProposal(for: built.id, basis: built.updated)
    XCTAssertEqual(store.current.updated, built.updated, "Recording a proposal does not count as a change")
    var j = DesignerJourney(project: store.current)
    XCTAssertTrue(store.current.proposalIsCurrent)
    XCTAssertEqual(j.next, .reviewProposal)
    XCTAssertEqual(j.state(.proposal), .done)
    // Any later change makes it stale — honestly, without pretending it was sent.
    store.add(noemi, variantKey: noemi.variants.first?.key)
    j = DesignerJourney(project: store.current)
    XCTAssertFalse(store.current.proposalIsCurrent)
    XCTAssertEqual(j.next, .refreshProposal)
    XCTAssertTrue(j.detail(.proposal).contains("изменился"))
    // It persists in the same projects file — no second database.
    let reopened = ProjectStore(fileURL: url, defaults: try XCTUnwrap(UserDefaults(suiteName: "Salini.designer.\(UUID())")))
    XCTAssertNotNil(reopened.projects.first { $0.id == built.id }?.proposalAt)
  }

  func testProjectsSavedBeforeTheProposalFieldsStillLoad() throws {
    let legacy = #"{"id":"P1","name":"Старый проект","client":"","lines":[],"updated":700000000}"#
    let project = try JSONDecoder().decode(SaliniProject.self, from: Data(legacy.utf8))
    XCTAssertNil(project.proposalAt)
    XCTAssertFalse(project.proposalIsCurrent)
  }

  @MainActor func testTabsUseTheOfficialWordmarkAndTheSoftGlyphs() throws {
    let previous = DemoStore.shared.role
    defer { DemoStore.shared.role = previous }
    for role in Audience.allCases {
      DemoStore.shared.role = role
      let tabs = MainTabs()
      tabs.loadViewIfNeeded()
      let items = try XCTUnwrap(tabs.viewControllers).map(\.tabBarItem!)
      XCTAssertEqual(items.first?.accessibilityIdentifier, "tab.TabSalini", "\(role): home is the Salini wordmark")
      XCTAssertEqual(items.first?.accessibilityLabel, "Salini, главная")
      for item in items {
        let image = try XCTUnwrap(item.image, "\(role) \(item.title ?? ""): glyph present")
        XCTAssertEqual(image.renderingMode, .alwaysTemplate, "Tinted by the tab bar for selected/unselected")
        XCTAssertFalse(item.accessibilityLabel?.isEmpty ?? true)
      }
      let expected: [String]
      switch role {
      case .home: expected = ["TabSalini", "TabCatalog", "TabProject", "TabProfile"]
      case .atelier: expected = ["TabSalini", "TabCatalog", "TabProject", "TabLibrary", "TabProfile"]
      case .partner: expected = ["TabSalini", "TabCatalog", "TabProject", "TabStock", "TabProfile"]
      }
      XCTAssertEqual(items.map { $0.accessibilityIdentifier?.replacingOccurrences(of: "tab.", with: "") }, expected)
    }
    // The wordmark keeps its proportions (wide), the Soft glyphs are square.
    let mark = try XCTUnwrap(UIImage(named: "TabSalini"))
    XCTAssertGreaterThan(mark.size.width / mark.size.height, 1.3)
    for name in ["TabCatalog", "TabProject", "TabLibrary", "TabStock", "TabProfile"] {
      let g = try XCTUnwrap(UIImage(named: name), name)
      XCTAssertEqual(g.size.width, g.size.height, accuracy: 0.5, name)
    }
  }

  func testDesignersClubLinksAreOfficialAndNothingIsInvented() {
    XCTAssertEqual(DesignersClubController.join.url.absoluteString, "https://salini-srl.com/auth/")
    for link in DesignersClubController.links {
      XCTAssertEqual(link.url.scheme, "https", link.title)
      XCTAssertTrue(["salini-srl.com", "salini.club"].contains(link.url.host ?? ""), link.url.absoluteString)
    }
    XCTAssertEqual(DesignersClubController.privileges.count, 6, "The six privileges of salini.club")
    let text = DesignersClubController.privileges.map(\.text).joined(separator: " ")
    XCTAssertTrue(text.contains("по согласованию"), "Samples and publications are «by agreement», as on the site")
    XCTAssertFalse(text.contains("баллов:"), "No points balance")
  }

  private func find(_ id: String, in v: UIView) -> UIView? {
    v.accessibilityIdentifier == id ? v : v.subviews.lazy.compactMap { self.find(id, in: $0) }.first
  }
  private func texts(_ v: UIView) -> [String] { ((v as? UILabel)?.text.map { [$0] } ?? []) + v.subviews.flatMap(texts) }

  /// The designer's tabs in a phone window, with a temporary object made current; restored after.
  @MainActor private func designerHome(_ fill: (ProjectStore) throws -> Void) throws -> (MainTabs, HomeController, UIWindow, () -> Void) {
    let previousRole = DemoStore.shared.role
    let store = ProjectStore.shared
    let previousId = store.currentId
    DemoStore.shared.role = .atelier
    store.newProject(name: "Тестовый объект")
    let testId = store.current.id
    try fill(store)
    let tabs = MainTabs()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = tabs
    window.makeKeyAndVisible()
    let nav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
    let home = try XCTUnwrap(nav.viewControllers.first as? HomeController)
    home.loadViewIfNeeded()
    tabs.view.layoutIfNeeded()
    home.view.layoutIfNeeded()
    let restore = {
      window.isHidden = true
      store.delete(testId)
      store.currentId = previousId
      DemoStore.shared.role = previousRole
    }
    return (tabs, home, window, restore)
  }

  @MainActor func testFirstScreenShowsTheActiveObjectAndAWorkingNextStep() throws {
    let (tabs, home, window, restore) = try designerHome { _ in }
    defer { restore() }
    let object = try XCTUnwrap(find("designer.entry.object", in: home.view))
    let cta = try XCTUnwrap(find("designer.cta", in: home.view) as? UIButton)
    let visibleBottom = window.bounds.height - tabs.tabBar.frame.height
    XCTAssertLessThanOrEqual(object.convert(object.bounds, to: window).maxY, visibleBottom)
    XCTAssertLessThanOrEqual(cta.convert(cta.bounds, to: window).maxY, visibleBottom, "The next step is on the first screen")
    XCTAssertTrue(object.accessibilityLabel?.contains("Тестовый объект") == true)
    let next = try XCTUnwrap(find("designer.next", in: home.view))
    XCTAssertTrue(texts(next).contains("Подберите изделия для объекта"))
    XCTAssertFalse(texts(try XCTUnwrap(find("designer.journey", in: home.view))).joined().contains("₽"), "Empty: no sum")
    XCTAssertNil(find("designer.technical", in: home.view), "Empty: no package card")
    let step = try XCTUnwrap(find("designer.step.1", in: home.view))
    XCTAssertTrue(step.accessibilityLabel?.contains("следующий шаг") == true, step.accessibilityLabel ?? "")
    // QA aid for Codex: the first screen as laid out (layer render; glass materials not captured).
    let shot = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
    try shot.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Salini-Designer-FirstScreen.png"))
    // The button works: an empty object opens the selection helper.
    cta.sendActions(for: .touchUpInside)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    XCTAssertTrue(home.navigationController?.topViewController is ChooseController)
  }

  @MainActor func testEveryChosenExecutionHasItsOwnRow() throws {
    var ids: [String] = []
    let (_, home, _, restore) = try designerHome { store in
      let noemi = try XCTUnwrap(StudioForm.noemi?.product)
      let gloss = try XCTUnwrap(noemi.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == .senseGloss })
      let stone = try XCTUnwrap(noemi.variants.first { StudioFinish(material: $0.material, finish: $0.finish) == .stoneMatte })
      ids.append(try XCTUnwrap(store.add(noemi, variantKey: stone.key)).id)
      ids.append(try XCTUnwrap(store.add(noemi, variantKey: gloss.key)).id)
      ids.append(try XCTUnwrap(store.add(noemi, variantKey: gloss.key, colour: .ral("7016"))).id)
    }
    defer { restore() }
    XCTAssertEqual(Set(ids).count, 3, "Three distinct lines of one product")
    for id in ids {
      XCTAssertNotNil(find("designer.line.\(id)", in: home.view), "Row for line \(id)")
      XCTAssertNotNil(find("designer.line.studio.\(id)", in: home.view), "Studio entry for line \(id)")
    }
    let ralRow = try XCTUnwrap(find("designer.line.studio.\(ids[2])", in: home.view) as? UIButton)
    XCTAssertTrue(ralRow.accessibilityLabel?.contains("RAL 7016") == true, ralRow.accessibilityLabel ?? "")
    XCTAssertNotNil(find("designer.technical", in: home.view))
  }
}
