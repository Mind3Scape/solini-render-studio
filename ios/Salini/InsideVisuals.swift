import UIKit

/// Owner-only visual tokens. The collection experience keeps its own art direction.
enum InsideStyle {
  static let canvas = UIColor(hex: 0xF3F4F5)
  // Cool concrete and asphalt let warm facades and living planting carry the colour.
  static let asphalt = UIColor(hex: 0x6C787E)
  static let serviceRoad = UIColor(hex: 0x98A4A9)
  static let paving = UIColor(hex: 0xD3D2CB)
  static let lawn = UIColor(hex: 0x8AB27B)
  static let foliage = UIColor(hex: 0x4E8A5B)
  static let ink = UIColor(hex: 0x20262B)
  static let muted = UIColor(hex: 0x667079)
  static let blue = UIColor(hex: 0x355A6C)
  static let amber = UIColor(hex: 0x9A642A)
  static let green = UIColor(hex: 0x477460)
  // Industrial equipment palette (production references): machine blue, mould green, ochre
  // guards, deep graphite metal and warm concrete. White products stay the brightest accent.
  static let machineBlue = UIColor(hex: 0x2F5D8A)
  static let mouldGreen = UIColor(hex: 0x2E6B52)
  static let guardOchre = UIColor(hex: 0xD2A23A)
  static let gunmetal = UIColor(hex: 0x2E3439)
  static let warmConcrete = UIColor(hex: 0xD9D3C8)
  static let casting = UIColor(hex: 0xEFEAE0)
  static func loadColor(_ value: Int) -> UIColor { value >= 85 ? amber : blue }
}

/// Map-only architectural identity. Illustrative process colours, not Salini corporate data.
extension FactoryZone {
  /// A restrained, saturated tone used on equipment and the fascia band of each hall.
  var accent: UIColor {
    let tones: [UInt] = [
      0x8B5E3F, 0xC08A35, 0x2E6B52, 0x2F5D8A, 0x8A5A3C, 0x3E8C68, 0xB7823F, 0x35597A, 0xC99A2E, 0x2F5D8A,
    ]
    return UIColor(hex: tones[rawValue])
  }
  /// Warm, near-white facade panels; each hall differs only slightly in temperature.
  var facade: UIColor {
    let tones: [UInt] = [
      0xF3EEE6, 0xEFE8DC, 0xF2EDE5, 0xEEF0EE, 0xF1E9DF, 0xF4F3EF, 0xF0EAE0, 0xE7ECEE, 0xF1EEE8, 0xECEEEC,
    ]
    return UIColor(hex: tones[rawValue])
  }
}

func insideEyebrow(_ text: String, color: UIColor = InsideStyle.muted) -> UILabel {
  let view = label(text, 10, .medium, color)
  view.attributedText = NSAttributedString(
    string: text, attributes: [.kern: 0.85, .font: view.font as Any, .foregroundColor: color])
  return view
}

/// A small drawn annotation with a 44 pt touch target, anchored to the scene below it.
final class CampusAnnotation: UIButton {
  private let caption = UILabel()
  private let leader = CAShapeLayer()
  var text = "" {
    didSet {
      caption.text = text
      invalidateIntrinsicContentSize()
    }
  }
  var color = InsideStyle.ink {
    didSet {
      caption.textColor = color
      leader.strokeColor = color.withAlphaComponent(0.55).cgColor
    }
  }
  var emphasized = false {
    didSet {
      caption.backgroundColor = emphasized ? .white : InsideStyle.canvas.withAlphaComponent(0.9)
      caption.layer.borderWidth = emphasized ? 0.5 : 0
      caption.layer.borderColor = color.withAlphaComponent(0.25).cgColor
      caption.font = .monospacedDigitSystemFont(ofSize: emphasized ? 12 : 11, weight: .medium)
      invalidateIntrinsicContentSize()
    }
  }
  init(_ text: String, action: @escaping () -> Void) {
    super.init(frame: .zero)
    self.text = text
    caption.text = text
    caption.textAlignment = .center
    caption.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    caption.textColor = InsideStyle.ink
    caption.backgroundColor = InsideStyle.canvas.withAlphaComponent(0.9)
    caption.layer.cornerRadius = 5
    caption.clipsToBounds = true
    caption.isUserInteractionEnabled = false
    addSubview(caption)
    leader.lineWidth = 0.6
    leader.strokeColor = InsideStyle.muted.withAlphaComponent(0.55).cgColor
    leader.fillColor = UIColor.clear.cgColor
    layer.addSublayer(leader)
    addAction(UIAction { _ in action() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: CGSize {
    CGSize(width: max(44, caption.intrinsicContentSize.width + 16), height: 46)
  }
  override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
  override func layoutSubviews() {
    super.layoutSubviews()
    caption.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 26)
    let p = UIBezierPath()
    p.move(to: CGPoint(x: bounds.midX, y: 28))
    p.addLine(to: CGPoint(x: bounds.midX, y: 41))
    p.append(UIBezierPath(ovalIn: CGRect(x: bounds.midX - 1.5, y: 41, width: 3, height: 3)))
    leader.path = p.cgPath
  }
  override var isHighlighted: Bool {
    didSet { alpha = isHighlighted ? 0.6 : 1 }
  }
}

func insideAction(
  _ title: String, icon: String? = nil, prominent: Bool = false,
  action: @escaping () -> Void
) -> UIButton {
  let button = UIButton(type: .system)
  var config = prominent ? UIButton.Configuration.prominentGlass() : .plain()
  config.title = title
  config.baseForegroundColor = prominent ? .white : InsideStyle.ink
  config.baseBackgroundColor = prominent ? InsideStyle.ink : .clear
  config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
  config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
    var value = $0
    value.font = .systemFont(ofSize: 14, weight: .medium)
    return value
  }
  if let icon, !icon.isEmpty {
    config.image = UIImage(systemName: icon)
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 15, weight: .regular)
    config.imagePlacement = .trailing
    config.imagePadding = 10
  }
  button.configuration = config
  button.addAction(
    UIAction { _ in
      UISelectionFeedbackGenerator().selectionChanged()
      action()
    }, for: .touchUpInside)
  button.accessibilityLabel = title
  return button
}
