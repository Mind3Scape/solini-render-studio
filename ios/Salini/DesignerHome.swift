import SafariServices
import UIKit

// MARK: - The designer's path for one client object

/// A professional's path for one client object — object → products and finishes → technical
/// package → proposal — derived only from what the saved project actually holds. Nothing here is
/// a server state: no order, manager or sync is implied. The client name is optional throughout.
struct DesignerJourney: Equatable {
  enum Step: Int, CaseIterable {
    case object, selection, technical, proposal
    var title: String {
      switch self {
      case .object: return "Объект"
      case .selection: return "Изделия и отделки"
      case .technical: return "Технический пакет"
      case .proposal: return "Предложение клиенту"
      }
    }
  }
  /// `partial`: something real exists but not for everything (files for some products).
  enum State: Equatable { case done, partial, next, open }
  /// Official files actually available for the chosen products — never «done» with zero files.
  enum Files: Equatable { case none, byRequest, partial, available }
  enum Next: Equatable {
    case chooseProducts
    case resolveExecutions(Int)
    case prepareProposal
    case refreshProposal
    case reviewProposal
    var step: Step {
      switch self {
      case .chooseProducts, .resolveExecutions: return .selection
      case .prepareProposal, .refreshProposal, .reviewProposal: return .proposal
      }
    }
  }

  let project: SaliniProject
  /// Distinct resolvable products of the object, in line order.
  let products: [CatalogProduct]
  /// Products with an official USDZ in the app (opened in AR / the material studio).
  let withModel: Int
  /// Products whose site card publishes a drawing or a passport.
  let withDrawings: Int
  /// Products with at least one of the two.
  let withAnyFile: Int
  let unresolved: Int

  init(project: SaliniProject, models: Set<String> = Set(StudioForm.all.map(\.product.id))) {
    self.project = project
    var seen = Set<String>()
    products = project.lines.compactMap(\.product).filter { seen.insert($0.id).inserted }
    func drawings(_ p: CatalogProduct) -> Bool { p.documents.contains { $0.kind == "drawing" || $0.kind == "passport" } }
    withModel = products.filter { models.contains($0.id) }.count
    withDrawings = products.filter(drawings).count
    withAnyFile = products.filter { models.contains($0.id) || drawings($0) }.count
    unresolved = project.lines.filter(\.needsClarification).count
  }

  var isEmpty: Bool { project.lines.isEmpty }
  var hasClient: Bool { !project.client.trimmingCharacters(in: .whitespaces).isEmpty }

  var files: Files {
    if products.isEmpty { return .none }
    if withAnyFile == 0 { return .byRequest }
    return withAnyFile == products.count ? .available : .partial
  }

  /// The single most useful next action. The client is never a gate.
  var next: Next {
    if isEmpty { return .chooseProducts }
    if unresolved > 0 { return .resolveExecutions(unresolved) }
    if project.proposalAt == nil { return .prepareProposal }
    return project.proposalIsCurrent ? .reviewProposal : .refreshProposal
  }

  func state(_ step: Step) -> State {
    switch step {
    // The object exists as soon as it is created; the client is optional.
    case .object: return .done
    case .selection:
      if !isEmpty && unresolved == 0 { return .done }
      return next.step == .selection ? .next : .open
    case .technical:
      switch files {
      case .available: return .done
      case .partial: return .partial
      case .none, .byRequest: return .open
      }
    case .proposal:
      if project.proposalIsCurrent { return .done }
      return next.step == .proposal ? .next : .open
    }
  }

  /// One honest line per step for the progress list.
  func detail(_ step: Step) -> String {
    switch step {
    case .object:
      return hasClient ? "Для: \(project.client)" : "Клиент не указан — по желанию"
    case .selection:
      if isEmpty { return "Пока без изделий" }
      let n = project.lines.count
      let base = "\(n) \(plural(n, "позиция", "позиции", "позиций")) · \(project.pieces) шт."
      return unresolved > 0 ? base + " · \(unresolved) требуют уточнения" : base
    case .technical:
      let n = products.count
      switch files {
      case .none: return "Появится вместе с изделиями"
      case .byRequest: return "Официальных файлов для выбранных изделий нет — по запросу"
      case .partial, .available: return "3D: \(withModel) из \(n) · чертежи и паспорта: \(withDrawings) из \(n)"
      }
    case .proposal:
      guard let at = project.proposalAt else { return isEmpty ? "Без изделий не собирается" : "Ещё не собрано" }
      let date = DesignerJourney.dateText(at)
      return project.proposalIsCurrent ? "PDF собран \(date)" : "Собрано \(date) · объект с тех пор изменился"
    }
  }

