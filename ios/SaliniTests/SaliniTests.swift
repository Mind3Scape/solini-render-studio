import AVFoundation
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
  func testCampusCameraBoundsZoomAndViewportFit() {
    var camera = CampusCamera()
    camera.viewport = CGSize(width: 402, height: 550)
    camera.overview()
    let width = 2 * camera.scale * Double(camera.viewport.width / camera.viewport.height)
    XCTAssertGreaterThan(width, (146 + 108) / sqrt(2.0))
    camera.pan(CGPoint(x: 100_000, y: -100_000), from: camera.focus)
    XCTAssertTrue((-58...70).contains(camera.focus.x))
    XCTAssertTrue((-45...49).contains(camera.focus.z))
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
  func testDispatchReleaseIsIdempotentAndCreatesAnEvent() {
    let simulation = FactorySimulation()
    simulation.releaseDispatch()
    let events = simulation.events
    simulation.releaseDispatch()
    XCTAssertTrue(simulation.dispatchReleased)
    XCTAssertEqual(simulation.events, events)
    XCTAssertTrue(simulation.events[0].contains("Москва"))
  }
  func testNinfeaClockHoldsTheGardenAndBoundsSeeking() {
    var film = NinfeaTimeline()
    for index in NinfeaTimeline.chapterTimes.indices {
      film.seek(NinfeaTimeline.chapterTimes[index] / NinfeaTimeline.duration)
      XCTAssertEqual(film.chapter, index)
    }
    film.seek(0.99)
    film.advance(2)
    XCTAssertEqual(film.seconds, 30)
    XCTAssertTrue(film.ended)
    film.advance(0.1)
    XCTAssertEqual(film.seconds, 30)
    film.seek(-2)
    XCTAssertEqual(film.seconds, 0)
    film.seek(.nan)
    film.advance(.infinity)
    XCTAssertEqual(film.seconds, 0)
    film.seek(5)
    XCTAssertTrue(film.ended)
  }
  func testBundledNinfeaMovieHasActualDecodableIntermediateFrames() async throws {
    let url = try XCTUnwrap(NinfeaCinemaAssets.filmURL)
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, NinfeaTimeline.duration, accuracy: 0.04)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let size = try await track.load(.naturalSize)
    let rate = try await track.load(.nominalFrameRate)
    XCTAssertEqual(size, CGSize(width: 1024, height: 1536))
    XCTAssertEqual(rate, 30, accuracy: 0.01)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var samples: [Data] = []
    for seconds in [4.0, 7.0, 21.0, 24.0, 29.9] {
      let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
      XCTAssertEqual(frame.image.width, 1024)
      XCTAssertEqual(frame.image.height, 1536)
      samples.append(try XCTUnwrap(frame.image.dataProvider?.data) as Data)
    }
    XCTAssertNotEqual(samples[0], samples[1], "Water filling must have distinct decoded frames")
    XCTAssertNotEqual(samples[2], samples[3], "Vine growth must continue within the garden chapter")
    XCTAssertNotEqual(samples[3], samples[4])
  }
  @MainActor func testNinfeaNativePlaybackAndPresentationState() throws {
    XCTAssertNotNil(UIImage(named: NinfeaCinemaAssets.posterName))
    XCTAssertNotNil(UIImage(named: "ninfea-official.webp"))
    XCTAssertEqual(CollectionGallery.stories.first?.id, "ninfea")
    let cinema = NinfeaCinemaView()
    cinema.seek(0.5)
    XCTAssertTrue(cinema.userPaused)
    XCTAssertFalse(cinema.isPlaying)
    cinema.chapter(2)
    XCTAssertEqual(cinema.timeline.chapter, 2)
    cinema.replay()
    XCTAssertFalse(cinema.userPaused)
    XCTAssertEqual(cinema.timeline.seconds, 0)
    // A detached/recycled hero must never keep its video playing.
    cinema.active = true
    XCTAssertFalse(cinema.isPlaying)
    let gallery = CollectionGallery(progress: 0.42, paused: true) { _ in }
    XCTAssertEqual(gallery.cinemaProgress, 0.42, accuracy: 0.0001)
    XCTAssertTrue(gallery.cinemaPaused)
    gallery.restoreCinema(progress: 0.7, paused: false)
    XCTAssertEqual(gallery.cinemaProgress, 0.7, accuracy: 0.0001)
    XCTAssertFalse(gallery.cinemaPaused)
    let fullScreen = NinfeaStoryController()
    fullScreen.loadViewIfNeeded()
    let info = NinfeaInformationController()
    info.loadViewIfNeeded()
  }
}
