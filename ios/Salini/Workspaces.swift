import QuickLook
import UIKit

// Local partner workflow. Demo stock is deliberately independent of public price data.
struct PartnerReservation: Codable, Identifiable {
  let id: String
  let productID: String
  let warehouse: Int
  let quantity: Int
  var scheduled = false
  var product: Product? { Product.all.first { $0.id == productID } }
}
final class PartnerStore {
  static let shared = PartnerStore()
  private let defaults: UserDefaults
  private(set) var orders: [PartnerReservation] = []
  static let warehouses = ["Белгород", "Москва"]
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: "salini.partner.orders"),
      let saved = try? JSONDecoder().decode([PartnerReservation].self, from: data)
    {
      orders = saved
    }
  }
  func available(_ productID: String, warehouse: Int) -> Int {
    let counts = ["aria": [8, 3], "opera": [12, 5], "greca": [6, 2], "opera-top": [24, 11]]
    guard (0...1).contains(warehouse) else { return 0 }
    let base = counts[productID]?[warehouse] ?? 0
    return max(
      0,
      base
        - orders.filter { $0.productID == productID && $0.warehouse == warehouse }.reduce(0) {
          $0 + $1.quantity
        })
  }
  @discardableResult func reserve(_ productID: String, warehouse: Int, quantity: Int)
    -> PartnerReservation?
  {
    guard quantity > 0, quantity <= available(productID, warehouse: warehouse) else { return nil }
    let r = PartnerReservation(
      id: "R-\(2101 + orders.count)", productID: productID, warehouse: warehouse, quantity: quantity
    )
    orders.insert(r, at: 0)
    save()
    return r
  }
  func schedule(_ id: String) {
    guard let i = orders.firstIndex(where: { $0.id == id }), !orders[i].scheduled else { return }
    orders[i].scheduled = true
    save()
  }
  private func save() {
    defaults.set(try? JSONEncoder().encode(orders), forKey: "salini.partner.orders")
    NotificationCenter.default.post(name: .demoChanged, object: nil)
  }
}

func workspaceCard(_ views: [UIView], spacing: CGFloat = 14) -> UIView {
  let card = stack(views, spacing: spacing).inset(22)
  card.backgroundColor = .white
  card.rounded(28)
  return card
}
func workspaceAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void)
  -> UIView
{
  let b = UIButton(type: .system)
  b.accessibilityLabel = title
  b.accessibilityIdentifier = "action.\(icon)"
  let texts = stack(
    [label(title, 16, .semibold), label(subtitle, 12, .regular, Palette.muted)], spacing: 5)
  let row = stack(
    [
      symbol(icon, size: 23), texts, UIView(),
      symbol("chevron.right", size: 11, color: Palette.muted),
    ], axis: .horizontal, spacing: 16)
  row.alignment = .center
  row.isUserInteractionEnabled = false
  b.pin(row, inset: 20)
  b.backgroundColor = .white
  b.rounded(23)
  b.addAction(
    UIAction { _ in
      UIImpactFeedbackGenerator(style: .soft).impactOccurred()
      action()
    }, for: .touchUpInside)
  return b
}

final class ModelPreviewController: QLPreviewController, QLPreviewControllerDataSource {
  let resource: String
  let ext: String
  init(_ resource: String = "Greca", ext: String = "usdz") {
    self.resource = resource
    self.ext = ext
    super.init(nibName: nil, bundle: nil)
    dataSource = self
  }
  required init?(coder: NSCoder) { fatalError() }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  {
    Bundle.main.url(forResource: resource, withExtension: ext)! as NSURL
  }
}

final class ChoiceControl: UIView {
  private var selected: Int
  private var buttons: [UIButton] = []
  init(_ titles: [String], selected: Int, onChange: @escaping (Int) -> Void) {
    self.selected = selected
    super.init(frame: .zero)
    backgroundColor = UIColor(hex: 0xEDEEF1)
    rounded(22)
    let row = stack([], axis: .horizontal, spacing: 4)
    row.distribution = .fillEqually
    for (index, title) in titles.enumerated() {
      let button = UIButton(type: .system)
      var config = UIButton.Configuration.plain()
      config.title = title
      config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 6)
      config.background.cornerRadius = 19
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 12, weight: .semibold)
        return a
      }
      button.configuration = config
      button.addAction(
        UIAction { [weak self] _ in
          self?.selected = index
          self?.update()
          onChange(index)
          UISelectionFeedbackGenerator().selectionChanged()
        }, for: .touchUpInside)
      row.addArrangedSubview(button)
      buttons.append(button)
    }
    pin(row, inset: 4)
    update()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func update() {
    for (index, button) in buttons.enumerated() {
      button.configuration?.baseForegroundColor = index == selected ? .white : Palette.ink
      button.configuration?.background.backgroundColor = index == selected ? Palette.ink : .clear
      button.accessibilityTraits = index == selected ? [.button, .selected] : [.button]
    }
  }
}