  var nextTitle: String {
    switch next {
    case .chooseProducts: return "Подберите изделия для объекта"
    case .resolveExecutions(let n): return "Уточните исполнение у \(n) \(plural(n, "позиции", "позиций", "позиций"))"
    case .prepareProposal: return "Соберите предложение клиенту"
    case .refreshProposal: return "Обновите предложение"
    case .reviewProposal: return "Предложение актуально"
    }
  }
  var nextDetail: String {
    switch next {
    case .chooseProducts:
      return "Объект пуст. Начните с формы и исполнения — из каталога или с помощью подбора."
    case .resolveExecutions:
      return "Сохранённое исполнение больше не найдено в каталоге — выберите актуальное в спецификации."
    case .prepareProposal:
      return "Изделия, отделки и спецификация собираются в PDF на устройстве. Отправляете вы — вручную."
    case .refreshProposal:
      return "После последнего PDF в объекте что-то изменилось — соберите предложение заново."
    case .reviewProposal:
      return "Последний PDF соответствует объекту. Отправка — только вручную из просмотра."
    }
  }
  var nextButton: String {
    switch next {
    case .chooseProducts: return "Подобрать изделия"
    case .resolveExecutions: return "Открыть спецификацию"
    case .prepareProposal: return "Собрать PDF"
    case .refreshProposal: return "Пересобрать PDF"
    case .reviewProposal: return "Открыть PDF заново"
    }
  }

  static func dateText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "d MMMM, HH:mm"
    return f.string(from: date)
  }
}

// MARK: - Designer home views

/// Builds the designer's home. The first screen is the active object itself — a compact
/// architectural image with its name, and its one next action as a working button; the object
/// strip, the path, the chosen executions, the technical package and the club follow.
@MainActor
final class DesignerWorkspace {
  private weak var host: HomeController?
  init(host: HomeController) { self.host = host }

  private var store: ProjectStore { .shared }

  /// Entry: the active object over an official Salini photograph, and its next step.
  func entry() -> UIView {
    let journey = DesignerJourney(project: store.current)
    let p = journey.project
    let picture = UIView()
    picture.height(236)
    picture.clipsToBounds = true
    picture.pin(photo("greca-editorial"))
    picture.pin(
      GradientView(colors: [.black.withAlphaComponent(0.05), .black.withAlphaComponent(0.62)], locations: [0.25, 1]))
    var meta: [String] = []
    if journey.hasClient { meta.append(p.client) }
    meta.append(journey.isEmpty ? "без изделий" : "\(p.lines.count) \(plural(p.lines.count, "позиция", "позиции", "позиций"))")
    let identity = stack(
      [
        eyebrow("АКТИВНЫЙ ОБЪЕКТ", color: .white.withAlphaComponent(0.85)),
        label(p.name, 30, .regular, .white, serif: true),
        label(meta.joined(separator: " · "), 14, .medium, .white.withAlphaComponent(0.88)),
      ], spacing: 6)
    identity.translatesAutoresizingMaskIntoConstraints = false
    picture.addSubview(identity)
    NSLayoutConstraint.activate([
      identity.leadingAnchor.constraint(equalTo: picture.leadingAnchor, constant: 22),
      identity.trailingAnchor.constraint(equalTo: picture.trailingAnchor, constant: -22),
      identity.bottomAnchor.constraint(equalTo: picture.bottomAnchor, constant: -20),
    ])
    picture.isAccessibilityElement = true
    picture.accessibilityLabel = "Активный объект: \(p.name). \(meta.joined(separator: ", "))"
    picture.accessibilityIdentifier = "designer.entry.object"
    let cta = ActionButton(journey.nextButton, icon: "arrow.right", prominent: true) { [weak self] in self?.perform(journey.next) }
    cta.accessibilityIdentifier = "designer.cta"
    let next = stack(
      [
        eyebrow("СЛЕДУЮЩИЙ ШАГ"),
        label(journey.nextTitle, 20, .semibold),
        label(journey.nextDetail, 13, .regular, Palette.muted),
        cta,
      ], spacing: 9
    ).inset(UIEdgeInsets(top: 18, left: 20, bottom: 20, right: 20))
    next.accessibilityIdentifier = "designer.next"
    let card = stack([picture, next], spacing: 0)
    card.backgroundColor = .white
    card.rounded(28)
    card.accessibilityIdentifier = "designer.entry"
    return card
  }

