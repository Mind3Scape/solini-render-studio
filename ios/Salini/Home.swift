import UIKit

final class HomeController: ScrollController {
  private var lastRole: Audience?
  override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
    render()
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let role = DemoStore.shared.role
    let logo = UIImageView(
      image: UIImage(named: "salini-logo.png")?.withRenderingMode(.alwaysTemplate))
    logo.tintColor = Palette.ink
    logo.contentMode = .scaleAspectFit
    logo.widthAnchor.constraint(equalToConstant: 88).isActive = true
    logo.height(36)
    logo.accessibilityLabel = "Salini"
    logo.isAccessibilityElement = true
    let search = ActionButton("", icon: role == .partner ? "shippingbox" : "magnifyingglass") {
      [weak self] in self?.tabBarController?.selectedIndex = 1
    }
    search.accessibilityLabel = role == .partner ? "Наличие на складе" : "Открыть каталог и файлы"
    search.widthAnchor.constraint(equalToConstant: 46).isActive = true
    let profile = ActionButton("", icon: "person.crop.circle") { [weak self] in
      self?.tabBarController?.selectedIndex = 3
    }
    profile.accessibilityLabel = "Профиль"
    profile.widthAnchor.constraint(equalToConstant: 46).isActive = true
    let top = stack([logo, UIView(), search, profile], axis: .horizontal, spacing: 10)
    top.alignment = .center
    add(top, inset: 22)
    let modes = stack([], axis: .horizontal, spacing: 4)
    modes.distribution = .fillEqually
    for audience in Audience.allCases {
      let b = UIButton(type: .system)
      var c = UIButton.Configuration.plain()
      c.title = audience.title
      c.baseForegroundColor = role == audience ? .white : Palette.ink
      c.background.backgroundColor = role == audience ? Palette.ink : .clear
      c.background.cornerRadius = 19
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 12, weight: .semibold)
        return a
      }
      c.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4)
      b.configuration = c
      b.accessibilityIdentifier = "audience.\(audience.rawValue)"
      b.accessibilityTraits = role == audience ? [.button, .selected] : [.button]
      b.addAction(
        UIAction { [weak self] _ in
          guard let self, DemoStore.shared.role != audience else { return }
          DemoStore.shared.role = audience
          (self.tabBarController as? MainTabs)?.applyAudience()
          UISelectionFeedbackGenerator().selectionChanged()
          UIView.transition(with: self.content, duration: 0.3, options: .transitionCrossDissolve) {
            self.render()
          }
          self.scroll.setContentOffset(
            CGPoint(x: 0, y: -self.scroll.adjustedContentInset.top), animated: false)
        }, for: .touchUpInside)
      modes.addArrangedSubview(b)
    }
    let modeWrap = modes.inset(4)
    modeWrap.backgroundColor = UIColor(hex: 0xEDEEF1)
    modeWrap.rounded(25)
    let wrapper = UIView()
    wrapper.pin(modeWrap, inset: 0)
    section(wrapper, top: 0, bottom: 14, inset: 18)
    switch role {
    case .home: buyer()
    case .atelier: designer()
    case .partner: partner()
    }
    lastRole = role
  }
  private func buyer() {
    add(
      hero(
        image: "aria", title: "Дизайн, который\nчувствуешь.", foot: "Aria",
        detail: "Скульптура повседневности", height: 390
      ) { [weak self] in
        if let p = Product.all.first(where: { $0.id == "aria" }) { self?.showProduct(p) }
      }, inset: 16)
    let actions = stack(
      [
        ActionButton("Подобрать", icon: "slider.horizontal.3", prominent: true) { [weak self] in
          self?.navigationController?.pushViewController(FinderController(), animated: true)
        },
        ActionButton("Сравнить", icon: "rectangle.split.2x1") { [weak self] in
          self?.navigationController?.pushViewController(CompareController(), animated: true)
        },
      ], axis: .horizontal, spacing: 10)
    actions.distribution = .fillEqually
    add(actions, inset: 20)
    add(
      workspaceAction(
        "Почувствуйте объём", subtitle: "Вращайте оригинальную 3D-модель Greca",
        icon: "cube.transparent"
      ) { [weak self] in self?.present(ObjectViewerController(), animated: true) }, inset: 20)
    let title = stack(
      [
        label("Избранные формы", 27, .semibold), UIView(),
        label("01 — 04", 10, .medium, Palette.muted),
      ], axis: .horizontal)
    title.alignment = .center
    add(title)
    add(
      horizontal(
        Product.all.map { p in ProductTile(product: p) { [weak self] in self?.showProduct(p) } },
        width: 260, height: 345), inset: 0)
    add(
      hero(
        image: "interior", title: "В деталях —\nхарактер.", foot: "Внутри интерьера",
        detail: "Коллекция Opera", height: 320
      ) { [weak self] in self?.sheet(InspirationController()) }, inset: 20)
    add(
      workspaceAction(
        "Материя Salini", subtitle: "Разница, которую хочется ощутить",
        icon: "circle.lefthalf.filled"
      ) { [weak self] in self?.sheet(MaterialsController()) }, inset: 20)
  }
  private func designer() {
    section(
      stack(
        [
          eyebrow("РАБОЧЕЕ ПРОСТРАНСТВО ДИЗАЙНЕРА"),
          label("Идеи становятся\nпроектами.", 30, .semibold),
        ], spacing: 12))
    let store = DemoStore.shared
    let pic = photo("interior", height: 150)
    pic.rounded(20)
    let count = store.items.reduce(0) { $0 + $1.quantity }
    section(
      workspaceCard([
        pic, eyebrow("ТЕКУЩИЙ ПРОЕКТ"), label(store.projectName, 26, .semibold),
        label(
          "\(count) \(plural(count, "изделие", "изделия", "изделий")) · \(rubles(store.total))", 14,
          .medium, Palette.muted),
        ActionButton("Продолжить комплектацию", icon: "arrow.up.right", prominent: true) {
          [weak self] in self?.tabBarController?.selectedIndex = 2
        },
      ]))
    section(
      stack(
        [
          eyebrow("ИНСТРУМЕНТЫ ПРОЕКТА"),
          workspaceAction(
            "Добавить изделие", subtitle: "Выбрать форму и исполнение", icon: "plus.square"
          ) { [weak self] in
            self?.navigationController?.pushViewController(CatalogController(), animated: true)
          },
          workspaceAction(
            "3D и технические файлы", subtitle: "USDZ, чертежи и размеры", icon: "cube"
          ) { [weak self] in self?.tabBarController?.selectedIndex = 1 },
          workspaceAction(
            "Спецификация проекта", subtitle: "Количество, состав, стоимость и PDF",
            icon: "doc.richtext"
          ) { [weak self] in self?.tabBarController?.selectedIndex = 2 },
        ], spacing: 14))
    section(
      workspaceCard([
        eyebrow("ПАЛИТРА ПРОЕКТА"), label("Сначала — ощущение.", 26, .medium), swatches(),
        ActionButton("Изучить поверхности", icon: "arrow.up.right") { [weak self] in
          self?.sheet(MaterialsController())
        },
      ]))
  }
  private func partner() {
    let orders = PartnerStore.shared.orders
    let reserved = orders.filter { !$0.scheduled }.count
    let scheduled = orders.filter { $0.scheduled }.count
    section(
      stack(
        [eyebrow("ПАРТНЁРСКИЙ КАБИНЕТ · ДЕМО"), label("Всё для вашего салона.", 27, .semibold)],
        spacing: 10))
    let metrics = stack(
      [
        metric("В РЕЗЕРВЕ", "\(reserved)", plural(reserved, "заказ", "заказа", "заказов")),
        metric("К ОТГРУЗКЕ", "\(scheduled)", plural(scheduled, "поставка", "поставки", "поставок")),
      ], axis: .horizontal, spacing: 12)
    metrics.distribution = .fillEqually
    section(metrics)
    let actions = stack(
      [
        ActionButton("Наличие", icon: "shippingbox", prominent: true) { [weak self] in
          self?.tabBarController?.selectedIndex = 1
        },
        ActionButton("Поставки", icon: "truck.box") { [weak self] in
          self?.tabBarController?.selectedIndex = 2
        },
      ], axis: .horizontal, spacing: 10)
    actions.distribution = .fillEqually
    section(actions)
    if let last = orders.first {
      section(
        workspaceCard([
          eyebrow("ПОСЛЕДНИЙ РЕЗЕРВ"),
          label("\(last.id) · \(last.product?.name ?? "Salini")", 23, .semibold),
          label(
            "\(last.quantity) шт. · \(PartnerStore.warehouses[last.warehouse]) · \(last.scheduled ? "К отгрузке" : "В резерве")",
            13, .regular, Palette.muted),
          ActionButton("Открыть поставку", icon: "arrow.up.right") { [weak self] in
            self?.navigationController?.pushViewController(
              PartnerOrderController(last.id), animated: true)
          },
        ]))
    } else {
      section(
        workspaceAction(
          "Создать первый резерв", subtitle: "Выберите склад и количество изделий",
          icon: "plus.square"
        ) { [weak self] in self?.tabBarController?.selectedIndex = 1 })
    }
    section(
      workspaceAction(
        "Документы для экспозиции", subtitle: "3D-модели, размеры и чертежи", icon: "doc.text"
      ) { [weak self] in
        self?.navigationController?.pushViewController(ResourcesController(), animated: true)
      })
    let pic = photo("production", height: 170)
    pic.rounded(24)
    section(
      stack([pic, label("За каждым изделием —\nточность производства.", 25, .medium)], spacing: 16))
  }
  private func section(_ v: UIView, top: CGFloat = 10, bottom: CGFloat = 10, inset: CGFloat = 20) {
    let wrap = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    wrap.addSubview(v)
    NSLayoutConstraint.activate([
      v.topAnchor.constraint(equalTo: wrap.topAnchor, constant: top),
      v.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -bottom),
      v.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: inset),
      v.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -inset),
    ])
    add(wrap, inset: 0)
  }
  private func metric(_ name: String, _ value: String, _ detail: String) -> UIView {
    workspaceCard(
      [eyebrow(name), label(value, 38, .medium), label(detail, 12, .regular, Palette.muted)],
      spacing: 7)
  }
  private func swatches() -> UIView {
    let shades: [(String, UIColor)] = [("S-Stone", UIColor(hex: 0xE9E7E2)), ("S-Sense", .white)]
    let row = stack(
      shades.map { name, color in
        let chip = UIView()
        chip.height(72)
        chip.rounded(18)
        chip.backgroundColor = color
        chip.layer.borderWidth = 0.7
        chip.layer.borderColor = Palette.line.cgColor
        return stack([chip, label(name, 12, .medium)], spacing: 8)
      }, axis: .horizontal, spacing: 14)
    row.distribution = .fillEqually
    return row
  }
  private func hero(
    image: String, title: String, foot: String, detail: String, height: CGFloat,
    action: @escaping () -> Void
  ) -> UIView {
    let hero = UIView()
    hero.height(height)
    hero.rounded(30)
    hero.pin(photo(image))
    hero.pin(
      GradientView(
        colors: [.black.withAlphaComponent(0.22), .clear, .black.withAlphaComponent(0.7)],
        locations: [0, 0.4, 1]))
    let top = stack(
      [
        eyebrow("SALINI COLLECTION", color: .white.withAlphaComponent(0.8)),
        label(title, 31, .medium, .white),
      ], spacing: 13)
    let b = ActionButton("", icon: "arrow.up.right", action: action)
    b.configuration?.baseForegroundColor = .white
    b.accessibilityLabel = "Открыть \(foot)"
    b.widthAnchor.constraint(equalToConstant: 54).isActive = true
    let bottom = stack(
      [
        stack(
          [
            label(foot, 32, .medium, .white),
            label(detail, 12, .regular, .white.withAlphaComponent(0.75)),
          ], spacing: 5), UIView(), b,
      ], axis: .horizontal)
    bottom.alignment = .center
    for sub in [top, bottom] {
      sub.translatesAutoresizingMaskIntoConstraints = false
      hero.addSubview(sub)
      sub.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 24).isActive = true
      sub.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -22).isActive = true
    }
    top.topAnchor.constraint(equalTo: hero.topAnchor, constant: 25).isActive = true
    bottom.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -24).isActive = true
    return hero
  }
}

