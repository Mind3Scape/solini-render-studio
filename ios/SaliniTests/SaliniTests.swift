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
  @MainActor func testAllMainScreensLoadWithBundledImages() {
    let screens: [UIViewController] =
      [
        HomeController(), CatalogController(), ProjectsController(), ProfileController(),
        OwnerController(), MaterialsController(), InspirationController(),
      ] + Product.all.map { ProductController($0) }
    for screen in screens {
      screen.loadViewIfNeeded()
      XCTAssertNotNil(screen.view)
    }
    for product in Product.all { XCTAssertNotNil(UIImage(named: product.image + ".jpg")) }
  }
}
