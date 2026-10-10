import SafariServices
import UIKit

/// Editorial copy is condensed from Salini's own pages, reviewed 10 October 2026.
/// Product navigation always uses the bundled catalogue, never the four prototype products.
/// Sources: /, /about-company/, /collection/luce/, /collection/oriente/, /collection/opera/.
enum HomeEditorialContent {
  struct Category {
    let title: String
    let productID: String
    var product: CatalogProduct? { Catalog.shared.products.first { $0.id == productID } }
  }
  static let categories = [
    Category(title: "Ванны", productID: "1364"),
    Category(title: "Раковины", productID: "1186"),
    Category(title: "Мебель", productID: "20381"),
    Category(title: "Зеркала", productID: "3709"),
    Category(title: "Душевые поддоны", productID: "1320"),
    Category(title: "Столешницы", productID: "37549"),
  ]
  struct Collection {
    let id: String
    let name: String
    let query: String
    let image: String
    let headline: String
    let summary: String
    let focus: CGFloat
    var source: String { "https://salini-srl.com/collection/\(id)/" }
  }
  static let collections = [
    Collection(id: "luce", name: "Luce", query: "Луче", image: "luce",
               headline: "Свет обретает форму.",
               summary: "Плавные линии и парящий силуэт. Дизайн Майка Шилова. Red Dot 2023.", focus: 0.67),
    Collection(id: "oriente", name: "Oriente", query: "Ориенте", image: "oriente",
               headline: "Свой ритуал тишины.",
               summary: "Глубокая ванна офуро и раковины, вдохновлённые эстетикой Востока. Майк Шилов.", focus: 0.35),
  ]
  static let warranty = "10 лет на сантехнику из минерального литья"
  static let brandSource = "https://salini-srl.com/about-company/"
  static let interiorSource = "https://salini-srl.com/collection/opera/"

  static func catalog(category: String? = nil, query: String? = nil) -> CatalogController {
    let controller = CatalogController()
    controller.initialCategory = category
    controller.initialQuery = query
    return controller
  }
}

/// A photograph has a permanent safety border and a tiny continuous drift. Copy and controls
/// never move. Elapsed time is retained while offscreen; viewport callbacks cannot restart it.
final class HomeAmbientPhoto: UIView {
  private let imageView = UIImageView()
  private var displayLink: CADisplayLink?
  private var previousTimestamp: CFTimeInterval?
  private(set) var elapsed: CFTimeInterval = 0
  private(set) var isPlaying = false
  private var observers: [NSObjectProtocol] = []
  private let focus: CGFloat
  var active = false { didSet { if active != oldValue { updatePlayback() } } }
  private var foreground = UIApplication.shared.applicationState == .active
  private var reducedMotion = UIAccessibility.isReduceMotionEnabled

