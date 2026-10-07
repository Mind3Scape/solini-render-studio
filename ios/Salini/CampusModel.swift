import SceneKit
import UIKit

// A designed business map, not a surveyed plan of the Salini plant.
enum FactoryZone: Int, CaseIterable {
  case office, materials, casting, finishing, assembly, quality, packing, warehouse, dispatch, robotics
  var title: String {
    [
      "Офис и заказы", "Материалы", "Минеральное литьё", "Обработка", "Комплектация", "Качество",
      "Упаковка", "Склад", "Логистика", "Роботизированный комплекс",
    ][rawValue]
  }
  /// Complex 1: casting, finishing and logistics. Complex 2: the robotic cell and mould store.
  var complex: Int { self == .robotics ? 2 : 1 }
  var shortTitle: String {
    [
      "Офис", "Материалы", "Литьё", "Обработка", "Комплектация", "Качество", "Упаковка", "Склад",
      "Логистика", "Роботы",
    ][rawValue]
  }
  var icon: String {
    [
      "building.2", "circle.hexagongrid", "drop.fill", "sparkles", "cabinet", "checkmark.seal",
      "shippingbox", "square.stack.3d.up", "truck.box", "gearshape.2",
    ][rawValue]
  }
  var code: String { String(format: "%02d", rawValue + 1) }
  var position: SCNVector3 {
    let points: [(Float, Float)] = [
      (-69, 36), (-69, -40), (-14, -40), (35, -40), (-18, 36), (33, 16), (33, 52), (83, -36), (83, 42),
      (73, 140),
    ]
    return SCNVector3(points[rawValue].0, 0, points[rawValue].1)
  }
  var footprint: CGSize {
    let sizes: [(Int, Int)] = [
      (18, 18), (20, 22), (36, 32), (24, 32), (28, 30), (22, 16), (22, 18), (22, 48), (24, 20), (36, 30),
    ]
    return CGSize(width: sizes[rawValue].0, height: sizes[rawValue].1)
  }
  var buildingHeight: Float { [8, 6, 7, 7, 6, 5, 5, 9, 0, 8][rawValue] }
  var count: Int { [18, 32, 24, 18, 16, 8, 12, 146, 3, 6][rawValue] }
  var metric: String {
    [
      "18 заказов в портфеле", "32 партии сырья", "24 изделия в формах", "18 изделий на финише",
      "16 комплектов", "8 изделий на проверке", "12 мест к отправке", "146 изделий в наличии",
      "3 рейса сегодня", "6 изделий в ячейках",
    ][rawValue]
  }
  var state: String {
    [
      "От проекта до производственного задания", "S-Stone и S-Sense · запас на смену",
      "Ванны, раковины и душевые поддоны", "Шлифовка, цвет и финишная поверхность",
      "Мебель, зеркала и готовые комплекты", "Геометрия, поверхность и комплектность",
      "Защита каждого изделия в пути", "Адресное хранение и подбор заказов",
      "От ворот производства до партнёра", "Обрезка и сверление перевёрнутых ванн · комплекс 2",
    ][rawValue]
  }
  var people: Int { [12, 4, 18, 12, 8, 4, 6, 8, 4, 3][rawValue] }
  var detailRows: [(String, String)] {
    switch self {
    case .office:
      return [("Новые проекты", "6"), ("В производстве", "9"), ("Готовы к отгрузке", "3")]
    case .materials:
      return [("S-Stone", "18 партий"), ("S-Sense", "14 партий"), ("Следующая приёмка", "14:30")]
    case .casting:
      return [("Ванны", "10 форм"), ("Раковины", "8 форм"), ("Душевые поддоны", "6 форм")]
    case .finishing:
      return [
        ("S-Stone · матовая поверхность", "10 изделий"), ("S-Sense · покрытие", "8 изделий"),
        ("Цвет по RAL", "4 задания"),
      ]
    case .assembly:
      return [
        ("Мебель и столешницы", "7 комплектов"), ("Зеркала", "5 комплектов"),
        ("Комплектующие", "4 комплекта"),
      ]
    case .quality:
      return [
        ("Контроль геометрии", "3 изделия"), ("Контроль поверхности", "4 изделия"),
        ("Повторная проверка", "1 изделие"),
      ]
    case .packing:
      return [
        ("Крупногабаритные изделия", "4 места"), ("Раковины и поддоны", "5 мест"),
        ("Мебель и зеркала", "3 места"),
      ]
    case .warehouse:
      return [
        ("Ванны и поддоны", "62 изделия"), ("Раковины", "48 изделий"),
        ("Мебель и комплектующие", "36 изделий"),
      ]
    case .dispatch:
      return [
        ("Москва · рейс 01", "Погрузка"), ("Санкт-Петербург · рейс 02", "Готов к выезду"),
        ("Партнёрский рейс 03", "Ожидает"),
      ]
    case .robotics:
      return [
        ("R-01 · обрезка борта", "2 ванны"), ("R-02 · сверление перелива", "1 ванна"),
        ("Шаттл из литья", "каждые 20 мин"),
      ]
    }
  }
  static let orderRoute: [FactoryZone] = [
    .office, .materials, .casting, .finishing, .quality, .packing, .warehouse, .dispatch,
  ]
}

