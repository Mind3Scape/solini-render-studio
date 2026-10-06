import UIKit

/// Manually selected collections. Ninfea contains its own film; it never turns the page.
final class CollectionGallery: UIView, UIScrollViewDelegate {
  struct Story {
    let id: String
    let name: String
    let image: String
    let headline: String
    let caption: String
    let focus: CGFloat
  }
  static let stories = [
    Story(
      id: "ninfea", name: "Ninfea", image: "ninfea-poster-v2", headline: "Природа\nобретает форму.",
      caption: "Вдохновлена водяной лилией.", focus: 0.5),
    Story(
      id: "aria", name: "Aria", image: "aria", headline: "Архитектура\nспокойствия.",
      caption: "Чистота линии. Сила формы.", focus: 0.5),
    Story(
      id: "opera", name: "Opera", image: "opera", headline: "Классика.\nВне времени.",
      caption: "Искусство повседневного ритуала.", focus: 0.46),
    Story(
      id: "greca", name: "Greca", image: "greca-editorial", headline: "Свой характер.\nСвой ритм.",
      caption: "Пластика камня в интерьере.", focus: 0.23),
  ]
  private let pager = UIScrollView()
  private var pages: [CollectionPage] = []
  private var selectors: [UIButton] = []
  private var previousWidth: CGFloat = 0
  private(set) var selectedIndex = 0
  var active = false { didSet { updatePlayback() } }
  var cinemaProgress: Double { pages.first?.cinema?.timeline.progress ?? 0 }
  var cinemaPaused: Bool { pages.first?.cinema?.userPaused ?? false }
  func restoreCinema(progress: Double, paused: Bool) {
    pages.first?.cinema?.restore(progress: progress, paused: paused)
  }
  init(progress: Double = 0, paused: Bool = false, open: @escaping (String) -> Void) {
    super.init(frame: .zero)
    pager.isPagingEnabled = true
    pager.showsHorizontalScrollIndicator = false
    pager.alwaysBounceHorizontal = true
    pager.isDirectionalLockEnabled = true
    pager.delegate = self
    pager.rounded(30)
    pager.translatesAutoresizingMaskIntoConstraints = false
    addSubview(pager)
    for story in Self.stories {
      let page = CollectionPage(story, progress: progress, paused: paused) { open(story.id) }
      pages.append(page)
      pager.addSubview(page)
    }
    let index = stack([], axis: .horizontal, spacing: 10)
    index.distribution = .fillEqually
    for (i, story) in Self.stories.enumerated() {
      let button = UIButton(type: .system)
      var configuration = UIButton.Configuration.plain()
      configuration.title = story.name
      configuration.subtitle = "0\(i + 1)"
      configuration.titleAlignment = .leading
      configuration.titlePadding = 5
      configuration.contentInsets = .init(top: 14, leading: 0, bottom: 13, trailing: 0)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 12, weight: .medium)
        return a
      }
      configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        return a
      }
      button.configuration = configuration
      button.accessibilityIdentifier = "collection.\(story.id)"
      button.accessibilityLabel = "Коллекция \(story.name)"
      button.addAction(UIAction { [weak self] _ in self?.select(i) }, for: .touchUpInside)
      index.addArrangedSubview(button)
      selectors.append(button)
    }
    index.translatesAutoresizingMaskIntoConstraints = false
    addSubview(index)
    NSLayoutConstraint.activate([
      pager.topAnchor.constraint(equalTo: topAnchor),
      pager.leadingAnchor.constraint(equalTo: leadingAnchor),
      pager.trailingAnchor.constraint(equalTo: trailingAnchor),
      pager.heightAnchor.constraint(equalTo: pager.widthAnchor, multiplier: 1.30),
      index.topAnchor.constraint(equalTo: pager.bottomAnchor, constant: 5),
      index.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      index.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      index.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    updateSelection(0)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let width = pager.bounds.width
    guard width > 0, width != previousWidth else { return }
    previousWidth = width
    for (i, page) in pages.enumerated() {
      page.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: pager.bounds.height)
    }
    pager.contentSize = CGSize(width: width * CGFloat(pages.count), height: pager.bounds.height)
    pager.contentOffset.x = CGFloat(selectedIndex) * width
  }
  func select(_ index: Int, animated: Bool = true) {
    guard pages.indices.contains(index) else { return }
    updateSelection(index)
    pager.setContentOffset(
      CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0),
      animated: animated && !UIAccessibility.isReduceMotionEnabled)
    UISelectionFeedbackGenerator().selectionChanged()
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard pager.bounds.width > 0 else { return }
    let progress = pager.contentOffset.x / pager.bounds.width
    for (i, page) in pages.enumerated() {
      page.parallax = UIAccessibility.isReduceMotionEnabled ? 0 : (CGFloat(i) - progress) * 24
    }
    updateSelection(max(0, min(pages.count - 1, Int(progress.rounded()))))
  }
  private func updateSelection(_ index: Int) {
    selectedIndex = index
    for (i, button) in selectors.enumerated() {
      button.configuration?.baseForegroundColor = i == index ? Palette.ink : Palette.muted
      button.accessibilityTraits = i == index ? [.button, .selected] : [.button]
      button.layer.borderWidth = 0
      pages[i].accessibilityElementsHidden = i != index
      let mark = button.viewWithTag(91) ?? UIView()
      mark.tag = 91
      if mark.superview == nil {
        mark.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(mark)
        NSLayoutConstraint.activate([
          mark.topAnchor.constraint(equalTo: button.topAnchor),
          mark.leadingAnchor.constraint(equalTo: button.leadingAnchor),
          mark.trailingAnchor.constraint(equalTo: button.trailingAnchor),
          mark.heightAnchor.constraint(equalToConstant: 1.5),
        ])
      }
      mark.backgroundColor = i == index ? Palette.ink : Palette.line
    }
    updatePlayback()
  }
  private func updatePlayback() {
    for (i, page) in pages.enumerated() { page.cinema?.active = active && i == selectedIndex }
  }
}