  init(_ image: String, focus: CGFloat = 0.5) {
    self.focus = focus
    super.init(frame: .zero)
    imageView.image = UIImage(named: image + ".jpg") ?? UIImage(named: image)
    configure()
  }
  init(product: CatalogProduct) {
    focus = 0.5
    super.init(frame: .zero)
    configure()
    CatalogImages.shared.image(for: product, maxPixel: 640) { [weak self] image in
      self?.imageView.image = image
      self?.setNeedsLayout()
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit {
    displayLink?.invalidate()
    observers.forEach(NotificationCenter.default.removeObserver)
  }
  private func configure() {
    clipsToBounds = true
    backgroundColor = UIColor(hex: 0xE9E7E4)
    isAccessibilityElement = false
    imageView.isAccessibilityElement = false
    imageView.contentMode = .scaleAspectFill
    addSubview(imageView)
    let center = NotificationCenter.default
    for event in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
      observers.append(center.addObserver(forName: event, object: nil, queue: .main) {
        [weak self] _ in MainActor.assumeIsolated { self?.foreground = false; self?.updatePlayback() }
      })
    }
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.foreground = true; self?.updatePlayback() }
    })
    observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated {
        self?.reducedMotion = UIAccessibility.isReduceMotionEnabled
        self?.updatePlayback()
      }
    })
  }
  override func didMoveToWindow() { super.didMoveToWindow(); updatePlayback() }
  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.transform = .identity
    imageView.frame = Self.imageFrame(size: imageView.image?.size ?? bounds.size, in: bounds, focus: focus)
    applyMotion()
  }
  /// The fixed inset is larger than the greatest displacement, including on compact cards.
  static func imageFrame(size: CGSize, in bounds: CGRect, focus: CGFloat) -> CGRect {
    guard size.width > 0, size.height > 0 else { return bounds.insetBy(dx: -8, dy: -8) }
    let overscan = bounds.insetBy(dx: -8, dy: -8)
    let scale = max(overscan.width / size.width, overscan.height / size.height) * 1.015
    let width = size.width * scale, height = size.height * scale
    return CGRect(x: overscan.minX - (width - overscan.width) * max(0, min(1, focus)),
                  y: bounds.midY - height / 2, width: width, height: height)
  }
  static func displacement(at elapsed: CFTimeInterval) -> CGPoint {
    CGPoint(x: sin(elapsed * .pi * 2 / 23) * 3.5,
            y: sin(elapsed * .pi * 2 / 29) * 4.5)
  }
  private func applyMotion() {
    let point = reducedMotion ? .zero : Self.displacement(at: elapsed)
    imageView.transform = CGAffineTransform(translationX: point.x, y: point.y)
  }
  private func updatePlayback() {
    let shouldPlay = active && window != nil && foreground && !reducedMotion
    if isPlaying != shouldPlay {
      isPlaying = shouldPlay
      previousTimestamp = nil
      if shouldPlay {
        let target = HomePhotoTickTarget(self)
        let link = CADisplayLink(target: target, selector: #selector(HomePhotoTickTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
      } else {
        displayLink?.invalidate()
        displayLink = nil
      }
    }
    applyMotion()
  }
  fileprivate func tick(_ link: CADisplayLink) {
    if let previousTimestamp { advance(by: link.timestamp - previousTimestamp) }
    previousTimestamp = link.timestamp
  }
  func advance(by interval: CFTimeInterval) {
    guard isPlaying else { return }
    elapsed += max(0, min(0.1, interval))
    applyMotion()
  }
  func updateVisibility(in viewport: UIScrollView, visible: Bool) {
    var intersection = convert(bounds, to: viewport).intersection(viewport.bounds)
    var ancestor = superview
    while let parent = ancestor, parent !== viewport {
      if parent.clipsToBounds { intersection = intersection.intersection(parent.convert(parent.bounds, to: viewport)) }
      ancestor = parent.superview
    }
    active = visible && !intersection.isNull && intersection.width > 24 && intersection.height > 24
  }
}
private final class HomePhotoTickTarget {
  weak var owner: HomeAmbientPhoto?
  init(_ owner: HomeAmbientPhoto) { self.owner = owner }
  @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

/// Keep each action intact on a narrow phone or with accessibility text sizes.
private final class HomeActionRow: UIStackView {
  override func layoutSubviews() {
    let vertical = bounds.width < 340 || traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    let desired: NSLayoutConstraint.Axis = vertical ? .vertical : .horizontal
    if axis != desired { axis = desired }
    super.layoutSubviews()
  }
}

/// One rail with intrinsic-height content; large text grows the entire rail instead of clipping.
final class HomeEditorialRail: UIScrollView, UIScrollViewDelegate {
  var onScroll: (() -> Void)?
  init(_ views: [UIView], width: CGFloat) {
    super.init(frame: .zero)
    delegate = self
    showsHorizontalScrollIndicator = false
    isDirectionalLockEnabled = true
    let row = stack(views, axis: .horizontal, spacing: 14)
    row.alignment = .fill
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 20),
      row.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -20),
      row.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
      row.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
    ])
    for view in views { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
  }
  required init?(coder: NSCoder) { fatalError() }
  func scrollViewDidScroll(_ scrollView: UIScrollView) { onScroll?() }
}

