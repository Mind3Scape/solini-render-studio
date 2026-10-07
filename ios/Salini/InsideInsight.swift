import Foundation

// Insight layer of Salini Inside: what deserves the owner's attention now, and the business
// board derived from the same deterministic demo simulation. Nothing here changes business
// state; it only reads `FactorySimulation`. Amounts are fixed demo orders, not Salini sales.

/// The two outbound trips of the demo shift.
enum InsideTrip: Int, CaseIterable {
  case moscow = 1, petersburg = 2
  var title: String { "Рейс 0\(rawValue)" }
  var destination: String { self == .moscow ? "Москва" : "Санкт-Петербург" }
  var cargo: String { self == .moscow ? "S-2039 · Aria · 4 изделия" : "Marea · 12 раковин + Domino · 6 комплектов" }
  var pieces: Int { self == .moscow ? 4 : InsideOrderID.marea.quantity + InsideOrderID.domino.quantity }
}

/// Where the camera should look right now.
enum InsideTarget: Equatable {
  case zone(FactoryZone)
  case trip(InsideTrip)
  /// The forklift carrying the packed batch from packing to the dock.
  case transfer
}

/// What the owner chose to watch: a process identity that stays the same while the process
/// moves (Marea: OTK → packing → forklift → dock → truck 02). Never swapped for another order.
enum InsideSubject: Equatable {
  case order(InsideOrderID)
  case trip(InsideTrip)
  case zone(FactoryZone)
}

/// What opens when the owner acts on a focus (a panel, never a business action by itself).
enum InsideDecision: Equatable {
  case order(InsideOrderID)
  case orders
  case dispatch
  case zone(FactoryZone)
}

struct InsideFocus: Equatable {
  enum Kind: Int, Comparable {
    // A live process outranks a merely busy hall; load is only the last fallback.
    case blocking, urgent, decision, live, load
    static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
  }
  let id: String
  let kind: Kind
  let subject: InsideSubject
  /// Current position of the subject when the focus was built (see `FactorySimulation.target`).
  let target: InsideTarget
  let title: String
  let reason: String
  let decision: InsideDecision?
}

extension InsideOrderID {
  /// Fixed demo order value: quantity × demo unit price. Aria uses the catalogue S-Stone price of
  /// Aria 190 (890 000 ₽); the others are round demonstration prices. Not Salini sales.
  var demoUnitPrice: Int {
    switch self {
    case .aria: return 890_000
    case .marea: return 64_000
    case .domino: return 185_000
    case .trays: return 72_000
    case .mirrors: return 48_000
    }
  }
  var demoAmount: Int { demoUnitPrice * quantity }
}

extension FactorySimulation {
  static let ariaPlanMinute: Double = 1020  // 17:00

  func tripState(_ trip: InsideTrip) -> (onRoad: Bool, ready: Bool, text: String) {
    switch trip {
    case .moscow:
      return dispatchReleased ? (true, false, "В пути · Москва") : (false, true, "Готов к выезду · док 01")
    case .petersburg:
      switch quality {
      case .departed: return (true, false, "В пути · Санкт-Петербург")
      case .ready: return (false, true, "Готов к выезду · док 02")
      case .loading: return (false, false, "Погрузка · док 02")
      default: return (false, false, "Ожидает Marea")
      }
    }
  }

