import MapKit
import SafariServices
import UIKit

// MARK: - Data (built by tools/build_support.py from the 2026-10-06 site archive)

struct DealerPhone: Codable, Hashable {
  let display: String
  let tel: String
  let `extension`: String?
}
struct DealerExposition: Codable, Hashable {
  let name: String
  let productId: String?
}
struct Dealer: Codable, Hashable {
  /// Site id, or a stable local id (name + address) for the 14 archived dealers without one.
  let id: String
  let sourceId: String?
  let name: String
  let city: String
  let address: String
  let latitude: Double?
  let longitude: Double?
  let phones: [DealerPhone]
  let website: String?
  let hours: String?
  let hasExposition: Bool
  let isDistributor: Bool
  let exposition: [DealerExposition]
  var coordinate: CLLocationCoordinate2D? {
    guard let latitude, let longitude else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}
struct HelpItem: Codable, Hashable {
  let q: String
  let a: String
}
struct HelpSection: Codable, Hashable {
  let title: String
  let items: [HelpItem]
}

enum SupportData {
  private struct DealerFile: Codable { let snapshot: String?; let dealers: [Dealer] }
  private struct HelpFile: Codable { let snapshot: String?; let sections: [HelpSection] }
  /// Strict decode: a single bad record must surface as an error, never as an empty list.
  private static func load<T: Decodable>(_ name: String, as type: T.Type) -> (T?, String?) {
    guard let url = Catalog.mediaURL?.appendingPathComponent(name) else { return (nil, "\(name): нет папки данных") }
    do {
      return (try JSONDecoder().decode(T.self, from: Data(contentsOf: url)), nil)
    } catch {
      let message = "\(name): \(error)"
      print("SupportData decode error — \(message)")
      return (nil, message)
    }
  }
  private static let dealerFile = load("dealers.json", as: DealerFile.self)
  private static let helpFile = load("help.json", as: HelpFile.self)
  static var loadErrors: [String] { [dealerFile.1, helpFile.1].compactMap { $0 } }
  static var dealers: [Dealer] { dealerFile.0?.dealers ?? [] }
  static var help: [HelpSection] { helpFile.0?.sections ?? [] }
  /// Cities by number of salons, for the filter menu.
  static let cities: [String] = {
    let counts = Dictionary(grouping: dealers, by: \.city).mapValues(\.count)
    return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
  }()
  /// Name, city or address; no location is requested.
  static func search(_ query: String, city: String?, expositionOnly: Bool, product: String? = nil) -> [Dealer] {
    let words = CatalogSearch.fold(query).split(separator: " ").map(String.init)
    return dealers.filter { d in
      if let city, d.city != city { return false }
      if expositionOnly && !d.hasExposition { return false }
      if let product, !d.exposition.contains(where: { $0.productId == product }) { return false }
      let text = CatalogSearch.fold("\(d.name) \(d.city) \(d.address)")
      return words.allSatisfy { text.contains($0) }
    }
  }
  static func dealers(exhibiting productId: String) -> [Dealer] {
    dealers.filter { $0.exposition.contains { $0.productId == productId } }
  }
  static let phone = DealerPhone(display: "+7 (495) 249-33-49", tel: "tel:+74952493349", extension: nil)
  static let infoMail = "info@salini-srl.com"
  static let designMail = "design@salini-srl.com"
}

private func openExternal(_ string: String) {
  guard let url = URL(string: string) else { return }
  UIApplication.shared.open(url)
}

// MARK: - Showrooms

final class ShowroomsController: UIViewController, UISearchResultsUpdating, UITableViewDataSource,
  UITableViewDelegate, MKMapViewDelegate
{
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let map = MKMapView()
  private let search = UISearchController(searchResultsController: nil)
  private let mode = UISegmentedControl(items: ["Список", "Карта"])
  private var city: String?
  private var expositionOnly = false
  /// Opened from a product card: only salons whose published exposition lists it.
  var productId: String?
  private var results: [Dealer] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    title = productId == nil ? "Салоны и шоурумы" : "Где посмотреть"
    view.backgroundColor = Palette.paper
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    search.searchBar.placeholder = "Город, название или адрес"
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "line.3.horizontal.decrease"), menu: filterMenu())
    navigationItem.rightBarButtonItem?.accessibilityLabel = "Фильтр салонов"
    mode.selectedSegmentIndex = 0
    mode.accessibilityLabel = "Вид"
    mode.addAction(UIAction { [weak self] _ in self?.updateMode() }, for: .valueChanged)
    navigationItem.titleView = mode
    table.dataSource = self
    table.delegate = self
    table.backgroundColor = .clear
    table.register(UITableViewCell.self, forCellReuseIdentifier: "dealer")
    view.pin(table)
    map.delegate = self
    map.isHidden = true
    map.pointOfInterestFilter = .excludingAll
    map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
    view.pin(map)
    reload()
  }
  private func filterMenu() -> UIMenu {
    UIMenu(children: [
      UIDeferredMenuElement.uncached { [weak self] done in
        guard let self else { return done([]) }
        let all = UIAction(title: "Все города", state: self.city == nil ? .on : .off) { [weak self] _ in
          self?.city = nil
          self?.reload()
        }
        // Every city (69), not a truncated top list; the search field also matches cities.
        let cities = SupportData.cities.map { c in
          UIAction(title: c, state: self.city == c ? .on : .off) { [weak self] _ in
            self?.city = c
            self?.reload()
          }
        }
        let expo = UIAction(title: "Только с экспозицией", image: UIImage(systemName: "eye"),
                            state: self.expositionOnly ? .on : .off) { [weak self] _ in
          self?.expositionOnly.toggle()
          self?.reload()
        }
        done([expo, UIMenu(title: "Город", options: .displayInline, children: [all] + cities)])
      }
    ])
  }
  func updateSearchResults(for searchController: UISearchController) { reload() }
  private func reload() {
    results = SupportData.search(search.searchBar.text ?? "", city: city, expositionOnly: expositionOnly, product: productId)
    table.reloadData()
    map.removeAnnotations(map.annotations)
    let pins = results.compactMap { d -> MKPointAnnotation? in
      guard let c = d.coordinate else { return nil }
      let a = MKPointAnnotation()
      a.coordinate = c
      a.title = d.name
      a.subtitle = d.address
      return a
    }
    map.addAnnotations(pins)
    if !pins.isEmpty { map.showAnnotations(pins, animated: false) }
  }
  private func updateMode() {
    map.isHidden = mode.selectedSegmentIndex == 0
    table.isHidden = !map.isHidden
  }

  func numberOfSections(in tableView: UITableView) -> Int { 1 }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    let withoutMap = results.filter { $0.coordinate == nil }.count
    var text = "\(results.count) \(plural(results.count, "салон", "салона", "салонов")) · данные salini-srl.com на \(Catalog.shared.snapshotText)"
    if withoutMap > 0 { text += " · \(withoutMap) без точки на карте" }
    return text
  }
  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    productId == nil ? nil : "Экспозиция — по данным сайта Salini. Наличие изделия и цвета уточняйте у салона."
  }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "dealer", for: indexPath)
    let d = results[indexPath.row]
    var c = UIListContentConfiguration.subtitleCell()
    c.text = d.name
    c.secondaryText = [d.address, d.hours, d.hasExposition ? "Есть экспозиция" : nil].compactMap { $0 }.joined(separator: "\n")
    c.secondaryTextProperties.color = Palette.muted
    c.secondaryTextProperties.numberOfLines = 0
    c.textProperties.font = .preferredFont(forTextStyle: .headline)
    c.image = UIImage(systemName: d.isDistributor ? "building.2.crop.circle" : "mappin.circle")
    c.imageProperties.tintColor = Palette.ink
    cell.contentConfiguration = c
    cell.accessoryType = .disclosureIndicator
    return cell
  }
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    navigationController?.pushViewController(DealerController(results[indexPath.row]), animated: true)
  }
  func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
    guard let a = view.annotation, let d = results.first(where: { $0.name == a.title && $0.address == a.subtitle }) else { return }
    navigationController?.pushViewController(DealerController(d), animated: true)
  }
  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation) as? MKMarkerAnnotationView
    v?.markerTintColor = Palette.ink
    v?.canShowCallout = true
    v?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
    return v
  }
}