final class FinderController: ScrollController {
  private var budget = 1
  private var compact = false
  private let result = UIStackView()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Личный подбор"
    add(
      stack(
        [eyebrow("ДВА ШАГА К СВОЕЙ ФОРМЕ"), label("Начнём с вашего\nпространства.", 33, .medium)],
        spacing: 13))
    let space = ChoiceControl(["До 180 см", "Без ограничений"], selected: 1) { [weak self] index in
      self?.compact = index == 0
      self?.render()
    }
    let money = ChoiceControl(["До 500 тыс.", "Любой бюджет"], selected: 1) { [weak self] index in
      self?.budget = index
      self?.render()
    }
    add(
      workspaceCard([eyebrow("ДЛИНА ВАННЫ"), space, spacer(5), eyebrow("БЮДЖЕТ"), money]), inset: 20
    )
    result.axis = .vertical
    result.spacing = 20
    add(result, inset: 20)
    render()
  }
  private func render() {
    result.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let products = Product.all.filter { p in
      p.category == "Ванны" && (budget == 1 || p.price <= 500000)
        && (!compact || (Int(p.dimensions.components(separatedBy: " ").first ?? "0") ?? 0) <= 1800)
    }
    result.addArrangedSubview(
      label(
        "\(products.count) \(plural(products.count, "форма подходит", "формы подходят", "форм подходят"))",
        24, .semibold))
    for p in products {
      let tile = ProductTile(product: p) { [weak self] in self?.showProduct(p) }
      tile.height(345)
      result.addArrangedSubview(tile)
    }
    if products.isEmpty {
      result.addArrangedSubview(label("Попробуйте увеличить длину или бюджет.", 17))
    }
  }
}

final class CompareController: ScrollController {
  private let body = UIStackView()
  private var selected = 0
  private let candidates = Product.all.filter { $0.category == "Ванны" }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Сравнить формы"
    add(
      stack(
        [eyebrow("ВЫБОР В ДЕТАЛЯХ"), label("Один взгляд.\nДве возможности.", 32, .medium)],
        spacing: 12))
    let picker = ChoiceControl(["Aria / Opera", "Aria / Greca"], selected: 0) { [weak self] index in
      self?.selected = index
      self?.render()
    }
    add(picker, inset: 20)
    body.axis = .vertical
    body.spacing = 18
    add(body, inset: 20)
    render()
  }
  private func render() {
    body.arrangedSubviews.forEach { $0.removeFromSuperview() }
    guard candidates.count == 3 else { return }
    let ps = [candidates[0], candidates[selected + 1]]
    let columns = ps.map { p -> UIView in
      let image = photo(p.image, height: 150)
      image.contentMode = .scaleAspectFit
      image.backgroundColor = .white
      image.rounded(20)
      return stack(
        [
          image, label(p.name, 25, .semibold), label(p.dimensions, 12, .regular, Palette.muted),
          label(rubles(p.price), 17, .medium),
          ActionButton("Выбрать", icon: "plus", prominent: true) { [weak self] in
            DemoStore.shared.add(p, stone: false)
            self?.message(
              "\(p.name) в проекте",
              "Выбранное изделие сохранено. Продолжить можно в разделе «Проекты».")
          },
        ], spacing: 13)
    }
    let row = stack(columns, axis: .horizontal, spacing: 14)
    row.distribution = .fillEqually
    row.alignment = .top
    body.addArrangedSubview(row)
    body.addArrangedSubview(
      workspaceCard([
        label("Форма и ощущение", 21, .semibold),
        label(
          selected == 0
            ? "Aria — строгая геометрия и встроенный свет. Opera — классическая пластика и мягкая линия борта."
            : "Aria — архитектурный акцент. Greca — округлый силуэт и более компактная длина.", 15,
          .regular, Palette.muted),
      ]))
  }
}

