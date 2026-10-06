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

final class DemoStore {
  static let shared = DemoStore()
  private let defaults: UserDefaults
  var role: Audience { didSet { defaults.set(role.rawValue, forKey: "salini.role") } }
  var items: [ProjectItem] { didSet { save() } }
  var favorites: Set<String> { didSet { save() } }
  var projectName: String { didSet { save() } }
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    role = Audience(rawValue: defaults.string(forKey: "salini.role") ?? "home") ?? .home
    items =
      (defaults.data(forKey: "salini.items").flatMap {
        try? JSONDecoder().decode([ProjectItem].self, from: $0)
      }) ?? []
    favorites = Set(defaults.stringArray(forKey: "salini.favorites") ?? [])
    projectName = defaults.string(forKey: "salini.projectName") ?? "Моё пространство"
  }
  private func save() {
    defaults.set(try? JSONEncoder().encode(items), forKey: "salini.items")
    defaults.set(Array(favorites), forKey: "salini.favorites")
    defaults.set(projectName, forKey: "salini.projectName")
    NotificationCenter.default.post(name: .demoChanged, object: nil)
  }
  func add(_ product: Product, stone: Bool) {
    if let i = items.firstIndex(where: { $0.productId == product.id && $0.stone == stone }) {
      items[i].quantity += 1
    } else {
      items.append(ProjectItem(productId: product.id, stone: stone))
    }
  }
  func toggle(_ product: Product) {
    if favorites.contains(product.id) {
      favorites.remove(product.id)
    } else {
      favorites.insert(product.id)
    }
  }
  var total: Int { items.reduce(0) { $0 + $1.total } }
  func reset() {
    items = []
    favorites = []
    projectName = "Моё пространство"
    role = .home
  }
}
extension Notification.Name { static let demoChanged = Notification.Name("salini.demoChanged") }
func rubles(_ value: Int) -> String {
  let f = NumberFormatter()
  f.numberStyle = .decimal
  f.groupingSeparator = " "
  return (f.string(from: NSNumber(value: value)) ?? "\(value)") + " ₽"
}

func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
  let n = abs(count)
  if (11...14).contains(n % 100) { return many }
  if n % 10 == 1 { return one }
  if (2...4).contains(n % 10) { return few }
  return many
}

final class MainTabs: UITabBarController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    let list: [(UIViewController, String, String)] = [
      (HomeController(), "Мир Salini", "sparkles"),
      (CatalogController(), "Коллекции", "square.grid.2x2"),
      (ProjectsController(), "Проекты", "square.stack.3d.up"),
      (ProfileController(), "Профиль", "person.crop.circle"),
    ]
    viewControllers = list.map { c, title, icon in
      let nav = UINavigationController(rootViewController: c)
      nav.tabBarItem = UITabBarItem(
        title: title, image: UIImage(systemName: icon),
        selectedImage: UIImage(systemName: icon + ".fill") ?? UIImage(systemName: icon))
      nav.navigationBar.prefersLargeTitles = false
      nav.navigationBar.tintColor = Palette.ink
      return nav
    }
    tabBar.tintColor = Palette.ink
    if #available(iOS 26.0, *) { tabBarMinimizeBehavior = .onScrollDown }
  }
}