  /// Where a subject is now. Marea follows its batch; Domino waits on truck 02.
  func target(of subject: InsideSubject) -> InsideTarget {
    switch subject {
    case .zone(let zone): return .zone(zone)
    case .trip(let trip): return .trip(trip)
    case .order(.marea):
      switch quality {
      case .held, .checking: return .zone(.quality)
      case .packing: return .zone(.packing)
      case .loading: return .transfer
      case .ready, .departed: return .trip(.petersburg)
      }
    case .order(.domino): return .trip(.petersburg)
    case .order(let order): return .zone(zone(for: order))
    }
  }
  /// The current stage of a subject in words — the title follows the same order as it moves.
  func stageTitle(of subject: InsideSubject) -> String {
    switch subject {
    case .order(.marea):
      switch quality {
      case .held: return "Marea · удержана ОТК"
      case .checking: return "Marea · повторный осмотр"
      case .packing: return "Marea · упаковка"
      case .loading: return "Marea · погрузка в док 02"
      case .ready: return "Marea · в машине рейса 02"
      case .departed: return "Marea · рейс 02 в пути"
      }
    case .order(.domino):
      return quality == .departed ? "Domino · рейс 02 в пути" : "Domino · в машине рейса 02"
    case .order(let order): return "\(order.product) · \(zone(for: order).shortTitle.lowercased())"
    case .trip(let trip):
      return "\(trip.title) · \(tripState(trip).onRoad ? "в пути" : tripState(trip).ready ? "готов к выезду" : "в доке")"
    case .zone(let zone): return zone.title
    }
  }
  func focus(
    _ id: String, _ kind: InsideFocus.Kind, _ subject: InsideSubject, _ title: String, _ reason: String,
    _ decision: InsideDecision?
  ) -> InsideFocus {
    InsideFocus(id: id, kind: kind, subject: subject, target: target(of: subject), title: title,
                reason: reason, decision: decision)
  }

  /// Deterministic priority: blocking problem → urgency with a closing window → decision waiting
  /// → a live process → (fallback) the busiest hall. The first item is the opening focus; the
  /// camera follows it only at opening or on the owner's tap, never on its own afterwards.
  var focuses: [InsideFocus] {
    var out: [InsideFocus] = []
    if quality == .held {
      out.append(focus(
        "marea-held", .blocking, .order(.marea), "Marea · удержана ОТК",
        "12 раковин ожидают повторного осмотра · рейс 02 не может выехать", .order(.marea)))
    }
    if needsAttention(.aria) {
      let late = Int((mainForecast.readyMinute - Self.ariaPlanMinute).rounded())
      let window = canActivateReserve ? " · резерв F-04 до 15:50" : ""
      out.append(focus(
        "aria-late", .urgent, .order(.aria), "Aria · срок готовности",
        late > 0 ? "+\(late) мин к плану 17:00\(window)" : "Очередь на обработку\(window)", .order(.aria)))
    }
    if quality == .ready {
      out.append(focus(
        "trip2-ready", .decision, .trip(.petersburg), "Рейс 02 готов к выезду",
        "Marea и Domino загружены · ожидает разрешения на выезд", .dispatch))
    }
    for trip in InsideTrip.allCases.reversed() where tripState(trip).onRoad {
      out.append(focus(
        "trip-\(trip.rawValue)", .live, .trip(trip), "\(trip.title) в пути",
        "\(trip.destination) · \(trip.cargo)", .dispatch))
    }
    if quality == .loading {
      out.append(focus(
        "loading", .live, .order(.marea), "Погрузка рейса 02", "Marea · упаковка → док 02", .dispatch))
    }
    if ariaPlan != nil && !ariaCompleted {
      out.append(focus("aria-work", .live, .order(.aria), "Aria в обработке", status(.aria), .order(.aria)))
    }
    // Last fallback only: no decision and no live process — the busiest hall.
    if out.isEmpty, let busiest = FactoryZone.allCases.max(by: { load($0) < load($1) }) {
      out.append(focus(
        "load-\(busiest.rawValue)", .load, .zone(busiest), busiest.title,
        "Загрузка \(load(busiest))% · \(summary(busiest))", .zone(busiest)))
    }
    return out.sorted { $0.kind < $1.kind }
  }
  var primaryFocus: InsideFocus { focuses[0] }
}

// MARK: - Business board

enum InsideMetricID: String, CaseIterable {
  case decisions, portfolio, production, accepted, ready, road
}

struct InsideMetric: Equatable {
  let id: InsideMetricID
  let title: String
  let value: String
  let detail: String
  let attention: Bool
  let focus: InsideFocus
}

/// Every board number comes from the simulation and the fixed demo orders — one source.
struct InsideBoard {
  static let productionZones: Set<FactoryZone> = [.casting, .finishing, .quality, .packing]

  let simulation: FactorySimulation

