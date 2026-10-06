import Foundation

// A deterministic demonstration, not telemetry or a model of Salini's actual factory.
// One advance is one demo second. Timed transitions deliberately compress industrial time.
enum CampusLens: Int, CaseIterable {
  case campus, load, orders
  var title: String { ["Территория", "Загрузка", "Заказы"][rawValue] }
}
enum InsideOrderID: String, CaseIterable {
  case aria = "S-2048"
  case marea = "S-2051"
  case domino = "S-2053"
  case trays = "S-2057"
  case mirrors = "S-2060"
  var product: String {
    switch self {
    case .aria: return "Aria 190"
    case .marea: return "Marea"
    case .domino: return "Domino"
    case .trays: return "Душевые поддоны"
    case .mirrors: return "Зеркала и аксессуары"
    }
  }
  var quantity: Int {
    switch self {
    case .aria: return 4
    case .marea: return 12
    case .domino: return 6
    case .trays: return 8
    case .mirrors: return 5
    }
  }
  var description: String {
    switch self {
    case .aria: return "4 ванны · S-Stone · матовый белый"
    case .marea: return "12 раковин · S-Stone"
    case .domino: return "6 мебельных комплектов · комплектация"
    case .trays: return "8 поддонов · S-Sense"
    case .mirrors: return "5 интерьерных комплектов"
    }
  }
  var destination: String {
    [
      .aria: "Москва", .marea: "Санкт-Петербург", .domino: "Санкт-Петербург", .trays: "Казань",
      .mirrors: "Москва",
    ][self]!
  }
  var route: [FactoryZone] {
    switch self {
    case .domino, .mirrors: return [.office, .assembly, .quality, .packing, .warehouse, .dispatch]
    case .marea: return [.office, .materials, .casting, .finishing, .quality, .packing, .dispatch]
    default: return FactoryZone.orderRoute
    }
  }
}
enum ReservePostState { case available, preparing, processing, finished }
enum QualityBatchState { case held, checking, packing, loading, ready, departed }
enum AriaProductionPlan { case mainQueue, reserve }
struct PostAssignment {
  let post: String
  let starts: Double
  let ends: Double
}
struct AriaForecast {
  let assignments: [PostAssignment]
  var processingEnds: Double { assignments.map(\.ends).max() ?? 900 }
  var readyMinute: Double { processingEnds + 40 }  // OTK 20, packaging 15, transfer 5 minutes.
  var reserveMinutes: Int {
    Int(assignments.filter { $0.post == "F-04" }.reduce(0) { $0 + $1.ends - $1.starts })
  }
  var reserveQuantity: Int { assignments.filter { $0.post == "F-04" }.count }
  var readyTime: String { FactorySimulation.time(readyMinute) }
}
/// Small job-shop forecast: schedule each bath on the first compatible available post.
/// The same assignments drive completion, capacity cost and the decision preview.
func forecastAria(at minute: Double, plan: AriaProductionPlan) -> AriaForecast {
  var posts: [(String, Double)] = [
    ("F-01", max(950, minute)), ("F-02", max(985, minute)), ("F-03", max(1005, minute)),
  ]
  if plan == .reserve { posts.append(("F-04", minute + 10)) }
  var jobs: [PostAssignment] = []
  for _ in 0..<4 {
    let index = posts.indices.min { posts[$0].1 < posts[$1].1 }!
    let start = posts[index].1
    jobs.append(PostAssignment(post: posts[index].0, starts: start, ends: start + 15))
    posts[index].1 = start + 15
  }
  return AriaForecast(assignments: jobs)
}
struct InsideEvent: Identifiable {
  let id: Int
  let second: Int
  let title: String
  let detail: String
  let zone: FactoryZone
  let order: InsideOrderID?
  var time: String { FactorySimulation.time(900 + Double(second) / 60) }
}
struct InsideStation {
  let code: String
  let name: String
  let status: String
  let detail: String
  let order: InsideOrderID?
}
extension Notification.Name {
  static let factoryChanged = Notification.Name("salini.factoryChanged")
}

