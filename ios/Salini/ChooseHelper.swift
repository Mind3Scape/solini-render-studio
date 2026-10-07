import UIKit

// MARK: - Rule-based selection («Помочь выбрать»)

/// Transparent rules over catalogue data: every result says why it fits. No scoring model,
/// no invented popularity; an unknown price never passes a budget.
enum ChooseHelper {
  enum Kind: String, CaseIterable {
    case freestanding, builtIn, corner, wallBath, washbasin, furniture, mirror
    var title: String {
      switch self {
      case .freestanding: return "Отдельностоящая ванна"
      case .builtIn: return "Встраиваемая ванна"
      case .corner: return "Угловая ванна"
      case .wallBath: return "Пристенная ванна"
      case .washbasin: return "Раковина"
      case .furniture: return "Мебель"
      case .mirror: return "Зеркало"
      }
    }
    var category: String {
      switch self {
      case .freestanding, .builtIn, .corner, .wallBath: return "Ванны"
      case .washbasin: return "Раковины"
      case .furniture: return "Мебель"
      case .mirror: return "Зеркала"
      }
    }
    var subcategory: String? {
      switch self {
      case .freestanding: return "Отдельностоящие"
      case .builtIn: return "Встраиваемые"
      case .corner: return "Угловые"
      case .wallBath: return "Пристенные"
      default: return nil
      }
    }
    var usesLength: Bool { category == "Ванны" || self == .washbasin }
  }
  struct Answers: Equatable {
    var kind: Kind = .freestanding
    /// Available length in mm; nil — any.
    var maxLength: Double?
    var finish: CatalogFilter.Finish?
    /// Budget for one item; nil — any.
    var budget: Int?
    var inStockOnly = false
  }
  struct Match {
    let product: CatalogProduct
    let variant: CatalogVariant?
    let reasons: [String]
  }

  static func recommend(_ a: Answers, catalog: Catalog = .shared) -> [Match] {
    var filter = CatalogFilter()
    filter.category = a.kind.category
    if let sub = a.kind.subcategory { filter.subcategories = [sub] }
    if let f = a.finish { filter.finishes = [f] }
    filter.maxPrice = a.budget
    filter.inStockOnly = a.inStockOnly
    var out: [(Match, Double, Int)] = []
    for p in catalog.products where filter.matches(p) {
      // A range (corner models) fits by its smallest length.
      let length: Double?
      switch p.dimensions.length {
      case .value(let v)?: length = v
      case .range(let lo, _)?: length = lo
      case nil: length = nil
      }
      if a.kind.usesLength, let max = a.maxLength {
        guard let length, length <= max else { continue }
      }
      let allowed = filter.allowedVariants(p)
      let variant = allowed.min { ($0.price ?? .max) < ($1.price ?? .max) }
      var reasons: [String] = []
      if a.kind.usesLength, let max = a.maxLength, let length {
        reasons.append("длина \(formatMM(length)) ≤ \(formatMM(max)) мм")
      } else if let d = p.dimensions.text {
        reasons.append(d)
      }
      if let f = a.finish { reasons.append("есть исполнение \(f.title)") }
      if let budget = a.budget, let price = variant?.price {
        reasons.append("\(rubles(price)) — в бюджете \(rubles(budget))")
      } else if let price = variant?.price {
        reasons.append("от \(rubles(price))")
      } else {
        reasons.append("цена по запросу")
      }
      if a.inStockOnly, let n = p.availability.stockQuantity { reasons.append("на складе: \(n) шт.") }
      out.append((Match(product: p, variant: variant, reasons: reasons), length ?? 0, variant?.price ?? .max))
    }
    // Closest to the available length first, then lower price; stable by name.
    return out.sorted {
      if a.maxLength != nil, $0.1 != $1.1 { return $0.1 > $1.1 }
      if $0.2 != $1.2 { return $0.2 < $1.2 }
      return $0.0.product.name < $1.0.product.name
    }.map(\.0)
  }
}