private final class CollectionPage: UIView {
  private let picture: UIImageView
  private let focus: CGFloat
  let cinema: NinfeaCinemaView?
  var parallax: CGFloat = 0 { didSet { setNeedsLayout() } }
  init(_ story: CollectionGallery.Story, progress: Double, paused: Bool, open: @escaping () -> Void)
  {
    picture = photo(story.image)
    focus = story.focus
    cinema = story.id == "ninfea" ? NinfeaCinemaView(progress: progress, paused: paused) : nil
    super.init(frame: .zero)
    clipsToBounds = true
    if let cinema {
      pin(cinema)
      pin(
        GradientView(
          colors: [
            .black.withAlphaComponent(0.40), .clear, .clear, .black.withAlphaComponent(0.58),
          ],
          locations: [0, 0.36, 0.70, 1]))
      let top = stack(
        [
          eyebrow("COLLEZIONE 01", color: .white.withAlphaComponent(0.78)),
          label("Ninfea", 44, .light, .white),
          label("Природа обретает форму.", 13, .regular, .white.withAlphaComponent(0.9)),
        ], spacing: 8)
      let controls = NinfeaCinemaControls(cinema: cinema, expand: open)
      for v in [top, controls] {
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22).isActive = true
        v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22).isActive = true
      }
      top.topAnchor.constraint(equalTo: topAnchor, constant: 26).isActive = true
      controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20).isActive = true
      return
    }
    addSubview(picture)
    pin(
      GradientView(
        colors: [.black.withAlphaComponent(0.28), .clear, .black.withAlphaComponent(0.7)],
        locations: [0, 0.45, 1]))
    let top = stack(
      [
        eyebrow("L’ANIMA DELL’ACQUA", color: .white.withAlphaComponent(0.72)),
        label(story.headline, 30, .regular, .white),
      ], spacing: 13)
    let link = ActionButton("", icon: "arrow.up.right", action: open)
    link.accessibilityLabel = "Открыть \(story.name)"
    link.accessibilityIdentifier = "hero.open.\(story.id)"
    link.configuration?.baseForegroundColor = .white
    link.widthAnchor.constraint(equalToConstant: 50).isActive = true
    let bottom = stack(
      [
        stack(
          [
            label(story.name, 39, .regular, .white),
            label(story.caption, 11, .regular, .white.withAlphaComponent(0.8)),
          ], spacing: 5),
        UIView(), link,
      ], axis: .horizontal, spacing: 6)
    bottom.alignment = .center
    for v in [top, bottom] {
      v.translatesAutoresizingMaskIntoConstraints = false
      addSubview(v)
      v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24).isActive = true
      v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22).isActive = true
    }
    top.topAnchor.constraint(equalTo: topAnchor, constant: 25).isActive = true
    bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -23).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard cinema == nil else { return }
    guard let image = picture.image, bounds.height > 0 else { return }
    let ratio = image.size.width / image.size.height
    let h = max(bounds.height, bounds.width / ratio) * 1.025
    let w = h * ratio
    picture.frame = CGRect(
      x: (bounds.width - w) * focus + parallax, y: (bounds.height - h) / 2, width: w, height: h)
  }
}
