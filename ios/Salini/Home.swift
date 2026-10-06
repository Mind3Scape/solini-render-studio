import UIKit

final class HomeController: ScrollController {
  override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    scroll.contentInsetAdjustmentBehavior = .always
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let logo = UIImageView(
      image: UIImage(named: "salini-logo.png")?.withRenderingMode(.alwaysTemplate))
    logo.tintColor = Palette.ink
    logo.contentMode = .scaleAspectFit
    logo.widthAnchor.constraint(equalToConstant: 94).isActive = true
    logo.height(39)
    logo.accessibilityLabel = "Salini"
    logo.isAccessibilityElement = true
    let search = ActionButton("", icon: "magnifyingglass") { [weak self] in
      self?.tabBarController?.selectedIndex = 1
    }
    search.accessibilityLabel = "Поиск коллекций"
    search.widthAnchor.constraint(equalToConstant: 48).isActive = true
    let profile = ActionButton("", icon: "person.crop.circle") { [weak self] in
      self?.tabBarController?.selectedIndex = 3
    }
    profile.accessibilityLabel = "Профиль"
    profile.widthAnchor.constraint(equalToConstant: 48).isActive = true
    let top = stack([logo, UIView(), search, profile], axis: .horizontal, spacing: 10)
    top.alignment = .center
    add(top, inset: 22)
    let modes = UISegmentedControl(items: Audience.allCases.map(\.title))
    modes.selectedSegmentIndex = Audience.allCases.firstIndex(of: DemoStore.shared.role) ?? 0
    modes.height(40)
    modes.accessibilityIdentifier = "home.audience"
    modes.setTitleTextAttributes(
      [.font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
    modes.addAction(
      UIAction { [weak self, weak modes] _ in
        guard let self, let modes else { return }
        DemoStore.shared.role = Audience.allCases[modes.selectedSegmentIndex]
        UISelectionFeedbackGenerator().selectionChanged()
        self.render()
        self.scroll.setContentOffset(
          CGPoint(x: 0, y: -self.scroll.adjustedContentInset.top), animated: false)
      }, for: .valueChanged)
    let modeWrap = UIView()
    modes.translatesAutoresizingMaskIntoConstraints = false
    modeWrap.addSubview(modes)
    NSLayoutConstraint.activate([
      modes.leadingAnchor.constraint(equalTo: modeWrap.leadingAnchor, constant: 22),
      modes.trailingAnchor.constraint(equalTo: modeWrap.trailingAnchor, constant: -22),
      modes.topAnchor.constraint(equalTo: modeWrap.topAnchor),
      modes.bottomAnchor.constraint(equalTo: modeWrap.bottomAnchor, constant: -18),
    ])
    add(modeWrap, inset: 0)
    let role = DemoStore.shared.role
    let hero = UIView()
    hero.height(446)
    hero.rounded(30)
    hero.pin(photo("aria"))
    hero.pin(
      GradientView(
        colors: [.black.withAlphaComponent(0.32), .clear, .black.withAlphaComponent(0.73)],
        locations: [0, 0.46, 1]))
    let topCopy = stack(
      [
        eyebrow("SALINI COLLECTION", color: .white.withAlphaComponent(0.7)),
        label(
          role == .home
            ? "Дизайн, который\nчувствуешь."
            : role == .atelier
              ? "Пространство\nдля ваших идей." : "Новый взгляд\nна вашу экспозицию.", 32, .medium,
          .white),
      ], spacing: 12)
    topCopy.translatesAutoresizingMaskIntoConstraints = false
    hero.addSubview(topCopy)
    NSLayoutConstraint.activate([
      topCopy.topAnchor.constraint(equalTo: hero.topAnchor, constant: 26),
      topCopy.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 24),
      topCopy.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -24),
    ])
    let action = ActionButton("", icon: "arrow.up.right") { [weak self] in
      if let p = Product.all.first(where: { $0.id == "aria" }) { self?.showProduct(p) }
    }
    action.configuration?.baseForegroundColor = .white
    action.accessibilityLabel = "Открыть Aria"
    action.widthAnchor.constraint(equalToConstant: 54).isActive = true
    let bottom = stack(
      [
        stack(
          [
            label("Aria", 36, .regular, .white),
            label("Скульптура повседневности", 13, .regular, .white.withAlphaComponent(0.72)),
          ], spacing: 5), UIView(), action,
      ], axis: .horizontal, spacing: 8)
    bottom.alignment = .center
    bottom.translatesAutoresizingMaskIntoConstraints = false
    hero.addSubview(bottom)
    NSLayoutConstraint.activate([
      bottom.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 24),
      bottom.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -22),
      bottom.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -24),
    ])
    let heroWrap = UIView()
    hero.translatesAutoresizingMaskIntoConstraints = false
    heroWrap.addSubview(hero)
    NSLayoutConstraint.activate([
      hero.topAnchor.constraint(equalTo: heroWrap.topAnchor),
      hero.bottomAnchor.constraint(equalTo: heroWrap.bottomAnchor),
      hero.leadingAnchor.constraint(equalTo: heroWrap.leadingAnchor, constant: 16),
      hero.trailingAnchor.constraint(equalTo: heroWrap.trailingAnchor, constant: -16),
    ])
    add(heroWrap, inset: 0)
    let actionTitle =
      role == .home
      ? "Найти свою форму" : role == .atelier ? "Собрать проект" : "Подобрать коллекцию"
    let roleAction = ActionButton(actionTitle, icon: role == .home ? "square.grid.2x2" : "plus") {
      [weak self] in self?.tabBarController?.selectedIndex = role == .home ? 1 : 2
    }
    add(roleAction, inset: 22)
    if role != .home {
      let pro = stack(
        [
          eyebrow(role == .atelier ? "ДЛЯ ДИЗАЙНЕРОВ" : "ДЛЯ ПАРТНЁРОВ"),
          label(
            role == .atelier ? "От идеи к спецификации." : "Всё для вашего салона.", 26, .medium),
          label(
            role == .atelier
              ? "Изделия, материалы и технические файлы — в одном проекте."
              : "Кураторская подборка для экспозиции. Сохраняйте состав и делитесь спецификацией.",
            14, .regular, Palette.muted),
        ], spacing: 12
      ).inset(22)
      pro.backgroundColor = .white
      pro.rounded(25)
      add(pro, inset: 22)
    }
    let heading = stack(
      [
        label("Избранные формы", 27, .semibold), UIView(),
        label("01 — 04", 11, .medium, Palette.muted),
      ], axis: .horizontal, spacing: 8)
    heading.alignment = .center
    add(heading, inset: 24)
    let cards = Product.all.map { p -> UIView in
      ProductTile(product: p) { [weak self] in self?.showProduct(p) }
    }
    add(horizontal(cards, width: 260, height: 345), inset: 0)
    add(
      stack(
        [eyebrow("ВДОХНОВЕНИЕ SALINI"), label("Искусство\nличного пространства.", 31, .medium)],
        spacing: 12), inset: 28)
    let editorial = UIView()
    editorial.height(360)
    editorial.rounded(28)
    editorial.pin(photo("interior"))
    editorial.pin(GradientView(colors: [.clear, .black.withAlphaComponent(0.65)]))
    let text = stack(
      [
        label("Классика\nв деталях.", 32, .medium, .white),
        ActionButton("Внутри интерьера", icon: "arrow.up.right") { [weak self] in
          self?.sheet(InspirationController())
        },
      ], spacing: 18)
    (text.arrangedSubviews.last as? UIButton)?.configuration?.baseForegroundColor = .white
    text.translatesAutoresizingMaskIntoConstraints = false
    editorial.addSubview(text)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: editorial.leadingAnchor, constant: 24),
      text.trailingAnchor.constraint(equalTo: editorial.trailingAnchor, constant: -24),
      text.bottomAnchor.constraint(equalTo: editorial.bottomAnchor, constant: -24),
    ])
    add(editorial, inset: 22)
    add(
      stack(
        [
          eyebrow("МАТЕРИЯ SALINI"), label("Совершенство\nна ощупь.", 31, .medium),
          label(
            "Литьевой камень. Чистая геометрия.\nВнимание к каждой поверхности.", 15, .regular,
            Palette.muted),
          ActionButton("О материалах", icon: "circle.lefthalf.filled") { [weak self] in
            self?.sheet(MaterialsController())
          },
        ], spacing: 15))
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