  /// Saved objects as a horizontal strip; the active one is filled. «Новый объект» creates one.
  func objects() -> UIView {
    var chips: [UIView] = store.projects.map { p in
      let active = p.id == store.current.id
      var c = UIButton.Configuration.plain()
      c.title = p.name
      c.subtitle = p.lines.isEmpty ? "без изделий" : "\(p.lines.count) \(plural(p.lines.count, "позиция", "позиции", "позиций"))"
      c.baseForegroundColor = active ? .white : Palette.ink
      c.background.backgroundColor = active ? Palette.ink : .white
      c.background.cornerRadius = 20
      c.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        return a
      }
      c.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 11))
        return a
      }
      let b = UIButton(configuration: c)
      b.accessibilityIdentifier = "designer.object.\(p.id)"
      b.accessibilityTraits = active ? [.button, .selected] : [.button]
      b.addAction(UIAction { [weak self] _ in
        guard let self, self.store.current.id != p.id else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        self.store.currentId = p.id
        self.host?.reloadDesigner()
      }, for: .touchUpInside)
      return b
    }
    var add = UIButton.Configuration.plain()
    add.title = "Новый объект"
    add.image = UIImage(systemName: "plus")
    add.imagePadding = 8
    add.baseForegroundColor = Palette.ink
    add.background.strokeColor = Palette.line
    add.background.strokeWidth = 1
    add.background.cornerRadius = 20
    add.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
    let create = UIButton(configuration: add)
    create.accessibilityIdentifier = "designer.object.new"
    create.addAction(UIAction { [weak self] _ in self?.createObject() }, for: .touchUpInside)
    chips.append(create)
    let row = stack(chips, axis: .horizontal, spacing: 10)
    row.alignment = .fill
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    row.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
      row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
      // The strip is as tall as its tallest chip, so large text never clips a subtitle.
      scroll.frameLayoutGuide.heightAnchor.constraint(equalTo: row.heightAnchor),
    ])
    return stack([eyebrow("ОБЪЕКТЫ · \(store.projects.count)").inset(UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)), scroll], spacing: 12)
  }

  /// The active object's path in four steps, with identity and specification as side actions.
  func path() -> UIView {
    let journey = DesignerJourney(project: store.current)
    let list = stack(DesignerJourney.Step.allCases.map { stepRow($0, journey) }, spacing: 0)
    list.accessibilityIdentifier = "designer.journey"
    var head: [UIView] = [eyebrow("ПУТЬ ОБЪЕКТА")]
    if !journey.isEmpty {
      let p = journey.project
      let sum = rubles(p.knownTotal) + (p.isTotalComplete ? "" : " + по запросу")
      head.append(label("Базовая сумма по публичным ценам: \(sum)", 14, .medium, Palette.muted))
    }
    let identity = ActionButton("Объект и клиент", icon: "pencil") { [weak self] in self?.editObject() }
    identity.accessibilityIdentifier = "designer.edit"
    var actions: [UIView] = [identity]
    actions.append(ActionButton(journey.isEmpty ? "Каталог" : "Добавить изделие", icon: "plus") { [weak self] in self?.openCatalog() })
    let row = stack(actions, axis: .horizontal, spacing: 10)
    row.distribution = .fillEqually
    let spec = ActionButton("Спецификация объекта", icon: "list.bullet.rectangle") { [weak self] in self?.openSpecification() }
    return workspaceCard([stack(head, spacing: 8), list, row, spec], spacing: 16)
  }

  private func stepRow(_ step: DesignerJourney.Step, _ journey: DesignerJourney) -> UIView {
    let state = journey.state(step)
    let glyph: String
    switch state {
    case .done: glyph = "checkmark.circle.fill"
    case .partial: glyph = "circle.lefthalf.filled"
    case .next: glyph = "circle.circle"
    case .open: glyph = "circle"
    }
    let mark = UIImageView(image: UIImage(systemName: glyph))
    mark.tintColor = state == .open ? Palette.muted.withAlphaComponent(0.5) : Palette.ink
    mark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
    mark.setContentHuggingPriority(.required, for: .horizontal)
    let number = label(String(format: "%02d", step.rawValue + 1), 11, .semibold, Palette.muted)
    number.setContentHuggingPriority(.required, for: .horizontal)
    let texts = stack(
      [label(step.title, 16, state == .next ? .semibold : .regular, state == .open ? Palette.muted : Palette.ink),
       label(journey.detail(step), 12, .regular, Palette.muted)], spacing: 3)
    let row = stack([number, texts, UIView(), mark], axis: .horizontal, spacing: 14)
    row.alignment = .center
    let wrap = row.inset(UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0))
    wrap.isAccessibilityElement = true
    let spoken: String
    switch state {
    case .done: spoken = "выполнено"
    case .partial: spoken = "частично"
    case .next: spoken = "следующий шаг"
    case .open: spoken = "впереди"
    }
    wrap.accessibilityLabel = "Шаг \(step.rawValue + 1). \(step.title), \(spoken). \(journey.detail(step))"
    wrap.accessibilityIdentifier = "designer.step.\(step.rawValue)"
    return wrap
  }

  /// Every chosen execution and colour as its own row (one per project line): the finish is seen
  /// on the form itself in that colour, and the files are per product.
  func executions() -> UIView? {
    let lines = store.current.lines
    guard !lines.isEmpty else { return nil }
    var rows: [UIView] = [eyebrow("ИСПОЛНЕНИЯ ОБЪЕКТА · \(lines.count)")]
    for line in lines { rows.append(lineRow(line)) }
    return stack(rows, spacing: 12)
  }

  /// What the studio can show for a line: the form, the finish and the colour, or a precise reason.
  enum StudioView: Equatable {
    case open(StudioForm, StudioFinish, RALColour?)
    case noModel
    case finishNotModelled(String)
  }
  static func studioView(for line: ProjectLine) -> StudioView {
    guard let p = line.product, let form = StudioForm.all.first(where: { $0.product.id == p.id }) else { return .noModel }
    guard let v = line.variant, let finish = StudioFinish(material: v.material, finish: v.finish), form.finishes.contains(finish)
    else { return .finishNotModelled(line.variant?.title ?? "исполнение уточняется") }
    return .open(form, finish, line.colour.ral)
  }

  private func lineRow(_ line: ProjectLine) -> UIView {
    let image = UIImageView()
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    image.backgroundColor = UIColor(hex: 0xECEDEF)
    image.rounded(16)
    image.widthAnchor.constraint(equalToConstant: 84).isActive = true
    image.heightAnchor.constraint(equalToConstant: 100).isActive = true
    if let p = line.product { CatalogImages.shared.image(for: p, maxPixel: 300) { image.image = $0 } }
    let name = line.product?.name ?? "Изделие недоступно в каталоге"
    let execution = line.variant?.title ?? "исполнение требует уточнения"
    let texts: [UIView] = [
      label(name, 19, .regular, serif: true),
      label("\(execution) · \(line.colour.longTitle)", 12, .regular, Palette.muted),
      label("\(line.quantity) шт.", 12, .medium, Palette.muted),
    ]
    let info = stack(texts, spacing: 4)
    let top = stack([image, info], axis: .horizontal, spacing: 14)
    top.alignment = .top
    var actions: [UIView] = []
    switch Self.studioView(for: line) {
    case .open(let form, let finish, let ral):
      let colour = ral.map { "RAL \($0.code)" } ?? "базовый белый"
      let b = ActionButton("Отделка на изделии · \(colour)", icon: "circle.lefthalf.filled") { [weak self] in
        guard let host = self?.host else { return }
        MaterialStudioController.present(form: form, finish: finish, ral: ral, from: host)
      }
      b.accessibilityIdentifier = "designer.line.studio.\(line.id)"
      actions.append(b)
    case .noModel:
      actions.append(label("Официальной 3D-модели формы нет — отделку смотрите в карточке и на образцах.", 12, .regular, Palette.muted))
    case .finishNotModelled(let title):
      actions.append(label("Исполнение «\(title)» в студии материалов не моделируется.", 12, .regular, Palette.muted))
    }
    if let p = line.product {
      let files = ActionButton("Файлы изделия", icon: "doc.text") { [weak self] in
        self?.host?.navigationController?.pushViewController(ProductDocumentsController(p), animated: true)
      }
      actions.append(files)
    }
    let card = workspaceCard([top] + actions, spacing: 12)
    card.accessibilityIdentifier = "designer.line.\(line.id)"
    return card
  }

  /// The package summary from the chosen products — never «ready» without files.
  func technical() -> UIView? {
    let journey = DesignerJourney(project: store.current)
    guard journey.files != .none else { return nil }
    let n = journey.products.count
    let text: String
    switch journey.files {
    case .byRequest:
      text = "Для выбранных изделий официальных 3D-моделей, чертежей и паспортов в приложении нет — их запрашивают в Salini."
    default:
      text = "Официальные 3D-модели: \(journey.withModel) из \(n). Чертежи и паспорта сайта Salini: \(journey.withDrawings) из \(n). Чего нет — по запросу."
    }
    let card = workspaceCard([
      eyebrow("ТЕХНИЧЕСКИЙ ПАКЕТ ОБЪЕКТА"),
      label("Файлы по выбранным изделиям — в одном месте.", 21, .regular, serif: true),
      label(text, 14, .regular, Palette.muted),
      ActionButton("Открыть библиотеку объекта", icon: "books.vertical") { [weak self] in
        self?.host?.tabBarController?.selectedIndex = MainTabs.toolTabIndex
      },
    ])
    card.accessibilityIdentifier = "designer.technical"
    return card
  }

  func club() -> UIView {
    let pic = photo("luce", height: 170)
    pic.rounded(20)
    let card = workspaceCard([
      pic,
      eyebrow("SALINI DESIGNERS CLUB"),
      label("Клуб дизайнеров Salini", 23, .regular, serif: true),
      label("DWG и 3D для проектов, изображения для мудбордов, образцы для бюро, мероприятия и публикации проектов.", 14, .regular, Palette.muted),
      ActionButton("О клубе", icon: "arrow.right") { [weak self] in
        self?.host?.navigationController?.pushViewController(DesignersClubController(), animated: true)
      },
    ])
    card.accessibilityIdentifier = "designer.club"
    return card
  }

  // MARK: Actions

  private func perform(_ next: DesignerJourney.Next) {
    switch next {
    case .chooseProducts:
      host?.navigationController?.pushViewController(ChooseController(), animated: true)
    case .resolveExecutions:
      openSpecification()
    case .prepareProposal, .refreshProposal, .reviewProposal:
      guard let host, !store.current.lines.isEmpty else { return }
      host.present(ProposalController(project: store.current, role: .atelier), animated: true)
    }
  }
  private func openCatalog() { host?.tabBarController?.selectedIndex = MainTabs.catalogTabIndex }
  private func openSpecification() { host?.tabBarController?.selectedIndex = MainTabs.projectTabIndex }

  private func createObject() {
    let a = UIAlertController(title: "Новый объект", message: "Хранится только на этом устройстве.", preferredStyle: .alert)
    a.addTextField { $0.placeholder = "Название объекта"; $0.autocapitalizationType = .sentences }
    a.addTextField { $0.placeholder = "Клиент (необязательно)"; $0.autocapitalizationType = .words }
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(UIAlertAction(title: "Создать", style: .default) { [weak self, weak a] _ in
      let name = a?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let client = a?.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self?.store.newProject(name: name.isEmpty ? "Новый объект" : name, client: client)
      self?.host?.reloadDesigner()
    })
    host?.present(a, animated: true)
  }
  private func editObject() {
    let a = UIAlertController(title: "Объект и клиент", message: "Клиент — по желанию.", preferredStyle: .alert)
    a.addTextField { [weak self] in
      $0.text = self?.store.current.name
      $0.placeholder = "Название объекта"
      $0.autocapitalizationType = .sentences
    }
    a.addTextField { [weak self] in
      $0.text = self?.store.current.client
      $0.placeholder = "Клиент (необязательно)"
      $0.autocapitalizationType = .words
    }
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak a] _ in
      guard let self else { return }
      var p = self.store.current
      let name = a?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !name.isEmpty { p.name = name }
      p.client = a?.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.store.current = p
      self.host?.reloadDesigner()
    })
    host?.present(a, animated: true)
  }
}

