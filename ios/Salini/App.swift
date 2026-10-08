import UIKit

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication, configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    UISceneConfiguration(name: "Default", sessionRole: session.role)
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    if ProcessInfo.processInfo.arguments.contains("-reset-demo") { DemoStore.shared.reset() }
    let window = UIWindow(windowScene: scene)
    window.tintColor = Palette.ink
    window.overrideUserInterfaceStyle = .light
    self.window = window
    setRoot(MainTabs(), animated: false)
    window.makeKeyAndVisible()
    // QA: open the shipping-section proof directly (projects and settings are untouched).
    if ProcessInfo.processInfo.arguments.contains("-shipping-atelier") {
      (window.rootViewController as? MainTabs)?.openShippingAtelier()
    }
  }
  func showWelcome(animated: Bool = true) { setRoot(MainTabs(), animated: animated) }
  func enter(_ role: Audience) {
    DemoStore.shared.role = role
    setRoot(MainTabs(), animated: true)
  }
  private func setRoot(_ controller: UIViewController, animated: Bool) {
    guard let window else { return }
    if animated {
      UIView.transition(with: window, duration: 0.45, options: .transitionCrossDissolve) {
        window.rootViewController = controller
      }
    } else {
      window.rootViewController = controller
    }
  }
}

enum Audience: String, CaseIterable, Codable {
  case home, atelier, partner
  var title: String {
    switch self {
    case .home: return "Покупатель"
    case .atelier: return "Дизайнер"
    case .partner: return "Партнёр"
    }
  }
  var detail: String {
    switch self {
    case .home: return "Подбор изделий для вашего интерьера"
    case .atelier: return "Проекты, материалы и спецификации"
    case .partner: return "Коллекции и комплектация салона"
    }
  }
  var icon: String {
    switch self {
    case .home: return "house"
    case .atelier: return "pencil.and.outline"
    case .partner: return "building.2"
    }
  }
  var caption: String {
    switch self {
    case .home: return "ДЛЯ СЕБЯ"
    case .atelier: return "ДИЗАЙНЕРАМ И АРХИТЕКТОРАМ"
    case .partner: return "ПАРТНЁРАМ SALINI"
    }
  }
}

struct Product: Codable, Equatable {
  let id: String
  let name: String
  let category: String
  let subtitle: String
  let dimensions: String
  let image: String
  let price: Int
  let stonePrice: Int?
  let article: String
  let stoneArticle: String?
  let story: String
  let source: String
  var canConfigure: Bool { stonePrice != nil }
  func price(stone: Bool) -> Int { stone ? (stonePrice ?? price) : price }
  func sku(stone: Bool) -> String { stone ? (stoneArticle ?? article) : article }
  static let all: [Product] = {
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let products = try? JSONDecoder().decode([Product].self, from: data)
    else { return [] }
    return products
  }()
}

struct ProjectItem: Codable, Equatable, Identifiable {
  var id = UUID().uuidString
  let productId: String
  let stone: Bool
  var quantity: Int = 1
  var product: Product? { Product.all.first { $0.id == productId } }
  var total: Int { (product?.price(stone: stone) ?? 0) * quantity }
}

/// Role and favourites. Projects live in ProjectStore; the prototype's project keys are migrated there.
final class DemoStore {
  static let shared = DemoStore()
  private let defaults: UserDefaults
  var role: Audience { didSet { defaults.set(role.rawValue, forKey: "salini.role") } }
  /// Catalogue product ids. Prototype ids («aria», «greca»…) are mapped on load.
  var favorites: Set<String> { didSet { save() } }
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    role = Audience(rawValue: defaults.string(forKey: "salini.role") ?? "home") ?? .home
    favorites = Set((defaults.stringArray(forKey: "salini.favorites") ?? []).map { Catalog.legacyIds[$0] ?? $0 })
  }
  private func save() {
    defaults.set(Array(favorites), forKey: "salini.favorites")
    NotificationCenter.default.post(name: .demoChanged, object: nil)
  }
  /// Prototype entry points (stories, 3D viewer, comparison) add the matching catalogue execution.
  func add(_ product: Product, stone: Bool) {
    guard let match = Catalog.shared.product(for: product, stone: stone) else { return }
    ProjectStore.shared.add(match.0, variantKey: match.1?.key)
  }
  func toggle(_ id: String) {
    if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
  }
  func reset() {
    favorites = []
    role = .home
    ProjectStore.shared.reset()
  }
}
extension Notification.Name { static let demoChanged = Notification.Name("salini.demoChanged") }
func rubles(_ value: Int) -> String {
  let f = NumberFormatter()
  f.numberStyle = .decimal
  // Non-breaking spaces: «790 000 ₽» never wraps into a lone «₽» or a split number.
  f.groupingSeparator = "\u{00A0}"
  return (f.string(from: NSNumber(value: value)) ?? "\(value)") + "\u{00A0}₽"
}

func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
  let n = abs(count)
  if (11...14).contains(n % 100) { return many }
  if n % 10 == 1 { return one }
  if (2...4).contains(n % 10) { return few }
  return many
}

final class MainTabs: UITabBarController {
  /// Shared positions: every role has the catalogue and a project; role tools follow.
  static let catalogTabIndex = 1
  static let projectTabIndex = 2
  static let toolTabIndex = 3
  private let home = UINavigationController(rootViewController: HomeController())
  private let profile = UINavigationController(rootViewController: ProfileController())
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    tabBar.tintColor = Palette.ink
    if #available(iOS 26.0, *) { tabBarMinimizeBehavior = .onScrollDown }
    applyAudience()
  }
  /// Profile → Salini Inside → «Участок отгрузки», without animation (QA launch argument).
  func openShippingAtelier() {
    loadViewIfNeeded()
    selectedViewController = profile
    let owner = OwnerController()
    owner.hidesBottomBarWhenPushed = true
    profile.setViewControllers([profile.viewControllers.first ?? ProfileController(), owner], animated: false)
    owner.loadViewIfNeeded()
    owner.openAtelier(animated: false)
  }
  func applyAudience() {
    let role = DemoStore.shared.role
    // Glyphs: the official Salini wordmark for the home tab and the «Soft» pack for the rest —
    // vector template assets from tools/export_brand_assets.swift (provenance in ios/design/icons).
    var list: [(UINavigationController, String, String, String)] = [
      (home, "Главная", "TabSalini", "Salini, главная"),
      (UINavigationController(rootViewController: CatalogController()), "Каталог", "TabCatalog", "Каталог"),
      (
        UINavigationController(rootViewController: ProjectsController()),
        role == .atelier ? "Проекты" : "Проект", "TabProject", role == .atelier ? "Проекты" : "Проект"
      ),
    ]
    // Designer library and partner stock/reserve tools stay as their own tabs.
    switch role {
    case .atelier:
      list.append((UINavigationController(rootViewController: ResourcesController()), "Библиотека", "TabLibrary", "Библиотека"))
    case .partner:
      list.append((UINavigationController(rootViewController: StockController()), "Наличие", "TabStock", "Наличие"))
    case .home: break
    }
    list.append((profile, "Профиль", "TabProfile", "Профиль"))
    viewControllers = list.map { nav, title, glyph, spoken in
      let image = UIImage(named: glyph)?.withRenderingMode(.alwaysTemplate)
      nav.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: image)
      nav.tabBarItem.accessibilityLabel = spoken
      nav.tabBarItem.accessibilityIdentifier = "tab.\(glyph)"
      nav.navigationBar.prefersLargeTitles = false
      nav.navigationBar.tintColor = Palette.ink
      return nav
    }
    selectedIndex = 0
  }
}
