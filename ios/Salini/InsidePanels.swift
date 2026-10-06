import UIKit

enum InsideStyle {
  static let blue = UIColor(hex: 0x476E89)
  static let amber = UIColor(hex: 0xA46D35)
  static let green = UIColor(hex: 0x507867)
  static func loadColor(_ value: Int) -> UIColor { value >= 85 ? amber : blue }
}

/// Solid content surfaces; glass is reserved for floating navigation and actions.
func insideCard(_ views: [UIView], spacing: CGFloat = 16) -> UIView {
  let v = stack(views, spacing: spacing).inset(20)
  v.backgroundColor = .white
  v.rounded(24)
  return v
}
func insideMetric(_ value: String, _ caption: String, color: UIColor = Palette.ink) -> UIView {
  let number = label(value, 27, .medium, color)
  number.font = .monospacedDigitSystemFont(ofSize: 27, weight: .medium)
  return stack([number, label(caption, 11, .medium, Palette.muted)], spacing: 5)
}
func insideRow(
  _ title: String, _ subtitle: String, icon: String, color: UIColor = InsideStyle.blue,
  action: @escaping () -> Void
) -> UIView {
  let button = UIButton(type: .system)
  var c = UIButton.Configuration.plain()
  c.title = title
  c.subtitle = subtitle
  c.image = UIImage(systemName: icon)
  c.imagePlacement = .leading
  c.imagePadding = 14
  c.titleAlignment = .leading
  c.titleLineBreakMode = .byWordWrapping
  c.subtitleLineBreakMode = .byWordWrapping
  c.baseForegroundColor = Palette.ink
  c.contentInsets = NSDirectionalEdgeInsets(top: 17, leading: 18, bottom: 17, trailing: 18)
  c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
    var a = $0
    a.font = .systemFont(ofSize: 15, weight: .semibold)
    return a
  }
  c.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
    var a = $0
    a.font = .systemFont(ofSize: 12)
    a.foregroundColor = Palette.muted
    return a
  }
  c.imageColorTransformer = UIConfigurationColorTransformer { _ in color }
  button.configuration = c
  button.contentHorizontalAlignment = .leading
  button.backgroundColor = .white
  button.rounded(19)
  button.addAction(
    UIAction { _ in
      UISelectionFeedbackGenerator().selectionChanged()
      action()
    }, for: .touchUpInside)
  button.accessibilityLabel = "\(title). \(subtitle)"
  return button
}

enum InsideDestination {
  case briefing
  case zone(FactoryZone)
  case order(InsideOrderID)
  case orders, dispatch, events
  case station(FactoryZone, String)
}

