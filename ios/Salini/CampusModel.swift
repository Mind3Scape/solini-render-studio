import SceneKit
import UIKit

// A designed business map, not a surveyed plan of the Salini plant.
enum FactoryZone: Int, CaseIterable {
  case office, materials, casting, finishing, assembly, quality, packing, warehouse, dispatch
  var title: String {
    [
      "Офис и заказы", "Материалы", "Минеральное литьё", "Обработка", "Комплектация", "Качество",
      "Упаковка", "Склад", "Логистика",
    ][rawValue]
  }
  var shortTitle: String {
    [
      "Офис", "Материалы", "Литьё", "Обработка", "Комплектация", "Качество", "Упаковка", "Склад",
      "Логистика",
    ][rawValue]
  }
  var icon: String {
    [
      "building.2", "circle.hexagongrid", "drop.fill", "sparkles", "cabinet", "checkmark.seal",
      "shippingbox", "square.stack.3d.up", "truck.box",
    ][rawValue]
  }
  var code: String { String(format: "%02d", rawValue + 1) }
  var position: SCNVector3 {
    let points: [(Float, Float)] = [
      (-43, 27), (-41, -29), (-5, -25), (27, -25), (-9, 17), (25, 6), (25, 31), (57, -12), (57, 32),
    ]
    return SCNVector3(points[rawValue].0, 0, points[rawValue].1)
  }
  var footprint: CGSize {
    let sizes: [(Int, Int)] = [
      (18, 18), (20, 22), (36, 32), (24, 32), (28, 30), (22, 16), (22, 18), (22, 48), (24, 20),
    ]
    return CGSize(width: sizes[rawValue].0, height: sizes[rawValue].1)
  }
  var buildingHeight: Float { [8, 6, 7, 7, 6, 5, 5, 9, 0][rawValue] }
  var count: Int { [18, 32, 24, 18, 16, 8, 12, 146, 3][rawValue] }
  var metric: String {
    [
      "18 заказов в портфеле", "32 партии сырья", "24 изделия в формах", "18 изделий на финише",
      "16 комплектов", "8 изделий на проверке", "12 мест к отправке", "146 изделий в наличии",
      "3 рейса сегодня",
    ][rawValue]
  }
  var state: String {
    [
      "От проекта до производственного задания", "S-Stone и S-Sense · запас на смену",
      "Ванны, раковины и душевые поддоны", "Шлифовка, цвет и финишная поверхность",
      "Мебель, зеркала и готовые комплекты", "Геометрия, поверхность и комплектность",
      "Защита каждого изделия в пути", "Адресное хранение и подбор заказов",
      "От ворот производства до партнёра",
    ][rawValue]
  }
  var people: Int { [12, 4, 18, 12, 8, 4, 6, 8, 4][rawValue] }
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
    }
  }
  static let orderRoute: [FactoryZone] = [
    .office, .materials, .casting, .finishing, .quality, .packing, .warehouse, .dispatch,
  ]
}

/// Equal X/Y/Z camera offsets give a true 35.264° elevation and 45° azimuth.
/// Orientation never changes: only the ground target and orthographic scale move.
struct CampusCamera {
  static let offset = SCNVector3(180, 180, 180)
  var focus = SCNVector3(3, 0, 0)
  var scale: Double = 95
  var viewport = CGSize(width: 402, height: 500)
  var overviewScale: Double {
    max(72, 100 * Double(viewport.height / max(1, viewport.width)))
  }
  mutating func overview() {
    focus = SCNVector3(3, 0, 0)
    scale = overviewScale
  }
  mutating func frame(_ zone: FactoryZone) {
    focus = zone.position
    let extent = Double(zone.footprint.width + zone.footprint.height) / sqrt(2)
    scale = max(24, extent * 0.68 * Double(viewport.height / max(1, viewport.width)))
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
    focus.x = min(70, max(-58, focus.x))
    focus.z = min(49, max(-45, focus.z))
  }
}
