import SafariServices
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

/// Search the real catalogue and return one product with the execution the hit stands for.
final class CatalogPickerController: UITableViewController, UISearchResultsUpdating {
  private let search = UISearchController(searchResultsController: nil)
  private var hits: [Catalog.Hit] = Catalog.shared.search("")
  private let onPick: (CatalogProduct, String?) -> Void
  init(title: String, onPick: @escaping (CatalogProduct, String?) -> Void) {
    self.onPick = onPick
    super.init(style: .plain)
    self.title = title
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    search.searchBar.placeholder = "Название, коллекция или артикул"
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "hit")
  }
  func updateSearchResults(for searchController: UISearchController) {
    hits = Catalog.shared.search(searchController.searchBar.text ?? "")
    tableView.reloadData()
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { hits.count }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "hit", for: indexPath)
    let hit = hits[indexPath.row]
    var c = UIListContentConfiguration.subtitleCell()
    c.text = hit.product.name
    c.secondaryText = [hit.product.category, hit.price.map(rubles) ?? "цена по запросу"].joined(separator: " · ")
    c.secondaryTextProperties.color = Palette.muted
    c.image = UIImage(systemName: "photo")
    c.imageProperties.maximumSize = CGSize(width: 54, height: 54)
    c.imageProperties.cornerRadius = 8
    cell.contentConfiguration = c
    let id = hit.product.id
    CatalogImages.shared.image(for: hit.product, maxPixel: 160) { [weak cell] image in
      guard let cell, var current = cell.contentConfiguration as? UIListContentConfiguration,
        current.text == hit.product.name, let image, id == hit.product.id
      else { return }
      current.image = image
      cell.contentConfiguration = current
    }
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let hit = hits[indexPath.row]
    dismiss(animated: true) { [onPick] in onPick(hit.product, hit.variantKey ?? hit.product.variants.first?.key) }
  }
}

