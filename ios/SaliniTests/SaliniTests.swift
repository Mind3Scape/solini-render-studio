import AVFoundation
import PDFKit
import SceneKit
import XCTest

@testable import Salini

/// A pan recognizer with a scripted state and translation, to drive the scene's real handler.
final class ScriptedPan: UIPanGestureRecognizer {
  var scriptedState: UIGestureRecognizer.State = .began
  var scriptedTranslation: CGPoint = .zero
  override var state: UIGestureRecognizer.State {
    get { scriptedState }
    set { scriptedState = newValue }
  }
  override func translation(in view: UIView?) -> CGPoint { scriptedTranslation }
  override func velocity(in view: UIView?) -> CGPoint { .zero }
}

final class SaliniTests: XCTestCase {
  func testCuratedCatalogHasSourcesAndMatchingAriaVariants() throws {
    XCTAssertEqual(Product.all.count, 4)
    XCTAssertTrue(Product.all.allSatisfy { $0.source.hasPrefix("https://salini-srl.com/") })
    let aria = try XCTUnwrap(Product.all.first { $0.id == "aria" })
    XCTAssertEqual(aria.price(stone: false), 790000)
    XCTAssertEqual(aria.sku(stone: false), "1051101G")
    XCTAssertEqual(aria.price(stone: true), 890000)
    XCTAssertEqual(aria.sku(stone: true), "1051201M")
  }
  func testProjectsPreserveDistinctExecutionsAndPersist() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "Salini.tests.\(UUID())"))
    let store = ProjectStore(fileURL: url, defaults: defaults)
    let aria = try XCTUnwrap(Catalog.shared.product("aria"))
    let sense = try XCTUnwrap(aria.variants.first { $0.sku == "1051101G" })
    let stone = try XCTUnwrap(aria.variants.first { $0.sku == "1051201M" })
    store.add(aria, variantKey: sense.key)
    store.add(aria, variantKey: stone.key, quantity: 2)
    store.add(aria, variantKey: stone.key, colour: .ral("7016"))
    XCTAssertEqual(store.current.lines.count, 3)
    XCTAssertNil(store.add(aria, variantKey: stone.key, quantity: -3), "Negative input never reduces a line")
    XCTAssertNil(store.add(aria, variantKey: "missing-variant"), "Unknown executions are not substituted")
    XCTAssertEqual(store.current.lines[1].quantity, 2)
    // A RAL line keeps its published custom article, but its price is base + colour on request.
    let ral = store.current.lines[2]
    XCTAssertEqual(ral.sku, "1051201MF")
    XCTAssertNil(ral.total)
    XCTAssertEqual(ral.priceText, "\(rubles(890000)) + цвет по запросу")
    XCTAssertEqual(store.current.knownTotal, 790000 + 890000 * 3)
    XCTAssertFalse(store.current.isTotalComplete)
    XCTAssertEqual(store.current.unpricedLines, 1)
    var p = store.current
    p.name = "Вилла у озера"
    p.client = "Тестовый клиент"
    store.current = p
    let restored = ProjectStore(fileURL: url, defaults: defaults)
    XCTAssertEqual(restored.current.lines, store.current.lines)
    XCTAssertEqual(restored.current.name, "Вилла у озера")
  }
  func testPrototypeProjectAndFavoritesMigrateToCatalogueIds() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let name = "Salini.tests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let legacy = [ProjectItem(productId: "aria", stone: true, quantity: 2), ProjectItem(productId: "greca", stone: false)]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "salini.items")
    defaults.set("Квартира", forKey: "salini.projectName")
    defaults.set(["aria", "opera-top"], forKey: "salini.favorites")
    let store = ProjectStore(fileURL: url, defaults: defaults)
    XCTAssertEqual(store.current.name, "Квартира")
    XCTAssertEqual(store.current.lines.map(\.productId), ["20645", "1120"])
    XCTAssertEqual(store.current.lines[0].sku, "1051201M")
    XCTAssertEqual(store.current.lines[0].quantity, 2)
    XCTAssertEqual(store.current.lines[1].sku, "103121M")
    let favorites = DemoStore(defaults: defaults)
    XCTAssertEqual(favorites.favorites, ["20645", "30919"])
  }
  func testCatalogueKeepsVerifiedVariantsAndNeverInventsValues() throws {
    let c = Catalog.shared
    XCTAssertGreaterThanOrEqual(c.products.count, 300)
    XCTAssertEqual(Set(c.products.map(\.id)).count, c.products.count)
    XCTAssertEqual(c.snapshot, "2026-10-06")
    for category in ["Ванны", "Раковины", "Душевые поддоны", "Столешницы", "Мебель", "Зеркала", "Комплектующие"] {
      XCTAssertTrue(c.categories.contains(category), category)
    }
    XCTAssertTrue(c.products.allSatisfy { $0.url.hasPrefix("https://salini-srl.com/") })
    XCTAssertTrue(c.products.flatMap(\.variants).allSatisfy { ($0.price ?? 1) > 0 }, "Unknown price is nil, never 0")
    let ornella = try XCTUnwrap(c.products.first { $0.siteName == "ОРНЕЛЛА 170х75" })
    XCTAssertEqual(ornella.variants.map(\.title), ["S-Sense · глянцевое", "S-Sense · матовое", "S-Stone · матовое"])
    XCTAssertEqual(ornella.variants.map(\.price), [113000, 126600, 171700])
    XCTAssertNil(ornella.variants[1].sku, "No article on the page for matte S-Sense — not invented")
    XCTAssertEqual(Set(ornella.documents.map(\.url)).count, ornella.documents.count)
    let corner = try XCTUnwrap(c.products.first { $0.siteName == "АЛЬДА УГЛОВАЯ Л 160x70" })
    XCTAssertEqual(corner.dimensions.length, .range(1715, 2015))
    let aria = try XCTUnwrap(c.product("aria"))
    XCTAssertEqual(aria.variants.map(\.weightKg), [144, 133])
    XCTAssertEqual(aria.dimensions.text, "1900 × 900 × 600 мм")
    let withImages = c.products.filter { $0.imageURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    XCTAssertGreaterThanOrEqual(withImages.count, 300)
    // Card photos come from the card's own gallery (or its unique hero), never a family banner.
    XCTAssertTrue(c.products.allSatisfy { $0.image == nil || $0.imageRole == "gallery" || $0.imageRole == "hero" })
    XCTAssertEqual(c.product("1230")?.imageRole, "gallery", "Noemi washbasin: its own gallery, not the bath hero")
    XCTAssertEqual(c.products.filter { $0.category == "Зеркала" }.count, 5)
  }
  func testVariantFiltersHoldForOneExecutionAndShowItsPrice() throws {
    var f = CatalogFilter()
    f.category = "Ванны"
    f.finishes = [.stoneMatte]
    f.maxPrice = 800_000
    let hits = Catalog.shared.search("", filter: f)
    XCTAssertFalse(hits.contains { $0.product.id == "20645" },
                   "Aria: S-Stone is 890 000; the 790 000 S-Sense must not satisfy an S-Stone + 800 000 filter")
    for hit in hits {
      let v = try XCTUnwrap(hit.product.variant(key: hit.variantKey))
      XCTAssertEqual(v.material, "sStone")
      XCTAssertLessThanOrEqual(try XCTUnwrap(v.price), 800_000)
      XCTAssertEqual(hit.price, v.price, "The hit shows the matching execution's price")
    }
    f.maxPrice = 900_000
    let aria = try XCTUnwrap(Catalog.shared.search("", filter: f).first { $0.product.id == "20645" })
    XCTAssertEqual(aria.product.variant(key: aria.variantKey)?.sku, "1051201M")
    var sku = CatalogFilter()
    sku.finishes = [.senseGloss]
    XCTAssertTrue(Catalog.shared.search("1051201M", filter: sku).isEmpty, "An article of a filtered-out execution")
  }
  func testVariantKeysAreStableAndUnknownKeysAreNotSubstituted() throws {
    let ornella = try XCTUnwrap(Catalog.shared.products.first { $0.siteName == "ОРНЕЛЛА 170х75" })
    XCTAssertEqual(ornella.variants.map(\.key), ["sSense-gloss-1", "sSense-matte-1", "sStone-matte-1"])
    XCTAssertNil(ornella.variant(key: "sSense-matte-2"))
    XCTAssertNil(ornella.variant(key: nil), "Several executions: nothing is chosen implicitly")
    let line = ProjectLine(productId: ornella.id, variantKey: "removed-execution")
    XCTAssertTrue(line.needsClarification)
    XCTAssertNil(line.total)
    XCTAssertEqual(line.priceText, "Исполнение требует уточнения")
  }
  func testUnreadableProjectsFileIsQuarantinedAndRecoveredFromBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("projects.json")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "Salini.tests.\(UUID())"))
    let aria = try XCTUnwrap(Catalog.shared.product("aria"))
    let store = ProjectStore(fileURL: url, defaults: defaults)
    store.add(aria, variantKey: aria.variants[0].key)
    store.add(aria, variantKey: aria.variants[1].key)
    try Data("{ not json".utf8).write(to: url)
    let recovered = ProjectStore(fileURL: url, defaults: defaults)
    XCTAssertTrue(recovered.recoveredFromBackup)
    XCTAssertEqual(recovered.current.lines.count, 1, "The last good version before the final save")
    let kept = try XCTUnwrap(recovered.quarantinedFile)
    XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "{ not json", "The unreadable copy is kept, not overwritten")
  }
  /// Real window + real layout: cells are dequeued through their registrations, chips and
  /// products both, while switching categories, scrolling, filtering and searching.
  @MainActor func testCatalogRendersInARealWindowAndSurvivesInteraction() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let catalog = CatalogController()
    let nav = UINavigationController(rootViewController: catalog)
    window.rootViewController = nav
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    nav.view.layoutIfNeeded()
    let grid = try XCTUnwrap(catalog.view.subviews.compactMap { $0 as? UICollectionView }.first)
    func settle() {
      grid.layoutIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    settle()
    XCTAssertGreaterThan(grid.numberOfItems(inSection: 1), 250)
    XCTAssertTrue(grid.visibleCells.contains { $0 is ChipCell }, "Category chips render, including «Все»")
    XCTAssertTrue(grid.visibleCells.contains { $0 is CatalogCell })
    let mirrors = try XCTUnwrap(Catalog.shared.categories.firstIndex(of: "Зеркала")) + 1
    catalog.collectionView(grid, didSelectItemAt: IndexPath(item: mirrors, section: 0))
    settle()
    XCTAssertEqual(grid.numberOfItems(inSection: 1), 5)
    catalog.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
    settle()
    for fraction in [0.3, 0.7, 1.0] {
      grid.setContentOffset(CGPoint(x: 0, y: max(0, (grid.contentSize.height - grid.bounds.height) * fraction)), animated: false)
      settle()
      XCTAssertTrue(grid.visibleCells.contains { $0 is CatalogCell })
    }
    var filter = CatalogFilter()
    filter.finishes = [.senseMatte]
    catalog.apply(filter: filter)
    settle()
    XCTAssertTrue(catalog.hits.allSatisfy { $0.product.variant(key: $0.variantKey)?.finish == "matte" })
    catalog.apply(filter: CatalogFilter())
    let search = try XCTUnwrap(catalog.navigationItem.searchController)
    search.searchBar.text = "1051201Ь"
    catalog.updateSearchResults(for: search)
    settle()
    XCTAssertEqual(catalog.hits.first?.product.variant(key: catalog.hits.first?.variantKey)?.sku, "1051201M")
    search.searchBar.text = "zzzz-нет-такого"
    catalog.updateSearchResults(for: search)
    settle()
    XCTAssertNotNil(grid.backgroundView, "Empty state instead of a blank grid")
  }
  func testDefaultOrderIsEditorialAndOtherSortsAreUntouched() {
    let hits = Catalog.shared.search("")
    XCTAssertEqual(hits.prefix(5).map(\.product.id), Catalog.signatureIds, "Aria, Ninfea, Greca, Opera, Noemi open the catalogue")
    let opening = hits.prefix(12)
    XCTAssertGreaterThanOrEqual(Set(opening.map(\.product.category)).count, 4, "Baths, washbasins, furniture, mirrors")
    XCTAssertTrue(opening.allSatisfy { $0.product.imageURL != nil })
    XCTAssertEqual(Set(hits.map(\.product.id)).count, hits.count, "Editorial order neither drops nor repeats products")
    var byPrice = CatalogFilter()
    byPrice.sort = .priceAscending
    let prices = Catalog.shared.search("", filter: byPrice).compactMap(\.price)
    XCTAssertEqual(prices, prices.sorted())
  }
  @MainActor func testSummaryCountsTheCurrentResults() throws {
    let catalog = CatalogController()
    let nav = UINavigationController(rootViewController: catalog)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = nav
    window.makeKeyAndVisible()
    catalog.view.layoutIfNeeded()
    let search = try XCTUnwrap(catalog.navigationItem.searchController)
    search.searchBar.text = "1051201M"
    catalog.updateSearchResults(for: search)
    let collection = try XCTUnwrap(catalog.view.subviews.compactMap { $0 as? UICollectionView }.first)
    collection.layoutIfNeeded()
    let headers = collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
      .compactMap { ($0 as? SummaryHeader)?.label.text }
    XCTAssertTrue(headers.contains { $0.hasPrefix("1 ИЗДЕЛИЕ") }, "Header shows the current result count: \(headers)")
    window.isHidden = true
  }
  func testChooseHelperExplainsEveryMatchAndRespectsBudgetAndLength() {
    var a = ChooseHelper.Answers()
    a.kind = .freestanding
    a.maxLength = 1750
    a.finish = .stoneMatte
    a.budget = 400_000
    let matches = ChooseHelper.recommend(a)
    XCTAssertFalse(matches.isEmpty)
    for m in matches {
      XCTAssertEqual(m.product.subcategory, "Отдельностоящие")
      XCTAssertLessThanOrEqual(m.product.dimensions.length?.exact ?? .infinity, 1750)
      XCTAssertEqual(m.variant?.material, "sStone", "The shown execution is the one that fits")
      XCTAssertLessThanOrEqual(m.variant?.price ?? .max, 400_000, "Unknown price never passes a budget")
      XCTAssertTrue(m.reasons.contains { $0.contains("≤ 1 750") || $0.contains("≤ 1750") })
    }
    let lengths = matches.compactMap { $0.product.dimensions.length?.exact }
    XCTAssertEqual(lengths, lengths.sorted(by: >), "Closest to the available length first")
  }
  func testDealersHaveSeparateValidPhonesAndHonestMaps() throws {
    XCTAssertEqual(SupportData.loadErrors, [], "Strict decode of dealers.json and help.json")
    let dealers = SupportData.dealers
    XCTAssertEqual(dealers.count, 270)
    XCTAssertEqual(Set(dealers.map(\.id)).count, 270, "Unique ids, including the 14 local ones")
    XCTAssertEqual(dealers.filter { $0.sourceId == nil }.count, 14)
    XCTAssertTrue(dealers.filter { $0.sourceId == nil }.allSatisfy { $0.id.hasPrefix("local-") })
    for d in dealers {
      for p in d.phones {
        let digits = p.tel.dropFirst(5)
        XCTAssertTrue(p.tel.hasPrefix("tel:+"), p.tel)
        XCTAssertTrue(digits.allSatisfy(\.isNumber) && (11...12).contains(digits.count), "\(d.id): \(p.tel)")
      }
    }
    let glued = try XCTUnwrap(dealers.first { $0.id == "1897" })
    XCTAssertEqual(glued.phones.map(\.tel), ["tel:+74956691733", "tel:+74998991414"])
    let ext = try XCTUnwrap(dealers.first { $0.id == "7181" })
    XCTAssertEqual(ext.phones.first?.extension, "512,436", "Extension stays separate from the dialled number")
    XCTAssertEqual(dealers.first { $0.id == "11214" }?.phones.first?.tel, "tel:+375259501205", "No wrong +7 prefix")
    let noMap = try XCTUnwrap(dealers.first { $0.id == "1883" })
    XCTAssertNil(noMap.coordinate)
    XCTAssertTrue(SupportData.search("Симферополь", city: nil, expositionOnly: false).contains(noMap), "Listed without a pin")
    XCTAssertFalse(SupportData.search("сантехкомплект симферополь", city: nil, expositionOnly: false).isEmpty)
    XCTAssertTrue(SupportData.search("", city: "Москва", expositionOnly: false).allSatisfy { $0.city == "Москва" })
  }
  @MainActor func testHelpHasPublishedSectionsAndScreensLoad() throws {
    XCTAssertEqual(SupportData.help.count, 13)
    XCTAssertTrue(SupportData.help.contains { $0.title == "Гарантия" && !$0.items.isEmpty })
    let first = try XCTUnwrap(SupportData.dealers.first)
    for screen: UIViewController in [ShowroomsController(), HelpController(), DealerController(first)] {
      screen.loadViewIfNeeded()
      XCTAssertNotNil(screen.view)
    }
  }
  // Proposal tests use fictional names only.
  private func proposalText(_ data: Data) throws -> (Int, String) {
    let doc = try XCTUnwrap(PDFDocument(data: data))
    // Whitespace-free: table cells wrap and letter-spaced eyebrows may extract with gaps.
    return (doc.pageCount, (doc.string ?? "").filter { !$0.isWhitespace })
  }
  func testProposalIsNotCreatedForAnEmptyProject() {
    let composer = ProposalComposer(project: SaliniProject(name: "Пустой проект", client: "Вымышленный Клиент"), role: .atelier)
    XCTAssertNil(composer.render())
  }
  func testProposalTotalsMatchTheSpecificationAndNeverHideUnpricedLines() throws {
    var project = SaliniProject(name: "Квартира на Тестовой", client: "Ирина Вымышленная")
    project.lines = [
      ProjectLine(productId: "1078", variantKey: "sSense-matte-1", quantity: 1, colour: .ral("6005")),  // RAL: base + colour
      ProjectLine(productId: "1139", variantKey: "sStone-matte-1", quantity: 2),
      ProjectLine(productId: "3709", variantKey: Catalog.shared.product("3709")?.variants.first?.key, quantity: 1),  // no price
    ]
    let composer = ProposalComposer(project: project, role: .atelier)
    composer.rendersStudies = false
    let (pages, text) = try proposalText(try XCTUnwrap(composer.render()))
    XCTAssertEqual(pages, composer.pageCount)
    XCTAssertEqual(project.knownTotal, 126600 + 274600 * 2)
    XCTAssertFalse(project.isTotalComplete)
    func has(_ s: String) -> Bool { text.contains(s.filter { !$0.isWhitespace }) }
    XCTAssertTrue(has("БАЗОВАЯ СУММА ПО ПУБЛИЧНЫМ ЦЕНАМ"))
    XCTAssertTrue(has("Итог неполный"))
    XCTAssertTrue(has("+ цвет по запросу"), "RAL line is never shown as a full price")
    XCTAssertTrue(has("Ирина Вымышленная"))
    XCTAssertTrue(has("Не является офертой"))
    XCTAssertFalse(has("ИТОГО ПО ПУБЛИЧНЫМ ЦЕНАМ"))
  }
  func testTwoPositionProposalIsCompactAndFreeOfNoise() throws {
    var project = SaliniProject(name: "Дом у воды · демо", client: "Вымышленный Клиент")
    project.lines = [
      ProjectLine(productId: "1139", variantKey: "sStone-matte-1", quantity: 3, colour: .ral("6005")),
      ProjectLine(productId: "30919", variantKey: Catalog.shared.product("30919")?.variants.first?.key, quantity: 2),
    ]
    let composer = ProposalComposer(project: project, role: .home)
    composer.rendersStudies = false
    let (pages, text) = try proposalText(try XCTUnwrap(composer.render()))
    XCTAssertTrue((3...5).contains(pages), "Two positions fit 4–5 pages, got \(pages)")
    XCTAssertFalse(text.contains("Подготовил"))
    XCTAssertFalse(text.contains("Тип:"))
    XCTAssertTrue(text.contains("ОфициальноефотоSalini"))
    XCTAssertTrue(text.contains("ДЛЯВАШЕГОПРОЕКТА") || text.contains("ДЛЯ ВАШЕГО ПРОЕКТА".filter { !$0.isWhitespace }))
    XCTAssertTrue(text.contains("S-Stone—матовыйSolidSurface"), "Cover facts of the chosen execution")
  }
  @MainActor func testTabLabelsSurviveRootScreenTitles() {
    let previous = DemoStore.shared.role
    defer { DemoStore.shared.role = previous }
    for role in Audience.allCases {
      DemoStore.shared.role = role
      let tabs = MainTabs()
      tabs.loadViewIfNeeded()
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
      window.rootViewController = tabs
      window.makeKeyAndVisible()
      let before = tabs.viewControllers?.map { $0.tabBarItem.title } ?? []
      for nav in tabs.viewControllers ?? [] { (nav as? UINavigationController)?.topViewController?.loadViewIfNeeded() }
      let after = tabs.viewControllers?.map { $0.tabBarItem.title } ?? []
      XCTAssertEqual(before, after, "\(role): opening a tab must not rename it")
      if role == .atelier { XCTAssertTrue(after.contains("Библиотека") && after.contains("Проекты")) }
      window.isHidden = true
    }
  }
  @MainActor func testStructureCardsWrapInsteadOfClipping() throws {
    let studio = MaterialStudioController(form: StudioForm.noemi)
    let nav = UINavigationController(rootViewController: studio)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = nav
    window.makeKeyAndVisible()
    studio.loadViewIfNeeded()
    studio.showPanel(2)
    studio.view.layoutIfNeeded()
    func labels(_ view: UIView) -> [UILabel] { ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap(labels) }
    let structure = labels(studio.view).filter { ["S-Stone", "S-Sense"].contains($0.text) || ($0.text ?? "").contains("Gelcoat 0,8") || ($0.text ?? "").contains("без покрытия") }
    XCTAssertGreaterThanOrEqual(structure.count, 4, "Titles and notes are real labels")
    for l in structure {
      let needed = l.sizeThatFits(CGSize(width: l.bounds.width, height: .greatestFiniteMagnitude)).height
      XCTAssertLessThanOrEqual(needed, l.bounds.height + 1, "«\(l.text ?? "")» is not clipped")
      XCTAssertEqual(l.numberOfLines, 0)
    }
    window.isHidden = true
  }
  @MainActor func testStudioAlwaysOpensAsALargeSheet() throws {
    let host = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = host
    window.makeKeyAndVisible()
    MaterialStudioController.present(from: host)
    let nav = try XCTUnwrap(host.presentedViewController as? UINavigationController)
    XCTAssertTrue(nav.topViewController is MaterialStudioController)
    XCTAssertEqual(nav.sheetPresentationController?.detents.map(\.identifier), [.large])
    nav.dismiss(animated: false)
    window.isHidden = true
  }
  func testOfficialModelsOpenWhereTheyCanBeSeen() {
    XCTAssertEqual(ModelViewing.subtitle, "примерка в комнате · масштаб 1:1")
    // Unsupported devices use the explicitly labelled room screen with a studio fallback.
    XCTAssertTrue(StudioForm.all.allSatisfy { FileManager.default.fileExists(atPath: $0.modelURL.path) })
  }
  func testSpecificationNumberColumnFitsThreeDigits() {
    let width = ProposalComposer.columns[0] - 8
    let font = UIFont.systemFont(ofSize: 10)
    let single = ("9" as NSString).boundingRect(
      with: CGSize(width: width, height: 200), options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
    let triple = ("999" as NSString).boundingRect(
      with: CGSize(width: width, height: 200), options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
    XCTAssertEqual(triple.height, single.height, accuracy: 0.5, "«999» stays on one line in the № column")
    XCTAssertEqual(ProposalComposer.columns.reduce(0, +), 507, accuracy: 0.01, "Table keeps the content width")
  }
  /// Root-cause probe for the iOS runtime: a flat paper background rendered off-screen with and
  /// without MSAA, with HDR, and with a deferred-shadow light. Values go to the log and to
  /// Salini-Render-QA.txt; only the path the app uses (no MSAA, no shadow pass) is asserted.
  func testOffscreenRenderKeepsTrueBackgroundValues() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let paper = ProposalComposer.studyPaper
    func corner(hdr: Bool, msaa: Bool, deferredLight: Bool) throws -> [UInt8] {
      let scene = SCNScene()
      scene.background.contents = paper
      let camera = SCNNode()
      camera.camera = SCNCamera()
      camera.camera?.wantsHDR = hdr
      camera.position = SCNVector3(0, 0, 5)
      scene.rootNode.addChildNode(camera)
      let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
      scene.rootNode.addChildNode(box)
      if deferredLight {
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.castsShadow = true
        light.light?.shadowMode = .deferred
        light.light?.shadowColor = UIColor(white: 0, alpha: 0.5)
        scene.rootNode.addChildNode(light)
      }
      let renderer = SCNRenderer(device: device, options: nil)
      renderer.scene = scene
      renderer.pointOfView = camera
      let image = renderer.snapshot(atTime: 0, with: CGSize(width: 200, height: 120),
                                    antialiasingMode: msaa ? .multisampling4X : .none)
      var pixel = [UInt8](repeating: 0, count: 4)
      let ctx = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      let cg = try XCTUnwrap(image.cgImage)
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
      return pixel
    }
    var lines = ["expected paper ≈ 237,236,232"]
    for (name, hdr, msaa, deferred) in [("plain", false, false, false), ("msaa4x", false, true, false),
                                         ("hdr", true, false, false), ("deferredShadow", false, false, true)] {
      let p = try corner(hdr: hdr, msaa: msaa, deferredLight: deferred)
      lines.append("\(name): \(p[0]),\(p[1]),\(p[2]) a\(p[3])")
    }
    let report = lines.joined(separator: "\n")
    print("Salini render QA\n" + report)
    try report.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Salini-Render-QA.txt"),
                     atomically: true, encoding: .utf8)
    let plain = try corner(hdr: false, msaa: false, deferredLight: false)
    XCTAssertGreaterThan(Int(plain[0]), 220, "Plain off-screen snapshot keeps the paper value")
  }
  /// Visual QA for the print studies: the chosen `balanced` preset with print tone mapping, three
  /// colours, written to the app's temporary folder for review on the real iOS runtime. No UI.
  func testPrintStudyLightingVariantsForReview() throws {
    let noemi = try XCTUnwrap(StudioForm.all.first { $0.product.id == "1139" })
    let colours: [(String, UIColor)] = [
      ("RAL6005", try XCTUnwrap(RALPalette.colour("6005")).colour), ("white", StudioScene.white),
      ("RAL7016", try XCTUnwrap(RALPalette.colour("7016")).colour),
    ]
    let folder = FileManager.default.temporaryDirectory
    let studio = try XCTUnwrap(ProposalComposer.PrintStudio(form: noemi, finish: .stoneMatte, lighting: .balanced))
    for (name, colour) in colours {
      let image = studio.render(colour)
      let url = folder.appendingPathComponent("Salini-Study-QA-final-\(name).png")
      try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)
      let cg = try XCTUnwrap(image.cgImage)
      let w = cg.width, h = cg.height
      var pixels = [UInt8](repeating: 0, count: w * h * 4)
      let ctx = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
      // The ground is exactly the page swatch (matted), not a tone-mapped grey or black field.
      var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0, pa: CGFloat = 0
      ProposalComposer.studyPaper.getRed(&pr, green: &pg, blue: &pb, alpha: &pa)
      for (c, expected) in [pr, pg, pb].enumerated() {
        XCTAssertEqual(Double(pixels[c]), Double(expected * 255), accuracy: 3, "\(name): corner matches the PDF swatch")
      }
      if name == "white" {
        // Highlights roll off: almost no pixel burns to flat white, so the bowl keeps its shape.
        let burned = stride(from: 0, to: pixels.count, by: 4).filter {
          pixels[$0] >= 254 && pixels[$0 + 1] >= 254 && pixels[$0 + 2] >= 254
        }.count
        XCTAssertLessThan(Double(burned) / Double(w * h), 0.02, "White bowl is not burned out")
      }
    }
    print("Salini study QA: \(folder.path)/Salini-Study-QA-final-*.png")
  }
  func testProposalLogoKeepsItsShape() throws {
    let logo = try XCTUnwrap(ProposalCanvas.blackLogo?.cgImage)
    let w = logo.width, h = logo.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(logo, in: CGRect(x: 0, y: 0, width: w, height: h))
    let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    let clear = alphas.filter { $0 == 0 }.count
    let solid = alphas.filter { $0 > 200 }.count
    XCTAssertGreaterThan(clear, alphas.count / 5, "Transparent background survives: not a black rectangle")
    XCTAssertGreaterThan(solid, alphas.count / 50, "The letters are there")
    XCTAssertEqual(alphas.first, 0, "Corner is transparent")
  }
  /// The UI export of «Дом у воды · демо»: two positions with real studies must stay 4 pages,
  /// the closing block with both links sharing the colour page instead of a near-empty fifth.
  func testTwoPositionProposalKeepsClosingOnTheColourPage() throws {
    let opera = try XCTUnwrap(Catalog.shared.product("30919"))
    var project = SaliniProject(name: "Дом у воды · демо", client: "Вымышленный Клиент")
    project.lines = [
      ProjectLine(productId: "1139", variantKey: "sStone-matte-1", quantity: 3, colour: .ral("6005")),
      ProjectLine(productId: opera.id, variantKey: opera.variants.first { $0.finish == "gloss" }?.key, quantity: 2),
    ]
    let composer = ProposalComposer(project: project, role: .home)
    let doc = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(composer.render())))
    XCTAssertEqual(doc.pageCount, 4)
    let last = (doc.page(at: doc.pageCount - 1)?.string ?? "").filter { !$0.isWhitespace }
    XCTAssertTrue(last.contains("Цвет·"), "The closing block shares the colour page")
    XCTAssertTrue(last.contains("ДАЛЬШЕ"))
    for p in [try XCTUnwrap(Catalog.shared.product("1139")), opera] {
      XCTAssertTrue(last.contains(p.url.filter { !$0.isWhitespace }), "\(p.name) link on the last page")
    }
  }
  func testProposalPaginatesLongSpecifications() throws {
    // Lead: Noemi 170 in RAL 6005 so the colour story with real studies is part of the fixture.
    let noemi = try XCTUnwrap(Catalog.shared.product("1139"))
    let others = Catalog.shared.products.filter { !$0.variants.isEmpty && $0.id != noemi.id }.prefix(39)
    let products = [noemi] + others
    var project = SaliniProject(name: "Гостиница «Вымысел»", client: "ООО Тестовая Компания")
    project.lines = [ProjectLine(productId: noemi.id, variantKey: "sStone-matte-1", quantity: 3, colour: .ral("6005"))]
      + others.map { ProjectLine(productId: $0.id, variantKey: $0.variants.first?.key, quantity: 3) }
    let composer = ProposalComposer(project: project, role: .partner)
    let data = try XCTUnwrap(composer.render())
    // Visual QA fixture: every page of a large proposal, saved for rendering outside the app.
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Salini-Proposal-40-lines-QA.pdf")
    try data.write(to: fixture, options: .atomic)
    print("Salini QA fixture: \(fixture.path) · \(composer.pageCount) pages")
    let (pages, text) = try proposalText(data)
    XCTAssertGreaterThan(pages, 8, "40 positions spill over several composition and specification pages")
    for p in products { XCTAssertTrue(text.contains(p.name.filter { !$0.isWhitespace }), "\(p.name) is in the proposal") }
  }
  func testProposalTextsRespectCategoryAndWarranty() throws {
    let operaTop = try XCTUnwrap(Catalog.shared.product("30919"))
    XCTAssertEqual(operaTop.category, "Раковины")
    XCTAssertTrue(ProposalTexts.advantages(for: operaTop).isEmpty, "Bath texts never reach the Opera washbasin")
    XCTAssertFalse(ProposalTexts.advantages(for: try XCTUnwrap(Catalog.shared.product("30897"))).isEmpty)
    // «Для вашего проекта»: only facts of the executions actually chosen.
    let opera = try XCTUnwrap(Catalog.shared.product("30919"))
    let chosen = [
      ProjectLine(productId: "1139", variantKey: "sStone-matte-1", quantity: 3, colour: .ral("6005")),
      ProjectLine(productId: opera.id, variantKey: opera.variants.first { $0.finish == "gloss" }?.key, quantity: 2),
    ]
    let facts = ProposalTexts.projectFacts(chosen)
    XCTAssertEqual(facts.count, 3)
    XCTAssertTrue(facts[0].hasPrefix("S-Stone — матовый Solid Surface"))
    XCTAssertTrue(facts[1].hasPrefix("S-Sense глянцевый"))
    XCTAssertTrue(facts[2].hasPrefix("RAL 6005 · Зелёный мох"))
    XCTAssertFalse(facts.joined().contains("10 лет"), "No blanket warranty promise")
    let mirror = try XCTUnwrap(Catalog.shared.products.first { $0.category == "Зеркала" && !$0.variants.isEmpty })
    let mirrorFacts = ProposalTexts.projectFacts([ProjectLine(productId: mirror.id, variantKey: mirror.variants.first?.key)])
    XCTAssertEqual(mirrorFacts, ["Зеркала: гарантия 2 года"], "Non-mineral items get only their own category facts")
    XCTAssertEqual(ProposalTexts.warranty(for: try XCTUnwrap(Catalog.shared.product("20381"))), "2 года")
    XCTAssertTrue(ProposalTexts.warranty(for: try XCTUnwrap(Catalog.shared.product("9079"))).hasPrefix("5 лет"))
    XCTAssertTrue(ProposalTexts.warranty(for: operaTop).hasPrefix("10 лет"))
  }
  func testProposalKeepsUnresolvedLinesAndNeverGuessesTheirFinish() throws {
    var project = SaliniProject(name: "Вымышленная дача")
    project.lines = [
      ProjectLine(productId: "1139", variantKey: "retired-execution"),  // execution gone
      ProjectLine(productId: "no-such-product", variantKey: nil),
      ProjectLine(productId: "1139", variantKey: "sStone-matte-1"),
    ]
    let composer = ProposalComposer(project: project, role: .home)
    composer.rendersStudies = false
    XCTAssertEqual(composer.lines.count, 3)
    XCTAssertNil(composer.leadFinish, "Unresolved saved execution: no surface is guessed")
    XCTAssertNil(composer.leadForm)
    let doc = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(composer.render())))
    let text = (doc.string ?? "").filter { !$0.isWhitespace }
    XCTAssertTrue(text.contains("Позициянедоступнавкаталоге"))
    XCTAssertTrue(text.contains("исполнениетребуетуточнения"))
  }
  func testMirrorLeadGetsAPhotoPageWithoutRALStudies() {
    guard let mirror = Catalog.shared.products.first(where: { $0.category == "Зеркала" && !$0.variants.isEmpty }) else {
      return XCTFail("No mirror in catalogue")
    }
    var project = SaliniProject(name: "Вымышленный номер")
    project.lines = [ProjectLine(productId: mirror.id, variantKey: mirror.variants.first?.key)]
    let composer = ProposalComposer(project: project, role: .partner)
    XCTAssertFalse(composer.leadPaintable)
    XCTAssertNil(composer.makeStudies(progress: { _ in }, isCancelled: { false }))
  }
  func testColourStudiesUseOnlyTheLeadItemsOwnModel() {
    var withModel = SaliniProject(name: "Вымышленный дом")
    withModel.lines = [ProjectLine(productId: "1139", variantKey: "sSense-gloss-1", colour: .ral("5014"))]
    let a = ProposalComposer(project: withModel, role: .home)
    XCTAssertEqual(a.leadForm?.product.id, "1139", "Noemi renders its own model")
    XCTAssertEqual(a.leadFinish, .senseGloss)
    XCTAssertEqual(a.studyColours().first?.0, "Выбранный · RAL 5014 · Голубино-синий")
    var noModel = SaliniProject(name: "Вымышленная студия")
    noModel.lines = [ProjectLine(productId: "20381", variantKey: "none-none-1")]
    let b = ProposalComposer(project: noModel, role: .home)
    XCTAssertNil(b.leadForm, "Velasca has no model: photo and swatches, nothing substituted")
    XCTAssertNil(b.makeStudies(progress: { _ in }, isCancelled: { false }))
  }
  @MainActor func testStudioAppliesTheLatestChoiceWhenTheModelArrives() throws {
    let form = try XCTUnwrap(StudioForm.noemi)
    let view = StudioSceneView(frame: CGRect(x: 0, y: 0, width: 373, height: 440))
    view.load(form, finish: .stoneMatte, colour: StudioScene.white, shot: .form)
    // Chosen while the model is still loading: must win over the values captured at load time.
    view.apply(finish: .senseGloss, colour: StudioScene.white)
    view.frame(.macro, animated: false)
    view.lightPosition = 0.8
    let deadline = Date().addingTimeInterval(20)
    while view.studio == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let studio = try XCTUnwrap(view.studio)
    XCTAssertEqual(studio.finish, .senseGloss)
    XCTAssertEqual(studio.shot, .macro)
    XCTAssertEqual(studio.aspect, 373.0 / 440.0, accuracy: 0.001)
  }
  // MARK: Material realism (8.1)

  func testRadianceDecoderReadsRunLengthAndFlatScanlines() throws {
    // Flat: two pixels. (128, 64, 32, e = 129) → value · 2^(129 − 136) = value / 128.
    var flat = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 1 +X 2\n".utf8)
    flat.append(contentsOf: [128, 64, 32, 129, 0, 0, 0, 0])
    let a = try XCTUnwrap(RadianceImage(data: flat))
    XCTAssertEqual(a.width, 2)
    XCTAssertEqual(a.pixels[0], 1.0, accuracy: 1e-6)
    XCTAssertEqual(a.pixels[1], 0.5, accuracy: 1e-6)
    XCTAssertEqual(a.pixels[2], 0.25, accuracy: 1e-6)
    XCTAssertEqual(a.pixels[3], 0, "e = 0 is black")
    // New-style RLE, width 8: R run of 8 × 200, G literal 0…7, B run 0, E run 136 (scale 1).
    var rle = Data("#?RADIANCE\n\n-Y 1 +X 8\n".utf8)
    let run: UInt8 = 128 + 8
    let scanline: [UInt8] = [2, 2, 0, 8, run, 200, 8, 0, 1, 2, 3, 4, 5, 6, 7, run, 0, run, 136]
    rle.append(contentsOf: scanline)
    let b = try XCTUnwrap(RadianceImage(data: rle))
    XCTAssertEqual(b.pixels[0], 200, "Values above 1 survive: this is radiance, not a picture")
    XCTAssertEqual(b.pixels[7 * 3 + 1], 7)
    XCTAssertNil(RadianceImage(data: Data("not an hdr".utf8)))
    var truncated = Data("#?RADIANCE\n\n-Y 2 +X 8\n".utf8)
    truncated.append(contentsOf: [2, 2, 0, 8, run])
    XCTAssertNil(RadianceImage(data: truncated), "Broken files fail instead of crashing")
  }
  func testStudioHDRIIsTheBundledUnclippedRadianceLoadedOnce() throws {
    let url = try XCTUnwrap(StudioHDRI.url, "CC0 HDRI is bundled")
    XCTAssertEqual(url.lastPathComponent, "studio_small_09_2k.hdr")
    let loaded = try XCTUnwrap(StudioHDRI.shared())
    XCTAssertEqual(loaded.width, 2048)
    XCTAssertEqual(loaded.height, 1024)
    XCTAssertGreaterThan(loaded.sourcePeak / loaded.sourceMean, 100, "Real studio range, not an 8-bit image")
    XCTAssertEqual(loaded.image.bitsPerComponent, 16)
    XCTAssertTrue(loaded.image.bitmapInfo.contains(.floatComponents), "Half-float radiance reaches SceneKit")
    XCTAssertTrue(StudioHDRI.shared()?.image === loaded.image, "Decoded once, shared by every studio")
    // The softbox the key light stands for is the brightest thing above the horizon at its azimuth.
    XCTAssertEqual(StudioHDRI.keyAzimuth, 168, accuracy: 0.5)
  }
  func testPhysicalStudioMaterialsLightsAndLifecycle() throws {
    let noemi = try XCTUnwrap(StudioForm.noemi)
    let studio = try XCTUnwrap(StudioScene(modelURL: noemi.modelURL, finish: .stoneMatte))
    XCTAssertEqual(studio.look, .physical, "The live studio default")
    XCTAssertNotNil(studio.technique, "PBR Neutral pass compiled")
    let hdri = try XCTUnwrap(StudioHDRI.shared())
    XCTAssertTrue((studio.scene.lightingEnvironment.contents as AnyObject) === hdri.image)
    var lights: [SCNLight] = []
    studio.scene.rootNode.enumerateHierarchy { n, _ in if let l = n.light { lights.append(l) } }
    XCTAssertFalse(lights.contains { $0.type == .ambient }, "No unoccluded ambient wash")
    XCTAssertEqual(lights.filter(\.castsShadow).count, 1, "One key, one coherent shadow")
    func bathMaterials() -> [SCNMaterial] {
      var out: [SCNMaterial] = []
      studio.model.enumerateHierarchy { n, _ in out += n.geometry?.materials ?? [] }
      return out
    }
    let green = try XCTUnwrap(RALPalette.colour("6005")).colour
    for finish in StudioFinish.allCases {
      // Twice: applying is idempotent, nothing accumulates.
      studio.apply(finish: finish, colour: green)
      studio.apply(finish: finish, colour: green)
      for m in bathMaterials() {
        XCTAssertEqual(m.lightingModel, .physicallyBased)
        XCTAssertEqual((m.metalness.contents as? NSNumber)?.doubleValue, 0, "\(finish): mineral, never metallic")
        XCTAssertEqual(m.diffuse.contents as? UIColor, green, "\(finish): colour unchanged")
        XCTAssertEqual(m.shaderModifiers?.count, 1)
        let coat = (m.clearCoat.contents as? NSNumber)?.doubleValue
        let coatRoughness = (m.clearCoatRoughness.contents as? NSNumber)?.doubleValue ?? -1
        switch finish {
        case .stoneMatte: XCTAssertEqual(coat, 0, "S-Stone: one honed lobe")
        case .senseMatte:
          XCTAssertEqual(coat, 1, "S-Sense: separate Gelcoat lobe")
          XCTAssertGreaterThan(coatRoughness, 0.2)
        case .senseGloss:
          XCTAssertEqual(coat, 1)
          XCTAssertLessThan(coatRoughness, 0.06, "Smooth Gelcoat")
        }
        XCTAssertEqual((m.value(forKey: "hasCoat") as? NSNumber)?.floatValue, finish == .stoneMatte ? 0 : 1)
      }
    }
    XCTAssertEqual(try XCTUnwrap(StudioScene(modelURL: noemi.modelURL, finish: .stoneMatte)).fittingCount, 0,
                   "One-piece forms have no fittings")
  }
  /// Position indices an element actually draws, decoded from its real encoding.
  ///
  /// Official USDZ load as `.polygon` elements: first `primitiveCount` per-polygon corner counts,
  /// then, per corner, one index per geometry source (position, normal, texcoord — in the order of
  /// `geometry.sources`), because normals and UVs are indexed separately. The channel count is
  /// derived from the data's real length; triangles / strips / lines / points are handled the same
  /// way. Index width 1, 2 or 4 bytes. Nil when the data does not match its own description —
  /// never a read past the buffer.
  static func positionIndices(of element: SCNGeometryElement, in geometry: SCNGeometry) -> [Int]? {
    let width = element.bytesPerIndex
    guard [1, 2, 4].contains(width) else { return nil }
    let data = element.data
    let stored = data.count / width
    func value(at i: Int) -> Int? {
      guard i >= 0, i < stored else { return nil }
      return data.withUnsafeBytes { raw in
        switch width {
        case 1: return Int(raw.load(fromByteOffset: i, as: UInt8.self))
        case 2: return Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
        default: return Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
        }
      }
    }
    let n = element.primitiveCount
    var corners: Int
    var first = 0
    switch element.primitiveType {
    case .triangles: corners = n * 3
    case .triangleStrip: corners = n > 0 ? n + 2 : 0
    case .line: corners = n * 2
    case .point: corners = n
    case .polygon:
      corners = 0
      for p in 0..<n {
        guard let c = value(at: p), c >= 3 else { return nil }
        corners += c
      }
      first = n
    @unknown default: return nil
    }
    guard corners > 0, (stored - first) % corners == 0 else { return nil }
    let channels = (stored - first) / corners
    guard channels >= 1 else { return nil }
    let position = channels > 1
      ? (geometry.sources.firstIndex { $0.semantic == .vertex } ?? 0) : 0
    guard position < channels else { return nil }
    var out: [Int] = []
    out.reserveCapacity(corners)
    for corner in 0..<corners {
      guard let v = value(at: first + corner * channels + position) else { return nil }
      out.append(v)
    }
    return out
  }
  /// World-space bounds (scene units) of the vertices drawn with one material. Reads positions by
  /// the source's own stride, offset and component size, bounds-checked.
  static func bounds(of material: SCNMaterial, in model: SCNNode) -> (lo: SIMD3<Float>, hi: SIMD3<Float>)? {
    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
    var found = false
    var failed = false
    model.enumerateHierarchy { node, _ in
      guard let g = node.geometry, g.materials.contains(where: { $0 === material }) else { return }
      guard let source = g.sources(for: .vertex).first, source.usesFloatComponents,
        source.componentsPerVector >= 3, [4, 8].contains(source.bytesPerComponent)
      else {
        failed = true
        return
      }
      let transform = node.simdWorldTransform
      let data = source.data
      func position(_ index: Int) -> SIMD3<Float>? {
        guard index >= 0, index < source.vectorCount else { return nil }
        let base = source.dataOffset + index * source.dataStride
        let size = source.bytesPerComponent
        guard base >= 0, base + 3 * size <= data.count else { return nil }
        return data.withUnsafeBytes { raw in
          size == 4
            ? SIMD3((0..<3).map { raw.loadUnaligned(fromByteOffset: base + $0 * 4, as: Float.self) })
            : SIMD3((0..<3).map { Float(raw.loadUnaligned(fromByteOffset: base + $0 * 8, as: Double.self)) })
        }
      }
      for (i, element) in g.elements.enumerated() where i < g.materials.count && g.materials[i] === material {
        // Anything undecodable fails the whole measurement instead of silently shrinking it.
        guard let indices = Self.positionIndices(of: element, in: g) else {
          failed = true
          continue
        }
        for index in indices {
          guard let v = position(index) else {
            failed = true
            continue
          }
          let p = transform * SIMD4<Float>(v, 1)
          lo = simd_min(lo, SIMD3(p.x, p.y, p.z))
          hi = simd_max(hi, SIMD3(p.x, p.y, p.z))
          found = true
        }
      }
    }
    return found && !failed ? (lo, hi) : nil
  }
  /// Fittings are an explicit, verified list per model — not a size heuristic. Checked against the
  /// real geometry: the built-ins' steel part reaches the floor (support feet) below the shell;
  /// Sofia's is the small waste fitting; Ninfea's dark lower band and Greca's pedestal stay mineral.
  func testOnlyVerifiedMetalPartsBecomeSteel() throws {
    let green = try XCTUnwrap(RALPalette.colour("6005")).colour
    func scene(_ siteName: String) throws -> StudioScene {
      let form = try XCTUnwrap(StudioForm.all.first { $0.product.siteName == siteName }, siteName)
      return try XCTUnwrap(StudioScene(modelURL: form.modelURL, finish: .stoneMatte, colour: green))
    }
    func materials(_ s: StudioScene) -> [SCNMaterial] {
      var out: [SCNMaterial] = []
      s.model.enumerateHierarchy { n, _ in
        for m in n.geometry?.materials ?? [] where !out.contains(where: { $0 === m }) { out.append(m) }
      }
      return out
    }
    for name in ["КАСКАТА 180x80", "ОРНЕЛЛА 170х75", "ОРЛАНДА 160x70"] {
      let s = try scene(name)
      XCTAssertEqual(s.fittingCount, 1, name)
      let steel = try XCTUnwrap(materials(s).first { s.isFitting($0) }, name)
      let shell = try XCTUnwrap(materials(s).first { !s.isFitting($0) }, name)
      XCTAssertEqual((steel.metalness.contents as? NSNumber)?.doubleValue, 1, "\(name): steel")
      XCTAssertNotEqual(steel.diffuse.contents as? UIColor, green, "\(name): fittings are not painted RAL")
      XCTAssertEqual(shell.diffuse.contents as? UIColor, green)
      let feet = try XCTUnwrap(Self.bounds(of: steel, in: s.model))
      let body = try XCTUnwrap(Self.bounds(of: shell, in: s.model))
      XCTAssertLessThan(feet.lo.y, 0.01, "\(name): the steel part stands on the floor (support feet)")
      XCTAssertGreaterThan(body.lo.y, feet.lo.y + 0.03, "\(name): the cast shell is above its feet")
    }
    let sofia = try scene("СОФИЯ 170")
    XCTAssertEqual(sofia.fittingCount, 1)
    let drain = try XCTUnwrap(materials(sofia).first { sofia.isFitting($0) })
    let drainBox = try XCTUnwrap(Self.bounds(of: drain, in: sofia.model))
    let sofiaBox = try XCTUnwrap(Self.bounds(of: try XCTUnwrap(materials(sofia).first { !sofia.isFitting($0) }), in: sofia.model))
    let span = (drainBox.hi - drainBox.lo).max()
    XCTAssertLessThan(span, (sofiaBox.hi - sofiaBox.lo).max() * 0.08, "Sofia's steel part is the small waste fitting")
    let ninfea = try scene("НИНФЕЯ")
    XCTAssertEqual(ninfea.fittingCount, 0, "Ninfea's dark lower band is not proven metal: it stays mineral")
    XCTAssertTrue(materials(ninfea).allSatisfy { ($0.diffuse.contents as? UIColor) == green && $0.shaderModifiers != nil })
    let greca = try scene("GRECA 180")
    XCTAssertEqual(greca.fittingCount, 0, "Greca's pedestal is cast with the bath")
    XCTAssertEqual(materials(greca).count, 1)
  }
  func testProductExposureKeepsWhiteShadedAndDarkReadableWithAStableSet() throws {
    let white = StudioScene.productExposure(for: StudioScene.white)
    let anthracite = StudioScene.productExposure(for: try XCTUnwrap(RALPalette.colour("7016")).colour)
    XCTAssertLessThan(white, -0.2, "White is exposed down: its walls keep their shading")
    XCTAssertGreaterThan(anthracite, 0.2, "Anthracite is exposed up: its form reads")
    let noemi = try XCTUnwrap(StudioForm.noemi)
    let studio = try XCTUnwrap(StudioScene(modelURL: noemi.modelURL, finish: .stoneMatte, colour: StudioScene.white))
    let whiteEnvironment = studio.scene.lightingEnvironment.intensity
    studio.apply(finish: .stoneMatte, colour: try XCTUnwrap(RALPalette.colour("7016")).colour)
    XCTAssertEqual(studio.scene.lightingEnvironment.intensity / whiteEnvironment, CGFloat(exp2(anthracite - white)), accuracy: 0.001)
    // The set does not change with the product: floor albedo × light stays constant.
    var floor: SCNMaterial?
    studio.scene.rootNode.enumerateHierarchy { n, _ in if n.geometry is SCNShape { floor = n.geometry?.firstMaterial } }
    let f = try XCTUnwrap(floor)
    XCTAssertEqual(f.diffuse.intensity * studio.scene.lightingEnvironment.intensity, StudioScene.physicalEnvironment, accuracy: 0.001)
  }
  func testThirdPartyNoticesShipWithTheApp() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "third-party-notices", withExtension: "txt"))
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(text.contains("KhronosGroup/ToneMapping"))
    XCTAssertTrue(text.contains("Copyright 2024 The Khronos Group, Inc."))
    XCTAssertTrue(text.contains("ported to the Metal Shading Language"))
    XCTAssertTrue(text.contains("Apache License"))
    XCTAssertTrue(text.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"), "Full licence text")
    XCTAssertTrue(text.contains("studio_small_09") && text.contains("Sergej Majboroda") && text.contains("CC0"))
  }
  @MainActor func testLiveStudioShowsThePhysicalLookAndPrintKeepsTheAcceptedOne() throws {
    let form = try XCTUnwrap(StudioForm.noemi)
    let view = StudioSceneView(frame: CGRect(x: 0, y: 0, width: 373, height: 440))
    XCTAssertTrue(view.isJitteringEnabled)
    view.load(form, finish: .stoneMatte, colour: StudioScene.white, shot: .form)
    let deadline = Date().addingTimeInterval(20)
    while view.studio == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let studio = try XCTUnwrap(view.studio)
    XCTAssertEqual(studio.look, .physical)
    XCTAssertTrue(view.technique === studio.technique, "The view maps the half-float frame with the studio's pass")
    let print = try XCTUnwrap(ProposalComposer.PrintStudio(form: form, finish: .stoneMatte))
    XCTAssertEqual(print.studio.look, .legacy, "Print studies keep their accepted look explicitly")
    XCTAssertNil(print.studio.technique)
  }
  /// Visual A/B for review (Codex): Noemi and Greca, whole form and macro, white / RAL 6005 / RAL
  /// 7016, every finish the form is sold in, legacy | physical side by side. Writes
  /// `Salini-Material-AB/*.png`, a grid per model and `report.txt` to the temporary folder. The
  /// assertions only catch broken renders; quality is judged by eye on the grid.
  func testMaterialRealismABForReview() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Salini-Material-AB")
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let colours: [(String, UIColor)] = [
      ("white", StudioScene.white), ("RAL6005", try XCTUnwrap(RALPalette.colour("6005")).colour),
      ("RAL7016", try XCTUnwrap(RALPalette.colour("7016")).colour),
    ]
    let size = CGSize(width: 600, height: 460)
    var report = ["model shot finish colour look burned% mean"]
    for name in ["НОЭМИ 170", "GRECA 180"] {
      let form = try XCTUnwrap(StudioForm.all.first { $0.product.siteName == name })
      var cells: [(String, UIImage, UIImage)] = []
      var renders: [StudioScene.Look: (StudioScene, SCNRenderer)] = [:]
      for look in StudioScene.Look.allCases {
        let studio = try XCTUnwrap(StudioScene(modelURL: form.modelURL, finish: form.finishes[0], look: look))
        studio.aspect = size.width / size.height
        studio.setLight(0.42)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = studio.scene
        renderer.pointOfView = studio.camera
        renderer.technique = studio.technique
        renders[look] = (studio, renderer)
      }
      for shot in [StudioScene.Shot.form, .macro] {
        for finish in form.finishes {
          var whiteMean: [StudioFinish: Double] = [:]
          for (colourName, colour) in colours {
            var pair: [StudioScene.Look: UIImage] = [:]
            for look in StudioScene.Look.allCases {
              let (studio, renderer) = try XCTUnwrap(renders[look])
              studio.frame(shot, animated: false)
              studio.apply(finish: finish, colour: colour)
              let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
              pair[look] = image
              let label = "\(form.product.model ?? name)-\(shot == .form ? "form" : "macro")-\(finish.rawValue)-\(colourName)-\(look.rawValue)"
              try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(label + ".png"))
              let stats = try XCTUnwrap(Self.lumaStats(image))
              report.append("\(label) \(String(format: "%.2f %.1f", stats.burned * 100, stats.mean))")
              XCTAssertGreaterThan(stats.mean, 8, "\(label): not a black frame")
              XCTAssertGreaterThan(stats.deviation, 6, "\(label): not a flat frame")
              if look == .physical, colourName == "white" {
                XCTAssertLessThan(stats.burned, 0.005, "\(label): white keeps its inner-bowl gradient")
                whiteMean[finish] = stats.mean
              }
            }
            cells.append(("\(shot == .form ? "Форма" : "Борт") · \(finish.short) · \(colourName)",
                          try XCTUnwrap(pair[.legacy]), try XCTUnwrap(pair[.physical])))
          }
        }
      }
      let grid = Self.abGrid(cells, cell: CGSize(width: 300, height: 230))
      try XCTUnwrap(grid.jpegData(compressionQuality: 0.9))
        .write(to: folder.appendingPathComponent("grid-\(form.product.model ?? name).jpg"))
    }
    try report.joined(separator: "\n").write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    print("Salini material A/B: \(folder.path)")
  }
  static func lumaStats(_ image: UIImage) -> (mean: Double, deviation: Double, burned: Double)? {
    guard let cg = image.cgImage else { return nil }
    let w = cg.width, h = cg.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var sum = 0.0, sq = 0.0, burned = 0
    for i in stride(from: 0, to: pixels.count, by: 4) {
      let y = 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
      sum += y
      sq += y * y
      if pixels[i] >= 250, pixels[i + 1] >= 250, pixels[i + 2] >= 250 { burned += 1 }
    }
    let n = Double(w * h)
    let mean = sum / n
    return (mean, sqrt(max(0, sq / n - mean * mean)), Double(burned) / n)
  }
  static func abGrid(_ cells: [(String, UIImage, UIImage)], cell: CGSize) -> UIImage {
    let label: CGFloat = 18
    let size = CGSize(width: cell.width * 2, height: (cell.height + label) * CGFloat(cells.count))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: size))
      for (i, (title, before, after)) in cells.enumerated() {
        let y = CGFloat(i) * (cell.height + label)
        ("\(title)    до | после" as NSString).draw(at: CGPoint(x: 4, y: y + 2), withAttributes: [
          .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black,
        ])
        before.draw(in: CGRect(x: 0, y: y + label, width: cell.width, height: cell.height))
        after.draw(in: CGRect(x: cell.width, y: y + label, width: cell.width, height: cell.height))
      }
    }
  }
  @MainActor func testHomeAndMaterialStudioLayOutInAWindow() throws {
    for screen in [UINavigationController(rootViewController: HomeController()),
                   UINavigationController(rootViewController: MaterialStudioController())] {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      window.rootViewController = screen
      window.makeKeyAndVisible()
      screen.view.layoutIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      XCTAssertNotNil(screen.topViewController?.view.window)
      window.isHidden = true
    }
    let noemi = try XCTUnwrap(StudioForm.noemi)
    XCTAssertEqual(noemi.product.siteName, "НОЭМИ 170")
    XCTAssertEqual(noemi.finishes, [.stoneMatte, .senseGloss], "Only executions Noemi is sold in")
    let ornella = try XCTUnwrap(StudioForm.all.first { $0.product.siteName == "ОРНЕЛЛА 170х75" })
    XCTAssertEqual(ornella.finishes, [.stoneMatte, .senseMatte, .senseGloss])
    XCTAssertTrue(StudioForm.all.allSatisfy { FileManager.default.fileExists(atPath: $0.modelURL.path) })
    let greca = try XCTUnwrap(StudioForm.all.first { $0.product.siteName == "GRECA 180" })
    XCTAssertEqual(greca.finishes, [.stoneMatte], "Greca is S-Stone only: no gloss is shown on it")
  }
  func testSearchOpensExactArticleAndForgivesKeyboardLayout() throws {
    let c = Catalog.shared
    let exact = try XCTUnwrap(c.search("1051201M").first)
    XCTAssertEqual(exact.product.id, "20645")
    XCTAssertEqual(exact.product.variant(key: exact.variantKey)?.sku, "1051201M")
    let layout = try XCTUnwrap(c.search("1051201Ь").first)
    XCTAssertEqual(layout.product.variant(key: layout.variantKey)?.sku, "1051201M")
    XCTAssertTrue(c.search("noemi").contains { $0.product.siteName == "НОЭМИ 170" })
    XCTAssertTrue(c.search("ноэми 170").contains { $0.product.siteName == "НОЭМИ 170" })
    XCTAssertTrue(c.search("орнелла 170x75").contains { $0.product.siteName == "ОРНЕЛЛА 170х75" })
    var f = CatalogFilter()
    f.category = "Ванны"
    f.finishes = [.senseMatte]
    let matte = c.search("", filter: f)
    XCTAssertFalse(matte.isEmpty)
    XCTAssertTrue(matte.allSatisfy { $0.product.variants.contains { $0.material == "sSense" && $0.finish == "matte" } })
    XCTAssertTrue(c.search("").allSatisfy { !$0.product.isOption }, "Options appear only on request")
  }
  func testSimulationPauseAndBoundedEventHistory() {
    let s = FactorySimulation()
    s.paused = true
    s.advance()
    XCTAssertEqual(s.tick, 0)
    s.paused = false
    for _ in 0..<100 { s.advance() }
    XCTAssertEqual(s.tick, 100)
    XCTAssertLessThanOrEqual(s.events.count, 20)
    XCTAssertGreaterThanOrEqual(s.progress, 0)
    XCTAssertLessThanOrEqual(s.progress, 1)
  }
  func testPriorityActionIsIdempotent() {
    let s = FactorySimulation()
    s.expedite()
    let count = s.events.count
    s.expedite()
    XCTAssertEqual(s.events.count, count)
    XCTAssertTrue(s.priority)
    s.resolve()
    XCTAssertTrue(s.resolved)
  }
  func testPartnerReservationsConserveStockAndPersist() throws {
    let suite = "Salini.partner.tests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PartnerStore(defaults: defaults)
    XCTAssertEqual(store.available("aria", warehouse: 0), 8)
    XCTAssertNil(store.reserve("aria", warehouse: 0, quantity: 0))
    XCTAssertNil(store.reserve("aria", warehouse: 0, quantity: 9))
    let order = try XCTUnwrap(store.reserve("aria", warehouse: 0, quantity: 3))
    XCTAssertEqual(store.available("aria", warehouse: 0), 5)
    XCTAssertEqual(store.available("aria", warehouse: 1), 3)
    store.schedule(order.id)
    store.schedule(order.id)
    let restored = PartnerStore(defaults: defaults)
    XCTAssertEqual(restored.orders.count, 1)
    XCTAssertTrue(restored.orders[0].scheduled)
    XCTAssertEqual(restored.available("aria", warehouse: 0), 5)
    XCTAssertNotNil(restored.reserve("aria", warehouse: 0, quantity: 5))
    XCTAssertNil(restored.reserve("aria", warehouse: 0, quantity: 1))
  }
  @MainActor func testOfficialGrecaModelLoadsWithGeometry() throws {
    let model = try GrecaModel.load()
    var geometryCount = 0
    model.enumerateChildNodes { node, _ in if node.geometry != nil { geometryCount += 1 } }
    XCTAssertGreaterThan(geometryCount, 0)
    XCTAssertGreaterThan(model.scale.x, 0)
  }
  @MainActor func testAudienceChangesFunctionalDestinations() throws {
    let role = DemoStore.shared.role
    defer { DemoStore.shared.role = role }
    let tabs = MainTabs()
    tabs.loadViewIfNeeded()
    func root(_ i: Int) -> UIViewController? {
      (tabs.viewControllers?[i] as? UINavigationController)?.viewControllers.first
    }
    for audience in Audience.allCases {
      DemoStore.shared.role = audience
      tabs.applyAudience()
      XCTAssertTrue(root(MainTabs.catalogTabIndex) is CatalogController, "\(audience)")
      XCTAssertTrue(root(MainTabs.projectTabIndex) is ProjectsController, "\(audience)")
    }
    DemoStore.shared.role = .atelier
    tabs.applyAudience()
    XCTAssertTrue(root(MainTabs.toolTabIndex) is ResourcesController)
    DemoStore.shared.role = .partner
    tabs.applyAudience()
    XCTAssertTrue(root(MainTabs.toolTabIndex) is StockController)
    DemoStore.shared.role = .home
    tabs.applyAudience()
    XCTAssertEqual(tabs.viewControllers?.count, 4)
  }
  @MainActor func testAllMainScreensLoadWithBundledImages() {
    let screens: [UIViewController] =
      [
        HomeController(), CatalogController(), ProjectsController(), ProfileController(),
        OwnerController(), MaterialsController(), HomeStoryController(.interior), HomeStoryController(.brand),
        ResourcesController(), ChooseController(), CompareController(), StockController(),
        PartnerOrdersController(), CatalogFilterController(filter: CatalogFilter()) { _ in },
      ] + Product.all.compactMap { Catalog.shared.product($0.id).map { CatalogProductController($0) } }
    for screen in screens {
      screen.loadViewIfNeeded()
      XCTAssertNotNil(screen.view)
    }
    for product in Product.all { XCTAssertNotNil(UIImage(named: product.image + ".jpg")) }
    XCTAssertNotNil(Bundle.main.url(forResource: "Greca", withExtension: "usdz"))
  }
  @MainActor func testProductDetailShowsPriceAndArticleOfTheChosenExecution() throws {
    let aria = try XCTUnwrap(Catalog.shared.product("aria"))
    func texts(_ view: UIView) -> [String] {
      ([(view as? UILabel)?.text].compactMap { $0 }) + view.subviews.flatMap(texts)
    }
    let stoneKey = try XCTUnwrap(aria.variants.first { $0.sku == "1051201M" }?.key)
    let stone = CatalogProductController(aria, variantKey: stoneKey)
    stone.loadViewIfNeeded()
    XCTAssertTrue(texts(stone.view).contains(rubles(890000)))
    XCTAssertTrue(texts(stone.view).contains { $0.contains("1051201M") })
    let sense = CatalogProductController(aria)
    sense.loadViewIfNeeded()
    XCTAssertTrue(texts(sense.view).contains(rubles(790000)))
    XCTAssertTrue(texts(sense.view).contains { $0.contains("1051101G") })
    let unknown = try XCTUnwrap(Catalog.shared.products.first { $0.siteName == "ОРНЕЛЛА 170х75" })
    let matte = CatalogProductController(unknown, variantKey: unknown.variants[1].key)
    matte.loadViewIfNeeded()
    XCTAssertTrue(texts(matte.view).contains("уточняется у менеджера"))
  }

  func testGroundPanTracksFingerInBothScreenAxes() {
    var camera = CampusCamera()
    camera.viewport = CGSize(width: 402, height: 600)
    camera.scale = 30
    let origin = camera.focus
    let gesture = CGPoint(x: 90, y: -35)
    camera.pan(gesture, from: origin)
    let dx = Double(camera.focus.x - origin.x)
    let dz = Double(camera.focus.z - origin.z)
    let unitsPerPoint = 2 * camera.scale / Double(camera.viewport.height)
    let screenX = -(dx - dz) / sqrt(2) / unitsPerPoint
    let screenY = -(dx + dz) / sqrt(6) / unitsPerPoint
    XCTAssertEqual(screenX, gesture.x, accuracy: 0.001)
    XCTAssertEqual(screenY, gesture.y, accuracy: 0.001)
    XCTAssertEqual(camera.focus.y, 0)
  }
  func testFocusedHallFillsMostOfTheVisibleWidth() {
    var camera = CampusCamera()
    camera.viewport = CGSize(width: 402, height: 520)
    for zone in FactoryZone.allCases {
      camera.frame(zone)
      let projected = Double(zone.footprint.width + zone.footprint.height) / sqrt(2)
      let visible = 2 * camera.scale * Double(camera.viewport.width / camera.viewport.height)
      XCTAssertTrue((0.7...0.82).contains(projected / visible), "\(zone.title): \(projected / visible)")
      XCTAssertLessThan(camera.scale, camera.overviewScale)
    }
  }
  func testCampusCameraBoundsZoomAndViewportFit() {
    var camera = CampusCamera()
    camera.viewport = CGSize(width: 402, height: 550)
    camera.overview()
    let width = 2 * camera.scale * Double(camera.viewport.width / camera.viewport.height)
    XCTAssertGreaterThan(width, Double(CampusSite.projectedSize.width))
    camera.pan(CGPoint(x: 100_000, y: -100_000), from: camera.focus)
    XCTAssertTrue((-90...160).contains(camera.focus.x))
    XCTAssertTrue((-72...172).contains(camera.focus.z))
    camera.quarter()
    XCTAssertLessThan(camera.scale, camera.overviewScale, "The opening view is closer than the territory")
    camera.zoom(0.001)
    XCTAssertEqual(camera.scale, 16)
    camera.zoom(100_000)
    XCTAssertEqual(camera.scale, camera.overviewScale * 1.15, accuracy: 0.001)
  }
  @MainActor func testSceneRetainsTrueIsometryAcrossEveryZoneAndZoom() throws {
    let view = FactorySceneView()
    view.frame = CGRect(x: 0, y: 0, width: 402, height: 550)
    view.layoutIfNeeded()
    let camera = try XCTUnwrap(view.pointOfView)
    let original = camera.orientation
    for zone in FactoryZone.allCases {
      view.focusOn(zone, animated: false)
      view.stepZoom(true)
      XCTAssertEqual(camera.orientation.x, original.x, accuracy: 0.0001)
      XCTAssertEqual(camera.orientation.y, original.y, accuracy: 0.0001)
      XCTAssertEqual(camera.orientation.z, original.z, accuracy: 0.0001)
      XCTAssertEqual(camera.orientation.w, original.w, accuracy: 0.0001)
      let offset = SCNVector3(
        camera.position.x - view.mapCamera.focus.x,
        camera.position.y - view.mapCamera.focus.y, camera.position.z - view.mapCamera.focus.z)
      XCTAssertEqual(offset.x, offset.y, accuracy: 0.0001)
      XCTAssertEqual(offset.y, offset.z, accuracy: 0.0001)
    }
    view.resetCamera()
    XCTAssertEqual(camera.orientation.x, original.x, accuracy: 0.0001)
    view.setPaused(true)
  }
  @MainActor func testChooseShowsTheWholeMatchingListInSteps() throws {
    var a = ChooseHelper.Answers()
    a.kind = .washbasin
    let all = ChooseHelper.recommend(a)
    XCTAssertGreaterThan(all.count, 12)
    let screen = ChooseController()
    let nav = UINavigationController(rootViewController: screen)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = nav
    window.makeKeyAndVisible()
    screen.loadViewIfNeeded()
    func find(_ id: String, in view: UIView) -> UIView? {
      view.accessibilityIdentifier == id ? view : view.subviews.lazy.compactMap { find(id, in: $0) }.first
    }
    // Default answer is freestanding baths; the "more" control appears whenever > 12 match.
    let first = ChooseHelper.recommend(ChooseHelper.Answers())
    XCTAssertEqual(find("choose.more", in: screen.view) != nil, first.count > 12)
    window.isHidden = true
  }
  @MainActor func testCompareUsesRealExecutionsAndLibraryListsEveryModel() {
    let compare = CompareController()
    compare.loadViewIfNeeded()
    func texts(_ view: UIView) -> [String] {
      ([(view as? UILabel)?.text].compactMap { $0 }) + view.subviews.flatMap(texts)
    }
    let all = texts(compare.view)
    XCTAssertTrue(all.contains(rubles(890000)), "Aria S-Stone keeps its own price")
    XCTAssertTrue(all.contains("1051201M"))
    let library = ResourcesController()
    library.loadViewIfNeeded()
    library.viewWillAppear(false)
    XCTAssertTrue(texts(library.view).contains { $0.contains("\(StudioForm.all.count)") })
    XCTAssertGreaterThan(StudioForm.all.count, 5)
  }
  @MainActor func testWholeTerritoryStaysChosenAcrossLayout() {
    let view = FactorySceneView()
    view.frame = CGRect(x: 0, y: 0, width: 402, height: 800)
    view.layoutIfNeeded()
    XCTAssertEqual(view.restingFrame, .quarter)
    XCTAssertLessThan(view.mapCamera.scale, view.mapCamera.overviewScale, "Opening view is the closer quarter")
    view.resetCamera()
    view.mapContentInsets = UIEdgeInsets(top: 160, left: 0, bottom: 220, right: 0)
    view.layoutIfNeeded()
    XCTAssertEqual(view.restingFrame, .territory)
    XCTAssertEqual(view.mapCamera.scale, view.mapCamera.overviewScale, accuracy: 0.001,
                   "«Вся территория» keeps both complexes after the next layout pass")
    view.setPaused(true)
  }
  // MARK: Insight board

  private func runUntil(_ sim: FactorySimulation, _ done: () -> Bool, limit: Int = 400) {
    var n = 0
    while !done() && n < limit { sim.advance(); n += 1 }
  }
  func testOpeningPriorityFollowsBlockingThenUrgencyThenLiveProcess() {
    let sim = FactorySimulation()
    XCTAssertEqual(sim.primaryFocus.id, "marea-held", "Blocking first: Marea stops trip 02")
    XCTAssertEqual(sim.primaryFocus.target, .zone(.quality))
    XCTAssertEqual(sim.primaryFocus.decision, .order(.marea))
    XCTAssertTrue(sim.startQualityCheck())
    XCTAssertEqual(sim.primaryFocus.id, "aria-late", "Then urgency with a closing window")
    XCTAssertTrue(sim.primaryFocus.reason.contains("+20 мин"), sim.primaryFocus.reason)
    XCTAssertTrue(sim.activateReserve())
    XCTAssertEqual(sim.primaryFocus.kind, .live, "No decision left: a live process, not the busiest hall")
    XCTAssertFalse(sim.focuses.contains { $0.kind == .load }, "Load is only the last fallback")
  }
  func testBoardNumbersAgreeWithTheModelAcrossTheScenario() {
    let sim = FactorySimulation()
    func check(_ stage: String) {
      let board = InsideBoard(simulation: sim)
      let m = Dictionary(uniqueKeysWithValues: board.metrics.map { ($0.id, $0) })
      XCTAssertEqual(board.portfolio, InsideOrderID.allCases.reduce(0) { $0 + $1.quantity * $1.demoUnitPrice }, stage)
      XCTAssertEqual(board.portfolio, 6_254_000, "Fixed demo orders: 3 560 000 + 768 000 + 1 110 000 + 576 000 + 240 000")
      XCTAssertEqual(m[.decisions]?.value, "\(sim.attentionCount)", stage)
      XCTAssertEqual(m[.accepted]?.value, "\(sim.completed)/68", stage)
      XCTAssertEqual(m[.production]?.value, "\(board.inProduction.reduce(0) { $0 + $1.0.quantity })", stage)
      XCTAssertEqual(m[.road]?.value, "\(InsideTrip.allCases.filter { sim.tripState($0).onRoad }.count)", stage)
      XCTAssertEqual(InsideMetricID.allCases.count, board.metrics.count, "One card per metric, no duplicates")
    }
    check("open")
    XCTAssertEqual(InsideBoard(simulation: sim).inProductionPieces, 4 + 12 + 8, "Aria, Marea, trays")
    sim.startQualityCheck(); check("quality check")
    sim.activateReserve(); check("reserve")
    runUntil(sim) { sim.quality == .loading }; check("loading")
    XCTAssertEqual(InsideBoard(simulation: sim).readyPieces, 5 + 4 + 6 + 12, "Mirrors, trip 01, Domino, Marea")
    runUntil(sim) { sim.quality == .ready }
    XCTAssertTrue(sim.releaseMareaDispatch()); check("trip 02 out")
    sim.releaseDispatch(); check("trip 01 out")
    XCTAssertEqual(InsideBoard(simulation: sim).tripsOnRoad, [.moscow, .petersburg])
    XCTAssertEqual(InsideBoard(simulation: sim).readyPieces, 5)
  }
  @MainActor private func ownerInWindow() -> (OwnerController, UIWindow) {
    let owner = OwnerController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = owner
    window.makeKeyAndVisible()
    owner.view.layoutIfNeeded()
    return (owner, window)
  }
  @MainActor func testOpensOnTheTopFocusWithoutAFlight() {
    let (owner, window) = ownerInWindow()
    XCTAssertEqual(owner.activeFocus.id, "marea-held")
    XCTAssertEqual(owner.factory.cameraMode, .event)
    XCTAssertEqual(owner.factory.mapCamera.focus.x, FactoryZone.quality.position.x, accuracy: 0.01)
    XCTAssertEqual(owner.factory.mapCamera.focus.z, FactoryZone.quality.position.z, accuracy: 0.01)
    XCTAssertTrue(owner.returnPill.isHidden)
    XCTAssertTrue(owner.board.cards[.decisions]?.isSelected == true)
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testManualExplorationSurvivesModelRevisions() {
    let (owner, window) = ownerInWindow()
    owner.factory.stepZoom(false)
    XCTAssertEqual(owner.factory.cameraMode, .manual)
    let focus = owner.factory.mapCamera.focus
    let scale = owner.factory.mapCamera.scale
    XCTAssertFalse(owner.returnPill.isHidden, "«К событию» offered while exploring")
    owner.simulation.startQualityCheck()
    for _ in 0..<40 { owner.simulation.advance() }
    owner.refresh()
    XCTAssertEqual(owner.factory.cameraMode, .manual, "No snap-back on revisions")
    XCTAssertEqual(owner.factory.mapCamera.focus.x, focus.x, accuracy: 0.001)
    XCTAssertEqual(owner.factory.mapCamera.scale, scale, accuracy: 0.001)
    XCTAssertTrue(owner.activeFocus.id.hasPrefix("marea-held"), "The chosen focus is kept, not replaced by the next one")
    XCTAssertEqual(owner.activeFocus.subject, .order(.marea))
    XCTAssertTrue(owner.activeFocus.reason.hasPrefix("Решение принято"))
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testStatTapFollowsTripsAndReturnsFromManual() {
    let (owner, window) = ownerInWindow()
    owner.choose(.road)
    XCTAssertEqual(owner.factory.cameraMode, .follow(.trip(.moscow)), "Trip 01 has a moving anchor too")
    XCTAssertFalse(owner.simulation.dispatchReleased, "A tap never releases a truck")
    owner.factory.stepZoom(true)
    XCTAssertEqual(owner.factory.cameraMode, .manual)
    owner.choose(.road)
    XCTAssertEqual(owner.factory.cameraMode, .follow(.trip(.moscow)), "Second tap returns to the event")
    XCTAssertTrue(owner.returnPill.isHidden)
    // Both trips can be followed; a departed truck rests the camera at the exit gate.
    owner.factory.follow(.trip(.petersburg), animated: false)
    XCTAssertEqual(owner.factory.cameraMode, .follow(.trip(.petersburg)))
    let docked = owner.factory.followPoint(.trip(.petersburg))
    XCTAssertGreaterThan(docked.z, 20, "Docked truck, not the gate")
    owner.factory.releaseDispatch(1, immediate: true)
    XCTAssertTrue(owner.factory.tripLeftCampus(.moscow))
    XCTAssertEqual(owner.factory.followPoint(.trip(.moscow)).z, FactorySceneView.exitGate.z, accuracy: 0.01)
    XCTAssertFalse(owner.factory.tripLeftCampus(.petersburg))
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testChosenBatchIsFollowedAlongItsOwnRoute() {
    let (owner, window) = ownerInWindow()
    let sim = owner.simulation
    XCTAssertEqual(owner.activeFocus.subject, .order(.marea))
    sim.startQualityCheck()
    runUntil(sim) { sim.quality == .packing }
    owner.refresh()
    XCTAssertEqual(owner.shownTarget, .zone(.packing), "OTK → packing with the same batch")
    XCTAssertEqual(owner.factory.cameraMode, .event)
    runUntil(sim) { sim.quality == .loading }
    owner.refresh()
    XCTAssertEqual(owner.shownTarget, .transfer, "Packing → the forklift carrying it")
    XCTAssertEqual(owner.factory.cameraMode, .follow(.transfer))
    runUntil(sim) { sim.quality == .ready }
    owner.refresh()
    XCTAssertEqual(owner.shownTarget, .trip(.petersburg), "Forklift → truck 02 at the dock")
    XCTAssertEqual(owner.activeFocus.subject, .order(.marea), "Never swapped for another order")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testManualOnlyUpdatesTextAndReturnGoesToTheCurrentPosition() {
    let (owner, window) = ownerInWindow()
    let sim = owner.simulation
    owner.factory.stepZoom(false)
    sim.startQualityCheck()
    runUntil(sim) { sim.quality == .packing }
    owner.refresh()
    XCTAssertEqual(owner.factory.cameraMode, .manual)
    XCTAssertEqual(owner.shownTarget, .zone(.quality), "Manual: the camera stays where the owner left it")
    XCTAssertEqual(owner.activeFocus.target, .zone(.packing), "…while the text already knows the batch moved")
    owner.showActiveFocus()
    XCTAssertEqual(owner.shownTarget, .zone(.packing), "«К событию» goes to where the batch is now")
    XCTAssertEqual(owner.factory.cameraMode, .event)
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testReleasedTripFromThePanelIsFollowed() throws {
    let (owner, window) = ownerInWindow()
    owner.simulation.releaseDispatch()
    owner.board.scroller.contentOffset = .zero
    owner.focusTrip(.moscow)
    XCTAssertEqual(owner.factory.cameraMode, .follow(.trip(.moscow)))
    XCTAssertEqual(owner.selectedMetric, .road)
    let card = try XCTUnwrap(owner.board.cards[.road])
    let visible = CGRect(origin: owner.board.scroller.contentOffset, size: owner.board.scroller.bounds.size)
    XCTAssertTrue(visible.contains(card.convert(card.bounds, to: owner.board.scroller)),
                  "The chosen card is brought into view")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testFocusTitleShowsTheCurrentStageOfTheSameOrder() {
    let (owner, window) = ownerInWindow()
    let sim = owner.simulation
    sim.startQualityCheck()
    runUntil(sim) { sim.quality == .packing }
    owner.refresh()
    XCTAssertEqual(owner.activeFocus.title, "Marea · упаковка", "Not «удержана ОТК» any more")
    XCTAssertTrue(owner.activeFocus.reason.hasPrefix("Решение принято"), "The decision itself was taken")
    owner.choose(.production)
    let chosen = owner.activeFocus.subject
    runUntil(sim) { sim.quality == .loading }
    owner.refresh()
    XCTAssertEqual(owner.activeFocus.subject, chosen)
    XCTAssertFalse(owner.activeFocus.reason.contains("Решение принято"), "A process, not a decision")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testMetricStripScrollsFromCardsAndKeepsItsOffsetOnUpdates() throws {
    let (owner, window) = ownerInWindow()
    let strip = owner.board.scroller
    let card = try XCTUnwrap(owner.board.cards[.portfolio])
    XCTAssertTrue(strip.canCancelContentTouches)
    XCTAssertTrue(strip.touchesShouldCancel(in: card), "A drag that starts on a card scrolls the strip")
    strip.layoutIfNeeded()
    let maxX = max(0, strip.contentSize.width - strip.bounds.width)
    XCTAssertGreaterThan(maxX, 0, "Six cards do not fit: the strip scrolls")
    strip.contentOffset.x = min(120, maxX)
    let offset = strip.contentOffset
    owner.simulation.startQualityCheck()
    owner.refresh()
    XCTAssertEqual(strip.contentOffset, offset, "Numbers update in place; scroll position stays")
    XCTAssertTrue(owner.board.cards[.decisions]?.isSelected == true, "Selection stays too")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testBoardFitsANarrowScreenWithTheLargestText() throws {
    let owner = OwnerController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    window.rootViewController = owner
    window.makeKeyAndVisible()
    owner.view.layoutIfNeeded()
    owner.view.layoutIfNeeded()
    XCTAssertLessThanOrEqual(owner.board.frame.height, window.bounds.height * 0.5 + 1, "Scene keeps half the screen")
    XCTAssertGreaterThanOrEqual(owner.board.frame.minX, 0)
    XCTAssertLessThanOrEqual(owner.board.frame.maxX, window.bounds.width)
    func find(_ id: String, in view: UIView) -> UIView? {
      view.accessibilityIdentifier == id ? view : view.subviews.lazy.compactMap { find(id, in: $0) }.first
    }
    let reason = try XCTUnwrap(find("insight.focus.reason", in: owner.board) as? UILabel)
    XCTAssertFalse(reason.isHidden)
    XCTAssertGreaterThan(reason.bounds.width, 100, "The reason takes the full width")
    let needed = reason.sizeThatFits(CGSize(width: reason.bounds.width, height: .greatestFiniteMagnitude)).height
    XCTAssertLessThanOrEqual(needed, reason.bounds.height + 1, "Reason is not clipped (the board scrolls instead)")
    let action = try XCTUnwrap(find("insight.action", in: owner.board))
    let inBoard = action.convert(action.bounds, to: owner.board)
    XCTAssertTrue(owner.board.bounds.insetBy(dx: -1, dy: -1000).contains(inBoard), "Action stays within the board width")
    // Our own views only (cards, labels, stacks, scrollers); system button internals are excluded.
    func ambiguous(_ v: UIView) -> [UIView] {
      if v is UIButton { return [] }
      let own = v is InsightMetricCard || v is UILabel || v is UIStackView || v is UIScrollView
      return (own && v.hasAmbiguousLayout ? [v] : []) + v.subviews.flatMap(ambiguous)
    }
    let unclear = ambiguous(owner.board)
    XCTAssertEqual(unclear.count, 0, "No ambiguous layout on the board: \(unclear.map { "\(type(of: $0)) \($0.accessibilityIdentifier ?? "") \($0.frame)" })")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testMapDragMovesTheCameraKeepsIsometryAndCanReturn() throws {
    let (owner, window) = ownerInWindow()
    let factory = owner.factory
    let camera = try XCTUnwrap(factory.pointOfView)
    let orientation = camera.orientation
    let start = factory.mapCamera.focus
    let pan = ScriptedPan()
    pan.scriptedState = .began
    factory.handlePan(pan)
    XCTAssertEqual(factory.cameraMode, .manual)
    pan.scriptedState = .changed
    pan.scriptedTranslation = CGPoint(x: 90, y: -60)
    factory.handlePan(pan)
    pan.scriptedState = .ended
    factory.handlePan(pan)
    let moved = factory.mapCamera.focus
    XCTAssertGreaterThan(abs(moved.x - start.x) + abs(moved.z - start.z), 1, "The drag really moves the map focus")
    // The same screen-space math as CampusCamera.pan: 90 pt right, 60 pt up.
    var expected = CampusCamera()
    expected.viewport = factory.mapCamera.viewport
    expected.scale = factory.mapCamera.scale
    expected.pan(CGPoint(x: 90, y: -60), from: start)
    XCTAssertEqual(moved.x, expected.focus.x, accuracy: 0.5)
    XCTAssertEqual(moved.z, expected.focus.z, accuracy: 0.5)
    // The camera node itself followed (model value; the presentation may still be gliding).
    XCTAssertEqual(camera.position.x - camera.position.z, moved.x - moved.z, accuracy: 3,
                   "Camera node position moved with the focus")
    XCTAssertEqual(camera.orientation.x, orientation.x, accuracy: 0.0001)
    XCTAssertEqual(camera.orientation.y, orientation.y, accuracy: 0.0001)
    XCTAssertEqual(camera.orientation.z, orientation.z, accuracy: 0.0001)
    XCTAssertEqual(camera.orientation.w, orientation.w, accuracy: 0.0001)
    // A model revision while exploring does not move it back.
    owner.simulation.startQualityCheck()
    owner.refresh()
    XCTAssertEqual(factory.mapCamera.focus.x, moved.x, accuracy: 0.001)
    XCTAssertFalse(owner.returnPill.isHidden)
    owner.showActiveFocus()
    XCTAssertEqual(factory.cameraMode, .event, "«К событию» returns")
    XCTAssertEqual(factory.mapCamera.focus.x, FactoryZone.quality.position.x, accuracy: 0.01)
    factory.setPaused(true)
    window.isHidden = true
  }
  func testMareaStagesComeFromQualityStatesWithTheModelsOwnProgress() throws {
    let sim = FactorySimulation()
    var route = try XCTUnwrap(sim.route(of: .order(.marea)))
    XCTAssertEqual(route.stages, ["ОТК", "Упаковка", "Погрузка", "Рейс 02"])
    XCTAssertEqual(route.current, 0)
    XCTAssertTrue(route.held, "Held at OTK: a block, not movement")
    XCTAssertNil(route.progress)
    XCTAssertEqual(sim.status(of: sim.primaryFocus), InsideStatus(text: "Блокирует рейс 02", tone: .amber))
    sim.startQualityCheck()
    for _ in 0..<4 { sim.advance() }
    route = try XCTUnwrap(sim.route(of: .order(.marea)))
    XCTAssertFalse(route.held)
    XCTAssertEqual(try XCTUnwrap(route.progress), Double(sim.qualityProgress), accuracy: 0.0001)
    XCTAssertGreaterThan(try XCTUnwrap(route.progress), 0)
    runUntil(sim) { sim.quality == .packing }
    XCTAssertEqual(sim.route(of: .order(.marea))?.current, 1)
    runUntil(sim) { sim.quality == .loading }
    route = try XCTUnwrap(sim.route(of: .order(.marea)))
    XCTAssertEqual(route.current, 2)
    XCTAssertEqual(try XCTUnwrap(route.progress), Double(sim.loadingProgress), accuracy: 0.0001)
    runUntil(sim) { sim.quality == .ready }
    route = try XCTUnwrap(sim.route(of: .order(.marea)))
    XCTAssertEqual(route.current, 3)
    XCTAssertNil(route.progress, "No invented trip progress")
    // Paused: the model does not move, nor does the stage progress.
    sim.paused = true
    let frozen = sim.route(of: .order(.marea))
    for _ in 0..<5 { sim.advance() }
    XCTAssertEqual(sim.route(of: .order(.marea)), frozen)
  }
  func testAriaAndTripStagesAreOnlyWhatTheModelReflects() throws {
    let sim = FactorySimulation()
    let aria = try XCTUnwrap(sim.route(of: .order(.aria)))
    XCTAssertEqual(aria.stages, ["Обработка", "ОТК"], "Only halls zone(for:) reflects — no forecast as done")
    XCTAssertEqual(aria.current, 0)
    XCTAssertNil(aria.progress)
    sim.activateReserve()
    runUntil(sim) { sim.reserve == .processing }
    XCTAssertEqual(try XCTUnwrap(sim.route(of: .order(.aria))?.progress), Double(sim.reserveProgress), accuracy: 0.0001)
    let trip = try XCTUnwrap(sim.route(of: .trip(.moscow)))
    XCTAssertEqual(trip.stages, ["Док", "В пути"], "No invented gate or delivery stages")
    XCTAssertEqual(trip.current, 0)
    sim.releaseDispatch()
    XCTAssertEqual(sim.route(of: .trip(.moscow))?.current, 1)
    XCTAssertNil(sim.route(of: .zone(.office)), "Portfolio and halls have no stage model")
    XCTAssertNil(sim.route(of: .order(.trays)))
  }
  func testOnlyAcceptedCarriesATypedProgress() {
    let sim = FactorySimulation()
    let metrics = InsideBoard(simulation: sim).metrics
    for metric in metrics {
      if metric.id == .accepted {
        XCTAssertEqual(metric.progress ?? -1, Double(sim.completed) / 68, accuracy: 0.0001)
      } else {
        XCTAssertNil(metric.progress, "\(metric.id): no progress without model data")
      }
      XCTAssertFalse(metric.icon.isEmpty)
    }
    XCTAssertEqual(metrics.first { $0.id == .decisions }?.tone, .amber)
    XCTAssertEqual(metrics.first { $0.id == .road }?.tone, .neutral, "Nothing on the road yet")
  }
  @MainActor func testBoardShowsStagesOnlyForSubjectsWithAStageModel() throws {
    let (owner, window) = ownerInWindow()
    func find(_ id: String, in view: UIView) -> UIView? {
      view.accessibilityIdentifier == id ? view : view.subviews.lazy.compactMap { find(id, in: $0) }.first
    }
    let route = try XCTUnwrap(find("insight.route", in: owner.board))
    XCTAssertFalse(route.isHidden, "Marea has stages")
    XCTAssertTrue(route.accessibilityLabel?.contains("ОТК — удержан") == true)
    XCTAssertFalse(route.accessibilityTraits.contains(.button), "Read-only, not navigation")
    let status = try XCTUnwrap(find("insight.focus.status", in: owner.board) as? UILabel)
    XCTAssertEqual(status.text, "БЛОКИРУЕТ РЕЙС 02")
    owner.choose(.portfolio)
    XCTAssertTrue(route.isHidden, "Portfolio has no stage model")
    let action = try XCTUnwrap(find("insight.action", in: owner.board))
    owner.view.layoutIfNeeded()
    XCTAssertGreaterThanOrEqual(action.bounds.height, 44, "Compact look, 44 pt hit target")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testTakenMareaDecisionShowsTheLiveStateOfTheSameOrder() throws {
    let (owner, window) = ownerInWindow()
    let sim = owner.simulation
    func find(_ id: String, in view: UIView) -> UIView? {
      view.accessibilityIdentifier == id ? view : view.subviews.lazy.compactMap { find(id, in: $0) }.first
    }
    let status = try XCTUnwrap(find("insight.focus.status", in: owner.board) as? UILabel)
    XCTAssertEqual(status.text, "БЛОКИРУЕТ РЕЙС 02")
    XCTAssertEqual(status.textColor, InsideStyle.amber)
    XCTAssertTrue(sim.startQualityCheck())
    func check(_ text: String, _ tone: InsideTone, _ stage: String) {
      owner.refresh()
      XCTAssertEqual(owner.activeFocus.subject, .order(.marea), "\(stage): the same order stays chosen")
      XCTAssertTrue(owner.activeFocus.id.hasSuffix("#taken"), "\(stage): identity keeps the taken decision")
      XCTAssertEqual(owner.activeFocus.kind, .live, stage)
      XCTAssertEqual(sim.status(of: owner.activeFocus), InsideStatus(text: text, tone: tone), stage)
      XCTAssertEqual(status.text, text.uppercased(), stage)
      XCTAssertEqual(status.textColor, tone.color, "\(stage): live colour, not a frozen neutral")
      XCTAssertNotEqual(status.text, "РЕШЕНИЕ ПРИНЯТО", stage)
      let reason = owner.activeFocus.reason
      XCTAssertTrue(reason.hasPrefix("Решение принято"), "\(stage): the decision stays a fact — \(reason)")
      XCTAssertFalse(reason.contains(text), "\(stage): the reason does not repeat the stage — \(reason)")
    }
    check("Осмотр идёт", .teal, "checking")
    runUntil(sim) { sim.quality == .packing }
    check("Упаковка", .teal, "packing")
    runUntil(sim) { sim.quality == .ready }
    check("Готов к выезду", .teal, "ready")
    XCTAssertTrue(sim.releaseMareaDispatch())
    runUntil(sim) { sim.quality == .departed }
    XCTAssertEqual(sim.quality, .departed)
    check("В пути", .cobalt, "departed")
    owner.factory.setPaused(true)
    window.isHidden = true
  }
  @MainActor func testMareaRouteFitsANarrowScreenWithoutTruncation() throws {
    for width in [320.0, 402.0] {
      let owner = OwnerController()
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 700))
      window.traitOverrides.preferredContentSizeCategory = .large
      window.rootViewController = owner
      window.makeKeyAndVisible()
      let sim = owner.simulation
      sim.startQualityCheck()
      for _ in 0..<4 { sim.advance() }
      owner.refresh()
      XCTAssertNotNil(sim.route(of: .order(.marea))?.progress, "Marea with the model's progress")
      owner.view.layoutIfNeeded()
      owner.view.layoutIfNeeded()
      func find(_ id: String, in view: UIView) -> UIView? {
        view.accessibilityIdentifier == id ? view : view.subviews.lazy.compactMap { find(id, in: $0) }.first
      }
      let route = try XCTUnwrap(find("insight.route", in: owner.board) as? InsightRouteView)
      XCTAssertFalse(route.isHidden)
      XCTAssertNotEqual(route.mode, .vertical, "\(width): normal text keeps the compact route")
      let routeInBoard = route.convert(route.bounds, to: owner.board)
      XCTAssertTrue(owner.board.bounds.insetBy(dx: -0.5, dy: -0.5).contains(routeInBoard), "\(width): route inside the board")
      var frames: [CGRect] = []
      for i in 0..<4 {
        let name = try XCTUnwrap(find("insight.route.stage.\(i)", in: route) as? UILabel)
        XCTAssertFalse(name.isHidden)
        XCTAssertGreaterThanOrEqual(name.font.pointSize, 11)
        XCTAssertEqual(name.numberOfLines, 1)
        let needed = name.intrinsicContentSize.width
        XCTAssertGreaterThanOrEqual(name.bounds.width + 0.5, needed, "\(width): «\(name.text ?? "")» is not truncated")
        let frame = name.convert(name.bounds, to: route)
        XCTAssertTrue(route.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(width): «\(name.text ?? "")» \(frame) inside \(route.bounds)")
        frames.append(frame)
      }
      for (i, a) in frames.enumerated() {
        for b in frames.dropFirst(i + 1) { XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b), "\(width): labels overlap") }
      }
      // The progress bar is under the current stage name, not beside it.
      let current = try XCTUnwrap(find("insight.route.stage.0", in: route))
      let bar = try XCTUnwrap(current.superview?.superview?.subviews.compactMap { $0.subviews.first as? UIProgressView }.first)
      let barFrame = bar.convert(bar.bounds, to: route)
      XCTAssertGreaterThanOrEqual(barFrame.minY, frames[0].maxY - 0.5, "\(width): bar below the name")
      XCTAssertEqual(barFrame.minX, frames[0].minX, accuracy: 1, "\(width): bar starts under the name")
      XCTAssertEqual(bar.alpha, 1)
      XCTAssertFalse(route.hasAmbiguousLayout)
      func ambiguous(_ v: UIView) -> [UIView] { (v.hasAmbiguousLayout ? [v] : []) + v.subviews.flatMap(ambiguous) }
      XCTAssertEqual(ambiguous(route).filter { !($0 is UIProgressView) && !($0.superview is UIProgressView) }.count, 0,
                     "\(width): no ambiguous route layout")
      owner.factory.setPaused(true)
      window.isHidden = true
    }
  }
  func testPausedScenarioKeepsTheFocus() {
    let sim = FactorySimulation()
    sim.paused = true
    let revision = sim.revision
    for _ in 0..<20 { sim.advance() }
    XCTAssertEqual(sim.primaryFocus.id, "marea-held")
    XCTAssertEqual(sim.tick, 0)
    XCTAssertGreaterThanOrEqual(sim.revision, revision)
  }
  func testCampusBuildingsDoNotOverlapAndRouteConnectsBusiness() {
    for (i, a) in FactoryZone.allCases.enumerated() {
      let ar = CGRect(
        x: CGFloat(a.position.x) - a.footprint.width / 2,
        y: CGFloat(a.position.z) - a.footprint.height / 2,
        width: a.footprint.width, height: a.footprint.height)
      for b in FactoryZone.allCases.dropFirst(i + 1) {
        let br = CGRect(
          x: CGFloat(b.position.x) - b.footprint.width / 2,
          y: CGFloat(b.position.z) - b.footprint.height / 2,
          width: b.footprint.width, height: b.footprint.height)
        XCTAssertFalse(ar.intersects(br), "\(a.title) overlaps \(b.title)")
      }
    }
    XCTAssertEqual(FactoryZone.orderRoute.first, .office)
    XCTAssertEqual(FactoryZone.orderRoute.last, .dispatch)
    XCTAssertEqual(Set(FactoryZone.orderRoute).count, FactoryZone.orderRoute.count)
  }
  @MainActor func testRenderedBuildingsRemainAlignedWithTheirLotsAfterMerging() throws {
    let view = FactorySceneView()
    let root = try XCTUnwrap(view.scene?.rootNode)
    for zone in FactoryZone.allCases {
      let building = try XCTUnwrap(root.childNodes.first { $0.name == "zone-\(zone.rawValue)" })
      let box = building.boundingBox
      let lot = CGRect(x: CGFloat(zone.position.x) - zone.footprint.width / 2,
                       y: CGFloat(zone.position.z) - zone.footprint.height / 2,
                       width: zone.footprint.width, height: zone.footprint.height).insetBy(dx: -4, dy: -4)
      for x in [box.min.x, box.max.x] {
        for y in [box.min.y, box.max.y] {
          for z in [box.min.z, box.max.z] {
            let point = building.convertPosition(SCNVector3(x, y, z), to: root)
            XCTAssertTrue(lot.contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.z))),
                          "\(zone.title): rendered geometry at \(point) escaped its lot \(lot)")
          }
        }
      }
    }
    var machinery: [SCNNode] = []
    root.enumerateChildNodes { node, _ in
      if !node.actionKeys.isEmpty { machinery.append(node) }
    }
    XCTAssertGreaterThan(machinery.count, 10, "Process equipment must retain its live nodes after merging")
    view.setPaused(true)
    XCTAssertTrue(machinery.allSatisfy(\.isPaused))
    view.setPaused(false)
    XCTAssertTrue(machinery.allSatisfy { $0.isPaused == UIAccessibility.isReduceMotionEnabled })
  }
  func testDispatchReleaseIsIdempotentAndCreatesAnEvent() {
    let simulation = FactorySimulation()
    simulation.releaseDispatch()
    let events = simulation.events
    simulation.releaseDispatch()
    XCTAssertTrue(simulation.dispatchReleased)
    XCTAssertEqual(simulation.events, events)
    XCTAssertTrue(simulation.events[0].contains("Москва"))
  }
  func testCollectionVisitRestartsRevealAndResetsAmbientCycles() {
    var state = NinfeaPlaybackState()
    state.beginVisit()
    state.update(seconds: 6)
    state.finish()
    state.completeAmbientCycle()
    state.completeAmbientCycle()
    state.update(seconds: 0)
    XCTAssertEqual(state.seconds, 6)
    XCTAssertTrue(state.finished)
    XCTAssertEqual(state.ambientCycles, 2)
    state.beginVisit()
    XCTAssertEqual(state.visit, 2)
    XCTAssertEqual(state.seconds, 0)
    XCTAssertFalse(state.finished)
    XCTAssertEqual(state.ambientCycles, 0)
    state.update(seconds: .nan)
    state.update(seconds: -1)
    XCTAssertEqual(state.seconds, 0)
  }
  func testEveryCollectionShipsMatchingSilentRevealAndLivingLoop() async throws {
    for collection in CollectionCinemaAssets.allCases {
      let intro = AVURLAsset(url: try XCTUnwrap(collection.introURL, collection.name))
      let loop = AVURLAsset(url: try XCTUnwrap(collection.loopURL, collection.name))
      let introTracks = try await intro.loadTracks(withMediaType: .video)
      let loopTracks = try await loop.loadTracks(withMediaType: .video)
      let introTrack = try XCTUnwrap(introTracks.first)
      let loopTrack = try XCTUnwrap(loopTracks.first)
      let introSize = try await introTrack.load(.naturalSize)
      let loopSize = try await loopTrack.load(.naturalSize)
      XCTAssertEqual(introSize, loopSize, "The intro/loop junction must not reframe \(collection.name)")
      let rate = try await loopTrack.load(.nominalFrameRate)
      XCTAssertGreaterThanOrEqual(rate, 24)
      let duration = try await loop.load(.duration).seconds
      // The loop's length is the release's measured frame count (8–10 s takes since 8 Oct).
      let expected = Double(collection.release.loopFrames) / Double(rate)
      XCTAssertGreaterThan(duration, 2)
      XCTAssertEqual(duration, expected, accuracy: 0.1, "\(collection.name): loop length as released")
      let audio = try await loop.loadTracks(withMediaType: .audio)
      XCTAssertTrue(audio.isEmpty)
      let generator = AVAssetImageGenerator(asset: loop)
      generator.maximumSize = CGSize(width: 128, height: 192)
      let first = try await generator.image(at: .zero)
      let middle = try await generator.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600))
      XCTAssertNotEqual(first.image.dataProvider?.data as Data?, middle.image.dataProvider?.data as Data?,
                        "The ending must retain actual motion: \(collection.name)")
    }
  }
  /// Every released reveal decodes, is silent, sharp enough for a 3× phone and actually moves.
  /// Durations and proportions come from the release itself (2:3 films of 6 Oct, 3:4 takes of 8 Oct).
  func testEveryReleasedRevealDecodesSilentlyAndMoves() async throws {
    for collection in CollectionCinemaAssets.allCases {
      let url = try XCTUnwrap(collection.introURL, "\(collection.name): the released reveal ships in the bundle")
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration)
      let tracks = try await asset.loadTracks(withMediaType: .video)
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      let track = try XCTUnwrap(tracks.first, collection.name)
      let size = try await track.load(.naturalSize)
      let rate = try await track.load(.nominalFrameRate)
      XCTAssertGreaterThanOrEqual(duration.seconds, 1.5, "\(collection.name): a reveal, not a flash")
      XCTAssertLessThan(duration.seconds, 16, collection.name)
      XCTAssertGreaterThanOrEqual(min(size.width, size.height), 720, collection.name)
      XCTAssertGreaterThanOrEqual(rate, 24, collection.name)
      XCTAssertTrue(audioTracks.isEmpty, "\(collection.name): the collection film is intentionally silent")
      let poster = try XCTUnwrap(UIImage(named: collection.release.startPoster), collection.release.startPoster)
      XCTAssertEqual(size.width / size.height, poster.size.width / poster.size.height, accuracy: 0.01,
                     "\(collection.name): the reveal keeps its poster's composition, nothing stretched")
      let generator = AVAssetImageGenerator(asset: asset)
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      generator.maximumSize = CGSize(width: 256, height: 384)
      var samples: [Data] = []
      for fraction in [0.0, 0.33, 0.66, 0.95] {
        let frame = try await generator.image(at: CMTime(seconds: duration.seconds * fraction, preferredTimescale: 600))
        let data = try XCTUnwrap(frame.image.dataProvider?.data, collection.name) as Data
        samples.append(data)
      }
      for index in 1..<samples.count {
        XCTAssertNotEqual(samples[index - 1], samples[index], "\(collection.name): the reveal moves")
      }
    }
  }
  @MainActor func testNinfeaAmbientLifecycleAndNoPlayerControls() throws {
    XCTAssertNotNil(UIImage(named: NinfeaCinemaAssets.posterName))
    XCTAssertNotNil(UIImage(named: "ninfea-official.webp"))
    XCTAssertNil(Bundle.main.url(forResource: "ninfea-film-v2", withExtension: "mp4"))
    XCTAssertEqual(CollectionGallery.stories.first?.id, "ninfea")
    let cinema = NinfeaCinemaView()
    cinema.active = true
    XCTAssertEqual(cinema.playback.visit, 1)
    cinema.active = true
    XCTAssertEqual(cinema.playback.visit, 1, "Visibility updates must not restart an active scene")
    cinema.active = false
    cinema.active = true
    XCTAssertEqual(cinema.playback.visit, 2)
    XCTAssertEqual(cinema.playback.seconds, 0)
    XCTAssertFalse(cinema.isPlaying, "A detached view must not play")
    let gallery = CollectionGallery { _ in }
    func descendants(_ view: UIView) -> [UIView] {
      view.subviews.flatMap { [$0] + descendants($0) }
    }
    let children = descendants(gallery)
    XCTAssertFalse(children.contains { $0 is UISlider || $0 is UIProgressView })
    let buttons = children.compactMap { $0 as? UIButton }
    XCTAssertFalse(buttons.contains { $0.accessibilityIdentifier?.contains("ninfea.play") == true })
    XCTAssertTrue(buttons.contains { $0.accessibilityLabel == "О коллекции Ninfea" })
    let info = NinfeaInformationController()
    info.loadViewIfNeeded()
  }
  /// Actual reveal and loop durations of a collection's release (seconds), loaded before any assertion.
  static func cinemaDurations(_ collection: CollectionCinemaAssets) async throws -> (intro: Double, loop: Double) {
    let introURL = try XCTUnwrap(collection.introURL)
    let loopURL = try XCTUnwrap(collection.loopURL)
    let intro = try await AVURLAsset(url: introURL).load(.duration).seconds
    let loop = try await AVURLAsset(url: loopURL).load(.duration).seconds
    return (intro, loop)
  }
  @MainActor func testVisibleCollectionAdvancesIntoLoopAndReleasesOffscreen() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKey = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    let cinema = NinfeaCinemaView(collection: .greca)
    window.rootViewController?.view.pin(cinema)
    window.makeKeyAndVisible()
    defer {
      cinema.active = false
      window.isHidden = true
      previousKey?.makeKey()
    }
    // The reveal plus one full loop, with headroom for decoder start-up — from the shipped files.
    let durations = try await Self.cinemaDurations(.greca)
    cinema.active = true
    let deadline = Date().addingTimeInterval(durations.intro + durations.loop + 6)
    while cinema.playback.ambientCycles == 0 && Date() < deadline {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(cinema.playback.finished, "The reveal must hand off to the queued ending")
    XCTAssertGreaterThan(cinema.playback.ambientCycles, 0, "The ending must actually repeat")
    XCTAssertTrue(cinema.isPlaying)
    cinema.active = false
    XCTAssertFalse(cinema.isPlaying)
    cinema.active = true
    XCTAssertEqual(cinema.playback.visit, 2)
    XCTAssertEqual(cinema.playback.ambientCycles, 0)
    XCTAssertFalse(cinema.playback.finished)
  }
  /// Every released collection: reveal, then three complete loop cycles with no pause at the
  /// handoff or a loop boundary and no playhead stall longer than 0.4 s. Deadlines and the
  /// observed share come from each release's actual durations (8–10 s loops since build 9).
  @MainActor func testEveryCollectionRunsThreeFullCyclesWithoutStalling() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKey = scene.windows.first(where: \.isKeyWindow)
    defer { previousKey?.makeKey() }
    for collection in CollectionCinemaAssets.allCases {
      let durations = try await Self.cinemaDurations(collection)
      let window = UIWindow(windowScene: scene)
      window.rootViewController = UIViewController()
      let cinema = NinfeaCinemaView(collection: collection)
      window.rootViewController?.view.pin(cinema)
      window.makeKeyAndVisible()
      cinema.active = true
      var loopSamples = 0
      var pausedSamples = 0
      var stalledRun = 0
      var longestStall = 0
      var previousPlayhead = Double.nan
      let deadline = Date().addingTimeInterval((durations.intro + 3 * durations.loop) * 1.5 + 6)
      while cinema.playback.ambientCycles < 3 && Date() < deadline {
        try await Task.sleep(nanoseconds: 100_000_000)
        guard cinema.playback.finished else { continue }
        loopSamples += 1
        if !cinema.isPlaying { pausedSamples += 1 }
        let playhead = cinema.playheadSeconds
        if playhead == previousPlayhead {
          stalledRun += 1
          longestStall = max(longestStall, stalledRun)
        } else {
          stalledRun = 0
        }
        previousPlayhead = playhead
      }
      let cycles = cinema.playback.ambientCycles
      let playing = cinema.isPlaying
      cinema.active = false
      window.isHidden = true
      XCTAssertGreaterThanOrEqual(cycles, 3, "\(collection.name): three full loop cycles must complete")
      XCTAssertGreaterThan(loopSamples, Int(3 * durations.loop * 10 * 0.625),
                           "\(collection.name): most of three \(String(format: "%.1f", durations.loop)) s cycles observed")
      XCTAssertEqual(pausedSamples, 0, "\(collection.name): the living ending paused during \(pausedSamples) samples")
      XCTAssertLessThanOrEqual(longestStall, 4, "\(collection.name): playhead stood still for \(longestStall * 100) ms")
      XCTAssertTrue(playing, "\(collection.name): still playing after three cycles")
    }
  }
  /// The ending must keep running through three complete loop cycles: the player never
  /// pauses at the reveal handoff or at a loop boundary, and the playhead never stalls.
  @MainActor func testLivingLoopRunsThreeFullCyclesWithoutStalling() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKey = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    // Greca has the shortest reveal; deadlines and sample counts follow its actual durations.
    let cinema = NinfeaCinemaView(collection: .greca)
    let durations = try await Self.cinemaDurations(.greca)
    window.rootViewController?.view.pin(cinema)
    window.makeKeyAndVisible()
    defer {
      cinema.active = false
      window.isHidden = true
      previousKey?.makeKey()
    }
    cinema.active = true
    var loopSamples = 0
    var pausedSamples = 0
    var stalledRun = 0
    var longestStall = 0
    var previousPlayhead = Double.nan
    // Reveal + three cycles at 1.5× real time, plus decoder start-up.
    let deadline = Date().addingTimeInterval((durations.intro + 3 * durations.loop) * 1.5 + 6)
    while cinema.playback.ambientCycles < 3 && Date() < deadline {
      try await Task.sleep(nanoseconds: 100_000_000)
      guard cinema.playback.finished else { continue }
      loopSamples += 1
      if !cinema.isPlaying { pausedSamples += 1 }
      let playhead = cinema.playheadSeconds
      if playhead == previousPlayhead {
        stalledRun += 1
        longestStall = max(longestStall, stalledRun)
      } else {
        stalledRun = 0
      }
      previousPlayhead = playhead
    }
    XCTAssertGreaterThanOrEqual(cinema.playback.ambientCycles, 3, "Three full loop cycles must complete")
    // Sampled every 0.1 s: most of the three cycles must have been observed (the same 62.5 %
    // share the 4 s loops were held to: 75 of 120 samples).
    let expectedSamples = Int(3 * durations.loop * 10 * 0.625)
    XCTAssertGreaterThan(loopSamples, expectedSamples,
                         "Most of three \(String(format: "%.1f", durations.loop)) s cycles must have been observed")
    XCTAssertEqual(pausedSamples, 0, "The living ending paused during \(pausedSamples) samples")
    XCTAssertLessThanOrEqual(longestStall, 4,
                             "The playhead stood still for \(longestStall * 100) ms inside the loop")
    XCTAssertTrue(cinema.isPlaying)
    // A system interruption is not a new page visit. Preserve the living ending
    // instead of replaying the entire growth sequence when the app becomes active.
    let visitBeforeInterruption = cinema.playback.visit
    let cyclesBeforeInterruption = cinema.playback.ambientCycles
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertFalse(cinema.isPlaying)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(cinema.playback.visit, visitBeforeInterruption)
    XCTAssertTrue(cinema.playback.finished)
    XCTAssertGreaterThanOrEqual(cinema.playback.ambientCycles, cyclesBeforeInterruption)
    XCTAssertTrue(cinema.isPlaying)
  }
}