final class ResourcesController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Библиотека дизайнера"
    add(
      stack(
        [
          eyebrow("ФАЙЛЫ ДЛЯ РАБОТЫ"), label("От замысла\nк точному проекту.", 34, .medium),
          label(
            "Оригинальные модели и документация Salini доступны прямо в приложении.", 15, .regular,
            Palette.muted),
        ], spacing: 14))
    let model = photo("greca", height: 220)
    model.rounded(24)
    add(
      workspaceCard([
        model, label("Greca / 3D", 26, .semibold),
        label("USDZ · оригинальная модель Salini", 12, .regular, Palette.muted),
        ActionButton("Открыть модель", icon: "cube.transparent", prominent: true) { [weak self] in
          self?.present(ObjectViewerController(), animated: true)
        },
        ActionButton("Поделиться USDZ", icon: "square.and.arrow.up") { [weak self] in
          self?.share("Greca", ext: "usdz")
        },
      ]), inset: 20)
    add(
      workspaceAction(
        "Чертёж Aria", subtitle: "Размеры, установка, подключения · PDF", icon: "ruler"
      ) { [weak self] in
        self?.present(ModelPreviewController("Aria-drawing", ext: "pdf"), animated: true)
      }, inset: 20)
    add(
      workspaceAction(
        "Материалы и покрытия", subtitle: "S-Stone и S-Sense", icon: "circle.lefthalf.filled"
      ) { [weak self] in self?.sheet(MaterialsController()) }, inset: 20)
    add(
      workspaceAction(
        "Добавить изделие в проект", subtitle: "Каталог и выбор исполнения", icon: "plus.square"
      ) { [weak self] in
        self?.navigationController?.pushViewController(CatalogController(), animated: true)
      }, inset: 20)
  }
  private func share(_ name: String, ext: String) {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    vc.popoverPresentationController?.sourceView = view
    present(vc, animated: true)
  }
}