// MARK: - Screen

final class ChooseController: ScrollController {
  private var answers = ChooseHelper.Answers()
  private var matches: [ChooseHelper.Match] = []
  private var shown = 12
  private let results = UIStackView()
  private let count = eyebrow("")
  private let lengthValue = label("", 15, .semibold)
  private let budgetValue = label("", 15, .semibold)
  private let lengthRow = UIStackView()

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Помочь выбрать"
    navigationItem.largeTitleDisplayMode = .never
    if presentingViewController != nil {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }
    add(stack([
      label("Для вашего пространства", 30, .regular, serif: true),
      label("Укажите размер, поверхность и бюджет — подберём подходящие изделия.", 15, .regular, Palette.muted),
    ], spacing: 10))

    var kind = UIButton.Configuration.filled()
    kind.baseBackgroundColor = .white
    kind.baseForegroundColor = Palette.ink
    kind.cornerStyle = .large
    let kindButton = UIButton(configuration: kind)
    kindButton.showsMenuAsPrimaryAction = true
    kindButton.changesSelectionAsPrimaryAction = true
    kindButton.menu = UIMenu(children: ChooseHelper.Kind.allCases.map { k in
      UIAction(title: k.title, state: k == answers.kind ? .on : .off) { [weak self] _ in
        self?.answers.kind = k
        self?.update()
      }
    })
    kindButton.accessibilityIdentifier = "choose.kind"

    let length = UISlider()
    length.minimumValue = 400
    length.maximumValue = 2100
    length.value = 2100
    length.tintColor = Palette.ink
    length.accessibilityLabel = "Доступная длина"
    length.addAction(UIAction { [weak self, weak length] _ in
      guard let v = length?.value else { return }
      self?.answers.maxLength = v >= 2090 ? nil : (Double(v) / 10).rounded() * 10
      self?.update()
    }, for: .valueChanged)
    lengthRow.axis = .vertical
    lengthRow.spacing = 6
    lengthRow.addArrangedSubview(row("2 · Доступная длина", lengthValue))
    lengthRow.addArrangedSubview(length)

    // A menu rather than four segments: full names stay readable at every text size.
    var finishConf = UIButton.Configuration.filled()
    finishConf.baseBackgroundColor = .white
    finishConf.baseForegroundColor = Palette.ink
    finishConf.cornerStyle = .large
    let finish = UIButton(configuration: finishConf)
    finish.showsMenuAsPrimaryAction = true
    finish.changesSelectionAsPrimaryAction = true
    let options: [(String, CatalogFilter.Finish?)] = [("Любое", nil)] + CatalogFilter.Finish.allCases.map { ($0.title, $0) }
    finish.menu = UIMenu(children: options.map { option in
      UIAction(title: option.0, state: option.1 == nil ? .on : .off) { [weak self] _ in
        self?.answers.finish = option.1
        self?.update()
      }
    })
    finish.accessibilityLabel = "Материал и покрытие"

    let budget = UISlider()
    budget.minimumValue = 20000
    budget.maximumValue = 1_500_000
    budget.value = 1_500_000
    budget.tintColor = Palette.ink
    budget.accessibilityLabel = "Бюджет на изделие"
    budget.addAction(UIAction { [weak self, weak budget] _ in
      guard let v = budget?.value else { return }
      self?.answers.budget = v >= 1_490_000 ? nil : Int((v / 10000).rounded()) * 10000
      self?.update()
    }, for: .valueChanged)

    let stock = UISwitch()
    stock.onTintColor = Palette.ink
    stock.accessibilityLabel = "Только в наличии на складе"
    stock.addAction(UIAction { [weak self, weak stock] _ in
      self?.answers.inStockOnly = stock?.isOn ?? false
      self?.update()
    }, for: .valueChanged)

