import UIKit

/// Owner-only visual tokens. The collection experience keeps its own art direction.
enum InsideStyle {
  static let canvas = UIColor(hex: 0xF0F1F2)
  static let ink = UIColor(hex: 0x20262B)
  static let muted = UIColor(hex: 0x667079)
  static let blue = UIColor(hex: 0x355A6C)
  static let amber = UIColor(hex: 0x9A642A)
  static let green = UIColor(hex: 0x477460)
  static func loadColor(_ value: Int) -> UIColor { value >= 85 ? amber : blue }
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
  config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
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