/// Two real catalogue items side by side, each in its own execution; differing values are bold.
final class CompareController: ScrollController {
  private struct Slot {
    var product: CatalogProduct
    var variantKey: String?
    var variant: CatalogVariant? { product.variant(key: variantKey) }
  }
  private var slots: [Slot] = []
  private let body = UIStackView()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Сравнить"
    // Opening pair: two signature baths; either side can be replaced from the whole catalogue.
    for (id, sku) in [("aria", "1051201M"), ("opera", nil)] as [(String, String?)] {
      if let p = Catalog.shared.product(id) {
        slots.append(Slot(product: p, variantKey: p.variants.first { sku == nil || $0.sku == sku }?.key ?? p.variants.first?.key))
      }
    }
    add(stack([eyebrow("СРАВНЕНИЕ"), label("Выберите свою форму", 30, .regular, serif: true)], spacing: 10))
    body.axis = .vertical
    body.spacing = 18
    add(body, inset: 20)
    render()
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.render() }
  }
  private func render() {
    body.arrangedSubviews.forEach { $0.removeFromSuperview() }
    guard slots.count == 2 else { return }
    let parts = slots.indices.map { column($0) }
    // Accessibility text sizes: the two positions stack instead of squeezing into half widths.
    if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
      body.addArrangedSubview(stack(parts.map { stack($0, spacing: 8) }, spacing: 24))
    } else {
      // Paired rows: photo, name, execution and buttons line up even when one name wraps.
      var rows: [UIView] = []
      for k in parts[0].indices {
        let pair = stack([parts[0][k], parts[1][k]], axis: .horizontal, spacing: 12)
        pair.distribution = .fillEqually
        pair.alignment = .fill
        rows.append(pair)
      }
      body.addArrangedSubview(stack(rows, spacing: 8))
    }
    body.addArrangedSubview(table())
    body.addArrangedSubview(label(
      "Цены на \(Catalog.shared.snapshotText). Наличие и сроки уточняйте у менеджера.",
      12, .regular, Palette.muted))
  }
  private func column(_ i: Int) -> [UIView] {
    let slot = slots[i]
    let image = UIImageView()
    image.contentMode = .scaleAspectFit
    image.backgroundColor = .white
    image.rounded(18)
    image.height(140)
    CatalogImages.shared.image(for: slot.product, maxPixel: 500) { image.image = $0 }
    var execution = UIButton.Configuration.plain()
    execution.title = slot.variant?.title ?? "Исполнение"
    execution.image = UIImage(systemName: "chevron.up.chevron.down")
    execution.imagePlacement = .trailing
    execution.imagePadding = 4
    execution.baseForegroundColor = Palette.ink
    execution.contentInsets = .init(top: 6, leading: 0, bottom: 6, trailing: 0)
    let executionButton = UIButton(configuration: execution)
    executionButton.titleLabel?.numberOfLines = 2
    executionButton.contentHorizontalAlignment = .leading
    executionButton.contentVerticalAlignment = .top
    executionButton.showsMenuAsPrimaryAction = true
    executionButton.menu = UIMenu(children: slot.product.variants.map { v in
      UIAction(title: v.title ?? "Базовое исполнение", subtitle: v.price.map(rubles) ?? "цена по запросу",
               state: v.key == slot.variantKey ? .on : .off) { [weak self] _ in
        self?.slots[i].variantKey = v.key
        self?.render()
      }
    })
    executionButton.isEnabled = slot.product.variants.count > 1
    executionButton.accessibilityLabel = "Исполнение: \(slot.variant?.title ?? "базовое")"
    let change = ActionButton("Заменить", icon: "magnifyingglass") { [weak self] in
      let picker = CatalogPickerController(title: "Позиция \(i + 1)") { product, key in
        self?.slots[i] = Slot(product: product, variantKey: key)
        self?.render()
      }
      self?.present(UINavigationController(rootViewController: picker), animated: true)
    }
    change.accessibilityIdentifier = "compare.change.\(i)"
    let add = ActionButton("В проект", icon: "plus", prominent: true) { [weak self] in
      guard ProjectStore.shared.add(slot.product, variantKey: slot.variantKey) != nil else {
        self?.message("Выберите исполнение", "Без исполнения позицию нельзя добавить в проект.")
        return
      }
      self?.message("\(slot.product.name) в проекте", "Исполнение: \(slot.variant?.title ?? "базовое").")
    }
    let open = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in
      self?.navigationController?.pushViewController(
        CatalogProductController(slot.product, variantKey: slot.variantKey), animated: true)
    })
    open.configuration?.title = slot.product.name
    open.configuration?.baseForegroundColor = Palette.ink
    open.configuration?.contentInsets = .zero
    open.titleLabel?.font = UIFont(descriptor: UIFont.systemFont(ofSize: 21).fontDescriptor.withDesign(.serif)!, size: 21)
    open.titleLabel?.numberOfLines = 3
    open.contentHorizontalAlignment = .leading
    open.contentVerticalAlignment = .top
    return [image, open, executionButton, change, add]
  }
  private func table() -> UIView {
    func values(_ s: Slot) -> [String] {
      let v = s.variant
      let d = s.product.dimensions
      return [
        s.product.category + (s.product.subcategory.map { " · \($0)" } ?? ""),
        v?.price.map(rubles) ?? "по запросу",
        v?.sku ?? "—",
        d.text ?? "—",
        s.product.depthToOverflow.map { "\(Int($0)) мм" } ?? "—",
        v?.weightKg.map(kg) ?? "—",
        v?.packedWeightKg.map(kg) ?? "—",
        s.product.availability.stockQuantity.flatMap { $0 > 0 ? "\($0) шт. на складе" : nil }
          ?? s.product.availability.text ?? "уточняется",
        ProposalTexts.warranty(for: s.product),
        s.product.model == nil ? "—" : "есть",
        v?.allowsRAL == true ? "RAL Classic по запросу" : "—",
      ]
    }
    let titles = ["Категория", "Цена", "Артикул", "Габариты", "До перелива", "Вес", "В упаковке", "Наличие",
                  "Гарантия", "3D-модель", "Цвет"]
    let a = values(slots[0])
    let b = values(slots[1])
    var rows: [UIView] = []
    for (i, title) in titles.enumerated() {
      let differs = a[i] != b[i]
      let left = label(a[i], 14, differs ? .semibold : .regular)
      let right = label(b[i], 14, differs ? .semibold : .regular)
      let pair = stack([left, right], axis: traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal, spacing: 12)
      pair.distribution = .fillEqually
      pair.alignment = .top
      let row = stack([label(title.uppercased(), 10, .semibold, Palette.muted), pair], spacing: 4)
      row.isAccessibilityElement = true
      row.accessibilityLabel = "\(title): \(slots[0].product.name) — \(a[i]); \(slots[1].product.name) — \(b[i])"
      rows.append(row)
      rows.append(line())
    }
    return workspaceCard(rows)
  }
}