    add(stack([
      question("1 · Что ищете", kindButton),
      lengthRow,
      question("3 · Материал и покрытие", finish),
      stack([row("4 · Бюджет на изделие", budgetValue), budget], spacing: 6),
      row("5 · Нужно сразу, со склада", stock),
    ], spacing: 22))
    kindButton.configuration?.title = answers.kind.title
    results.axis = .vertical
    results.spacing = 12
    add(stack([count, results], spacing: 12))
    update()
  }

  private func question(_ title: String, _ control: UIView) -> UIView {
    stack([label(title.uppercased(), 10, .semibold, Palette.muted), control], spacing: 8)
  }
  private func row(_ title: String, _ value: UIView) -> UIView {
    let r = stack([label(title, 15, .regular, Palette.muted), UIView(), value], axis: .horizontal, spacing: 12)
    r.alignment = .center
    return r
  }

  private func update() {
    lengthRow.isHidden = !answers.kind.usesLength
    lengthValue.text = answers.maxLength.map { "до \(formatMM($0)) мм" } ?? "любая"
    budgetValue.text = answers.budget.map { "до \(rubles($0))" } ?? "любой"
    matches = ChooseHelper.recommend(answers)
    shown = 12
    count.text = matches.isEmpty
      ? "НЕТ ПОДХОДЯЩИХ ИЗДЕЛИЙ — ПОПРОБУЙТЕ ДРУГОЙ РАЗМЕР ИЛИ БЮДЖЕТ"
      : "ПОДХОДИТ: \(matches.count) \(plural(matches.count, "ИЗДЕЛИЕ", "ИЗДЕЛИЯ", "ИЗДЕЛИЙ"))"
    renderResults()
  }
  /// The whole matching list is reachable: 12 at a time, the answers stay as chosen.
  private func renderResults() {
    results.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for m in matches.prefix(shown) { results.addArrangedSubview(card(m)) }
    let rest = matches.count - shown
    if rest > 0 {
      let more = ActionButton("Показать ещё \(min(12, rest)) из \(rest)", icon: "chevron.down") { [weak self] in
        self?.shown += 12
        self?.renderResults()
      }
      more.accessibilityIdentifier = "choose.more"
      results.addArrangedSubview(more)
    }
    if answers.budget != nil {
      results.addArrangedSubview(label("Изделия с ценой по запросу при заданном бюджете не показываем.", 12, .regular, Palette.muted))
    }
  }

  private func card(_ m: ChooseHelper.Match) -> UIView {
    let pic = UIImageView()
    pic.contentMode = .scaleAspectFit
    pic.backgroundColor = UIColor(hex: 0xEDEEF0)
    pic.rounded(14)
    pic.widthAnchor.constraint(equalToConstant: 88).isActive = true
    pic.height(88)
    CatalogImages.shared.image(for: m.product, maxPixel: 300) { pic.image = $0 }
    let texts = stack([
      label(m.product.name, 20, .regular, serif: true),
      label(m.variant?.title ?? "", 12, .regular, Palette.muted),
      label(m.reasons.map { "✓ \($0)" }.joined(separator: "\n"), 13, .medium),
    ], spacing: 4)
    let top = stack([pic, texts], axis: .horizontal, spacing: 14)
    top.alignment = .center
    let card = top.inset(14)
    card.backgroundColor = .white
    card.rounded(18)
    card.isAccessibilityElement = true
    card.accessibilityTraits = .button
    card.accessibilityLabel = "\(m.product.name). \(m.variant?.title ?? ""). Почему подходит: \(m.reasons.joined(separator: ", "))"
    card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open(_:))))
    card.accessibilityIdentifier = "choose.\(m.product.id)|\(m.variant?.key ?? "")"
    return card
  }
  @objc private func open(_ g: UITapGestureRecognizer) {
    guard let id = g.view?.accessibilityIdentifier?.dropFirst("choose.".count) else { return }
    let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard let p = Catalog.shared.product(parts[0]) else { return }
    navigationController?.pushViewController(
      CatalogProductController(p, variantKey: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil), animated: true)
  }
}
