import SafariServices
import UIKit

final class NinfeaStoryController: UIViewController, UIAdaptivePresentationControllerDelegate {
  private let cinema: NinfeaCinemaView
  private let slider = UISlider()
  private var chapters: [UIButton] = []
  private var scrubbing = false
  private let play = UIButton(type: .system)
  private var currentChapter = -1
  private var lastPlaying: Bool?
  var onClose: ((Double, Bool) -> Void)?
  init(progress: Double = 0, paused: Bool = false) {
    cinema = NinfeaCinemaView(progress: progress, paused: paused)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(hex: 0x0C1714)
    let art = UIView()
    art.pin(cinema)
    art.pin(
      GradientView(
        colors: [
          UIColor(hex: 0x0C1714), .clear, .clear,
          UIColor(hex: 0x0C1714),
        ], locations: [0, 0.13, 0.76, 1]))
    art.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(art)
    NSLayoutConstraint.activate([
      art.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      art.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 1.5),
      art.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
    ])
    let close = smallButton("xmark", name: "Закрыть историю Ninfea", id: "ninfea.close") {
      [weak self] in
      guard let self else { return }
      self.onClose?(self.cinema.timeline.progress, self.cinema.userPaused)
      self.dismiss(animated: true)
    }
    let more = smallButton("info", name: "О коллекции Ninfea", id: "ninfea.info") {
      [weak self] in self?.showInformation()
    }
    let wordmark = UIImageView(
      image: UIImage(named: "salini-logo.png")?.withRenderingMode(.alwaysTemplate))
    wordmark.tintColor = .white
    wordmark.contentMode = .scaleAspectFit
    wordmark.widthAnchor.constraint(equalToConstant: 78).isActive = true
    wordmark.height(32)
    let leftSpace = UIView()
    let rightSpace = UIView()
    let header = stack(
      [close, leftSpace, wordmark, rightSpace, more], axis: .horizontal, spacing: 16)
    leftSpace.widthAnchor.constraint(equalTo: rightSpace.widthAnchor).isActive = true
    header.alignment = .center
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
    ])

    let title = stack(
      [
        eyebrow("L’ANIMA DELL’ACQUA", color: .white.withAlphaComponent(0.62)),
        label("Ninfea", 50, .light, .white),
      ], spacing: 10)
    title.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(title)
    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 28),
      title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
    ])

    let chapterRow = stack([], axis: .horizontal, spacing: 8)
    chapterRow.distribution = .fillEqually
    for (index, name) in NinfeaTimeline.chapterNames.enumerated() {
      let button = UIButton(type: .system)
      var config = UIButton.Configuration.plain()
      config.title = "0\(index + 1)  \(name)"
      config.baseForegroundColor = .white
      config.contentInsets = .init(top: 13, leading: 0, bottom: 13, trailing: 0)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .systemFont(ofSize: 12, weight: .medium)
        return a
      }
      button.configuration = config
      button.accessibilityIdentifier = "ninfea.chapter.\(index)"
      button.accessibilityLabel = "Ninfea: \(name)"
      button.addAction(
        UIAction { [weak self] _ in
          self?.cinema.chapter(index)
          UISelectionFeedbackGenerator().selectionChanged()
        }, for: .touchUpInside)
      chapterRow.addArrangedSubview(button)
      chapters.append(button)
    }
    slider.minimumValue = 0
    slider.maximumValue = 1
    slider.minimumTrackTintColor = .white.withAlphaComponent(0.9)
    slider.maximumTrackTintColor = .white.withAlphaComponent(0.22)
    slider.thumbTintColor = .white
    slider.accessibilityIdentifier = "ninfea.timeline"
    slider.accessibilityLabel = "Момент истории Ninfea"
    slider.addAction(UIAction { [weak self] _ in self?.scrubbing = true }, for: .touchDown)
    slider.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.cinema.seek(Double(self.slider.value))
      }, for: .valueChanged)
    slider.addAction(
      UIAction { [weak self] _ in self?.scrubbing = false },
      for: [.touchUpInside, .touchUpOutside, .touchCancel])
    var config = UIButton.Configuration.glass()
    config.cornerStyle = .capsule
    config.baseForegroundColor = .white
    config.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
    play.configuration = config
    play.widthAnchor.constraint(equalToConstant: 44).isActive = true
    play.height(44)
    play.accessibilityIdentifier = "ninfea.fullscreen.play"
    play.addAction(UIAction { [weak self] _ in self?.cinema.togglePlayback() }, for: .touchUpInside)
    let replay = smallButton(
      "arrow.counterclockwise", name: "Смотреть Ninfea с начала", id: "ninfea.replay"
    ) {
      [weak self] in self?.cinema.replay()
    }
    let progressRow = stack([play, slider, replay], axis: .horizontal, spacing: 18)
    progressRow.alignment = .center
    let caption = label("Природа обретает форму.", 20, .regular, .white)
    caption.textAlignment = .center
    let bottom = stack([caption, chapterRow, progressRow], spacing: 12)
    bottom.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bottom)
    NSLayoutConstraint.activate([
      bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
      bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
      bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
    ])
    cinema.onFrame = { [weak self] timeline, playing in self?.update(timeline, playing: playing) }
    update(cinema.timeline, playing: false)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    cinema.active = true
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    cinema.active = false
  }
  private func smallButton(_ icon: String, name: String, id: String, action: @escaping () -> Void)
    -> UIButton
  {
    let button = ActionButton("", icon: icon, action: action)
    button.configuration?.baseForegroundColor = .white
    button.configuration?.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.height(44)
    button.accessibilityLabel = name
    button.accessibilityIdentifier = id
    return button
  }
  private func update(_ timeline: NinfeaTimeline, playing: Bool) {
    if !scrubbing { slider.value = Float(timeline.progress) }
    slider.accessibilityValue = "\(Int(timeline.seconds)) из 22 секунд"
    play.isHidden = UIAccessibility.isReduceMotionEnabled || !cinema.available
    let image = playing ? "pause.fill" : "play.fill"
    if lastPlaying != playing {
      lastPlaying = playing
      play.configuration?.image = UIImage(systemName: image)
      play.accessibilityLabel =
        playing ? "Приостановить историю Ninfea" : "Продолжить историю Ninfea"
    }
    guard currentChapter != timeline.chapter else { return }
    currentChapter = timeline.chapter
    for (index, button) in chapters.enumerated() {
      button.configuration?.baseForegroundColor =
        index == currentChapter ? .white : .white.withAlphaComponent(0.45)
      button.accessibilityTraits = index == currentChapter ? [.button, .selected] : [.button]
    }
  }
  private func showInformation() {
    cinema.active = false
    let info = NinfeaInformationController()
    info.onClose = { [weak self] in self?.cinema.active = true }
    let nav = UINavigationController(rootViewController: info)
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    nav.presentationController?.delegate = self
    present(nav, animated: true)
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    cinema.active = true
  }
}