/// Opening an official USDZ. On a device: QuickLook with AR. QuickLook in the iOS Simulator
/// shows only a file card, so there the same form opens in the material studio, whose SceneKit
/// scene renders the model. The original file is always shared as is.
enum ModelViewing {
  static var subtitle: String {
    #if targetEnvironment(simulator)
      return "просмотр в студии"
    #else
      return "просмотр и AR"
    #endif
  }
  static func open(_ form: StudioForm, from host: UIViewController) {
    #if targetEnvironment(simulator)
      MaterialStudioController.present(form: form, from: host)
    #else
      host.present(ProposalPreviewController(fileURL: form.modelURL), animated: true)
    #endif
  }
  static func share(_ form: StudioForm, from host: UIViewController) {
    let sheet = UIActivityViewController(activityItems: [form.modelURL], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = host.view
    host.present(sheet, animated: true)
  }
}

/// Designer library: every bundled official model, the documents of the current project and
/// a catalogue search for any other item's documents.
final class ResourcesController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Библиотека дизайнера"
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(stack([
      eyebrow("ФАЙЛЫ ДЛЯ РАБОТЫ"), label("От замысла\nк точному проекту.", 34, .regular, serif: true),
      label("По каждому изделию объекта — отделка на самой форме, официальная 3D-модель, чертежи и паспорта карточки.", 15, .regular, Palette.muted),
    ], spacing: 12))
    // Project documents first: what the designer is working on right now.
    let project = ProjectStore.shared.current
    let projectProducts = project.lines.compactMap(\.product).reduce(into: [CatalogProduct]()) { list, p in
      if !list.contains(where: { $0.id == p.id }) { list.append(p) }
    }
    var projectRows: [UIView] = [eyebrow("ОБЪЕКТ «\(project.name.uppercased())»")]
    if projectProducts.isEmpty {
      projectRows.append(label("Добавьте изделия в проект — здесь появятся их паспорта, чертежи и модели.", 14, .regular, Palette.muted))
    }
    for p in projectProducts { projectRows.append(documentsBlock(p)) }
    add(stack(projectRows, spacing: 12), inset: 20)
    var models: [UIView] = [eyebrow("3D-МОДЕЛИ USDZ · \(StudioForm.all.count)")]
    for form in StudioForm.all {
      models.append(workspaceAction(form.name, subtitle: "Официальная модель · \(ModelViewing.subtitle)", icon: "cube.transparent") {
        [weak self] in self.map { ModelViewing.open(form, from: $0) }
      })
    }
    add(stack(models, spacing: 10), inset: 20)
    add(stack([
      eyebrow("ДРУГИЕ ИЗДЕЛИЯ"),
      workspaceAction("Документы любого изделия", subtitle: "Поиск по 305 карточкам каталога", icon: "magnifyingglass") {
        [weak self] in
        let picker = CatalogPickerController(title: "Документы изделия") { product, _ in
          self?.navigationController?.pushViewController(ProductDocumentsController(product), animated: true)
        }
        self?.present(UINavigationController(rootViewController: picker), animated: true)
      },
      workspaceAction("Чертёж Aria", subtitle: "Размеры, установка, подключения · PDF в приложении", icon: "ruler") {
        [weak self] in self?.present(ModelPreviewController("Aria-drawing", ext: "pdf"), animated: true)
      },
      workspaceAction("Материалы и покрытия", subtitle: "S-Stone и S-Sense в студии", icon: "circle.lefthalf.filled") {
        [weak self] in self.map { MaterialStudioController.present(from: $0) }
      },
    ], spacing: 10), inset: 20)
  }
  private func documentsBlock(_ p: CatalogProduct) -> UIView {
    let docs = p.documents.filter { !$0.isOption }
    let model = StudioForm.all.first { $0.product.id == p.id }
    var rows: [UIView] = [label(p.name, 20, .regular, serif: true)]
    if let model {
      // The finish is judged on the form itself, in the execution the object uses.
      let line = ProjectStore.shared.current.lines.first { $0.productId == p.id }
      let finish = line?.variant.flatMap { StudioFinish(material: $0.material, finish: $0.finish) }
      let ral = line?.colour.ral
      rows.append(ActionButton("Отделка на изделии", icon: "circle.lefthalf.filled", prominent: true) { [weak self] in
        self.map { MaterialStudioController.present(form: model, finish: finish, ral: ral, from: $0) }
      })
      rows.append(ActionButton("3D-модель · \(ModelViewing.subtitle)", icon: "cube.transparent") { [weak self] in
        self.map { ModelViewing.open(model, from: $0) }
      })
      rows.append(ActionButton("Поделиться USDZ", icon: "square.and.arrow.up") { [weak self] in
        self.map { ModelViewing.share(model, from: $0) }
      })
    }
    for d in docs.prefix(6) { rows.append(documentButton(d)) }
    if docs.isEmpty && model == nil {
      rows.append(label("Документы в карточке сайта не опубликованы — запросите у менеджера.", 13, .regular, Palette.muted))
    }
    return workspaceCard(rows)
  }
  private func documentButton(_ d: CatalogDocument) -> UIView {
    documentLink(d) { [weak self] url in self?.present(SFSafariViewController(url: url), animated: true) }
  }
}