final class ProductTile: UIView {
  init(product: Product, action: @escaping () -> Void) {
    super.init(frame: .zero)
    backgroundColor = .white
    rounded(24)
    let image = photo(product.image, height: 235)
    let info = stack(
      [
        eyebrow(product.category.uppercased()), label(product.name, 27, .regular),
        label("от " + rubles(product.price), 13, .medium, Palette.muted),
      ], spacing: 6
    ).inset(18)
    pin(stack([image, info], spacing: 0))
    let tap = UIButton()
    tap.accessibilityLabel = "\(product.name), от \(rubles(product.price))"
    tap.accessibilityIdentifier = "product.\(product.id)"
    pin(tap)
    tap.addAction(UIAction { _ in action() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
}
final class InspirationController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "В деталях — характер"
    add(photo("interior", height: 380), inset: 0)
    add(
      stack([
        eyebrow("ИНТЕРЬЕР SALINI"), label("Классика\nв деталях.", 34, .medium),
        label(
          "Камень, тёплый металл и архитектурная симметрия. Интерьер из галереи Salini.", 16,
          .regular, Palette.muted),
        ActionButton("Сохранить Opera Top в проект", icon: "plus", prominent: true) { [weak self] in
          if let p = Product.all.first(where: { $0.id == "opera-top" }) {
            DemoStore.shared.add(p, stone: false)
            self?.message("Сохранено", "Opera Top добавлена в ваш проект.")
          }
        },
      ]))
  }
}
final class MaterialsController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Материя Salini"
    add(photo("stone", height: 230), inset: 0)
    add(
      stack(
        [
          eyebrow("КАМЕНЬ. СВЕТ. ПРИКОСНОВЕНИЕ."), label("Природа формы.", 34, .medium),
          label("S-Stone", 25, .medium),
          label(
            "Матовая поверхность и выразительная тактильность. Спокойное рассеивание света подчёркивает геометрию изделия.",
            16, .regular, Palette.muted), line(), label("S-Sense", 25, .medium),
          label(
            "Глянцевая поверхность с глубокими отражениями. Один силуэт приобретает другой характер.",
            16, .regular, Palette.muted),
          label(
            "Доступность материалов и отделок зависит от выбранной модели.", 13, .regular,
            Palette.muted),
        ], spacing: 18))
  }
}