final class InsidePanelController: ScrollController {
  let simulation: FactorySimulation
  let destination: InsideDestination
  let onLocate: (FactoryZone, InsideOrderID?) -> Void
  private var observer: NSObjectProtocol?
  private var lastRevision = -1
  private var forecastMinute: Double = -1
  private var progressView: UIProgressView?
  private var progressCaption: UILabel?
  private var filter = 0
  private var searchText = ""
  init(
    _ destination: InsideDestination, simulation: FactorySimulation,
    onLocate: @escaping (FactoryZone, InsideOrderID?) -> Void
  ) {
    self.destination = destination
    self.simulation = simulation
    self.onLocate = onLocate
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  override func viewDidLoad() {
    super.viewDidLoad()
    content.spacing = 0
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
    )
    observer = NotificationCenter.default.addObserver(
      forName: .factoryChanged, object: simulation, queue: .main
    ) { [weak self] _ in
      guard let self, self.view.window != nil else { return }
      let forecasting: Bool
      switch self.destination {
      case .order(.aria), .station(.finishing, "F-04"):
        forecasting = self.simulation.reserve == .available
      default: forecasting = false
      }
      if self.lastRevision != self.simulation.revision
        || (forecasting && self.forecastMinute != self.simulation.minute)
      {
        self.render()
      }
      self.updateProgress()
    }
    render()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if lastRevision != simulation.revision { render() }
  }
  private func push(_ destination: InsideDestination) {
    navigationController?.pushViewController(
      InsidePanelController(destination, simulation: simulation, onLocate: onLocate), animated: true
    )
  }
  private func locate(_ zone: FactoryZone, _ order: InsideOrderID? = nil) {
    dismiss(animated: true) { [onLocate] in onLocate(zone, order) }
  }
  private func section(_ title: String) { add(eyebrow(title), inset: 22) }
  private func card(_ views: [UIView]) { add(insideCard(views), inset: 16) }
  private func row(
    _ title: String, _ subtitle: String, _ icon: String, color: UIColor = InsideStyle.blue,
    action: @escaping () -> Void
  ) {
    add(insideRow(title, subtitle, icon: icon, color: color, action: action), inset: 12)
  }
  private func heading(_ kicker: String, _ title: String, _ subtitle: String) {
    add(
      stack(
        [
          eyebrow(kicker), label(title, 32, .semibold),
          label(subtitle, 14, .regular, Palette.muted),
        ], spacing: 12))
  }
  private func render() {
    lastRevision = simulation.revision
    forecastMinute = simulation.minute
    let offset = scroll.contentOffset
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    progressView = nil
    progressCaption = nil
    switch destination {
    case .briefing: briefing()
    case .zone(let zone): zonePanel(zone)
    case .orders: orders()
    case .order(let order): orderPanel(order)
    case .dispatch: dispatch()
    case .events: events()
    case .station(let zone, let code): station(zone, code)
    }
    add(
      label(
        "Демонстрационная смена. Данные и сценарии условные; действия меняют только эту модель.",
        11, .regular, Palette.muted))
    view.layoutIfNeeded()
    scroll.contentOffset = CGPoint(
      x: 0,
      y: min(
        offset.y,
        max(
          -scroll.adjustedContentInset.top,
          scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)))
    updateProgress()
  }
  private func briefing() {
    title = "Обзор смены"
    heading(
      "SALINI INSIDE · ДЕМО", "Всё начинается\nс ясности.",
      "Производство, заказы и решения — в одном пространстве.")
    let metrics = stack(
      [
        insideMetric("\(simulation.completed)/68", "принято ОТК"),
        insideMetric("\(simulation.attentionCount)", "требует решения", color: InsideStyle.amber),
        insideMetric("3", "рейса в плане"),
      ], axis: .horizontal)
    metrics.distribution = .fillEqually
    card([metrics, ShiftOutputView(completed: simulation.completed)])
    section("В ФОКУСЕ РУКОВОДИТЕЛЯ")
    row(
      "Aria · срок готовности", "\(simulation.ariaForecast) · \(simulation.status(.aria))", "clock",
      color: simulation.needsAttention(.aria) ? InsideStyle.amber : InsideStyle.green
    ) { [weak self] in self?.push(.order(.aria)) }
    row(
      "Marea · качество и доставка", simulation.status(.marea), "checkmark.seal",
      color: simulation.needsAttention(.marea) ? InsideStyle.amber : InsideStyle.green
    ) { [weak self] in self?.push(.order(.marea)) }
    section("КОМПАНИЯ")
    row("Заказы", "5 демонстрационных проектов · разные категории", "square.stack.3d.up") {
      [weak self] in self?.push(.orders)
    }
    row("Отгрузки", "Москва · Санкт-Петербург · Казань", "truck.box") { [weak self] in
      self?.push(.dispatch)
    }
    row(
      "Журнал решений",
      "\(simulation.journal.count) \(plural(simulation.journal.count, "событие", "события", "событий")) · вся цепочка изменений",
      "clock.arrow.circlepath"
    ) { [weak self] in self?.push(.events) }
  }
  private func zonePanel(_ zone: FactoryZone) {
    title = "Участок \(zone.code)"
    heading("ТЕРРИТОРИЯ / \(zone.shortTitle.uppercased())", zone.title, zone.state)
    let metrics = stack(
      [
        insideMetric(
          "\(simulation.load(zone))%", "загрузка",
          color: InsideStyle.loadColor(simulation.load(zone))),
        insideMetric("\(zone.people)", "команда смены"),
        insideMetric("\(simulation.count(zone))", simulation.countCaption(zone)),
      ], axis: .horizontal)
    metrics.distribution = .fillEqually
    let meter = UIProgressView(progressViewStyle: .bar)
    meter.progress = Float(simulation.load(zone)) / 100
    meter.progressTintColor = InsideStyle.loadColor(simulation.load(zone))
    meter.trackTintColor = Palette.paper
    card([
      metrics, meter,
      label("Загрузка доступной мощности · демонстрационная оценка", 11, .regular, Palette.muted),
    ])
    add(
      ActionButton("Показать на территории", icon: "viewfinder") { [weak self] in self?.locate(zone)
      }, inset: 16)
    section("ПОСТЫ И ПРОЦЕССЫ")
    for item in simulation.stations(zone) {
      row("\(item.code) · \(item.name)", item.status, zone.icon) { [weak self] in
        self?.push(.station(zone, item.code))
      }
    }
    let orders = InsideOrderID.allCases.filter { simulation.zone(for: $0) == zone }
    if !orders.isEmpty {
      section("ЗАКАЗЫ НА УЧАСТКЕ")
      for order in orders { orderRow(order) }
    }
    section("СОСТАВ УЧАСТКА")
    for (name, value) in simulation.detailRows(zone) {
      card([
        stack([label(name, 14, .medium), UIView(), label(value, 14, .semibold)], axis: .horizontal)
      ])
    }
  }
  private func station(_ zone: FactoryZone, _ code: String) {
    guard let station = simulation.stations(zone).first(where: { $0.code == code }) else { return }
    title = code
    heading("\(zone.shortTitle.uppercased()) / \(code)", station.name, station.detail)
    card([
      symbol(zone.icon, size: 34, color: InsideStyle.blue), label(station.status, 24, .semibold),
      label(
        "Состояние поста связано с текущей демонстрационной сменой.", 13, .regular, Palette.muted),
    ])
    if code == "F-04" {
      reserveDecision()
    } else if code == "Q-02" {
      qualityDecision()
    } else if let order = station.order {
      orderRow(order)
    } else {
      card([
        label("Процесс в штатном режиме", 19, .semibold),
        label(
          "Отклонений в текущем сценарии нет. Состав и загрузка доступны в карточке участка.", 14,
          .regular, Palette.muted),
      ])
    }
    add(
      ActionButton("К участку на карте", icon: "viewfinder") { [weak self] in
        self?.locate(zone, station.order)
      }, inset: 16)
  }
  private func orders() {
    title = "Заказы"
    heading("ПОРТФЕЛЬ · ДЕМО", "От замысла\nдо адреса.", "Пять проектов связывают всю компанию.")
    let search = UISearchBar()
    search.placeholder = "Номер, коллекция или город"
    search.searchBarStyle = .minimal
    search.text = searchText
    search.delegate = self
    add(search, inset: 12)
    let filters = UISegmentedControl(items: ["Все", "Внимание", "В пути"])
    filters.selectedSegmentIndex = filter
    filters.addAction(
      UIAction { [weak self, weak filters] _ in
        self?.filter = filters?.selectedSegmentIndex ?? 0
        self?.render()
      }, for: .valueChanged)
    add(filters, inset: 16)
    let results = matchingOrders()
    if results.isEmpty {
      card([
        label("Заказов не найдено", 20, .semibold),
        label("Попробуйте другую коллекцию, город или номер.", 14, .regular, Palette.muted),
      ])
    }
    for order in results { orderRow(order) }
  }
  private func matchingOrders() -> [InsideOrderID] {
    InsideOrderID.allCases.filter {
      let searchable = "\($0.rawValue) \($0.product) \($0.destination)"
      let matches = searchText.isEmpty || searchable.localizedCaseInsensitiveContains(searchText)
      let state =
        filter == 0 || (filter == 1 && simulation.needsAttention($0))
        || (filter == 2 && simulation.quality == .departed && ($0 == .marea || $0 == .domino))
      return matches && state
    }
  }
  private func orderRow(_ order: InsideOrderID) {
    row(
      "\(order.rawValue) · \(order.product)", "\(order.destination) · \(simulation.status(order))",
      simulation.zone(for: order).icon,
      color: simulation.needsAttention(order) ? InsideStyle.amber : InsideStyle.blue
    ) { [weak self] in self?.push(.order(order)) }
  }
  private func orderPanel(_ order: InsideOrderID) {
    title = order.rawValue
    heading("ЗАКАЗ / \(order.destination.uppercased())", order.product, order.description)
    card([
      label(
        simulation.status(order), 20, .semibold,
        simulation.needsAttention(order) ? InsideStyle.amber : InsideStyle.blue),
      label(
        order == .aria
          ? "Готовность к погрузке: план 17:00 · прогноз \(simulation.ariaForecast). Москва · отдельный рейс, не рейс 02."
          : order == .marea
            ? "Рейс 02 · выезд после ОТК, упаковки и погрузки"
            : "Текущий участок: \(simulation.zone(for: order).title)", 13, .regular, Palette.muted),
    ])
    add(
      ActionButton("Найти заказ на карте", icon: "location", prominent: true) { [weak self] in
        guard let self else { return }
        self.locate(self.simulation.zone(for: order), order)
      }, inset: 16)
    if order == .aria { reserveDecision() }
    if order == .marea { qualityDecision() }
    if order == .domino {
      card([
        label("Один рейс с Marea", 20, .semibold),
        label(
          simulation.quality == .departed
            ? "Комплекты отгружены вместе с раковинами."
            : "Комплектация и погрузка завершены. Выезд зависит от повторного контроля партии Marea.",
          14, .regular, Palette.muted),
      ])
      row("Открыть связанную партию", "S-2051 · Marea · 12 раковин", "link") { [weak self] in
        self?.push(.order(.marea))
      }
    }
    section("МАРШРУТ ИЗДЕЛИЯ")
    let current = order.route.firstIndex(of: simulation.zone(for: order)) ?? 0
    let departed = simulation.quality == .departed && (order == .marea || order == .domino)
    let timeline = stack([], spacing: 8)
    for (i, zone) in order.route.enumerated() {
      let done = i < current || departed
      let now = i == current && !departed
      let subtitle = done ? "Завершено" : now ? "Сейчас здесь" : "Следующий этап"
      timeline.addArrangedSubview(
        insideRow(
          zone.title, subtitle,
          icon: done ? "checkmark.circle.fill" : now ? "record.circle" : "circle",
          color: done ? InsideStyle.green : now ? InsideStyle.blue : UIColor(hex: 0xBBC1C5)
        ) { [weak self] in self?.locate(zone, order) })
    }
    add(timeline, inset: 16)
    let entries = simulation.journal.filter { $0.order == order }
    if !entries.isEmpty {
      section("ИСТОРИЯ ЗАКАЗА")
      for event in entries {
        card([
          label("\(event.time) · \(event.title)", 14, .semibold),
          label(event.detail, 13, .regular, Palette.muted),
        ])
      }
    }
  }
  private func reserveDecision() {
    section("РЕШЕНИЕ / МОЩНОСТЬ")
    if !simulation.ariaCompleted && simulation.reserve == .available {
      let metrics = stack(
        [
          insideMetric(
            (simulation.ariaAssignments ?? simulation.mainForecast).readyTime, "основная очередь",
            color: InsideStyle.amber), symbol("arrow.right", size: 18),
          insideMetric(
            simulation.reserveForecast.readyTime, "с резервом", color: InsideStyle.green),
        ], axis: .horizontal)
      metrics.distribution = .equalSpacing
      card([
        label("Подключить пост F-04", 23, .semibold), metrics, line(),
        label(
          "Пост исправен. Квалифицированный оператор доступен. \(simulation.reserveForecast.reserveQuantity) из 4 ванн назначаются на F-04; остальные — на основную линию.",
          14, .regular, Palette.muted),
        label(
          "Цена решения · \(simulation.reserveForecast.reserveMinutes) минут F-04 + 10 минут подготовки.\nОператор откладывает подготовку форм на завтра. Другие заказы сохраняют очередь.",
          13, .medium),
        label(
          "Расчёт по доступности каждого поста и циклу 15 мин/ванна. Затем 40 минут на ОТК, упаковку и передачу. Решение доступно до 15:50.",
          11, .regular, Palette.muted),
      ])
      let b = ActionButton("Подключить резерв", icon: "plus.circle", prominent: true) {
        [weak self] in self?.simulation.activateReserve()
      }
      b.isEnabled = simulation.canActivateReserve
      b.accessibilityIdentifier = "inside.reserve.activate"
      add(b, inset: 16)
      if !simulation.canActivateReserve {
        card([label(simulation.reserveUnavailableReason, 14, .medium)])
      }
      if simulation.ariaPlan == nil {
        add(
          ActionButton("Оставить основную очередь", icon: "clock") { [weak self] in
            self?.simulation.keepMainQueue()
          }, inset: 16)
      } else if simulation.ariaPlan == .mainQueue {
        card([
          label("Основная очередь сохранена", 18, .semibold),
          label(
            "Прогноз \(simulation.ariaForecast). План готовности 17:00 под риском. Резерв можно подключить до начала обработки.",
            14, .regular, Palette.muted),
        ])
      }
    } else {
      let done = simulation.ariaCompleted
      card([
        label(done ? "Обработка завершена" : "Резерв подключён", 23, .semibold, InsideStyle.green),
        label(
          done
            ? "Четыре ванны переданы на контроль качества. Прогноз готовности \(simulation.ariaForecast) сохранён."
            : "Подготовка поста → параллельная обработка → передача в ОТК. Основная очередь продолжает работу.",
          14, .regular, Palette.muted),
        label("96% → 72% · загрузка обработки после запуска", 14, .semibold),
      ])
      if !done { addProgress("Процесс по расчётному плану · 1 с = 2,5 мин") }
    }
  }
  private func qualityDecision() {
    section("РЕШЕНИЕ / КАЧЕСТВО")
    switch simulation.quality {
    case .held:
      card([
        label("Сначала — уверенность\nв каждом изделии.", 23, .semibold),
        label(
          "Партия Marea удержана для перепроверки до упаковки. Дефект не установлен. В рейсе 02 уже ждут 6 мебельных комплектов Domino.",
          14, .regular, Palette.muted), line(),
        label("Q-02 · инспектор доступен\n12 раковин · поверхность и геометрия", 14, .medium),
        label(
          "Назначение осмотра не разрешает отгрузку. Нужен положительный протокол и завершённая погрузка.",
          12, .regular, Palette.muted),
      ])
      let b = ActionButton("Назначить повторный осмотр", icon: "checkmark.seal", prominent: true) {
        [weak self] in self?.simulation.startQualityCheck()
      }
      b.accessibilityIdentifier = "inside.quality.start"
      add(b, inset: 16)
    case .checking:
      card([
        label("Осмотр идёт", 23, .semibold),
        label(
          "Q-02 · проверяем поверхность и геометрию. Рейс 02 остаётся заблокированным.", 14,
          .regular, Palette.muted),
      ])
      addProgress("Осмотр · 30 мин · 12 секунд при ×150")
    case .packing:
      card([
        label("12 из 12 — принято", 25, .semibold, InsideStyle.green),
        label(
          "Демо-исход: протокол Q-051 положительный. Партия перешла в упаковку: защита кромок и маркировка.",
          14, .regular, Palette.muted),
      ])
      addProgress("Упаковка · 15 мин · 6 секунд при ×150")
    case .loading:
      card([
        label("Док 02 · погрузка", 25, .semibold),
        label(
          "12 упакованных мест перемещаются к машине. Разрешение на выезд появится после завершения погрузки.",
          14, .regular, Palette.muted),
      ])
      addProgress("Погрузка · 10 мин · 4 секунды при ×150")
    case .ready:
      card([
        label("Можно отправляться", 25, .semibold, InsideStyle.green),
        label(
          "Marea и Domino загружены. Протокол ОТК и документы проверены. Решение о выезде — за диспетчером.",
          14, .regular, Palette.muted),
      ])
      add(
        ActionButton("К рейсу 02", icon: "truck.box", prominent: true) { [weak self] in
          self?.push(.dispatch)
        }, inset: 16)
    case .departed:
      card([
        symbol("checkmark.circle", size: 34, color: InsideStyle.green),
        label("На пути в Санкт-Петербург", 24, .semibold),
        label(
          "Рейс 02 выпущен. Партии Marea и Domino отгружены вместе.", 14, .regular, Palette.muted),
      ])
    }
  }
  private func addProgress(_ text: String) {
    let meter = UIProgressView(progressViewStyle: .bar)
    meter.trackTintColor = UIColor(hex: 0xE3E8EA)
    meter.progressTintColor = InsideStyle.blue
    let caption = label(text, 12, .medium, Palette.muted)
    progressView = meter
    progressCaption = caption
    card([
      caption, meter,
      label(
        "\(simulation.paused ? "На паузе" : "Время ×150 на базовой скорости") · пауза доступна на карте",
        11, .regular, Palette.muted),
    ])
  }
  private func updateProgress() {
    let isReserve: Bool
    switch destination {
    case .order(.aria), .station(.finishing, "F-04"): isReserve = true
    default: isReserve = false
    }
    let value =
      isReserve
      ? simulation.reserveProgress
      : simulation.quality == .packing
        ? simulation.packingProgress
        : simulation.quality == .loading ? simulation.loadingProgress : simulation.qualityProgress
    progressView?.setProgress(value, animated: !UIAccessibility.isReduceMotionEnabled)
    progressView?.accessibilityLabel = "Прогресс демонстрационного процесса"
    progressView?.accessibilityValue = "\(Int(value * 100)) процентов"
  }
  private func dispatch() {
    title = "Отгрузки"
    heading(
      "ДИСПЕТЧЕРСКАЯ · ДЕМО", "Последний этап.\nСледующий адрес.",
      "Состав рейса и разрешение на выезд связаны с производством.")
    let passed = simulation.quality != .held && simulation.quality != .checking
    let ready = simulation.quality == .ready || simulation.quality == .departed
    card([
      label("02 · Санкт-Петербург", 24, .semibold),
      label("12 раковин Marea + 6 комплектов Domino", 14, .regular, Palette.muted),
      dispatchCheck("Протокол Q-051", done: passed),
      dispatchCheck("Упаковка и погрузка", done: ready),
      dispatchCheck("Документы и комплектность", done: ready),
      label(
        simulation.quality == .departed
          ? "Машина вышла на маршрут"
          : ready ? "Все условия выполнены" : "Выезд заблокирован · ожидаем Marea", 14, .semibold,
        ready ? InsideStyle.green : InsideStyle.amber),
    ])
    let release = ActionButton(
      simulation.quality == .departed ? "Выезд подтверждён" : "Выпустить рейс 02",
      icon: "truck.box", prominent: true
    ) { [weak self] in
      guard let self, self.simulation.releaseMareaDispatch() else { return }
      self.locate(.dispatch, .marea)
    }
    release.isEnabled = simulation.quality == .ready
    release.accessibilityIdentifier = "inside.dispatch.release02"
    add(release, inset: 16)
    if !ready {
      row("Что удерживает рейс", simulation.status(.marea), "arrow.up.right") { [weak self] in
        self?.push(.order(.marea))
      }
    }
    card([
      label("01 · Москва", 22, .semibold),
      label("S-2039 · 4 ванны Aria\nПогрузка и документы проверены", 14, .regular, Palette.muted),
      label(
        simulation.dispatchReleased ? "В пути" : "Готов к выезду", 14, .semibold, InsideStyle.green),
    ])
    let first = ActionButton(
      simulation.dispatchReleased ? "Рейс 01 отправлен" : "Выпустить рейс 01", icon: "truck.box"
    ) { [weak self] in
      guard let self else { return }
      self.simulation.releaseDispatch()
      self.locate(.dispatch)
    }
    first.isEnabled = !simulation.dispatchReleased
    add(first, inset: 16)
    card([
      label("03 · Казань", 22, .semibold),
      label(
        "Душевые поддоны · S-2057\nРейс планируется после завершения производства.", 14, .regular,
        Palette.muted),
    ])
  }
  private func dispatchCheck(_ title: String, done: Bool) -> UIView {
    stack(
      [
        symbol(
          done ? "checkmark.circle.fill" : "circle", size: 18,
          color: done ? InsideStyle.green : Palette.muted), label(title, 14, .medium),
      ], axis: .horizontal, spacing: 10)
  }
  private func events() {
    title = "Журнал решений"
    heading(
      "ДЕМО-СМЕНА / \(simulation.clockTime)", "Причина. Действие.\nРезультат.",
      "Время сценария · старт в 15:00. Нажмите событие, чтобы увидеть его контекст.")
    for event in simulation.journal {
      row("\(event.time) · \(event.title)", event.detail, event.zone.icon) { [weak self] in
        guard let self else { return }
        if let order = event.order { self.push(.order(order)) } else { self.locate(event.zone) }
      }
    }
  }
}
extension InsidePanelController: UISearchBarDelegate {
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    searchText = searchBar.text ?? ""
    searchBar.resignFirstResponder()
    render()
  }
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    self.searchText = searchText
    // Keep the keyboard and focus stable; search applies on the system Search action.
    if searchText.isEmpty {
      searchBar.resignFirstResponder()
      render()
    }
  }
}

final class ShiftOutputView: UIView {
  let completed: Int
  init(completed: Int) {
    self.completed = completed
    super.init(frame: .zero)
    height(62)
    isAccessibilityElement = true
    accessibilityLabel = "Принято ОТК \(completed) из 68 изделий"
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ rect: CGRect) {
    let count = 34
    let gap: CGFloat = 4
    let width = (bounds.width - CGFloat(count - 1) * gap) / CGFloat(count)
    for i in 0..<count {
      let h: CGFloat = i % 5 == 0 ? 42 : i % 3 == 0 ? 34 : 26
      let r = CGRect(
        x: CGFloat(i) * (width + gap), y: (bounds.height - h) / 2, width: width, height: h)
      (i * 2 < completed ? InsideStyle.blue : UIColor(hex: 0xE6EBED)).setFill()
      UIBezierPath(roundedRect: r, cornerRadius: width / 2).fill()
    }
  }
}
