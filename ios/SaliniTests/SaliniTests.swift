import SceneKit
import XCTest

@testable import Salini

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
  func testProjectsPreserveDistinctConfigurationsAndPersist() throws {
    let name = "Salini.tests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = DemoStore(defaults: defaults)
    let aria = try XCTUnwrap(Product.all.first { $0.id == "aria" })
    store.add(aria, stone: false)
    store.add(aria, stone: true)
    store.add(aria, stone: true)
    XCTAssertEqual(store.items.count, 2)
    XCTAssertEqual(store.total, 790000 + 890000 * 2)
    store.projectName = "Вилла"
    store.role = .partner
    store.toggle(aria)
    let restored = DemoStore(defaults: defaults)
    XCTAssertEqual(restored.items, store.items)
    XCTAssertEqual(restored.projectName, "Вилла")
    XCTAssertEqual(restored.role, .partner)
    XCTAssertTrue(restored.favorites.contains("aria"))
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
    DemoStore.shared.role = .home
    tabs.applyAudience()
    XCTAssertTrue(
      (tabs.viewControllers?[1] as? UINavigationController)?.viewControllers.first
        is CatalogController)
    DemoStore.shared.role = .atelier
    tabs.applyAudience()
    XCTAssertTrue(
      (tabs.viewControllers?[1] as? UINavigationController)?.viewControllers.first
        is ResourcesController)
    DemoStore.shared.role = .partner
    tabs.applyAudience()
    XCTAssertTrue(
      (tabs.viewControllers?[1] as? UINavigationController)?.viewControllers.first
        is StockController)
    XCTAssertTrue(
      (tabs.viewControllers?[2] as? UINavigationController)?.viewControllers.first
        is PartnerOrdersController)
  }
  @MainActor func testAllMainScreensLoadWithBundledImages() {
    let screens: [UIViewController] =
      [
        HomeController(), CatalogController(), ProjectsController(), ProfileController(),
        OwnerController(), MaterialsController(), InspirationController(),
        ResourcesController(), FinderController(), CompareController(), StockController(),
        PartnerOrdersController(),
      ] + Product.all.map { ProductController($0) }
    for screen in screens {
      screen.loadViewIfNeeded()
      XCTAssertNotNil(screen.view)
    }
    for product in Product.all { XCTAssertNotNil(UIImage(named: product.image + ".jpg")) }
    XCTAssertNotNil(Bundle.main.url(forResource: "Greca", withExtension: "usdz"))
  }
  @MainActor func testMaterialStudioSelectionOpensMatchingAriaPriceAndArticle() throws {
    let aria = try XCTUnwrap(Product.all.first { $0.id == "aria" })
    func texts(_ view: UIView) -> [String] {
      ([(view as? UILabel)?.text].compactMap { $0 }) + view.subviews.flatMap(texts)
    }
    let stone = ProductController(aria, stone: true)
    stone.loadViewIfNeeded()
    XCTAssertTrue(texts(stone.view).contains(rubles(890000)))
    XCTAssertTrue(texts(stone.view).contains { $0.contains("1051201M") })
    let sense = ProductController(aria, stone: false)
    sense.loadViewIfNeeded()
    XCTAssertTrue(texts(sense.view).contains(rubles(790000)))
    XCTAssertTrue(texts(sense.view).contains { $0.contains("1051101G") })
  }
}
