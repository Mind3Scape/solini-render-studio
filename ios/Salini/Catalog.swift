import QuickLook
import SafariServices
import UIKit

// MARK: - Catalogue browser

/// All verified public cards, lazily laid out. Article queries open the matching execution.
final class CatalogController: UIViewController, UISearchResultsUpdating, UICollectionViewDelegate {
  enum Section: Int { case categories, products }
  /// Non-optional chip model: an Optional cell model crashes the ObjC-bridged registration.
  enum CategoryChip: Hashable {
    case all
    case named(String)
    var title: String {
      if case .named(let n) = self { return n }
      return "Все"
    }
    var category: String? {
      if case .named(let n) = self { return n }
      return nil
    }
  }
  enum Item: Hashable {
    case category(CategoryChip)
    case product(Catalog.Hit)
  }
  private var collection: UICollectionView!
  private var source: UICollectionViewDiffableDataSource<Section, Item>!
  private let searchController = UISearchController(searchResultsController: nil)
  private(set) var filter = CatalogFilter()
  private(set) var hits: [Catalog.Hit] = []
  private var filterButton: UIBarButtonItem!
  private let summary = UILabel()
  var initialCategory: String?
  /// Editorial entry points open the ordinary, editable catalogue search.
  var initialQuery: String?
  /// A filter to start from (for example from the material studio).
  var preset: CatalogFilter?
  var showsFavoritesOnly = false

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(false, animated: animated)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Navigation title only: the tab label is set by MainTabs and must not be overwritten.
    navigationItem.title = showsFavoritesOnly ? "Избранное" : "Каталог"
    view.backgroundColor = Palette.paper
    if let preset { filter = preset }
    if let initialCategory { filter.category = initialCategory }
    searchController.searchBar.text = initialQuery
    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "Название, коллекция или артикул"
    searchController.searchBar.accessibilityIdentifier = "catalog.search"
    searchController.searchBar.autocapitalizationType = .none
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    filterButton = UIBarButtonItem(
      image: UIImage(systemName: "line.3.horizontal.decrease"),
      primaryAction: UIAction { [weak self] _ in self?.showFilters() })
    filterButton.accessibilityLabel = "Фильтры"
    filterButton.accessibilityIdentifier = "catalog.filters"
    navigationItem.rightBarButtonItems = [filterButton, sortButton()]
    if navigationItem.leftBarButtonItem == nil {
      let choose = UIBarButtonItem(
        title: "Подбор", image: UIImage(systemName: "checklist"),
        primaryAction: UIAction { [weak self] _ in self?.navigationController?.pushViewController(ChooseController(), animated: true) })
      choose.accessibilityLabel = "Помочь выбрать"
      choose.accessibilityIdentifier = "catalog.choose"
      navigationItem.leftBarButtonItem = choose
      navigationItem.leftItemsSupplementBackButton = true
    }
    collection = UICollectionView(frame: .zero, collectionViewLayout: layout())
    collection.backgroundColor = .clear
    collection.delegate = self
    collection.keyboardDismissMode = .onDrag
    collection.accessibilityIdentifier = "catalog.grid"
    view.pin(collection)
    configureSource()
    reload()
    NotificationCenter.default.addObserver(
      self, selector: #selector(favoritesChanged), name: .demoChanged, object: nil)
  }
  @objc private func favoritesChanged() { if showsFavoritesOnly { reload() } }