final class NinfeaInformationController: ScrollController {
  var onClose: (() -> Void)?
  private func section(_ child: UIView, top: CGFloat, bottom: CGFloat, inset: CGFloat = 24) {
    let wrapper = UIView()
    child.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(child)
    NSLayoutConstraint.activate([
      child.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: top),
      child.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -bottom),
      child.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -inset),
    ])
    add(wrapper, inset: 0)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Ninfea"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        self.dismiss(animated: true, completion: self.onClose)
      })
    section(
      stack(
        [
          eyebrow("DESIGN · MAURIZIO MANZONI"),
          label("Форма\nводяной лилии.", 36),
          label(
            "Широкие горизонтальные крылья, мягкая чаша и ощущение покоя на воде. Идея водяной лилии заложена в самой коллекции Ninfea.",
            16, .regular, Palette.muted),
        ], spacing: 17), top: 24, bottom: 26)
    let original = UIImageView(image: UIImage(named: "ninfea-official.webp"))
    original.contentMode = .scaleAspectFill
    original.height(220)
    original.rounded(22)
    section(original, top: 0, bottom: 9, inset: 18)
    section(
      label("Оригинальное изображение Salini", 10, .regular, Palette.muted), top: 0, bottom: 24)
    section(
      stack(
        [
          label("1800 × 820 × 575 мм", 23),
          label("Ванна Ninfea · дизайн Маурицио Мандзони", 13, .regular, Palette.muted),
          line(),
          label("S-Stone + S-Shine", 21),
          label(
            "Матовый минеральный материал и полупрозрачное основание. В коллекции также есть напольная и накладная раковины.",
            15, .regular, Palette.muted),
          ActionButton("Коллекция Salini", icon: "arrow.up.right") { [weak self] in
            guard let url = URL(string: "https://salini-srl.com/collection/ninfea/") else { return }
            self?.present(SFSafariViewController(url: url), animated: true)
          },
          label(
            "Водный сад — авторская визуальная история для концепта приложения. Изображения созданы с ИИ по фотографиям Ninfea; это не съёмка готового интерьера и не цветопроба.",
            11, .regular, Palette.muted),
        ], spacing: 17), top: 0, bottom: 24)
  }
}
