import UIKit

enum Palette {
  static let paper = UIColor(hex: 0xF7F7F8)
  static let ink = UIColor(hex: 0x17191D)
  static let muted = UIColor(hex: 0x7A7D85)
  static let lime = UIColor(hex: 0xE3E5EA)
  static let line = UIColor(hex: 0xE2E3E7)
  static let clay = UIColor(hex: 0xBD7E60)
}
extension UIColor {
  convenience init(hex: UInt, alpha: CGFloat = 1) {
    self.init(
      red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
      blue: CGFloat(hex & 255) / 255, alpha: alpha)
  }
}
func label(
  _ text: String, _ size: CGFloat = 16, _ weight: UIFont.Weight = .regular,
  _ color: UIColor = Palette.ink, serif: Bool = false
) -> UILabel {
  let l = UILabel()
  l.text = text
  l.numberOfLines = 0
  l.textColor = color
  let base = UIFont.systemFont(ofSize: size, weight: serif ? .regular : weight)
  l.font = UIFontMetrics(forTextStyle: size >= 28 ? .title1 : .body).scaledFont(
    for: base, maximumPointSize: size * 1.35)
  l.adjustsFontForContentSizeCategory = true
  return l
}
func eyebrow(_ text: String, color: UIColor = Palette.muted) -> UILabel {
  let l = label(text, 10, .semibold, color)
  l.attributedText = NSAttributedString(
    string: text, attributes: [.kern: 2.1, .font: l.font as Any, .foregroundColor: color])
  return l
}
func stack(_ views: [UIView], axis: NSLayoutConstraint.Axis = .vertical, spacing: CGFloat = 12)
  -> UIStackView
{
  let s = UIStackView(arrangedSubviews: views)
  s.axis = axis
  s.spacing = spacing
  return s
}
func spacer(_ height: CGFloat = 16) -> UIView {
  let v = UIView()
  v.heightAnchor.constraint(equalToConstant: height).isActive = true
  return v
}
func line() -> UIView {
  let v = UIView()
  v.backgroundColor = Palette.line
  v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
  return v
}
extension UIView {
  func pin(_ child: UIView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false
    addSubview(child)
    NSLayoutConstraint.activate([
      child.topAnchor.constraint(equalTo: topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
      child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
    ])
  }
  func inset(_ amount: CGFloat = 24) -> UIView {
    let wrapper = UIView()
    wrapper.pin(self, inset: amount)
    return wrapper
  }
  func inset(_ insets: UIEdgeInsets) -> UIView {
    let wrapper = UIView()
    translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(self)
    NSLayoutConstraint.activate([
      topAnchor.constraint(equalTo: wrapper.topAnchor, constant: insets.top),
      bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -insets.bottom),
      leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: insets.left),
      trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -insets.right),
    ])
    return wrapper
  }
  func rounded(_ radius: CGFloat = 24) {
    layer.cornerRadius = radius
    layer.cornerCurve = .continuous
    clipsToBounds = true
  }
  func height(_ h: CGFloat) { heightAnchor.constraint(equalToConstant: h).isActive = true }
}
func photo(_ name: String, height: CGFloat? = nil) -> UIImageView {
  let v = UIImageView(image: UIImage(named: name + ".jpg"))
  v.contentMode = .scaleAspectFill
  v.clipsToBounds = true
  v.isAccessibilityElement = false
  if let height { v.height(height) }
  return v
}
func symbol(_ name: String, size: CGFloat = 20, color: UIColor = Palette.ink) -> UIImageView {
  let v = UIImageView(
    image: UIImage(
      systemName: name,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)))
  v.tintColor = color
  v.contentMode = .scaleAspectFit
  v.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
  return v
}

final class ActionButton: UIButton {
  init(_ title: String, icon: String? = nil, prominent: Bool = false, action: @escaping () -> Void)
  {
    super.init(frame: .zero)
    var c = prominent ? UIButton.Configuration.prominentGlass() : .glass()
    c.title = title
    c.baseForegroundColor = prominent ? .white : Palette.ink
    if prominent { c.baseBackgroundColor = Palette.ink }
    c.cornerStyle = .capsule
    c.contentInsets = NSDirectionalEdgeInsets(top: 17, leading: 22, bottom: 17, trailing: 22)
    c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var a = incoming
      a.font = .systemFont(ofSize: 15, weight: .semibold)
      return a
    }
    if let icon {
      c.image = UIImage(systemName: icon)
      c.imagePadding = 10
      c.imagePlacement = .trailing
    }
    configuration = c
    addAction(
      UIAction { _ in
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        action()
      }, for: .touchUpInside)
    accessibilityLabel = title
  }
  required init?(coder: NSCoder) { fatalError() }
}
final class GlassView: UIVisualEffectView {
  init(tint: UIColor? = nil, clear: Bool = false) {
    let effect = UIGlassEffect(style: clear ? .clear : .regular)
    effect.tintColor = tint
    effect.isInteractive = true
    super.init(effect: effect)
    rounded(26)
  }
  required init?(coder: NSCoder) { fatalError() }
}
final class GradientView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }
  init(colors: [UIColor], locations: [NSNumber]? = nil) {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    let g = layer as! CAGradientLayer
    g.colors = colors.map(\.cgColor)
    g.locations = locations
  }
  required init?(coder: NSCoder) { fatalError() }
}
class ScrollController: UIViewController {
  let scroll = UIScrollView()
  let content = UIStackView()
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    content.axis = .vertical
    content.spacing = 0
    view.pin(scroll)
    scroll.showsVerticalScrollIndicator = false
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(
        equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -36),
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(false, animated: animated)
  }
  func add(_ view: UIView, inset: CGFloat = 24) {
    content.addArrangedSubview(inset == 0 ? view : view.inset(inset))
  }
  func showProduct(_ product: Product) {
    guard let match = Catalog.shared.product(for: product) else { return }
    navigationController?.pushViewController(CatalogProductController(match.0, variantKey: match.1?.key), animated: true)
  }
  func message(_ title: String, _ text: String) {
    let a = UIAlertController(title: title, message: text, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Понятно", style: .default))
    present(a, animated: true)
  }
}
func horizontal(_ views: [UIView], width: CGFloat, height: CGFloat) -> UIScrollView {
  let scroll = UIScrollView()
  scroll.showsHorizontalScrollIndicator = false
  scroll.height(height)
  let row = stack(views, axis: .horizontal, spacing: 14)
  row.translatesAutoresizingMaskIntoConstraints = false
  scroll.addSubview(row)
  NSLayoutConstraint.activate([
    row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
    row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
    row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
    row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
    row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
  ])
  for view in views { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
  return scroll
}
extension UIViewController {
  var appScene: SceneDelegate? { view.window?.windowScene?.delegate as? SceneDelegate }
  func sheet(_ vc: UIViewController) {
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.medium(), .large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    present(nav, animated: true)
  }
}