final class DealerController: ScrollController {
  private let dealer: Dealer
  init(_ dealer: Dealer) {
    self.dealer = dealer
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = dealer.city
    navigationItem.largeTitleDisplayMode = .never
    var badges: [String] = []
    if dealer.isDistributor { badges.append("Официальный дистрибьютор") }
    badges.append(dealer.hasExposition ? "Есть экспозиция" : "Без экспозиции")
    add(stack([
      eyebrow(badges.joined(separator: " · ").uppercased()),
      label(dealer.name, 34, .regular, serif: true),
      label(dealer.address, 16, .regular, Palette.muted),
    ] + (dealer.hours.map { [label($0, 15, .medium)] } ?? []), spacing: 10))
    var actions: [UIView] = []
    for phone in dealer.phones {
      let b = ActionButton(phone.display, icon: "phone", prominent: actions.isEmpty) { openExternal(phone.tel) }
      b.accessibilityLabel = "Позвонить \(phone.display)" + (phone.extension.map { ", добавочный \($0)" } ?? "")
      actions.append(b)
      if let ext = phone.extension { actions.append(label("Добавочный: \(ext)", 13, .regular, Palette.muted)) }
    }
    if let site = dealer.website {
      actions.append(ActionButton("Сайт салона", icon: "safari") { [weak self] in
        guard let url = URL(string: site) else { return }
        self?.present(SFSafariViewController(url: url), animated: true)
      })
    }
    if let c = dealer.coordinate {
      let map = MKMapView()
      map.height(200)
      map.rounded(18)
      map.isScrollEnabled = false
      map.pointOfInterestFilter = .excludingAll
      let pin = MKPointAnnotation()
      pin.coordinate = c
      pin.title = dealer.name
      map.addAnnotation(pin)
      map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: false)
      map.isAccessibilityElement = true
      map.accessibilityLabel = "Карта: \(dealer.address)"
      actions.append(map)
      actions.append(ActionButton("Маршрут в Картах", icon: "arrow.triangle.turn.up.right.diamond") { [dealer] in
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = dealer.name
        item.openInMaps()
      })
    } else {
      actions.append(label("Координаты салона на сайте не указаны — адрес выше.", 13, .regular, Palette.muted))
    }
    add(stack(actions, spacing: 12))
    if !dealer.exposition.isEmpty {
      var rows: [UIView] = [
        eyebrow("ЭКСПОЗИЦИЯ ПО ДАННЫМ САЙТА SALINI"),
        label("Список опубликован на salini-srl.com на \(Catalog.shared.snapshotText). Наличие конкретного изделия и цвета уточняйте у салона.", 13, .regular, Palette.muted),
      ]
      for e in dealer.exposition.prefix(40) {
        if let id = e.productId, let p = Catalog.shared.product(id) {
          rows.append(ActionButton(e.name, icon: "arrow.up.right") { [weak self] in
            self?.navigationController?.pushViewController(CatalogProductController(p), animated: true)
          })
        } else {
          rows.append(label(e.name, 15, .regular))
        }
      }
      if dealer.exposition.count > 40 { rows.append(label("и ещё \(dealer.exposition.count - 40)", 13, .regular, Palette.muted)) }
      add(stack(rows, spacing: 8))
    }
  }
}

