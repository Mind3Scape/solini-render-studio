import UIKit

/// A quiet orientation aid. It shares the same immutable isometric basis as the scene.
final class CampusOverview: UIControl {
  var camera = CampusCamera() { didSet { setNeedsDisplay() } }
  var selectedZone: FactoryZone? { didSet { setNeedsDisplay() } }
  var onSelect: ((FactoryZone) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = InsideStyle.canvas.withAlphaComponent(0.96)
    layer.cornerRadius = 16
    clipsToBounds = true
    layer.borderColor = InsideStyle.ink.withAlphaComponent(0.12).cgColor
    layer.borderWidth = 0.5
    accessibilityLabel = "Мини-карта территории"
    accessibilityHint = "Выберите корпус"
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(choose(_:))))
  }
  required init?(coder: NSCoder) { fatalError() }
  private var modelScale: CGFloat { min((bounds.width - 14) / 180, (bounds.height - 12) / 106) }
  private func point(_ x: CGFloat, _ z: CGFloat) -> CGPoint {
    CGPoint(
      x: bounds.midX + (x - z - 5) / sqrt(2) * modelScale,
      y: bounds.midY + (x + z - 5) / sqrt(6) * modelScale)
  }
  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    for zone in FactoryZone.allCases {
      let x = CGFloat(zone.position.x)
      let z = CGFloat(zone.position.z)
      let w = zone.footprint.width / 2
      let h = zone.footprint.height / 2
      let points = [
        point(x - w, z - h), point(x + w, z - h), point(x + w, z + h), point(x - w, z + h),
      ]
      context.addLines(between: points)
      context.closePath()
      context.setFillColor(
        (selectedZone == zone ? InsideStyle.blue : UIColor(hex: 0xB7C5C9)).cgColor)
      context.fillPath()
    }
    if camera.scale < camera.overviewScale * 0.85 {
      let center = point(CGFloat(camera.focus.x), CGFloat(camera.focus.z))
      let width =
        CGFloat(camera.scale * 2) / max(0.1, camera.viewport.height / camera.viewport.width)
        * modelScale
      let height = CGFloat(camera.scale * 2) * modelScale
      let rect = CGRect(
        x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
      context.setStrokeColor(UIColor(hex: 0x527E92).cgColor)
      context.setLineWidth(1)
      context.stroke(rect)
    }
  }
  @objc private func choose(_ gesture: UITapGestureRecognizer) {
    let p = gesture.location(in: self)
    let nearest = FactoryZone.allCases.min {
      let a = point(CGFloat($0.position.x), CGFloat($0.position.z))
      let b = point(CGFloat($1.position.x), CGFloat($1.position.z))
      return hypot(a.x - p.x, a.y - p.y) < hypot(b.x - p.x, b.y - p.y)
    }
    if let nearest { onSelect?(nearest) }
  }
}