  private func sortButton() -> UIBarButtonItem {
    let item = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), menu: sortMenu())
    item.accessibilityLabel = "Сортировка"
    return item
  }
  private func sortMenu() -> UIMenu {
    UIMenu(
      title: "Сортировка",
      children: CatalogFilter.Sort.allCases.map { sort in
        UIAction(title: sort.title, state: filter.sort == sort ? .on : .off) { [weak self] _ in
          guard let self else { return }
          self.filter.sort = sort
          self.navigationItem.rightBarButtonItems?.last?.menu = self.sortMenu()
          self.reload()
        }
      })
  }

  private func layout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { section, env in
      if section == Section.categories.rawValue {
        let item = NSCollectionLayoutItem(
          layoutSize: .init(widthDimension: .estimated(90), heightDimension: .absolute(44)))
        let group = NSCollectionLayoutGroup.horizontal(
          layoutSize: .init(widthDimension: .estimated(90), heightDimension: .absolute(44)), subitems: [item])
        let s = NSCollectionLayoutSection(group: group)
        s.orthogonalScrollingBehavior = .continuous
        s.interGroupSpacing = 8
        s.contentInsets = .init(top: 4, leading: 20, bottom: 6, trailing: 20)
        let header = NSCollectionLayoutBoundarySupplementaryItem(
          layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(30)),
          elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        header.contentInsets = .init(top: 0, leading: 20, bottom: 0, trailing: 20)
        s.boundarySupplementaryItems = [header]
        return s
      }
      let width = env.container.effectiveContentSize.width
      let columns = width > 900 ? 4 : width > 600 ? 3 : 2
      let item = NSCollectionLayoutItem(
        layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .estimated(300)))
      item.contentInsets = .init(top: 0, leading: 7, bottom: 0, trailing: 7)
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(300)),
        repeatingSubitem: item, count: columns)
      let s = NSCollectionLayoutSection(group: group)
      s.interGroupSpacing = 26
      s.contentInsets = .init(top: 14, leading: 13, bottom: 40, trailing: 13)
      return s
    }
  }

  private func configureSource() {
    let chip = UICollectionView.CellRegistration<ChipCell, CategoryChip> { [weak self] cell, _, chip in
      cell.configure(title: chip.title, selected: self?.filter.category == chip.category)
    }
    let product = UICollectionView.CellRegistration<CatalogCell, Catalog.Hit> { cell, _, hit in
      cell.configure(hit)
    }
    let header = UICollectionView.SupplementaryRegistration<SummaryHeader>(
      elementKind: UICollectionView.elementKindSectionHeader
    ) { [weak self] view, _, _ in
      view.label.attributedText = self?.summary.attributedText
    }
    source = UICollectionViewDiffableDataSource(collectionView: collection) { cv, index, item in
      switch item {
      case .category(let c): return cv.dequeueConfiguredReusableCell(using: chip, for: index, item: c)
      case .product(let h): return cv.dequeueConfiguredReusableCell(using: product, for: index, item: h)
      }
    }
    source.supplementaryViewProvider = { cv, kind, index in
      cv.dequeueConfiguredReusableSupplementary(using: header, for: index)
    }
  }

  func updateSearchResults(for searchController: UISearchController) { reload() }

  func apply(filter newFilter: CatalogFilter) {
    filter = newFilter
    reload()
  }
  func reload() {
    var f = filter
    if showsFavoritesOnly { f.favoritesOnly = DemoStore.shared.favorites }
    hits = Catalog.shared.search(searchController.searchBar.text ?? "", filter: f)
    let count = hits.count
    let text = "\(count) \(plural(count, "ИЗДЕЛИЕ", "ИЗДЕЛИЯ", "ИЗДЕЛИЙ")) · ДАННЫЕ SALINI-SRL.COM НА \(Catalog.shared.snapshotText)"
    summary.attributedText = NSAttributedString(
      string: text,
      attributes: [.kern: 1.6, .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: Palette.muted])
    filterButton?.image = UIImage(
      systemName: filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
    filterButton?.accessibilityValue = filter.activeCount > 0 ? "Активно: \(filter.activeCount)" : nil
    var snap = NSDiffableDataSourceSnapshot<Section, Item>()
    snap.appendSections([.categories, .products])
    snap.appendItems(
      ([CategoryChip.all] + Catalog.shared.categories.map(CategoryChip.named)).map(Item.category), toSection: .categories)
    snap.appendItems(hits.map(Item.product), toSection: .products)
    snap.reconfigureItems(snap.itemIdentifiers(inSection: .categories))
    source?.apply(snap, animatingDifferences: false)
    // The header is not part of the snapshot diff: refresh the count of the current results directly.
    for case let header as SummaryHeader in collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
      header.label.attributedText = summary.attributedText
    }
    if hits.isEmpty { showEmpty() } else { collection.backgroundView = nil }
  }
  private func showEmpty() {
    let text = stack(
      [
        label("Ничего не нашлось", 27, .regular, serif: true),
        label("Проверьте артикул или сбросьте фильтры.\nНапример: 1051201M, Ноэми, раковина 60.", 15, .regular, Palette.muted),
      ], spacing: 10)
    let wrapper = UIView()
    text.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(text)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 28),
      text.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -28),
      text.topAnchor.constraint(equalTo: wrapper.safeAreaLayoutGuide.topAnchor, constant: 170),
    ])
    collection.backgroundView = wrapper
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    switch source.itemIdentifier(for: indexPath) {
    case .category(let chip):
      filter.category = chip.category
      filter.subcategories = []
      reload()
    case .product(let hit):
      navigationController?.pushViewController(
        CatalogProductController(hit.product, variantKey: hit.variantKey), animated: true)
    case nil: break
    }
  }

  private func showFilters() {
    let sheet = CatalogFilterController(filter: filter) { [weak self] f in self?.apply(filter: f) }
    let nav = UINavigationController(rootViewController: sheet)
    nav.sheetPresentationController?.detents = [.medium(), .large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    present(nav, animated: true)
  }
}