// MARK: - Help

final class HelpController: UITableViewController, UISearchResultsUpdating {
  private let search = UISearchController(searchResultsController: nil)
  private var sections: [HelpSection] = SupportData.help
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Помощь"
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    search.searchBar.placeholder = "Вопрос: гарантия, уход, доставка…"
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
  }
  func updateSearchResults(for searchController: UISearchController) {
    let words = CatalogSearch.fold(searchController.searchBar.text ?? "").split(separator: " ").map(String.init)
    sections = words.isEmpty ? SupportData.help : SupportData.help.compactMap { s in
      let items = s.items.filter { item in
        let text = CatalogSearch.fold(item.q + " " + item.a)
        return words.allSatisfy { text.contains($0) }
      }
      return items.isEmpty ? nil : HelpSection(title: s.title, items: items)
    }
    tableView.reloadData()
  }
  /// Fixed sections first: warranty by category and contacts for the current role.
  private enum Fixed: Int, CaseIterable { case warranty, contacts }
  private var contactRows: [(String, String, String)] {
    var rows = [("Позвонить в Salini", SupportData.phone.display, SupportData.phone.tel),
                ("Написать", SupportData.infoMail, "mailto:\(SupportData.infoMail)")]
    switch DemoStore.shared.role {
    case .atelier: rows.append(("Для дизайнеров", SupportData.designMail, "mailto:\(SupportData.designMail)"))
    case .partner: rows.append(("Сотрудничество", SupportData.infoMail, "mailto:\(SupportData.infoMail)"))
    case .home: rows.append(("Салоны и шоурумы", "по городу и названию", "showrooms"))
    }
    return rows
  }
  private static let warranty: [(String, String)] = [
    ("Ванны, раковины, поддоны, столешницы, унитазы и биде", "10 лет при правильной установке и эксплуатации"),
    ("Мебель и зеркала", "2 года"), ("Линейка Salini Essentials", "5 лет"), ("Комплектующие", "1 год"),
  ]
  override func numberOfSections(in tableView: UITableView) -> Int { Fixed.allCases.count + sections.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Fixed(rawValue: section) {
    case .warranty: return Self.warranty.count
    case .contacts: return contactRows.count
    case nil: return sections[section - Fixed.allCases.count].items.count
    }
  }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Fixed(rawValue: section) {
    case .warranty: return "Гарантия по категориям"
    case .contacts: return "Связаться"
    case nil: return sections[section - Fixed.allCases.count].title
    }
  }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    section == Fixed.warranty.rawValue ? "По FAQ и текстам сайта Salini. Точные условия для изделия — в паспорте и у менеджера." : nil
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    var c = UIListContentConfiguration.valueCell()
    c.prefersSideBySideTextAndSecondaryText = false
    c.secondaryTextProperties.color = Palette.muted
    c.textProperties.numberOfLines = 0
    c.secondaryTextProperties.numberOfLines = 0
    cell.accessoryType = .none
    cell.selectionStyle = .default
    switch Fixed(rawValue: indexPath.section) {
    case .warranty:
      c = UIListContentConfiguration.subtitleCell()
      c.text = Self.warranty[indexPath.row].0
      c.secondaryText = Self.warranty[indexPath.row].1
      c.secondaryTextProperties.color = Palette.muted
      c.textProperties.numberOfLines = 0
      cell.selectionStyle = .none
    case .contacts:
      let row = contactRows[indexPath.row]
      c = UIListContentConfiguration.subtitleCell()
      c.text = row.0
      c.secondaryText = row.1
      c.secondaryTextProperties.color = Palette.muted
      cell.accessoryType = .disclosureIndicator
    case nil:
      c = UIListContentConfiguration.cell()
      c.text = sections[indexPath.section - Fixed.allCases.count].items[indexPath.row].q
      c.textProperties.numberOfLines = 0
      cell.accessoryType = .disclosureIndicator
    }
    cell.contentConfiguration = c
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch Fixed(rawValue: indexPath.section) {
    case .warranty: return
    case .contacts:
      let target = contactRows[indexPath.row].2
      if target == "showrooms" {
        navigationController?.pushViewController(ShowroomsController(), animated: true)
      } else {
        openExternal(target)
      }
    case nil:
      let item = sections[indexPath.section - Fixed.allCases.count].items[indexPath.row]
      navigationController?.pushViewController(HelpAnswerController(item), animated: true)
    }
  }
}

final class HelpAnswerController: ScrollController {
  private let item: HelpItem
  init(_ item: HelpItem) {
    self.item = item
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    add(stack([
      label(item.q, 26, .regular, serif: true),
      label(item.a, 16, .regular),
      label("Ответ из раздела FAQ на salini-srl.com, \(Catalog.shared.snapshotText).", 12, .regular, Palette.muted),
    ], spacing: 16))
  }
}
