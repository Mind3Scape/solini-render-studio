import XCTest
import UIKit
@testable import Salini

@MainActor
final class HomeEditorialTests: XCTestCase {
  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }
  private func find(_ identifier: String, in view: UIView) -> UIView? {
    descendants(view).first { $0.accessibilityIdentifier == identifier }
  }

  func testCategoriesAndCollectionsOpenRealCatalogueResults() throws {
    for category in HomeEditorialContent.categories {
      let product = try XCTUnwrap(category.product)
      XCTAssertEqual(product.category, category.title, "The category photograph must depict that category")
      let imageURL = try XCTUnwrap(product.imageURL)
      XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
      let controller = HomeEditorialContent.catalog(category: category.title)
      controller.loadViewIfNeeded()
      XCTAssertFalse(controller.hits.isEmpty, category.title)
      XCTAssertTrue(controller.hits.allSatisfy { $0.product.category == category.title })
    }
    for collection in HomeEditorialContent.collections {
      let controller = HomeEditorialContent.catalog(query: collection.query)
      controller.loadViewIfNeeded()
      XCTAssertEqual(controller.navigationItem.searchController?.searchBar.text, collection.query)
      XCTAssertFalse(controller.hits.isEmpty, collection.name)
      let expected = Catalog.shared.search(collection.query)
      XCTAssertEqual(controller.hits.map(\.product.id), expected.map(\.product.id))
      XCTAssertTrue(controller.hits.contains { $0.product.category == "Ванны" })
      XCTAssertTrue(controller.hits.contains { $0.product.category == "Раковины" })
      XCTAssertNotNil(UIImage(named: collection.image + ".jpg"))
      // A preset must remain an ordinary editable search, including its no-results state.
      let search = try XCTUnwrap(controller.navigationItem.searchController)
      search.searchBar.text = "no-such-salini-product"
      controller.updateSearchResults(for: search)
      XCTAssertTrue(controller.hits.isEmpty)
    }
  }

  func testHomeRoutesAndKeepsGalleryMaterialAndScrollOnReturn() throws {
    let previousRole = DemoStore.shared.role
    DemoStore.shared.role = .home
    let home = HomeController()
    let navigation = ImmediateHomeNavigation(rootViewController: home)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    defer { window.isHidden = true; DemoStore.shared.role = previousRole }
    navigation.view.layoutIfNeeded()
    home.view.layoutIfNeeded()
    let gallery = try XCTUnwrap(find("home.gallery", in: home.view) as? CollectionGallery)
    let material = try XCTUnwrap(find("material.feature", in: home.view) as? EssenceFeatureView)
    gallery.select(2, animated: false)
    material.select(.senseMatte, animated: false)
    home.scroll.contentOffset.y = 720
    let offset = home.scroll.contentOffset
    let brand = try XCTUnwrap(find("home.story.brand", in: home.view) as? UIButton)
    UIView.performWithoutAnimation { brand.sendActions(for: .touchUpInside) }
    XCTAssertTrue(navigation.topViewController is HomeStoryController)
    navigation.popViewController(animated: false)
    XCTAssertTrue(find("home.gallery", in: home.view) === gallery, "Returning must not replay/recreate the films")
    XCTAssertTrue(find("material.feature", in: home.view) === material)
    XCTAssertEqual(gallery.selectedIndex, 2)
    XCTAssertEqual(material.finish, .senseMatte)
    XCTAssertEqual(home.scroll.contentOffset.y, offset.y, accuracy: 1)

    let category = HomeEditorialContent.categories[2]
    let categoryButton = try XCTUnwrap(find("home.category.\(category.productID)", in: home.view) as? UIButton)
    UIView.performWithoutAnimation { categoryButton.sendActions(for: .touchUpInside) }
    let catalog = try XCTUnwrap(navigation.topViewController as? CatalogController)
    catalog.loadViewIfNeeded()
    catalog.beginAppearanceTransition(true, animated: false)
    catalog.endAppearanceTransition()
    XCTAssertFalse(navigation.isNavigationBarHidden, "Catalogue search and back navigation must be available from the home")
    XCTAssertEqual(catalog.filter.category, category.title)
    XCTAssertFalse(catalog.hits.isEmpty)
  }

  func testEditorialRailsAndControlsFitACompactPhoneAtLargeText() throws {
    let previousRole = DemoStore.shared.role
    DemoStore.shared.role = .home
    defer { DemoStore.shared.role = previousRole }
    let home = HomeController()
    let navigation = ImmediateHomeNavigation(rootViewController: home)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    home.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    navigation.view.layoutIfNeeded()
    home.view.layoutIfNeeded()
    let rails = descendants(home.view).compactMap { $0 as? HomeEditorialRail }
    XCTAssertEqual(rails.count, 2)
    for rail in rails {
      XCTAssertGreaterThan(rail.bounds.height, 140, "A rail must get a content-driven height")
      XCTAssertEqual(rail.contentSize.height, rail.bounds.height, accuracy: 1, "No vertical scrolling/clipping inside a horizontal rail")
      for caption in descendants(rail).compactMap({ $0 as? UILabel }) {
        let required = caption.sizeThatFits(CGSize(width: caption.bounds.width, height: .greatestFiniteMagnitude))
        XCTAssertGreaterThanOrEqual(caption.bounds.height + 1, required.height, caption.text ?? "")
      }
    }
    for identifier in ["home.colour.studio", "home.story.brand", "home.story.interior", "home.help", "home.showrooms"] {
      let control = try XCTUnwrap(find(identifier, in: home.view), identifier)
      XCTAssertGreaterThanOrEqual(control.bounds.height, 44)
      XCTAssertLessThanOrEqual(control.bounds.width, home.view.bounds.width)
    }
    XCTAssertLessThanOrEqual(home.scroll.contentSize.width, home.scroll.bounds.width + 1)
    for identifier in ["home.choose", "home.compare"] {
      let button = try XCTUnwrap(find(identifier, in: home.view) as? UIButton)
      let title = try XCTUnwrap(button.titleLabel)
      XCTAssertLessThanOrEqual(title.bounds.height, title.font.lineHeight + 1,
                               "A short action must fit without splitting a word on compact phones")
    }
  }

  func testAmbientPhotographyNeverExposesAnEdge() {
    for bounds in [CGRect(x: 0, y: 0, width: 145, height: 122), CGRect(x: 0, y: 0, width: 343, height: 415)] {
      for source in [CGSize(width: 1450, height: 816), CGSize(width: 1450, height: 1813)] {
        for focus: CGFloat in [0, 0.35, 0.67, 1] {
          let frame = HomeAmbientPhoto.imageFrame(size: source, in: bounds, focus: focus)
          for second in stride(from: 0.0, through: 180.0, by: 0.5) {
            let point = HomeAmbientPhoto.displacement(at: second)
            XCTAssertLessThanOrEqual(hypot(point.x, point.y), 6)
            XCTAssertTrue(frame.offsetBy(dx: point.x, dy: point.y).contains(bounds), "Movement may never uncover the card background")
          }
        }
      }
    }
  }

  func testAmbientPlaybackPausesWithoutRestartingItsPhase() throws {
    try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "System Reduce Motion disables automatic motion")
    let photo = HomeAmbientPhoto("luce")
    photo.frame = CGRect(x: 0, y: 0, width: 300, height: 250)
    let controller = UIViewController()
    controller.view.addSubview(photo)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { photo.active = false; window.isHidden = true }
    photo.active = true
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    photo.advance(by: 0.05)
    XCTAssertTrue(photo.isPlaying)
    XCTAssertGreaterThan(photo.elapsed, 0)
    let started = photo.elapsed
    photo.active = true
    XCTAssertEqual(photo.elapsed, started, "Repeated visibility updates don't reset the phase")
    photo.active = false
    let paused = photo.elapsed
    photo.advance(by: 0.05)
    XCTAssertFalse(photo.isPlaying)
    XCTAssertEqual(photo.elapsed, paused)
    photo.active = true
    XCTAssertEqual(photo.elapsed, paused, "Resuming starts at the retained position")
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertFalse(photo.isPlaying)
    XCTAssertEqual(photo.elapsed, paused)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertTrue(photo.isPlaying)
    photo.removeFromSuperview()
    XCTAssertFalse(photo.isPlaying)
  }
}

/// Navigation routing/state tests are synchronous; UIKit's animated transition completion is
/// tested interactively, not guessed with a fixed delay while unrelated suites run.
private final class ImmediateHomeNavigation: UINavigationController {
  override func pushViewController(_ viewController: UIViewController, animated: Bool) {
    super.pushViewController(viewController, animated: false)
  }
  override func popViewController(animated: Bool) -> UIViewController? {
    super.popViewController(animated: false)
  }
}