final class FactorySimulation {
  static let minutesPerDemoSecond = 2.5
  static func time(_ minute: Double) -> String {
    String(format: "%02d:%02d", Int(minute) / 60, Int(minute) % 60)
  }
  private(set) var minute: Double = 900  // 15:00. The clock rests at decision points.
  private(set) var ariaPlan: AriaProductionPlan?
  private(set) var ariaAssignments: AriaForecast?
  private(set) var ariaCompleted = false
  private var qualityStartMinute: Double?
  private var reserveStartMinute: Double?
  private var reserveWindowClosed = false
  private(set) var tick = 0
  var paused = false { didSet { changed() } }
  private(set) var completed = 42
  private(set) var priority = false
  private(set) var resolved = false
  private(set) var dispatchReleased = false
  private(set) var reserve: ReservePostState = .available
  private(set) var quality: QualityBatchState = .held
  private(set) var reserveStarted: Int?
  private(set) var qualityStarted: Int?
  private(set) var revision = 0
  var selected: FactoryZone = .casting
  private(set) var journal: [InsideEvent] = []
  private var nextEventID = 0
  init() {
    record("Смена открыта", "План: 68 изделий. Два вопроса требуют решения.", .office)
    record(
      "Marea · требуется повторный осмотр",
      "S-2051 · 12 раковин · рейс 02 удержан до протокола ОТК.", .quality, .marea)
    record(
      "Aria · очередь на обработку", "S-2048 · прогноз 17:20 при плане готовности 17:00.",
      .finishing, .aria)
  }
  var events: [String] { journal.map { "\($0.time) · \($0.title)" } }
  var progress: Float { Float(completed) / 68 }
  var elapsed: String { String(format: "%02d:%02d", tick / 60, tick % 60) }
  var attentionCount: Int {
    (reserve == .available && !ariaCompleted ? 1 : 0)
      + (quality == .held || quality == .ready ? 1 : 0)
  }
  var mainForecast: AriaForecast { forecastAria(at: minute, plan: .mainQueue) }
  var reserveForecast: AriaForecast { forecastAria(at: minute, plan: .reserve) }
  var ariaForecast: String { (ariaAssignments ?? mainForecast).readyTime }
  var canActivateReserve: Bool { reserve == .available && !ariaCompleted && minute < 950 }
  var reserveUnavailableReason: String {
    ariaCompleted
      ? "Обработка уже завершена"
      : minute >= 950 ? "Основная линия уже приняла партию" : "Резерв уже назначен"
  }
  var clockTime: String { Self.time(minute) }
  var hasActiveProcesses: Bool {
    (ariaPlan != nil && !ariaCompleted) || quality == .checking || quality == .packing
      || quality == .loading
  }
  var reserveProgress: Float {
    guard let start = reserveStartMinute, let forecast = ariaAssignments else { return 0 }
    return min(1, max(0, Float((minute - start) / (forecast.processingEnds - start))))
  }
  var qualityProgress: Float {
    guard let start = qualityStartMinute else { return 0 }
    return min(1, max(0, Float((minute - start) / 30)))
  }
  var packingProgress: Float {
    guard let start = qualityStartMinute else { return 0 }
    return min(1, max(0, Float((minute - start - 30) / 15)))
  }
  var loadingProgress: Float {
    guard let start = qualityStartMinute else { return 0 }
    return min(1, max(0, Float((minute - start - 45) / 10)))
  }
  func advance() {
    guard !paused else { return }
    tick += 1
    if hasActiveProcesses { minute += Self.minutesPerDemoSecond }
    if minute >= 950 && !reserveWindowClosed && reserve == .available && !ariaCompleted {
      reserveWindowClosed = true
      record(
        "Aria · окно резервирования закрыто",
        "Основная линия начала работу. Текущий план сохраняется.", .finishing, .aria)
    }
    if let start = reserveStartMinute, reserve == .preparing && minute - start >= 10 {
      reserve = .processing
      record(
        "Пост F-04 работает", "Aria распределена между F-04 и основной линией. Загрузка 96% → 72%.",
        .finishing, .aria)
    }
    if let forecast = ariaAssignments, !ariaCompleted, minute >= forecast.processingEnds {
      ariaCompleted = true
      if ariaPlan == .reserve { reserve = .finished }
      record(
        "Aria · обработка завершена",
        "4 ванны переданы в ОТК. Готовность к \(forecast.readyTime) остаётся прогнозом.", .quality,
        .aria)
    }
    if let start = qualityStartMinute {
      if quality == .checking && minute - start >= 30 {
        quality = .packing
        completed += InsideOrderID.marea.quantity
        record(
          "Marea · повторный контроль пройден",
          "Демо-исход Q-051: 12 из 12 принято. Передано в упаковку.", .packing, .marea)
      }
      if quality == .packing && minute - start >= 45 {
        quality = .loading
        record(
          "Marea · упаковка завершена", "12 мест промаркированы. Погрузчик везёт партию к доку 02.",
          .dispatch, .marea)
      }
      if quality == .loading && minute - start >= 55 {
        quality = .ready
        record(
          "Рейс 02 готов к выезду",
          "Marea загружена. Domino уже в составе рейса; документы проверены.", .dispatch, .marea)
      }
    }
    NotificationCenter.default.post(name: .factoryChanged, object: self)
  }
  @discardableResult func keepMainQueue() -> Bool {
    guard ariaPlan == nil else { return false }
    ariaPlan = .mainQueue
    ariaAssignments = mainForecast
    record(
      "Aria · сохранена основная очередь",
      "Прогноз \(ariaForecast) при плане 17:00. Резерв можно подключить до начала обработки в 15:50.",
      .finishing, .aria)
    return true
  }
  @discardableResult func activateReserve() -> Bool {
    guard canActivateReserve else { return false }
    ariaPlan = .reserve
    ariaAssignments = reserveForecast
    reserveStartMinute = minute
    reserve = .preparing
    reserveStarted = tick
    priority = true
    record(
      "Резерв F-04 назначен на Aria",
      "Прогноз \(ariaForecast). F-04: \(ariaAssignments!.reserveQuantity) ванны, \(ariaAssignments!.reserveMinutes) минут. Подготовка форм на завтра отложена.",
      .finishing, .aria)
    return true
  }
  @discardableResult func startQualityCheck() -> Bool {
    guard quality == .held else { return false }
    quality = .checking
    resolved = true
    qualityStarted = tick
    qualityStartMinute = minute
    record(
      "Повторный осмотр назначен",
      "ОТК · пост Q-02 · поверхность и геометрия Marea. Отгрузка пока заблокирована.", .quality,
      .marea)
    return true
  }
  @discardableResult func releaseMareaDispatch() -> Bool {
    guard quality == .ready else { return false }
    quality = .departed
    record(
      "Рейс 02 вышел на маршрут", "Санкт-Петербург · Marea и Domino · выезд подтверждён.",
      .dispatch, .marea)
    return true
  }
  // Compatibility with the original demo's actions.
  func expedite() { activateReserve() }
  func resolve() { startQualityCheck() }
  func releaseDispatch() {
    guard !dispatchReleased else { return }
    dispatchReleased = true
    record(
      "Рейс 01 → Москва · выезд подтверждён",
      "S-2039 · Aria · 4 изделия. Документы и погрузка проверены.", .dispatch)
  }
  func zone(for order: InsideOrderID) -> FactoryZone {
    switch order {
    case .aria: return ariaCompleted ? .quality : .finishing
    case .marea:
      switch quality {
      case .held, .checking: return .quality
      case .packing: return .packing
      case .loading, .ready, .departed: return .dispatch
      }
    case .domino: return .dispatch
    case .trays: return .casting
    case .mirrors: return .warehouse
    }
  }
  func status(_ order: InsideOrderID) -> String {
    switch order {
    case .aria:
      if ariaCompleted { return "Обработка завершена · ОТК" }
      if ariaPlan == .mainQueue { return "Основная очередь · риск срока" }
      switch reserve {
      case .available: return "Риск задержки · +20 мин"
      case .preparing: return "Подготовка резервного поста"
      case .processing: return "В работе · пост F-04"
      case .finished: return "Обработка завершена · ОТК"
      }
    case .marea:
      switch quality {
      case .held: return "Удержан на ОТК"
      case .checking: return "Повторный осмотр"
      case .packing: return "Принят · упаковка"
      case .loading: return "Док 02 · погрузка"
      case .ready: return "Рейс 02 · готов к выезду"
      case .departed: return "Рейс 02 · в пути"
      }
    case .domino: return quality == .departed ? "Рейс 02 · в пути" : "Укомплектован · ожидает Marea"
    case .trays: return "Отверждение · партия C-07"
    case .mirrors: return "Склад A-12 · резерв подтверждён"
    }
  }
  func needsAttention(_ order: InsideOrderID) -> Bool {
    (order == .aria && reserve == .available && !ariaCompleted)
      || (order == .marea && quality == .held)
  }
  func load(_ zone: FactoryZone) -> Int {
    switch zone {
    case .office: return 64
    case .materials: return 58
    case .casting: return 78
    case .finishing: return reserve == .available || reserve == .preparing ? 96 : 72
    case .assembly: return 62
    case .quality: return quality == .held || quality == .checking ? 88 : 56
    case .packing: return quality == .packing ? 82 : 54
    case .warehouse: return 68
    case .dispatch: return quality == .departed ? 33 : 67
    }
  }
  func count(_ zone: FactoryZone) -> Int {
    switch zone {
    case .office: return InsideOrderID.allCases.count
    case .finishing: return ariaCompleted ? 14 : 18
    case .quality:
      return 4 + (ariaCompleted ? 4 : 0) + ((quality == .held || quality == .checking) ? 12 : 0)
    case .packing: return 12 + (quality == .packing ? 12 : 0)
    default: return zone.count
    }
  }
  func countCaption(_ zone: FactoryZone) -> String {
    switch zone {
    case .office: return "заказов в демо"
    case .materials: return "партий сырья"
    case .assembly: return "комплектов"
    case .dispatch: return "рейса в плане"
    default: return "изделий в зоне"
    }
  }
  func summary(_ zone: FactoryZone) -> String { "\(count(zone)) \(countCaption(zone))" }
  func detailRows(_ zone: FactoryZone) -> [(String, String)] {
    switch zone {
    case .office:
      return [
        ("Производство и контроль", "3 заказа"), ("Комплекты", "2 заказа"),
        ("Требуют решения", "\(attentionCount)"),
      ]
    case .quality:
      return [
        (
          "Marea · повторный осмотр",
          quality == .held || quality == .checking ? "12 изделий" : "Завершён"
        ), ("Aria · после обработки", ariaCompleted ? "4 изделия" : "Ожидаем"),
        ("Другие партии", "4 изделия"),
      ]
    case .finishing:
      return [
        ("В основной очереди", "14 изделий"),
        ("Aria", ariaCompleted ? "Передана в ОТК" : "4 ванны"),
        (
          "Пост F-04",
          reserve == .available
            ? "Резерв"
            : reserve == .preparing
              ? "Подготовка" : reserve == .processing ? "В работе" : "Завершил партию"
        ),
      ]
    case .packing:
      return [
        ("Базовая очередь", "12 мест"),
        (
          "Marea",
          quality == .packing
            ? "12 раковин"
            : quality == .held || quality == .checking ? "Ожидаем ОТК" : "Передана на погрузку"
        ),
      ]
    case .dispatch:
      return [
        ("Москва · рейс 01", dispatchReleased ? "В пути" : "Готов"),
        (
          "Санкт-Петербург · рейс 02",
          quality == .departed
            ? "В пути"
            : quality == .ready ? "Готов" : quality == .loading ? "Погрузка" : "Ожидает Marea"
        ), ("Казань · рейс 03", "Планируется"),
      ]
    default: return zone.detailRows
    }
  }
  func stations(_ zone: FactoryZone) -> [InsideStation] {
    let rows: [(String, String, String, String, InsideOrderID?)]
    switch zone {
    case .office:
      rows = [
        ("O-01", "Проектное бюро", "6 проектов", "Спецификации и согласование материалов", nil),
        ("O-02", "Планирование", "2 сценария", "Сроки, мощности и отгрузки в одной цепочке", .aria),
      ]
    case .materials:
      rows = [
        ("M-01", "S-Stone", "18 партий", "Минеральная смесь · запас на смену", nil),
        ("M-02", "S-Sense", "14 партий", "Сырьё зарезервировано для C-07", .trays),
      ]
    case .casting:
      rows = [
        ("C-01", "Формы ванн", "10 форм", "Подготовка и минеральное литьё", .aria),
        ("C-04", "Раковины", "8 форм", "Компактные формы · серия Marea", .marea),
        ("C-07", "Поддоны", "6 форм", "Отверждение · план 8 изделий", .trays),
      ]
    case .finishing:
      rows = [
        ("F-01", "Шлифовка", "В работе", "Основная очередь · 18 изделий", nil),
        ("F-02", "Финиш поверхности", "В работе", "Матовая поверхность · S-Stone", nil),
        (
          "F-04", "Резервный пост",
          reserve == .available
            ? "Резерв"
            : reserve == .preparing
              ? "Подготовка" : reserve == .processing ? "Aria · 4 ванны" : "Работа завершена",
          "Исправен · оператор в резерве · +45 минут", .aria
        ),
      ]
    case .assembly:
      rows = [
        ("A-01", "Мебель и столешницы", "7 комплектов", "Комплектация готовых изделий", .domino),
        ("A-02", "Зеркала", "5 комплектов", "Проверка комплектности и крепежа", .mirrors),
      ]
    case .quality:
      rows = [
        ("Q-01", "Геометрия", "Контроль", "Размеры и допуски изделий", .trays),
        (
          "Q-02", "Поверхность",
          quality == .held
            ? "Требует осмотра" : quality == .checking ? "Осмотр идёт" : "Протокол Q-051",
          "Marea · 12 раковин · повторный контроль", .marea
        ),
      ]
    case .packing:
      rows = [
        ("P-01", "Крупные изделия", "4 места", "Защитная упаковка ванн и поддонов", .aria),
        (
          "P-02", "Раковины", quality == .packing ? "Marea · упаковка" : "Готов к работе",
          "Маркировка, защита кромок, комплектность", .marea
        ),
      ]
    case .warehouse:
      rows = [
        (
          "W-A", "Зона A · готовые изделия", "62 изделия", "Ванны и поддоны · адресное хранение",
          nil
        ),
        (
          "W-B", "Зона B · комплекты", "84 изделия", "Раковины, мебель, зеркала и аксессуары",
          .mirrors
        ),
      ]
    case .dispatch:
      rows = [
        (
          "D-01", "Москва", dispatchReleased ? "В пути" : "Готов к выезду",
          "Рейс 01 · 4 изделия Aria", nil
        ),
        (
          "D-02", "Санкт-Петербург",
          quality == .departed ? "В пути" : quality == .ready ? "Готов к выезду" : "Ожидает Marea",
          "Рейс 02 · 12 раковин + 6 мебельных комплектов", .marea
        ), ("D-03", "Казань", "Планирование", "Рейс 03 · поддоны", .trays),
      ]
    }
    return rows.map {
      InsideStation(code: $0.0, name: $0.1, status: $0.2, detail: $0.3, order: $0.4)
    }
  }
  private func record(
    _ title: String, _ detail: String, _ zone: FactoryZone, _ order: InsideOrderID? = nil
  ) {
    nextEventID += 1
    journal.insert(
      InsideEvent(
        id: nextEventID, second: Int((minute - 900) * 60), title: title, detail: detail, zone: zone,
        order: order), at: 0)
    journal = Array(journal.prefix(20))
    changed()
  }
  private func changed() {
    revision += 1
    NotificationCenter.default.post(name: .factoryChanged, object: self)
  }
}