final class StockController: ScrollController {
  private var warehouse = 0
  private let results = UIStackView()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Наличие"
    add(
      stack(
        [
          eyebrow("ПАРТНЁРСКИЙ КАБИНЕТ · ДЕМО"),
          label("Нужное изделие.\nНа нужном складе.", 32, .medium),
        ], spacing: 12))
    let picker = ChoiceControl(PartnerStore.warehouses, selected: 0) { [weak self] index in
      self?.warehouse = index
      self?.render()
    }
    add(picker, inset: 20)
    results.axis = .vertical
    results.spacing = 16
    add(results, inset: 20)
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    render()
  }
  private func render() {
    results.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for p in Product.all {
      let count = PartnerStore.shared.available(p.id, warehouse: warehouse)
      let image = photo(p.image, height: 110)
      image.widthAnchor.constraint(equalToConstant: 94).isActive = true
      image.rounded(16)
      let row = stack(
        [
          image,
          stack(
            [
              label(p.name, 23, .semibold),
              label("\(count) доступно", 14, .medium, UIColor(hex: 0x306BCB)),
              label(p.article, 11, .regular, Palette.muted),
            ], spacing: 9),
        ], axis: .horizontal, spacing: 18)
      row.alignment = .center
      let button = ActionButton("Зарезервировать", icon: "shippingbox", prominent: true) {
        [weak self] in
        guard let self else { return }
        self.sheet(
          ReservationController(p, warehouse: self.warehouse) { [weak self] in self?.render() })
      }
      button.isEnabled = count > 0
      button.accessibilityIdentifier = "reserve.\(p.id)"
      results.addArrangedSubview(workspaceCard([row, button]))
    }
    results.addArrangedSubview(
      label(
        "Остатки и резервы демонстрационные. Действия сохраняются только на этом устройстве.", 12,
        .regular, Palette.muted))
  }
}
final class ReservationController: ScrollController {
  let product: Product
  let warehouse: Int
  let onChange: () -> Void
  private var quantity = 1
  private let quantityLabel = label("1 изделие", 26, .semibold)
  init(_ product: Product, warehouse: Int, onChange: @escaping () -> Void) {
    self.product = product
    self.warehouse = warehouse
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Новый резерв"
    add(
      stack(
        [
          eyebrow("\(PartnerStore.warehouses[warehouse].uppercased()) · ДЕМО"),
          label(product.name, 36, .semibold),
          label(
            "Доступно \(PartnerStore.shared.available(product.id, warehouse: warehouse)) изделий",
            14, .regular, Palette.muted),
        ], spacing: 12))
    let stepper = UIStepper()
    stepper.minimumValue = 1
    stepper.maximumValue = Double(PartnerStore.shared.available(product.id, warehouse: warehouse))
    stepper.value = 1
    stepper.addAction(
      UIAction { [weak self, weak stepper] _ in
        guard let self else { return }
        self.quantity = Int(stepper?.value ?? 1)
        self.quantityLabel.text =
          "\(self.quantity) \(plural(self.quantity, "изделие", "изделия", "изделий"))"
      }, for: .valueChanged)
    let row = stack([quantityLabel, UIView(), stepper], axis: .horizontal)
    row.alignment = .center
    add(row)
    add(
      ActionButton("Создать резерв", icon: "checkmark", prominent: true) { [weak self] in
        guard let self else { return }
        guard
          let order = PartnerStore.shared.reserve(
            self.product.id, warehouse: self.warehouse, quantity: self.quantity)
        else {
          self.message("Остаток изменился", "Уменьшите количество и попробуйте ещё раз.")
          return
        }
        self.onChange()
        self.navigationController?.setViewControllers(
          [PartnerOrderController(order.id)], animated: true)
      })
  }
}
final class PartnerOrdersController: ScrollController {
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    title = "Заказы и отгрузки"
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(
      stack(
        [
          eyebrow("ПАРТНЁРСКИЙ КАБИНЕТ · ДЕМО"),
          label("Каждое изделие\nпод контролем.", 32, .medium),
        ], spacing: 12))
    let orders = PartnerStore.shared.orders
    if orders.isEmpty {
      add(
        workspaceCard([
          label("Первая поставка\nначинается здесь.", 27, .medium),
          label(
            "Создайте резерв на складе. Здесь появятся его состав и маршрут отгрузки.", 15,
            .regular, Palette.muted),
          ActionButton("Открыть наличие", icon: "shippingbox", prominent: true) { [weak self] in
            self?.tabBarController?.selectedIndex = 1
          },
        ]), inset: 20)
    }
    for order in orders {
      add(
        workspaceAction(
          "\(order.id) · \(order.product?.name ?? "Изделие")",
          subtitle:
            "\(order.quantity) шт. · \(order.scheduled ? "Отгрузка запланирована" : "В резерве")",
          icon: order.scheduled ? "truck.box" : "shippingbox"
        ) { [weak self] in
          self?.navigationController?.pushViewController(
            PartnerOrderController(order.id), animated: true)
        }, inset: 20)
    }
  }
}
final class PartnerOrderController: ScrollController {
  let orderID: String
  init(_ id: String) {
    orderID = id
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    render()
  }
  private func render() {
    guard let order = PartnerStore.shared.orders.first(where: { $0.id == orderID }),
      let p = order.product
    else { return }
    title = orderID
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(
      stack(
        [
          eyebrow("ДЕМОНСТРАЦИОННЫЙ РЕЗЕРВ"),
          label(
            order.scheduled ? "Готовимся\nк отправлению." : "Изделия\nзарезервированы.", 33, .medium
          ),
          label(
            "\(p.name) · \(order.quantity) шт.\nСклад: \(PartnerStore.warehouses[order.warehouse])",
            17, .medium),
        ], spacing: 16))
    for (i, stage) in ["Резерв создан", "Отгрузка запланирована", "Передано перевозчику"]
      .enumerated()
    {
      add(
        stack(
          [
            symbol(
              i < (order.scheduled ? 2 : 1) ? "checkmark.circle.fill" : "circle",
              color: i < (order.scheduled ? 2 : 1) ? UIColor(hex: 0x306BCB) : Palette.muted),
            label(stage, 16),
          ], axis: .horizontal, spacing: 15), inset: 20)
    }
    if !order.scheduled {
      add(
        ActionButton("Запланировать отгрузку", icon: "truck.box", prominent: true) { [weak self] in
          guard let self else { return }
          PartnerStore.shared.schedule(self.orderID)
          self.render()
        })
    }
    add(
      label(
        "Это локальный сценарий: резерв и распоряжение на реальный склад не отправляются.", 12,
        .regular, Palette.muted))
  }
}