final class SummaryHeader: UICollectionReusableView {
  let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    label.numberOfLines = 0
    pin(label, inset: 4)
  }
  required init?(coder: NSCoder) { fatalError() }
}

final class ChipCell: UICollectionViewCell {
  private let title = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.layer.cornerRadius = 22
    contentView.layer.cornerCurve = .continuous
    contentView.layer.borderWidth = 1
    title.font = .systemFont(ofSize: 15, weight: .medium)
    title.adjustsFontForContentSizeCategory = true
    title.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(title)
    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
      title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
      title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  func configure(title text: String, selected: Bool) {
    title.text = text
    title.textColor = selected ? .white : Palette.ink
    contentView.backgroundColor = selected ? Palette.ink : .white
    contentView.layer.borderColor = (selected ? Palette.ink : Palette.line).cgColor
    accessibilityLabel = text
    accessibilityTraits = selected ? [.button, .selected] : .button
  }
}

final class CatalogCell: UICollectionViewCell {
  private let picture = UIImageView()
  private let name = UILabel()
  private let detail = UILabel()
  private let price = UILabel()
  private let badge = UILabel()
  private var productId: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    picture.contentMode = .scaleAspectFill
    picture.backgroundColor = UIColor(hex: 0xECEDEF)
    picture.rounded(20)
    picture.translatesAutoresizingMaskIntoConstraints = false
    name.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
    name.numberOfLines = 2
    detail.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13))
    detail.textColor = Palette.muted
    detail.numberOfLines = 2
    price.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .medium))
    for l in [name, detail, price] { l.adjustsFontForContentSizeCategory = true }
    badge.font = .systemFont(ofSize: 11, weight: .semibold)
    badge.textColor = Palette.ink
    badge.backgroundColor = UIColor.white.withAlphaComponent(0.92)
    badge.textAlignment = .center
    badge.rounded(11)
    badge.isHidden = true
    badge.translatesAutoresizingMaskIntoConstraints = false
    let texts = stack([name, detail, price], spacing: 4)
    texts.setCustomSpacing(8, after: detail)
    texts.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(picture)
    contentView.addSubview(texts)
    picture.addSubview(badge)
    NSLayoutConstraint.activate([
      picture.topAnchor.constraint(equalTo: contentView.topAnchor),
      picture.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      picture.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      picture.heightAnchor.constraint(equalTo: picture.widthAnchor, multiplier: 1.12),
      texts.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: 12),
      texts.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
      texts.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
      texts.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      badge.topAnchor.constraint(equalTo: picture.topAnchor, constant: 10),
      badge.leadingAnchor.constraint(equalTo: picture.leadingAnchor, constant: 10),
      badge.heightAnchor.constraint(equalToConstant: 22),
      badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  func configure(_ hit: Catalog.Hit) {
    let p = hit.product
    productId = p.id
    name.text = p.name
    let variant = hit.variantKey.flatMap { p.variant(key: $0) }
    detail.text = [variant?.sku.map { "Арт. \($0)" } ?? p.subtitle, p.dimensions.text].compactMap { $0 }.joined(separator: " · ")
    price.text = variant.map { $0.price.map(rubles) ?? "Цена по запросу" } ?? p.priceText
    badge.text = p.model != nil ? "  3D  " : nil
    badge.isHidden = p.model == nil
    picture.image = nil
    CatalogImages.shared.image(for: p, maxPixel: 700) { [weak self] image in
      guard self?.productId == p.id else { return }
      self?.picture.image = image
    }
    accessibilityLabel = [p.name, detail.text, price.text].compactMap { $0 }.joined(separator: ", ")
    accessibilityIdentifier = "catalog.product.\(p.id)"
  }
}