func homeTextButton(_ title: String, color: UIColor = Palette.ink, identifier: String? = nil,
                    action: @escaping () -> Void) -> UIButton {
  var configuration = UIButton.Configuration.plain()
  configuration.title = title
  configuration.image = UIImage(systemName: "arrow.up.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
  configuration.imagePlacement = .trailing
  configuration.imagePadding = 12
  configuration.baseForegroundColor = color
  configuration.contentInsets = .init(top: 12, leading: 0, bottom: 12, trailing: 0)
  configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
    var attributes = $0
    attributes.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: 14, weight: .semibold), maximumPointSize: 19)
    return attributes
  }
  let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
  button.contentHorizontalAlignment = .leading
  button.accessibilityIdentifier = identifier
  button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
  return button
}

/// Assembles the buyer's magazine. Its host owns navigation and preserves the views on return.
final class HomeEditorial {
  private weak var host: UIViewController?
  private(set) var photos: [HomeAmbientPhoto] = []
  var onScroll: (() -> Void)?
  init(host: UIViewController) { self.host = host }
  private func image(_ name: String, focus: CGFloat = 0.5) -> HomeAmbientPhoto {
    let photo = HomeAmbientPhoto(name, focus: focus)
    photos.append(photo)
    return photo
  }
  private func push(_ controller: UIViewController) { host?.navigationController?.pushViewController(controller, animated: true) }
  func catalog(category: String? = nil, query: String? = nil) {
    push(HomeEditorialContent.catalog(category: category, query: query))
  }
  func introduction() -> UIView {
    let body = stack([
      eyebrow("L’ANIMA DELL’ACQUA"),
      label("Ваша ванная.\nВаш характер.", 35, .regular),
      label("Итальянский взгляд на форму, тактильный камень и пространство для себя.", 16, .regular, Palette.muted),
    ], spacing: 11)
    body.accessibilityIdentifier = "home.introduction"
    return body
  }
  func categories() -> UIView {
    let cards = HomeEditorialContent.categories.compactMap { category -> UIView? in
      guard let product = category.product else { return nil }
      let photo = HomeAmbientPhoto(product: product)
      photo.height(122)
      photo.rounded(16)
      photos.append(photo)
      let caption = stack([label(category.title, 14, .medium), UIView(), symbol("arrow.up.right", size: 11)], axis: .horizontal, spacing: 4)
      caption.alignment = .top
      let card = stack([photo, caption], spacing: 10)
      let tap = UIButton()
      tap.accessibilityLabel = "\(category.title). Открыть каталог"
      tap.accessibilityIdentifier = "home.category.\(category.productID)"
      tap.addAction(UIAction { [weak self] _ in self?.catalog(category: category.title) }, for: .touchUpInside)
      card.pin(tap)
      card.accessibilityElements = [tap]
      return card
    }
    let rail = HomeEditorialRail(cards, width: 145)
    rail.onScroll = { [weak self] in self?.onScroll?() }
    return rail
  }
  func selection() -> UIView {
    let choose = ActionButton("Подобрать", icon: "slider.horizontal.3", prominent: true) { [weak self] in
      self?.push(ChooseController())
    }
    choose.accessibilityIdentifier = "home.choose"
    let compare = ActionButton("Сравнить", icon: "rectangle.split.2x1") { [weak self] in
      self?.push(CompareController())
    }
    compare.accessibilityIdentifier = "home.compare"
    for button in [choose, compare] {
      button.configuration?.contentInsets = .init(top: 17, leading: 12, bottom: 17, trailing: 12)
      button.configuration?.imagePadding = 7
    }
    let controls = HomeActionRow(arrangedSubviews: [choose, compare])
    controls.spacing = 10
    controls.distribution = .fillEqually
    return stack([
      line(), label("От вдохновения —\nк вашей форме.", 27, .medium),
      label("Подберите размеры и исполнение. Сохраните подходящие изделия в проект.", 14, .regular, Palette.muted),
      controls,
      homeTextButton("Рассмотреть Greca в 3D", identifier: "home.greca3d") { [weak self] in
        self?.host?.present(ObjectViewerController(), animated: true)
      },
    ], spacing: 16)
  }
  func colour() -> UIView {
    let cover = image("aria-red", focus: 0.35)
    cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 0.72).isActive = true
    let head = stack([
      eyebrow("ЦВЕТ КАК ПРОДОЛЖЕНИЕ ВАС", color: UIColor(hex: 0x7F5C4C)),
      label("За пределами\nбелого.", 37, .regular, UIColor(hex: 0x38241C)),
    ], spacing: 12).inset(UIEdgeInsets(top: 26, left: 24, bottom: 23, right: 24))
    let swatches = stack([], axis: .horizontal, spacing: 5)
    for code in ["1015", "3012", "3005", "6005", "7016"] {
      guard let colour = RALPalette.colour(code) else { continue }
      let swatch = UIButton(type: .custom)
      swatch.widthAnchor.constraint(equalToConstant: 44).isActive = true
      swatch.height(44)
      let dot = UIView()
      dot.isUserInteractionEnabled = false
      dot.backgroundColor = colour.colour
      dot.layer.cornerRadius = 14
      swatch.pin(dot, inset: 8)
      swatch.accessibilityLabel = "Примерить \(colour.name), RAL \(code), в студии"
      swatch.accessibilityIdentifier = "home.colour.\(code)"
      swatch.addAction(UIAction { [weak self] _ in self?.openColour(colour) }, for: .touchUpInside)
      swatches.addArrangedSubview(swatch)
    }
    swatches.addArrangedSubview(UIView())
    let body = stack([
      label("Спокойный нюанс или смелый акцент — найдите своё сочетание формы и цвета.", 16, .regular, UIColor(hex: 0x624C40)),
      swatches,
      homeTextButton("Примерить палитру в 3D", color: UIColor(hex: 0x38241C), identifier: "home.colour.studio") { [weak self] in self?.openColour(nil) },
    ], spacing: 10).inset(UIEdgeInsets(top: 20, left: 24, bottom: 17, right: 24))
    let card = stack([head, cover, body], spacing: 0)
    card.backgroundColor = UIColor(hex: 0xEDE4DA)
    card.rounded(26)
    card.accessibilityIdentifier = "home.colour"
    return card
  }
  private func openColour(_ colour: RALColour?) {
    guard let host else { return }
    MaterialStudioController.present(form: StudioForm.noemi, finish: .stoneMatte, ral: colour, from: host)
  }
  func collections() -> UIView {
    let cards = HomeEditorialContent.collections.map { collection -> UIView in
      let photo = image(collection.image, focus: collection.focus)
      photo.height(258)
      photo.rounded(22)
      let name = stack([label(collection.name, 31, .regular), UIView(), symbol("arrow.up.right", size: 17)], axis: .horizontal)
      name.alignment = .center
      let body = stack([
        photo, name, label(collection.headline, 16, .medium),
        label(collection.summary, 13, .regular, Palette.muted),
      ], spacing: 10)
      let tap = UIButton()
      tap.accessibilityLabel = "\(collection.name). \(collection.summary) Открыть коллекцию"
      tap.accessibilityIdentifier = "home.collection.\(collection.id)"
      tap.addAction(UIAction { [weak self] _ in self?.catalog(query: collection.query) }, for: .touchUpInside)
      body.pin(tap)
      body.accessibilityElements = [tap]
      return body
    }
    let rail = HomeEditorialRail(cards, width: 282)
    rail.onScroll = { [weak self] in self?.onScroll?() }
    return rail
  }
  func production() -> UIView {
    let photo = image("production", focus: 0.64)
    photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: 0.68).isActive = true
    photo.rounded(22)
    let headline = stack([eyebrow("ЗА КАЖДОЙ ФОРМОЙ — ЛЮДИ"), label("Точность технологии.\nТепло рук.", 32, .regular)], spacing: 12)
    let body = stack([
      headline, photo,
      label("Бренд, основанный в Италии. Собственное производство в России. От минерального литья до ручной финишной обработки.", 16, .regular, Palette.muted),
      homeTextButton("Из чего складывается Salini", identifier: "home.story.brand") { [weak self] in
        self?.push(HomeStoryController(.brand))
      },
    ], spacing: 17)
    return body
  }
  func interior() -> UIView {
    let card = UIView()
    card.rounded(26)
    let cover = image("interior", focus: 0.55)
    card.pin(cover)
    card.pin(GradientView(colors: [.clear, .black.withAlphaComponent(0.15), .black.withAlphaComponent(0.75)], locations: [0, 0.4, 1]))
    let button = homeTextButton("Рассмотреть интерьер", color: .white, identifier: "home.story.interior") { [weak self] in
      self?.push(HomeStoryController(.interior))
    }
    let body = stack([
      eyebrow("SALINI В ИНТЕРЬЕРЕ", color: .white.withAlphaComponent(0.8)),
      label("Классика\nв новом ритме.", 34, .regular, .white),
      label("Opera · архитектура деталей", 14, .regular, .white.withAlphaComponent(0.85)), button,
    ], spacing: 12)
    body.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(body)
    NSLayoutConstraint.activate([
      card.heightAnchor.constraint(greaterThanOrEqualToConstant: 415),
      body.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 160),
      body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
      body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
    ])
    return card
  }
  func service() -> UIView {
    let warranty = stack([
      eyebrow("УВЕРЕННОСТЬ В ВЫБОРЕ"),
      label("10 лет", 49, .light),
      label("Гарантия на сантехнику\nиз минерального литья", 17, .medium),
      label("При правильной установке и эксплуатации. Условия для других категорий — в разделе помощи.", 13, .regular, Palette.muted),
      homeTextButton("Гарантия и уход", identifier: "home.help") { [weak self] in self?.push(HelpController()) },
    ], spacing: 10)
    let showrooms = stack([
      line(),
      label("Познакомимся ближе?", 26, .regular),
      label("Увидеть оттенок при живом свете и почувствовать материал — в салоне рядом с вами.", 15, .regular, Palette.muted),
      ActionButton("Найти салон", icon: "mappin.and.ellipse", prominent: true) { [weak self] in self?.push(ShowroomsController()) },
    ], spacing: 16)
    showrooms.arrangedSubviews.last?.accessibilityIdentifier = "home.showrooms"
    return stack([warranty, showrooms], spacing: 27)
  }
  func footer() -> UIView {
    let wordmark = UIImageView(image: UIImage(named: "salini-logo.png")?.withRenderingMode(.alwaysTemplate))
    wordmark.tintColor = Palette.ink
    wordmark.contentMode = .scaleAspectFit
    wordmark.widthAnchor.constraint(equalToConstant: 82).isActive = true
    wordmark.height(30)
    let footer = stack([
      line(), wordmark,
      label("L’anima dell’acqua", 14, .regular, Palette.muted),
      homeTextButton("Официальный сайт", identifier: "home.website") { [weak self] in
        homeOpenSource("https://salini-srl.com/", from: self?.host)
      },
    ], spacing: 15)
    footer.alignment = .leading
    footer.arrangedSubviews.first?.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
    return footer
  }
}