// MARK: - Designers Club

/// Salini Designers Club as published on salini.club (checked 7 October 2026). The programme is
/// run by Salini: the screen presents its privileges and hands over to the official pages. No
/// membership, points or status are shown, and nothing is sent from the app.
final class DesignersClubController: ScrollController {
  struct Link: Equatable {
    let title: String
    let detail: String
    let url: URL
  }
  static let join = Link(title: "Вступить в клуб", detail: "Регистрация на сайте Salini", url: URL(string: "https://salini-srl.com/auth/")!)
  static let links: [Link] = [
    join,
    Link(title: "Страница клуба", detail: "salini.club", url: URL(string: "https://salini.club/")!),
    Link(title: "Политика конфиденциальности клуба", detail: "salini.club/privacy-policy", url: URL(string: "https://salini.club/privacy-policy")!),
    Link(title: "Официальный сайт Salini", detail: "salini-srl.com", url: URL(string: "https://salini-srl.com/")!),
  ]
  /// The six privileges listed on salini.club, in the app's words; «по согласованию» where the site says so.
  static let privileges: [(icon: String, title: String, text: String)] = [
    ("cube.transparent", "Технические файлы и 3D", "Чертежи, DWG, 3D-модели, скетчи и PNG для мудбордов; каталоги, дайджесты и брошюры. Образцы материалов и печатные каталоги для бюро — по согласованию."),
    ("person.2", "Профессиональные мероприятия", "Бизнес-встречи Salini для членов клуба и вебинары для дизайнеров."),
    ("gift", "Бонусы за реализованные проекты", "Бонусы обмениваются на брендированные сувениры Salini, интерьерные фотосъёмки проектов, сертификаты на обучение и публикации в профильных изданиях."),
    ("bubble.left.and.text.bubble.right", "Поддержка менеджера", "Помощь в подборе сантехники, вопросы по рекламациям и уточнения."),
    ("rosette", "Награды клуба", "Номинации Salini по итогам года или реализации проекта."),
    ("newspaper", "Информационная поддержка", "Публикации проектов на ресурсах Salini, съёмки и коллаборации для СМИ — по согласованию."),
  ]

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Designers Club"
    navigationItem.largeTitleDisplayMode = .never
    let pic = photo("luce", height: 300)
    pic.rounded(28)
    add(pic, inset: 20)
    add(stack([
      eyebrow("SALINI DESIGNERS CLUB"),
      label("Клуб для тех, кто\nделает интерьеры.", 32, .regular, serif: true),
      label("Партнёрская программа Salini для дизайнеров и архитекторов: файлы и образцы для работы, поддержка, мероприятия и публикации реализованных проектов.", 15, .regular, Palette.muted),
    ], spacing: 12))
    var rows: [UIView] = [eyebrow("ПРИВИЛЕГИИ · ПО ДАННЫМ SALINI.CLUB")]
    for item in Self.privileges {
      let icon = symbol(item.icon, size: 20)
      icon.setContentHuggingPriority(.required, for: .horizontal)
      let texts = stack([label(item.title, 16, .semibold), label(item.text, 13, .regular, Palette.muted)], spacing: 4)
      let row = stack([icon, texts], axis: .horizontal, spacing: 14)
      row.alignment = .top
      row.isAccessibilityElement = true
      row.accessibilityLabel = "\(item.title). \(item.text)"
      rows.append(row)
    }
    add(workspaceCard(rows, spacing: 18), inset: 20)
    add(label("Вступление и участие — на официальном сайте Salini.", 14, .regular, Palette.muted))
    var actions: [UIView] = []
    for (i, link) in Self.links.enumerated() {
      let b = ActionButton(link.title, icon: "arrow.up.right", prominent: i == 0) { [weak self] in self?.open(link.url) }
      b.accessibilityHint = "Откроется \(link.detail)"
      b.accessibilityIdentifier = "club.link.\(i)"
      actions.append(b)
    }
    add(stack(actions, spacing: 10), inset: 20)
  }
  private func open(_ url: URL) {
    present(SFSafariViewController(url: url), animated: true)
  }
}