// MARK: - Filters

final class CatalogFilterController: ScrollController {
  private var filter: CatalogFilter
  private let onApply: (CatalogFilter) -> Void
  private let showButton = ActionButton("Показать", prominent: true) {}
  init(filter: CatalogFilter, onApply: @escaping (CatalogFilter) -> Void) {
    self.filter = filter
    self.onApply = onApply
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Фильтры"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "Сбросить",
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        let keep = self.filter.category
        self.filter = CatalogFilter()
        self.filter.category = keep
        self.render()
      })
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    showButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.onApply(self.filter)
      self.dismiss(animated: true)
    }, for: .touchUpInside)
    showButton.accessibilityIdentifier = "catalog.filters.apply"
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let products = Catalog.shared.products.filter { filter.category == nil || $0.category == filter.category }
    let subs = Array(Set(products.compactMap(\.subcategory))).sorted()
    if !subs.isEmpty {
      add(group("Тип", chips(subs, selected: { self.filter.subcategories.contains($0) }) { s in
        if self.filter.subcategories.contains(s) { self.filter.subcategories.remove(s) } else { self.filter.subcategories.insert(s) }
      }))
    }
    add(group("Материал и поверхность", chips(CatalogFilter.Finish.allCases.map(\.title), selected: { t in
      self.filter.finishes.contains { $0.title == t }
    }) { t in
      guard let f = CatalogFilter.Finish.allCases.first(where: { $0.title == t }) else { return }
      if self.filter.finishes.contains(f) { self.filter.finishes.remove(f) } else { self.filter.finishes.insert(f) }
    }))
    let lengths: [(String, ClosedRange<Double>)] = [
      ("до 160 см", 0...1600), ("160–170 см", 1601...1700), ("171–180 см", 1701...1800), ("от 181 см", 1801...4000),
    ]
    add(group("Длина", chips(lengths.map(\.0), selected: { t in
      self.filter.lengthRange == lengths.first { $0.0 == t }?.1
    }) { t in
      let r = lengths.first { $0.0 == t }?.1
      self.filter.lengthRange = self.filter.lengthRange == r ? nil : r
    }))
    let prices: [(String, Int)] = [("до \(rubles(100_000))", 100_000), ("до \(rubles(250_000))", 250_000), ("до \(rubles(500_000))", 500_000)]
    add(group("Цена", chips(prices.map(\.0), selected: { t in
      self.filter.maxPrice == prices.first { $0.0 == t }?.1
    }) { t in
      let v = prices.first { $0.0 == t }?.1
      self.filter.maxPrice = self.filter.maxPrice == v ? nil : v
    }))
    add(toggle("В наличии по данным сайта", detail: "Остаток на \(Catalog.shared.snapshotText); при заказе уточняется", on: filter.inStockOnly) {
      self.filter.inStockOnly = $0
    })
    add(toggle("Есть официальная 3D-модель", detail: nil, on: filter.withModelOnly) { self.filter.withModelOnly = $0 })
    add(toggle("Показывать опции и кастомизацию", detail: "Вырезы, ниши, кронштейны и другие доработки", on: filter.includeOptions) {
      self.filter.includeOptions = $0
    })
    let count = Catalog.shared.search("", filter: filter).count
    showButton.configuration?.title = count == 0 ? "Нет подходящих изделий" : "Показать \(count)"
    showButton.isEnabled = count > 0
    add(showButton)
  }
  private func group(_ title: String, _ body: UIView) -> UIView {
    stack([eyebrow(title.uppercased()), body], spacing: 12)
  }
  private func chips(_ titles: [String], selected: @escaping (String) -> Bool, toggle: @escaping (String) -> Void) -> UIView {
    let flow = FlowView()
    for t in titles {
      let on = selected(t)
      var c = UIButton.Configuration.filled()
      c.title = t
      c.cornerStyle = .capsule
      c.baseBackgroundColor = on ? Palette.ink : .white
      c.baseForegroundColor = on ? .white : Palette.ink
      c.contentInsets = .init(top: 11, leading: 16, bottom: 11, trailing: 16)
      let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in
        toggle(t)
        self?.render()
      })
      b.layer.borderColor = Palette.line.cgColor
      b.layer.borderWidth = on ? 0 : 1
      b.layer.cornerRadius = 22
      b.accessibilityTraits = on ? [.button, .selected] : .button
      flow.addSubview(b)
    }
    return flow
  }
  private func toggle(_ title: String, detail: String?, on: Bool, change: @escaping (Bool) -> Void) -> UIView {
    let s = UISwitch()
    s.isOn = on
    s.onTintColor = Palette.ink
    s.addAction(UIAction { [weak self, weak s] _ in
      change(s?.isOn ?? false)
      self?.render()
    }, for: .valueChanged)
    s.accessibilityLabel = title
    let texts = stack([label(title, 16, .medium)] + (detail.map { [label($0, 12, .regular, Palette.muted)] } ?? []), spacing: 3)
    let row = stack([texts, s], axis: .horizontal, spacing: 12)
    row.alignment = .center
    return row
  }
}