final class HomeStoryController: ScrollController, UIScrollViewDelegate {
  enum Story { case brand, interior }
  let story: Story
  private var photos: [HomeAmbientPhoto] = []
  private var visible = false
  init(_ story: Story) { self.story = story; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    scroll.delegate = self
    switch story {
    case .brand: brand()
    case .interior: interior()
    }
  }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true; playback() }
  override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; playback() }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); playback() }
  func scrollViewDidScroll(_ scrollView: UIScrollView) { playback() }
  private func playback() { photos.forEach { $0.updateVisibility(in: scroll, visible: visible) } }
  private func picture(_ name: String, ratio: CGFloat) -> UIView {
    let image = HomeAmbientPhoto(name)
    photos.append(image)
    image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: ratio).isActive = true
    image.rounded(24)
    return image
  }
  private func brand() {
    title = "Мир Salini"
    add(stack([
      eyebrow("L’ANIMA DELL’ACQUA"), label("От идеи до\nприкосновения.", 39, .regular),
      label("Основанный в Италии бренд объединяет авторский дизайн и собственное производство в России.", 18, .regular, Palette.muted),
      picture("production", ratio: 0.78),
    ], spacing: 18))
    add(stack([
      eyebrow("ПРОИЗВОДСТВО"), label("Форма рождается\nв деталях.", 29, .regular),
      label("Минеральное литьё позволяет создавать цельные, бесшовные формы. После формования изделия проходят обработку и финишную доводку вручную.", 16, .regular, Palette.muted),
      label("Более 12 000 м² производства", 23, .medium),
      label("Собственная площадка объединяет технологические процессы и контроль качества. Партнёрская сеть Salini насчитывает более 700 партнёров.", 15, .regular, Palette.muted),
    ], spacing: 13))
    add(stack([
      line(), eyebrow("АВТОРЫ ФОРМЫ"), label("Два взгляда\nна пространство.", 30, .regular),
      designer("Майк Шилов", image: "designer-shilov", description: "Архитектурный и предметный дизайнер. В коллекциях Luce и Oriente исследует свет, плавность линий и личные ритуалы."),
      homeTextButton("Коллекция Luce", identifier: "home.story.luce") { [weak self] in self?.openCollection("Луче") },
      designer("Маурицио Мандзони", image: "designer-manzoni", description: "Итальянский дизайнер и архитектор. Создаёт предметы, мебель и интерьеры для международных брендов; один из авторов коллекций Salini."),
    ], spacing: 18))
    add(stack([
      line(), eyebrow("ПРИЗНАНИЕ"),
      label("Red Dot · 2023", 25, .regular),
      label("Международная награда за дизайн коллекции Luce.", 15, .regular, Palette.muted),
      label("BUILD · 2023", 25, .regular),
      label("Best Sanitary Ware Manufacturer — награда Salini в категории производителей сантехники.", 15, .regular, Palette.muted),
      label("Tagline · 2023", 25, .regular),
      label("Награда Tagline Awards, отмеченная среди достижений Salini.", 15, .regular, Palette.muted),
      homeTextButton("О компании на salini-srl.com") { [weak self] in homeOpenSource(HomeEditorialContent.brandSource, from: self) },
    ], spacing: 12))
  }
  private func designer(_ name: String, image: String, description: String) -> UIView {
    var views: [UIView] = []
    if UIImage(named: image + ".jpg") != nil { views.append(picture(image, ratio: 0.90)) }
    views.append(label(name, 24, .medium))
    views.append(label(description, 16, .regular, Palette.muted))
    return stack(views, spacing: 12)
  }
  private func interior() {
    title = "Opera в интерьере"
    add(stack([
      eyebrow("ИНТЕРЬЕР ИЗ ГАЛЕРЕИ SALINI"),
      label("Классика\nв новом ритме.", 39, .regular),
      label("Opera", 19, .medium, Palette.muted),
      picture("interior", ratio: 1.12),
      label("Скруглённые силуэты, пластика борта и ритм архитектурных линий. Коллекция Opera поддерживает классическую композицию ванной комнаты.", 17, .regular, Palette.muted),
    ], spacing: 18))
    add(stack([
      label("Соберите свою\nкомпозицию.", 29, .regular),
      label("Начните с ванны и раковины. В карточках изделий — размеры, варианты материала и возможность сохранить выбор в проект.", 16, .regular, Palette.muted),
      ActionButton("Изделия Opera", icon: "arrow.up.right", prominent: true) { [weak self] in self?.openCollection("Opera") },
      homeTextButton("Интерьеры и коллекция на сайте") { [weak self] in homeOpenSource(HomeEditorialContent.interiorSource, from: self) },
    ], spacing: 16))
  }
  private func openCollection(_ query: String) {
    navigationController?.pushViewController(HomeEditorialContent.catalog(query: query), animated: true)
  }
}

/// Source links stay in an in-app browser and are limited to the official HTTPS site.
private func homeOpenSource(_ address: String, from host: UIViewController?) {
  guard let host, let url = URL(string: address), url.scheme == "https", url.host == "salini-srl.com" else { return }
  host.present(SFSafariViewController(url: url), animated: true)
}
