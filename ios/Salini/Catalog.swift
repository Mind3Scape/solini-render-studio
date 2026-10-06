import QuickLook
import UIKit

final class CatalogController: ScrollController, UISearchBarDelegate {
  private let results = UIStackView()
  private let search = UISearchBar()
  private let filters = UISegmentedControl(items: ["Все", "Ванны", "Раковины", "Избранное"])
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Коллекции"
    navigationItem.largeTitleDisplayMode = .never
    add(
      stack(
        [
          eyebrow("НАЙДИТЕ СВОЮ ФОРМУ"),
          label("Предметы\nс характером.", 37, .regular, serif: true),
        ], spacing: 12))
    search.placeholder = "Название или артикул"
    search.searchBarStyle = .minimal
    search.delegate = self
    search.accessibilityIdentifier = "catalog.search"
    add(search, inset: 16)
    filters.selectedSegmentIndex = 0
    filters.addAction(UIAction { [weak self] _ in self?.render() }, for: .valueChanged)
    add(filters, inset: 24)
    results.axis = .vertical
    results.spacing = 18
    add(results, inset: 24)
    render()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    render()
  }
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { render() }
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
  private func render() {
    results.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let q = (search.text ?? "").lowercased().replacingOccurrences(of: "ь", with: "m")
    let list = Product.all.filter { p in
      let match =
        q.isEmpty
        || [p.name, p.article, p.stoneArticle ?? "", p.category].contains {
          $0.lowercased().contains(q)
        }
      return match
        && (filters.selectedSegmentIndex == 0
          || (filters.selectedSegmentIndex == 1 && p.category == "Ванны")
          || (filters.selectedSegmentIndex == 2 && p.category == "Раковины")
          || (filters.selectedSegmentIndex == 3 && DemoStore.shared.favorites.contains(p.id)))
    }
    results.addArrangedSubview(
      eyebrow(
        "\(list.count) \(plural(list.count, "ИЗДЕЛИЕ", "ИЗДЕЛИЯ", "ИЗДЕЛИЙ")) · ПОДБОРКА SALINI"))
    if list.isEmpty {
      results.addArrangedSubview(
        label("Пока ничего.\nПопробуйте Aria или 1051201M.", 25, .regular, serif: true))
      return
    }
    for p in list {
      let tile = ProductTile(product: p) { [weak self] in self?.showProduct(p) }
      tile.height(345)
      results.addArrangedSubview(tile)
    }
  }
}

final class ProductController: ScrollController {
  let product: Product
  private var stone = false
  private let price = label("", 29, .medium)
  private let sku = label("", 12, .regular, Palette.muted)
  private var heart: UIBarButtonItem!
  init(_ product: Product, stone: Bool = false) {
    self.product = product
    self.stone = stone && product.canConfigure
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = product.name
    heart = UIBarButtonItem(
      image: UIImage(systemName: "heart"),
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        DemoStore.shared.toggle(self.product)
        self.update()
      })
    heart.accessibilityIdentifier = "product.favorite"
    navigationItem.rightBarButtonItem = heart
    add(photo(product.image, height: 330), inset: 0)
    add(
      stack(
        [
          eyebrow(product.subtitle.uppercased()), label(product.name, 45, .regular, serif: true),
          label(product.story, 16, .regular, Palette.muted), spacer(2),
          label(product.dimensions, 15, .medium), line(), price, sku,
        ], spacing: 13))
    if product.canConfigure {
      let control = UISegmentedControl(items: ["S-Sense · глянец", "S-Stone · матовый"])
      control.selectedSegmentIndex = stone ? 1 : 0
      control.accessibilityIdentifier = "product.material"
      control.addAction(
        UIAction { [weak self, weak control] _ in
          self?.stone = control?.selectedSegmentIndex == 1
          self?.update()
        }, for: .valueChanged)
      add(
        stack(
          [
            eyebrow("ВАШЕ ИСПОЛНЕНИЕ"), control,
            label("Белый · производство под заказ, до 30 дней", 13, .regular, Palette.muted),
          ], spacing: 13))
    } else {
      add(
        stack([
          eyebrow("КОЛЛЕКЦИОННОЕ ИСПОЛНЕНИЕ"),
          label(
            "Цена — по базовому исполнению сайта. Цвет и отделку уточним при комплектации.", 14,
            .regular, Palette.muted),
        ]))
    }
    let addButton = ActionButton("Добавить в проект", icon: "plus", prominent: true) {
      [weak self] in
      guard let self else { return }
      DemoStore.shared.add(self.product, stone: self.stone)
      let done = SavedController(self.product) { [weak self] in
        self?.tabBarController?.selectedIndex = 2
      }
      self.sheet(done)
    }
    addButton.accessibilityIdentifier = "product.add"
    add(addButton)
    let details = stack(
      [
        eyebrow("ПРОДУМАНО ДО МЕЛОЧЕЙ"),
        label(
          product.id == "aria"
            ? "Свет, который меняет ощущение." : "Форма, которая остаётся с вами.", 28, .regular,
          serif: true),
        label(
          product.id == "aria"
            ? "Встроенная LED-подсветка и донный клапан D403 входят в комплектацию Aria."
            : "Точные параметры, материалы и документы помогают собрать целостный интерьер.", 15,
          .regular, Palette.muted),
      ], spacing: 15)
    if product.id == "aria" {
      details.addArrangedSubview(
        ActionButton("Технический чертёж", icon: "doc.text") { [weak self] in
          self?.present(DrawingController(), animated: true)
        })
    }
    details.addArrangedSubview(
      ActionButton("Материалы Salini", icon: "circle.lefthalf.filled") { [weak self] in
        self?.sheet(MaterialsController())
      })
    add(details)
    add(
      label(
        "Концепт приложения · цены из публичного каталога на 06.10.2026. Заказ в этом демо не отправляется.",
        11, .regular, Palette.muted))
    update()
  }
  private func update() {
    price.text = rubles(product.price(stone: stone))
    price.accessibilityIdentifier = "product.price"
    sku.text = "Артикул \(product.sku(stone:stone))"
    let saved = DemoStore.shared.favorites.contains(product.id)
    heart.image = UIImage(systemName: saved ? "heart.fill" : "heart")
    heart.accessibilityLabel = saved ? "Убрать из избранного" : "В избранное"
  }
}

final class SavedController: ScrollController {
  let product: Product
  let onOpen: () -> Void
  init(_ p: Product, onOpen: @escaping () -> Void) {
    product = p
    self.onOpen = onOpen
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "В вашем проекте"
    let icon = symbol("checkmark.circle.fill", size: 45)
    icon.height(55)
    add(
      stack(
        [
          icon, label("\(product.name)\nуже в подборке.", 35, .regular, serif: true),
          label(
            "\(DemoStore.shared.projectName) · \(DemoStore.shared.items.count) \(plural(DemoStore.shared.items.count, "позиция", "позиции", "позиций"))",
            15,
            .regular, Palette.muted),
          ActionButton("Открыть проект", icon: "arrow.up.right", prominent: true) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true, completion: self.onOpen)
          },
          ActionButton("Продолжить подбор", icon: "plus") { [weak self] in
            self?.dismiss(animated: true)
          },
        ], spacing: 20))
  }
}
final class DrawingController: QLPreviewController, QLPreviewControllerDataSource {
  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
  }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    Bundle.main.url(forResource: "Aria-drawing", withExtension: "pdf") == nil ? 0 : 1
  }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  { Bundle.main.url(forResource: "Aria-drawing", withExtension: "pdf")! as NSURL }
}