/// Wrapping row of intrinsically sized subviews.
final class FlowView: UIView {
  var spacing: CGFloat = 8
  override func layoutSubviews() {
    super.layoutSubviews()
    var x: CGFloat = 0
    var y: CGFloat = 0
    var row: CGFloat = 0
    for v in subviews {
      let size = v.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
      if x > 0 && x + size.width > bounds.width {
        x = 0
        y += row + spacing
        row = 0
      }
      v.frame = CGRect(x: x, y: y, width: min(size.width, bounds.width), height: max(size.height, 44))
      x += size.width + spacing
      row = max(row, max(size.height, 44))
    }
    invalidateIntrinsicContentSize()
  }
  override var intrinsicContentSize: CGSize {
    guard bounds.width > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: 44) }
    var x: CGFloat = 0
    var y: CGFloat = 0
    var row: CGFloat = 0
    for v in subviews {
      let size = v.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
      if x > 0 && x + size.width > bounds.width {
        x = 0
        y += row + spacing
        row = 0
      }
      x += size.width + spacing
      row = max(row, max(size.height, 44))
    }
    return CGSize(width: UIView.noIntrinsicMetric, height: y + row)
  }
}

// MARK: - Product detail

final class CatalogProductController: ScrollController {
  let product: CatalogProduct
  private(set) var variantKey: String?
  private var quantity = 1
  private var colour: LineColour = .standard
  private let colourButton = UIButton(configuration: .plain())
  private var heart: UIBarButtonItem!
  private let picture = UIImageView()
  private let summary = UIStackView()
  private let variantsStack = UIStackView()
  private let quantityLabel = label("1 шт.", 17, .semibold)
  init(_ product: CatalogProduct, variantKey: String? = nil, colour: LineColour = .standard) {
    self.product = product
    self.variantKey = variantKey ?? product.variants.first?.key
    self.colour = colour
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  var variant: CatalogVariant? { product.variant(key: variantKey) }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = product.name
    navigationItem.largeTitleDisplayMode = .never
    heart = UIBarButtonItem(
      image: UIImage(systemName: "heart"),
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        DemoStore.shared.toggle(self.product.id)
        self.updateHeart()
      })
    heart.accessibilityIdentifier = "product.favorite"
    navigationItem.rightBarButtonItem = heart
    // The official photograph is shown whole: the frame takes the image's own proportions
    // (within 240–520 pt), so a wide photo does not float in a tall grey field.
    let frame = UIView()
    frame.backgroundColor = UIColor(hex: 0xEDEEF0)
    picture.contentMode = .scaleAspectFit
    picture.isAccessibilityElement = true
    picture.accessibilityLabel = "Фотография \(product.name), сайт Salini"
    frame.pin(picture)
    var ratio = frame.heightAnchor.constraint(equalTo: frame.widthAnchor, multiplier: 0.75)
    ratio.priority = .defaultHigh
    NSLayoutConstraint.activate([
      ratio, frame.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
      frame.heightAnchor.constraint(lessThanOrEqualToConstant: 520),
    ])
    add(frame, inset: 0)
    CatalogImages.shared.image(for: product, maxPixel: 1400) { [weak self, weak frame] image in
      guard let self, let frame else { return }
      self.picture.image = image
      guard let size = image?.size, size.width > 0, size.height > 0 else { return }
      ratio.isActive = false
      ratio = frame.heightAnchor.constraint(equalTo: frame.widthAnchor, multiplier: size.height / size.width)
      ratio.priority = .defaultHigh
      ratio.isActive = true
    }
    add(
      stack(
        [
          eyebrow([product.category, product.subcategory].compactMap { $0 }.joined(separator: " · ").uppercased()),
          label(product.name, 40, .regular, serif: true),
        ], spacing: 10))
    summary.axis = .vertical
    summary.spacing = 0
    variantsStack.axis = .vertical
    variantsStack.spacing = 10
    if product.variants.count > 1 {
      add(stack([eyebrow("ИСПОЛНЕНИЕ"), variantsStack], spacing: 12))
    }
    add(summary)
    add(quantityRow())
    if StudioForm.all.contains(where: { $0.product.id == product.id }) {
      let room = ActionButton("Примерить в комнате", icon: "viewfinder", prominent: false) { [weak self] in
        guard let self, let selected = RoomProduct.selection(self.product, variant: self.variant, colour: self.colour) else { return }
        RoomPlacementController.present(selected, from: self)
      }
      room.accessibilityIdentifier = "product.room"
      room.accessibilityHint = "Задняя камера, установка изделия в натуральную величину"
      add(room)
      let studio = ActionButton("Форма и материалы в 3D", icon: "cube.transparent") { [weak self] in
        guard let self, let selected = RoomProduct.selection(self.product, variant: self.variant, colour: self.colour) else { return }
        MaterialStudioController.present(form: selected.form, finish: selected.finish, ral: selected.ral, from: self)
      }
      studio.accessibilityIdentifier = "product.studio"
      add(studio)
    }
    let addButton = ActionButton("Добавить в проект", icon: "plus", prominent: true) { [weak self] in self?.addToProject() }
    addButton.accessibilityIdentifier = "product.add"
    add(addButton)
    if product.legacyId == "aria" {
      add(ActionButton("Технический чертёж Aria", icon: "ruler") { [weak self] in
        self?.present(DrawingController(), animated: true)
      })
    }
    let exhibiting = SupportData.dealers(exhibiting: product.id).count
    if exhibiting > 0 {
      let see = ActionButton("Где посмотреть вживую · \(exhibiting) \(plural(exhibiting, "салон", "салона", "салонов"))",
                             icon: "mappin.and.ellipse") { [weak self] in
        guard let self else { return }
        let list = ShowroomsController()
        list.productId = self.product.id
        self.navigationController?.pushViewController(list, animated: true)
      }
      see.accessibilityHint = "Экспозиция по данным сайта Salini; наличие уточняйте у салона"
      add(see)
    }
    let files = product.documents.filter { !$0.isOption }
    if !files.isEmpty {
      let docs = stack([eyebrow("ДОКУМЕНТЫ SALINI")], spacing: 4)
      for d in files { docs.addArrangedSubview(linkRow(d.label, url: d.url)) }
      add(docs)
    }
    let options = product.documents.filter(\.isOption)
    if !options.isEmpty {
      let opts = stack([eyebrow("ДОРАБОТКИ ПО ЗАПРОСУ")], spacing: 4)
      for d in options { opts.addArrangedSubview(linkRow(d.label, url: d.url)) }
      add(opts)
    }
    add(linkRow("Карточка на salini-srl.com", url: product.url))
    add(
      label(
        "Цены, артикулы и наличие — публичные данные сайта Salini на \(Catalog.shared.snapshotText). Это не оферта; заказ в приложении не отправляется.",
        12, .regular, Palette.muted))
    render()
    updateHeart()
  }

  private func render() {
    variantsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for v in product.variants {
      variantsStack.addArrangedSubview(variantRow(v))
    }
    summary.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let v = variant
    let custom = colour != .standard
    let base = v?.price.map(rubles)
    let price = label(
      v == nil ? "Выберите исполнение" : custom ? (base.map { "\($0) + цвет по запросу" } ?? "Цена по запросу") : base ?? "Цена по запросу",
      custom ? 24 : 30, .medium)
    price.accessibilityIdentifier = "product.price"
    summary.addArrangedSubview(price)
    summary.setCustomSpacing(14, after: price)
    var rows: [(String, String)] = []
    if let t = v?.title { rows.append(("Исполнение", t)) }
    rows.append(("Артикул", custom ? v?.customColourSku ?? "уточняется (цвет RAL)" : v?.sku ?? "уточняется у менеджера"))
    if custom { rows.append(("Цвет", colour.longTitle)) }
    if let d = product.dimensions.text { rows.append(("Габариты", d)) }
    if let o = product.depthToOverflow { rows.append(("Глубина до перелива", "\(Int(o)) мм")) }
    if let w = v?.weightKg {
      rows.append(("Вес", v?.packedWeightKg.map { "\(kg(w)) · с упаковкой \(kg($0))" } ?? kg(w)))
    }
    rows.append(("Наличие", custom ? "Под заказ · цвет RAL" : availabilityText()))
    for (title, value) in rows {
      let r = stack([label(title, 14, .regular, Palette.muted), label(value, 15, .medium)], axis: .horizontal, spacing: 12)
      r.distribution = .fillEqually
      r.alignment = .firstBaseline
      r.isAccessibilityElement = true
      r.accessibilityLabel = "\(title): \(value)"
      if title == "Артикул" { r.accessibilityIdentifier = "product.sku" }
      summary.addArrangedSubview(r.inset(0))
      summary.addArrangedSubview(spacer(10))
      summary.addArrangedSubview(line())
      summary.addArrangedSubview(spacer(10))
    }
    if custom {
      // One short footnote instead of a long value squeezed into the right column.
      let stock = product.availability.stockQuantity.flatMap { $0 > 0 ? "Склад \($0) шт. — по базовому исполнению на сайте. " : nil } ?? ""
      let note = label(
        "\(stock)Выбранный цвет RAL изготавливается под заказ: срок, наличие и надбавку за цвет подтверждает менеджер. Цена указана базовая.",
        12, .regular, Palette.muted)
      note.accessibilityIdentifier = "product.colourNote"
      summary.addArrangedSubview(note)
    }
  }
  private func availabilityText() -> String {
    let a = product.availability
    if let q = a.stockQuantity, q > 0 { return "\(q) шт. на складе по данным сайта" }
    if a.madeToOrder { return (a.text ?? "Под заказ") + " · срок подтверждает менеджер" }
    return "Уточняется у менеджера"
  }
  private func variantRow(_ v: CatalogVariant) -> UIView {
    let selected = v.key == variantKey
    var c = UIButton.Configuration.filled()
    c.baseBackgroundColor = selected ? Palette.ink : .white
    c.baseForegroundColor = selected ? .white : Palette.ink
    c.cornerStyle = .large
    c.title = v.title ?? "Базовое исполнение"
    c.subtitle = [v.price.map(rubles) ?? "Цена по запросу", v.sku.map { "арт. \($0)" }].compactMap { $0 }.joined(separator: " · ")
    c.titleAlignment = .leading
    c.contentInsets = .init(top: 14, leading: 18, bottom: 14, trailing: 18)
    c.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
    c.imagePlacement = .trailing
    let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in
      self?.variantKey = v.key
      self?.updateColour()
      self?.render()
    })
    b.contentHorizontalAlignment = .fill
    b.layer.borderColor = Palette.line.cgColor
    b.layer.borderWidth = selected ? 0 : 1
    b.layer.cornerRadius = 14
    b.accessibilityTraits = selected ? [.button, .selected] : .button
    b.accessibilityIdentifier = "product.variant.\(v.key)"
    return b
  }
  private func quantityRow() -> UIView {
    let stepper = UIStepper()
    stepper.minimumValue = 1
    stepper.maximumValue = 99
    stepper.value = 1
    stepper.accessibilityLabel = "Количество"
    stepper.addAction(UIAction { [weak self, weak stepper] _ in
      self?.quantity = Int(stepper?.value ?? 1)
      self?.quantityLabel.text = "\(self?.quantity ?? 1) шт."
    }, for: .valueChanged)
    let row = stack([label("Количество", 15, .regular, Palette.muted), UIView(), quantityLabel, stepper], axis: .horizontal, spacing: 12)
    row.alignment = .center
    colourButton.showsMenuAsPrimaryAction = true
    colourButton.configuration?.imagePlacement = .trailing
    colourButton.configuration?.imagePadding = 8
    colourButton.configuration?.baseForegroundColor = Palette.ink
    colourButton.configuration?.contentInsets = .init(top: 10, leading: 0, bottom: 10, trailing: 0)
    colourButton.accessibilityIdentifier = "product.colour"
    let colourRow = stack([label("Цвет", 15, .regular, Palette.muted), UIView(), colourButton], axis: .horizontal, spacing: 12)
    colourRow.alignment = .center
    updateColour()
    return stack([colourRow, row], spacing: 4)
  }
  private func updateColour() {
    let allowed = variant?.allowsRAL ?? false
    if !allowed { colour = .standard }
    colourButton.isEnabled = allowed
    colourButton.configuration?.title = allowed ? colour.longTitle : "Стандартный"
    colourButton.configuration?.image = allowed ? UIImage(systemName: "chevron.up.chevron.down") : nil
    colourButton.menu = colourMenu(selected: colour) { [weak self] c in
      self?.colour = c
      self?.updateColour()
      self?.render()
    }
    colourButton.accessibilityLabel = "Цвет: \(allowed ? colour.longTitle : "стандартный")"
  }
  private func linkRow(_ title: String, url: String) -> UIView {
    var c = UIButton.Configuration.plain()
    c.title = title
    c.image = UIImage(systemName: "arrow.up.right")
    c.imagePlacement = .trailing
    c.imagePadding = 8
    c.baseForegroundColor = Palette.ink
    c.contentInsets = .init(top: 12, leading: 0, bottom: 12, trailing: 0)
    let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in
      guard let u = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else { return }
      self?.present(SFSafariViewController(url: u), animated: true)
    })
    b.contentHorizontalAlignment = .leading
    return b
  }
  private func updateHeart() {
    let saved = DemoStore.shared.favorites.contains(product.id)
    heart.image = UIImage(systemName: saved ? "heart.fill" : "heart")
    heart.accessibilityLabel = saved ? "Убрать из избранного" : "В избранное"
  }
  private func addToProject() {
    guard ProjectStore.shared.add(product, variantKey: variantKey, quantity: quantity, colour: colour) != nil else {
      message("Выберите исполнение", "Без исполнения позицию нельзя добавить в проект.")
      return
    }
    let done = SavedController(product.name) { [weak self] in
      self?.tabBarController?.selectedIndex = MainTabs.projectTabIndex
    }
    sheet(done)
  }
}

func kg(_ value: Double) -> String {
  (value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")) + " кг"
}

final class SavedController: ScrollController {
  let name: String
  let onOpen: () -> Void
  init(_ name: String, onOpen: @escaping () -> Void) {
    self.name = name
    self.onOpen = onOpen
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "В проекте"
    let icon = symbol("checkmark.circle.fill", size: 45)
    icon.height(55)
    let project = ProjectStore.shared.current
    add(
      stack(
        [
          icon, label("\(name)\nв проекте.", 35, .regular, serif: true),
          label(
            "\(project.name) · \(project.lines.count) \(plural(project.lines.count, "позиция", "позиции", "позиций"))",
            15, .regular, Palette.muted),
          ActionButton("Открыть проект", icon: "arrow.up.right", prominent: true) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true, completion: self.onOpen)
          },
          ActionButton("Продолжить подбор", icon: "plus") { [weak self] in self?.dismiss(animated: true) },
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
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    Bundle.main.url(forResource: "Aria-drawing", withExtension: "pdf")! as NSURL
  }
}