  var portfolio: Int { InsideOrderID.allCases.reduce(0) { $0 + $1.demoAmount } }
  /// Pieces of orders currently in production (casting → finishing → OTK → packing).
  var inProduction: [(InsideOrderID, FactoryZone)] {
    InsideOrderID.allCases.compactMap { order in
      let zone = simulation.zone(for: order)
      if order == .marea && [.loading, .ready, .departed].contains(simulation.quality) { return nil }
      return Self.productionZones.contains(zone) ? (order, zone) : nil
    }
  }
  var inProductionPieces: Int { inProduction.reduce(0) { $0 + $1.0.quantity } }
  /// Pieces waiting at the warehouse or the docks for a trip that has not left.
  var readyPieces: Int {
    var total = InsideOrderID.mirrors.quantity
    if !simulation.tripState(.moscow).onRoad { total += InsideTrip.moscow.pieces }
    if !simulation.tripState(.petersburg).onRoad {
      total += InsideOrderID.domino.quantity
      if [.loading, .ready].contains(simulation.quality) { total += InsideOrderID.marea.quantity }
    }
    return total
  }
  var tripsOnRoad: [InsideTrip] { InsideTrip.allCases.filter { simulation.tripState($0).onRoad } }

  var metrics: [InsideMetric] {
    let s = simulation
    let primary = s.primaryFocus
    let largest = inProduction.max { $0.0.quantity < $1.0.quantity }
    let productionSubject: InsideSubject = largest.map { .order($0.0) } ?? .zone(.casting)
    let roadTrip = tripsOnRoad.last ?? (s.quality == .ready || s.quality == .loading ? .petersburg : .moscow)
    let decisions = s.attentionCount
    return [
      InsideMetric(
        id: .decisions, title: "Решения", value: "\(decisions)",
        detail: decisions > 0 ? primary.title : "Все приняты", attention: decisions > 0, focus: primary),
      InsideMetric(
        id: .portfolio, title: "Портфель демо-заказов", value: compactRubles(portfolio),
        detail: "\(InsideOrderID.allCases.count) демо-заказов", attention: false,
        focus: s.focus(
          "portfolio", .live, .zone(.office), "Портфель демо-заказов",
          "\(InsideOrderID.allCases.count) демо-заказов · \(rubles(portfolio))", .orders)),
      InsideMetric(
        id: .production, title: "В работе", value: "\(inProductionPieces)",
        detail: "изделий · литьё → упаковка", attention: false,
        focus: s.focus(
          "production-\(largest?.0.rawValue ?? "none")", .live, productionSubject,
          largest.map { "\($0.0.product) · \($0.1.title)" } ?? FactoryZone.casting.title,
          largest.map { "\($0.0.quantity) шт. · \(s.status($0.0))" } ?? "Нет партий",
          largest.map { .order($0.0) } ?? .zone(.casting))),
      InsideMetric(
        id: .accepted, title: "Принято ОТК", value: "\(s.completed)/68",
        detail: "план смены", attention: s.quality == .held,
        focus: s.focus(
          "accepted", .live, .zone(.quality), "Контроль качества",
          "Принято \(s.completed) из 68 · \(s.status(.marea))", .zone(.quality))),
      InsideMetric(
        id: .ready, title: "К отгрузке", value: "\(readyPieces)",
        detail: "мест на складе и в доках", attention: s.quality == .ready,
        focus: s.focus(
          "ready", .live, s.quality == .loading || s.quality == .ready ? .order(.marea) : .zone(.warehouse),
          "Склад и доки", "\(readyPieces) мест · \(s.tripState(.petersburg).text)", .dispatch)),
      InsideMetric(
        id: .road, title: "В пути", value: "\(tripsOnRoad.count)",
        detail: tripsOnRoad.isEmpty ? "рейсы в доках" : tripsOnRoad.map(\.destination).joined(separator: " · "),
        attention: false,
        focus: s.focus(
          "road-\(roadTrip.rawValue)", .live, .trip(roadTrip), roadTrip.title,
          "\(s.tripState(roadTrip).text) · \(roadTrip.cargo)", .dispatch)),
    ]
  }
}

/// «6,25 млн ₽» — board-sized money with a non-breaking space before the sign.
func compactRubles(_ value: Int) -> String {
  if value >= 1_000_000 {
    let millions = Double(value) / 1_000_000
    return String(format: "%.2f", millions).replacingOccurrences(of: ".", with: ",") + "\u{00A0}млн\u{00A0}₽"
  }
  return rubles(value)
}