func documentLink(_ d: CatalogDocument, open: @escaping (URL) -> Void) -> UIView {
  let kinds = ["passport": "Паспорт", "drawing": "Чертёж", "model": "Модель", "presentation": "Презентация"]
  let b = ActionButton("\(kinds[d.kind].map { "\($0) · " } ?? "")\(d.label)", icon: "doc.text") {
    guard let url = URL(string: d.url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? d.url) else { return }
    open(url)
  }
  b.accessibilityHint = "Откроется на сайте Salini"
  return b
}

final class ProductDocumentsController: ScrollController {
  private let product: CatalogProduct
  init(_ product: CatalogProduct) {
    self.product = product
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = product.name
    navigationItem.largeTitleDisplayMode = .never
    var rows: [UIView] = [eyebrow("ДОКУМЕНТЫ КАРТОЧКИ"), label(product.name, 30, .regular, serif: true)]
    if let model = StudioForm.all.first(where: { $0.product.id == product.id }) {
      rows.append(ActionButton("3D-модель · \(ModelViewing.subtitle)", icon: "cube.transparent", prominent: true) { [weak self] in
        self.map { ModelViewing.open(model, from: $0) }
      })
      rows.append(ActionButton("Поделиться USDZ", icon: "square.and.arrow.up") { [weak self] in
        self.map { ModelViewing.share(model, from: $0) }
      })
    }
    let docs = product.documents.filter { !$0.isOption }
    for d in docs { rows.append(documentLink(d) { [weak self] url in self?.present(SFSafariViewController(url: url), animated: true) }) }
    if docs.isEmpty { rows.append(label("В карточке сайта документы не опубликованы — запросите у менеджера.", 14, .regular, Palette.muted)) }
    rows.append(ActionButton("Открыть карточку", icon: "arrow.up.right") { [weak self] in
      guard let self else { return }
      self.navigationController?.pushViewController(CatalogProductController(self.product), animated: true)
    })
    add(stack(rows, spacing: 12))
  }
}

final class StockController: ScrollController {
  private var warehouse = 0
  private let results = UIStackView()
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Наличие"
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
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Поставки", image: UIImage(systemName: "truck.box"),
      primaryAction: UIAction { [weak self] _ in
        self?.navigationController?.pushViewController(PartnerOrdersController(), animated: true)
      })
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
            if let tabs = self?.tabBarController, (tabs.viewControllers?.count ?? 0) > MainTabs.toolTabIndex + 1 {
              tabs.selectedIndex = MainTabs.toolTabIndex
            } else {
              self?.navigationController?.pushViewController(StockController(), animated: true)
            }
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