/// Shared geometry for the illustrative campus, roads, camera and logistics animations.
/// These are design units, not a survey or a claimed reconstruction of 12,000 m².
enum CampusSite {
  /// Two linked complexes on separate model plinths; complex 2 sits "below" complex 1 on screen
  /// so a portrait viewport is filled instead of showing one small island.
  static let complexOne = CGRect(x: -107, y: -85, width: 224, height: 170)
  static let complexTwo = CGRect(x: 40, y: 98, width: 130, height: 82)
  static let complexes = [complexOne, complexTwo]
  static let bounds = complexOne.union(complexTwo)
  /// Projected extents of both plinths: u = x − z (screen right), v = x + z (screen down).
  static let projectedRange: (u: ClosedRange<CGFloat>, v: ClosedRange<CGFloat>) = {
    var us: [CGFloat] = []
    var vs: [CGFloat] = []
    for r in complexes {
      for x in [r.minX, r.maxX] {
        for z in [r.minY, r.maxY] {
          us.append(x - z)
          vs.append(x + z)
        }
      }
    }
    return (us.min()!...us.max()!, vs.min()!...vs.max()!)
  }()
  /// Ground point whose projection is the middle of both plinths.
  static let center: SCNVector3 = {
    let u = (projectedRange.u.lowerBound + projectedRange.u.upperBound) / 2
    let v = (projectedRange.v.lowerBound + projectedRange.v.upperBound) / 2
    return SCNVector3(Float((u + v) / 2), 0, Float((v - u) / 2))
  }()
  /// Opening view: the production quarter of complex 1 (materials, casting, finishing) with the
  /// link to complex 2 in reach — closer than the full territory.
  static let quarterFocus = SCNVector3(8, 0, -14)
  /// The shuttle between the casting hall and the robotic cell, along roads only.
  static func shuttleRoute() -> [SCNVector3] {
    [SCNVector3(58, 0.35, -5), SCNVector3(58, 0.35, 72), SCNVector3(104, 0.35, 72),
     SCNVector3(104, 0.35, 95), SCNVector3(104, 0.35, 140), SCNVector3(97, 0.35, 140)]
  }
  static let gatePosition = SCNVector3(104, 0, 101)
  struct Road {
    let rect: CGRect
    let primary: Bool
    init(_ x: CGFloat, _ z: CGFloat, _ width: CGFloat, _ depth: CGFloat, primary: Bool = true) {
      rect = CGRect(x: x - width / 2, y: z - depth / 2, width: width, height: depth)
      self.primary = primary
    }
  }
  static let roads: [Road] = [
    Road(7, -72, 206, 12), Road(7, 72, 206, 12),
    Road(-90, 0, 12, 144), Road(104, 0, 12, 144),
    Road(7, -5, 182, 12), Road(58, 0, 12, 144, primary: false),
    Road(-43, 0, 10, 144, primary: false),
    // Link road between the complexes and the spine of complex 2.
    Road(104, 120, 12, 108), Road(105, 106, 128, 9, primary: false),
  ]
  static func roadSurfaces() -> (primary: CGPath, service: CGPath, outline: CGPath) {
    var primary: CGPath = CGMutablePath()
    var service: CGPath = CGMutablePath()
    for road in roads {
      let path = CGPath(rect: road.rect, transform: nil)
      if road.primary { primary = primary.union(path) } else { service = service.union(path) }
    }
    // Curved approaches belong to the service road; the spine remains one continuous tone.
    for (x, width): (CGFloat, CGFloat) in [(-43, 10), (58, 12)] {
      for sx: CGFloat in [-1, 1] {
        for sz: CGFloat in [-1, 1] {
          let half = width / 2
          let radius: CGFloat = 6
          let path = UIBezierPath()
          path.flatness = 0.05
          path.move(to: CGPoint(x: half, y: 6))
          path.addLine(to: CGPoint(x: half, y: 6 + radius))
          path.addArc(withCenter: CGPoint(x: half + radius, y: 6 + radius),
                      radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
          path.close()
          path.apply(CGAffineTransform(scaleX: sx, y: sz))
          path.apply(CGAffineTransform(translationX: x, y: -5))
          service = service.union(path.cgPath)
        }
      }
    }
    let outline = primary.union(service)
    return (primary, service.subtracting(primary), outline)
  }
  static var projectedSize: CGSize {
    CGSize(width: (projectedRange.u.upperBound - projectedRange.u.lowerBound) / sqrt(2),
           height: (projectedRange.v.upperBound - projectedRange.v.lowerBound) / sqrt(6))
  }
  static func transferRoute() -> [SCNVector3] {
    [SCNVector3(49, 0.1, 52), SCNVector3(58, 0.1, 52),
     SCNVector3(58, 0.1, 21), SCNVector3(83, 0.1, 21), SCNVector3(83, 0.1, 35)]
  }
  static func departureRoute(_ number: Int) -> [SCNVector3] {
    let x = FactoryZone.dispatch.position.x + Float((number - 2) * 7)
    return [SCNVector3(x, 0.4, 45), SCNVector3(x, 0.4, 72),
            SCNVector3(104, 0.4, 72), SCNVector3(104, 0.4, -91)]
  }
  /// Front-door spurs join the east-west spine through the actual open aisles.
  static func accessPath(_ zone: FactoryZone) -> [SCNVector3] {
    let p = zone.position
    let z = p.z + Float(zone.footprint.height / 2) + 3
    let door = SCNVector3(p.x, 0.55, z)
    let aisle: Float
    switch zone {
    case .office, .materials, .assembly: aisle = -43
    case .quality, .packing: aisle = 58
    case .dispatch: aisle = 104
    case .casting, .finishing, .warehouse: aisle = p.x
    case .robotics:
      // Out through the open east side to the link road, then north to the spine.
      let side = SCNVector3(p.x + Float(zone.footprint.width / 2) + 3, 0.55, p.z)
      return [side, SCNVector3(104, 0.55, p.z), SCNVector3(104, 0.55, 72), SCNVector3(104, 0.55, -5)]
    }
    return [door, SCNVector3(aisle, 0.55, z), SCNVector3(aisle, 0.55, -5)]
  }
  static func processRoute(_ zones: [FactoryZone]) -> [SCNVector3] {
    guard let first = zones.first else { return [] }
    var points = accessPath(first)
    for zone in zones.dropFirst() {
      let path = accessPath(zone)
      points.append(contentsOf: path.reversed())
      if zone != zones.last { points.append(contentsOf: path.dropFirst()) }
    }
    return points
  }
}

/// Equal X/Y/Z camera offsets give a true 35.264° elevation and 45° azimuth.
/// Orientation never changes: only the ground target and orthographic scale move.
struct CampusCamera {
  static let offset = SCNVector3(180, 180, 180)
  var focus = CampusSite.center
  var scale: Double = 95
  var viewport = CGSize(width: 402, height: 500)
  var overviewScale: Double {
    max(Double(CampusSite.projectedSize.height) * 0.58,
        Double(CampusSite.projectedSize.width) * 0.55 * Double(viewport.height / max(1, viewport.width)))
  }
  mutating func overview() {
    focus = CampusSite.center
    scale = overviewScale
  }
  /// Closer opening view of the production quarter; the minimap keeps both complexes in sight.
  mutating func quarter() {
    focus = CampusSite.quarterFocus
    scale = max(48, overviewScale * 0.42)
  }
  mutating func frame(_ zone: FactoryZone) {
    focus = zone.position
    let extent = Double(zone.footprint.width + zone.footprint.height) / sqrt(2)
    // A focused hall spans ~78% of the visible width so its equipment reads at once.
    scale = max(20, extent * 0.64 * Double(viewport.height / max(1, viewport.width)))
  }
  mutating func pan(_ translation: CGPoint, from origin: SCNVector3) {
    let units = Float(2 * scale / Double(max(1, viewport.height)))
    let right = Float(translation.x) * units / sqrt(2)
    let forward = Float(translation.y) * units * sqrt(1.5)
    focus = SCNVector3(origin.x - right - forward, 0, origin.z + right - forward)
    clamp()
  }
  mutating func zoom(_ proposedScale: Double) {
    scale = min(overviewScale * 1.15, max(16, proposedScale))
  }
  mutating func clamp() {
    // The link road lets the view travel south into complex 2; elsewhere it stays on a plinth.
    focus.x = min(160, max(-90, focus.x))
    focus.z = min(172, max(-72, focus.z))
    if focus.z > 80 { focus.x = max(48, focus.x) }
  }
}
