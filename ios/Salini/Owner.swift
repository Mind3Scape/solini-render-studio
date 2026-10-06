import SceneKit
import UIKit

final class OwnerController: UIViewController {
  let simulation = FactorySimulation()
  private let factory = FactorySceneView()
  private let minimap = CampusOverview()
  private let dockContent = UIStackView()
  private let zoneRail = UIStackView()
  private let zoneScroll = UIScrollView()
  private let eventText = label("Перемещайте карту одним пальцем", 11, .medium, Palette.muted)
  private let live = label("ДЕМО · LIVE", 10, .semibold, UIColor(hex: 0x3975D9))
  private let complete = label("42", 25, .semibold)
  private var timer: Timer?
  private var seconds = 0
  private var speed = 1
  private var selected: FactoryZone?
  private var tourIndex: Int?
  private var tourSeconds = 0
  private var pauseButton: UIButton!
  private var speedButton: UIButton!
  private var roofButton: UIButton!
  private var zoneButtons: [UIButton] = []
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(hex: 0xEDF0F2)
    factory.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(factory)
    NSLayoutConstraint.activate([
      factory.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      factory.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      factory.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 121),
      factory.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -187),
    ])
    factory.onSelect = { [weak self] zone in self?.select(zone) }
    factory.onExplore = { [weak self] in self?.stopTour() }
    factory.onViewport = { [weak self] camera in self?.minimap.camera = camera }
    minimap.onSelect = { [weak self] zone in self?.select(zone) }
    makeHeader()
    makeDock()
    makeControls()
    renderDock()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
    factory.setPaused(simulation.paused)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick()
    }
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    timer?.invalidate()
    timer = nil
    factory.setPaused(true)
    factory.isPlaying = false
  }
  private func iconButton(_ icon: String, _ name: String, action: @escaping () -> Void) -> UIButton
  {
    let b = ActionButton("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.accessibilityIdentifier = "inside.\(icon)"
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 11, leading: 11, bottom: 11, trailing: 11)
    return b
  }
  private func makeHeader() {
    let back = iconButton("chevron.left", "Закрыть Salini Inside") { [weak self] in
      self?.navigationController?.popViewController(animated: true)
    }
    let info = iconButton("info", "О производственном демо") { [weak self] in
      self?.sheet(AboutController())
    }
    let title = stack(
      [
        label("Salini Inside", 19, .semibold),
        label("Компания в пространстве", 11, .regular, Palette.muted),
      ], spacing: 3)
    let heading = stack([back, title, UIView(), info], axis: .horizontal, spacing: 12)
    heading.alignment = .center
    let metrics = stack(
      [
        metric(label("12 000+", 23, .medium), "м² производства¹"),
        metric(label("9", 23, .medium), "зон на карте"),
        metric(complete, "готово · демо"),
      ], axis: .horizontal, spacing: 0)
    metrics.distribution = .fillEqually
    let header = stack([heading, metrics], spacing: 18)
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 7),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
    ])
  }
  private func metric(_ value: UILabel, _ title: String) -> UIView {
    let v = stack([value, label(title, 10, .medium, Palette.muted)], spacing: 4)
    v.alignment = .center
    return v
  }
  private func makeControls() {
    pauseButton = iconButton("pause", "Приостановить демо") { [weak self] in
      self?.togglePause()
    }
    speedButton = iconButton("forward", "Скорость анимации") { [weak self] in
      guard let self else { return }
      self.speed = self.speed == 1 ? 3 : 1
      self.factory.simulationSpeed = CGFloat(self.speed)
      self.speedButton.configuration?.image = nil
      self.speedButton.configuration?.title = "\(self.speed)×"
      self.speedButton.accessibilityLabel = "Скорость \(self.speed)×"
    }
    speedButton.configuration?.image = nil
    speedButton.configuration?.title = "1×"
    roofButton = iconButton("square.3.layers.3d", "Открыть все корпуса") { [weak self] in
      guard let self else { return }
      self.factory.setRoof(!self.factory.roofVisible)
      self.roofButton.accessibilityLabel =
        self.factory.roofVisible ? "Открыть все корпуса" : "Показать крыши"
    }
    let reset = iconButton("viewfinder", "Вся территория") { [weak self] in self?.overview() }
    let closer = iconButton("plus", "Приблизить карту") { [weak self] in
      self?.factory.stepZoom(true)
    }
    let farther = iconButton("minus", "Отдалить карту") { [weak self] in
      self?.factory.stepZoom(false)
    }
    let tools = stack([closer, farther, reset, roofButton], spacing: 8)
    tools.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tools)
    NSLayoutConstraint.activate([
      tools.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      tools.topAnchor.constraint(equalTo: factory.topAnchor, constant: 48),
    ])
    let liveRow = stack(
      [symbol("circle.fill", size: 5, color: UIColor(hex: 0x537F85)), live], axis: .horizontal,
      spacing: 5)
    liveRow.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(liveRow)
    let iso = label("ИЗОМЕТРИЯ", 9, .medium, Palette.muted)
    iso.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(iso)
    minimap.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(minimap)
    let playback = stack([pauseButton, speedButton], axis: .horizontal, spacing: 8)
    playback.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playback)
    NSLayoutConstraint.activate([
      liveRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
      liveRow.topAnchor.constraint(equalTo: factory.topAnchor, constant: 13),
      iso.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      iso.centerYAnchor.constraint(equalTo: liveRow.centerYAnchor),
      minimap.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      minimap.bottomAnchor.constraint(equalTo: factory.bottomAnchor, constant: -18),
      minimap.widthAnchor.constraint(equalToConstant: 112),
      minimap.heightAnchor.constraint(equalToConstant: 80),
      playback.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      playback.bottomAnchor.constraint(equalTo: factory.bottomAnchor, constant: -18),
    ])
  }
  private func makeDock() {
    let glass = GlassView()
    glass.layer.shadowColor = UIColor(hex: 0x6680A8).cgColor
    glass.layer.shadowOpacity = 0.08
    glass.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(glass)
    dockContent.axis = .vertical
    dockContent.spacing = 11
    glass.contentView.pin(dockContent, inset: 18)
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
      glass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
      glass.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
    ])
    let rail = zoneScroll
    rail.showsHorizontalScrollIndicator = false
    rail.translatesAutoresizingMaskIntoConstraints = false
    zoneRail.axis = .horizontal
    zoneRail.spacing = 8
    zoneRail.translatesAutoresizingMaskIntoConstraints = false
    rail.addSubview(zoneRail)
    view.addSubview(rail)
    NSLayoutConstraint.activate([
      rail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      rail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      rail.heightAnchor.constraint(equalToConstant: 37),
      rail.bottomAnchor.constraint(equalTo: glass.topAnchor, constant: -13),
      zoneRail.topAnchor.constraint(equalTo: rail.contentLayoutGuide.topAnchor),
      zoneRail.bottomAnchor.constraint(equalTo: rail.contentLayoutGuide.bottomAnchor),
      zoneRail.leadingAnchor.constraint(
        equalTo: rail.contentLayoutGuide.leadingAnchor, constant: 18),
      zoneRail.trailingAnchor.constraint(
        equalTo: rail.contentLayoutGuide.trailingAnchor, constant: -18),
      zoneRail.heightAnchor.constraint(equalTo: rail.frameLayoutGuide.heightAnchor),
    ])
    for zone in FactoryZone.allCases {
      let button = ActionButton(zone.shortTitle) { [weak self] in self?.select(zone) }
      button.configuration?.contentInsets = NSDirectionalEdgeInsets(
        top: 9, leading: 14, bottom: 9, trailing: 14)
      button.configuration?.titleTextAttributesTransformer =
        UIConfigurationTextAttributesTransformer {
          var a = $0
          a.font = .systemFont(ofSize: 12, weight: .medium)
          return a
        }
      button.accessibilityIdentifier = "zone.\(zone.rawValue)"
      zoneRail.addArrangedSubview(button)
      zoneButtons.append(button)
    }
    eventText.numberOfLines = 1
    eventText.adjustsFontSizeToFitWidth = true
    eventText.minimumScaleFactor = 0.8
    eventText.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(eventText)
    NSLayoutConstraint.activate([
      eventText.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      eventText.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      eventText.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -2),
    ])
  }
  private func renderDock() {
    dockContent.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, b) in zoneButtons.enumerated() {
      b.configuration?.baseForegroundColor =
        selected?.rawValue == index ? UIColor(hex: 0x286DE0) : Palette.ink
    }
    if let zone = selected {
      let title = label(zone.title, 23, .semibold)
      title.accessibilityIdentifier = "owner.selectedZone"
      title.adjustsFontSizeToFitWidth = true
      title.minimumScaleFactor = 0.75
      title.numberOfLines = 1
      let detail = label(
        tourIndex != nil
          ? "S-2048 · этап \(tourIndex! + 1) из \(FactoryZone.orderRoute.count)" : zone.metric,
        12, .regular, Palette.muted)
      let arrow = iconButton("arrow.up.right", "Подробнее об участке \(zone.title)") {
        [weak self] in self?.details(zone)
      }
      let row = stack([stack([title, detail], spacing: 5), UIView(), arrow], axis: .horizontal)
      row.alignment = .center
      dockContent.addArrangedSubview(row)
      let order = compactButton(
        zone == .office ? "Портфель заказов" : (zone == .dispatch ? "Рейсы сегодня" : "Процессы"),
        icon: zone.icon, prominent: true
      ) {
        [weak self] in
        guard let self else { return }
        if zone == .office {
          self.largeSheet(CompanyOrdersController(self.simulation))
        } else if zone == .dispatch {
          self.largeSheet(
            DispatchController(self.simulation) { [weak self] in
              self?.factory.releaseDispatch()
              self?.showEvent("Рейс 01 → Москва · машина выезжает")
            })
        } else {
          self.details(zone)
        }
      }
      let camera = compactButton("Камера", icon: "video") { [weak self] in
        self?.largeSheet(CameraController(zone))
      }
      let buttons = stack([order, camera], axis: .horizontal, spacing: 9)
      buttons.distribution = .fillEqually
      dockContent.addArrangedSubview(buttons)
    } else {
      let row = stack(
        [
          stack(
            [
              label("Вся компания", 23, .semibold),
              label("От проекта до доставки · 9 связанных зон", 12, .regular, Palette.muted),
            ], spacing: 5), UIView(),
          symbol("building.2.crop.circle", size: 30, color: UIColor(hex: 0x6386C7)),
        ], axis: .horizontal)
      row.alignment = .center
      dockContent.addArrangedSubview(row)
      let follow = compactButton(
        "Путь заказа", icon: "point.topleft.down.to.point.bottomright.curvepath", prominent: true
      ) { [weak self] in self?.startTour() }
      follow.accessibilityIdentifier = "owner.follow"
      let events = compactButton("События", icon: "waveform.path") { [weak self] in
        guard let self else { return }
        self.largeSheet(FactoryEventsController(self.simulation))
      }
      let actions = stack([follow, events], axis: .horizontal, spacing: 9)
      actions.distribution = .fillEqually
      dockContent.addArrangedSubview(actions)
    }
  }
  private func compactButton(
    _ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void
  ) -> UIButton {
    let b = ActionButton(title, icon: icon, prominent: prominent, action: action)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 12, leading: 13, bottom: 12, trailing: 13)
    b.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var a = $0
      a.font = .systemFont(ofSize: 12, weight: .semibold)
      return a
    }
    return b
  }
  private func select(_ zone: FactoryZone, fromTour: Bool = false) {
    if !fromTour { stopTour() }
    selected = zone
    minimap.selectedZone = zone
    simulation.selected = zone
    if zone == .dispatch { factory.logistics() } else { factory.focusOn(zone) }
    roofButton.accessibilityLabel = "Открыть все корпуса"
    zoneScroll.scrollRectToVisible(
      zoneButtons[zone.rawValue].convert(zoneButtons[zone.rawValue].bounds, to: zoneScroll)
        .insetBy(dx: -18, dy: 0), animated: !UIAccessibility.isReduceMotionEnabled)
    UISelectionFeedbackGenerator().selectionChanged()
    UIView.transition(
      with: dockContent, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
      options: .transitionCrossDissolve
    ) { self.renderDock() }
    if fromTour { showEvent("S-2048 · \(zone.state)") }
  }
  private func overview() {
    stopTour()
    selected = nil
    minimap.selectedZone = nil
    factory.resetCamera()
    renderDock()
    showEvent("Перемещайте карту · выбирайте корпус · приближайте детали")
  }
  private func startTour() {
    tourIndex = 0
    tourSeconds = 0
    factory.showRoute(true)
    select(.office, fromTour: true)
    live.text = "МАРШРУТ S-2048"
  }
  private func stopTour() {
    let wasTouring = tourIndex != nil
    tourIndex = nil
    factory.showRoute(false)
    live.text = simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · LIVE"
    if wasTouring { renderDock() }
  }
  private func tick() {
    guard !simulation.paused else { return }
    seconds += speed
    if seconds >= 5 {
      seconds = 0
      simulation.advance()
      UIView.transition(with: complete, duration: 0.25, options: .transitionCrossDissolve) {
        self.complete.text = "\(self.simulation.completed)"
      }
      if tourIndex == nil { showEvent(simulation.events.first ?? "Смена идёт по плану") }
    }
    if let step = tourIndex {
      tourSeconds += speed
      if tourSeconds >= 6 {
        tourSeconds = 0
        if step + 1 < FactoryZone.orderRoute.count {
          tourIndex = step + 1
          select(FactoryZone.orderRoute[step + 1], fromTour: true)
        } else {
          stopTour()
          showEvent("S-2048 · маршрут пройден, готово к отгрузке")
        }
      }
    }
  }
  private func togglePause() {
    simulation.paused.toggle()
    factory.setPaused(simulation.paused)
    pauseButton.configuration?.image = UIImage(systemName: simulation.paused ? "play" : "pause")
    pauseButton.accessibilityLabel =
      simulation.paused ? "Продолжить демо" : "Приостановить демо"
    live.text =
      simulation.paused ? "ДЕМО · ПАУЗА" : (tourIndex == nil ? "ДЕМО · LIVE" : "МАРШРУТ S-2048")
  }
  private func showEvent(_ text: String) {
    UIView.transition(with: eventText, duration: 0.3, options: .transitionCrossDissolve) {
      self.eventText.text = text
    }
  }
  private func details(_ zone: FactoryZone) {
    largeSheet(
      ZoneController(zone, simulation: simulation) { [weak self] in
        self?.showEvent("Контроль поверхности назначен")
      })
  }
  private func largeSheet(_ vc: UIViewController) {
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    present(nav, animated: true)
  }
}

final class FactoryEventsController: ScrollController {
  let simulation: FactorySimulation
  init(_ simulation: FactorySimulation) {
    self.simulation = simulation
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "События компании"
    add(
      stack(
        [
          eyebrow("СОБЫТИЯ ТЕКУЩЕЙ ДЕМО-СМЕНЫ"),
          label("Каждое движение\nимеет значение.", 31, .medium),
        ], spacing: 13))
    for event in simulation.events { add(workspaceCard([label(event, 16, .medium)]), inset: 16) }
    add(
      ActionButton("Площадки и логистика", icon: "point.3.connected.trianglepath.dotted") {
        [weak self] in
        self?.navigationController?.pushViewController(NetworkController(), animated: true)
      })
  }
}

final class ZoneController: ScrollController {
  let zone: FactoryZone
  let simulation: FactorySimulation
  let onChange: () -> Void
  init(_ zone: FactoryZone, simulation: FactorySimulation, onChange: @escaping () -> Void) {
    self.zone = zone
    self.simulation = simulation
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "\(zone.shortTitle) · \(zone.code)"
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let heading = stack(
      [
        eyebrow("ДЕМО · ОБНОВЛЕНО СЕЙЧАС"), label(zone.title, 34, .medium),
        label(zone.state, 15, .regular, Palette.muted), line(),
        label(
          "\(zone.count) \(plural(zone.count,"объект","объекта","объектов"))  ·  \(zone.people) \(plural(zone.people,"сотрудник","сотрудника","сотрудников"))",
          16, .medium),
        label(zone.metric, 21, .semibold),
      ], spacing: 14)
    add(heading)
    for (title, value) in zone.detailRows {
      let row = stack(
        [label(title, 15, .medium), UIView(), label(value, 15, .semibold)], axis: .horizontal)
      add(workspaceCard([row]), inset: 16)
    }
    let camera = ActionButton("Камера \(zone.code)", icon: "video") { [weak self] in
      guard let self else { return }
      self.navigationController?.pushViewController(CameraController(self.zone), animated: true)
    }
    let order = ActionButton("Открыть заказ", icon: "arrow.up.right", prominent: true) {
      [weak self] in
      guard let self else { return }
      self.navigationController?.pushViewController(
        OrderController(self.simulation, onChange: self.onChange), animated: true)
    }
    add(stack([camera, order], spacing: 12))
    if zone == .quality {
      let button = ActionButton(
        simulation.resolved ? "Контроль назначен" : "Назначить контроль",
        icon: simulation.resolved ? "checkmark" : "person.badge.plus"
      ) { [weak self] in
        guard let self else { return }
        self.simulation.resolve()
        self.onChange()
        self.render()
      }
      button.isEnabled = !simulation.resolved
      add(button)
    }
  }
}

final class OrderController: ScrollController {
  let simulation: FactorySimulation
  let onChange: () -> Void
  init(_ s: FactorySimulation, onChange: @escaping () -> Void) {
    simulation = s
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Заказ S-2048"
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(
      stack(
        [
          eyebrow("ДЕМО · ПРОИЗВОДСТВЕННЫЙ ЗАКАЗ"),
          label("Aria.\nНа пути к дому.", 35, .regular, serif: true), photo("aria", height: 180),
          label("4 изделия · S-Stone", 20, .semibold),
          label(
            "Салон «Интерьер» · Москва\nПлан отгрузки: 8 октября\nОтветственный: менеджер производства",
            14, .regular, Palette.muted),
        ], spacing: 17))
    let stages = stack([], spacing: 17)
    for (i, t) in ["Литьё", "Обработка поверхности", "Контроль качества", "Упаковка и отгрузка"]
      .enumerated()
    {
      stages.addArrangedSubview(
        stack(
          [
            symbol(
              i == 0 ? "checkmark.circle.fill" : i == 1 ? "circle.inset.filled" : "circle",
              size: 17, color: i < 2 ? Palette.ink : Palette.muted),
            label(t, 15, .regular, i < 2 ? Palette.ink : Palette.muted),
          ], axis: .horizontal, spacing: 14))
    }
    add(stages)
    let button = ActionButton(
      simulation.priority ? "Приоритет установлен" : "Повысить приоритет",
      icon: simulation.priority ? "checkmark" : "arrow.up", prominent: true
    ) { [weak self] in self?.confirm() }
    button.accessibilityIdentifier = "order.priority"
    button.isEnabled = !simulation.priority
    add(button)
  }
  private func confirm() {
    let a = UIAlertController(
      title: "Изменить приоритет?",
      message:
        "Заказ S-2048 поднимется в очереди демонстрационного производства. Действие появится в ленте событий.",
      preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(
      UIAlertAction(title: "Повысить", style: .default) { [weak self] _ in
        self?.simulation.expedite()
        self?.onChange()
        self?.render()
      })
    present(a, animated: true)
  }
}

final class CameraController: ScrollController {
  let zone: FactoryZone
  private let camera = FactorySceneView()
  init(_ z: FactoryZone) {
    zone = z
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Камера \(zone.code)"
    camera.closeUp(zone)
    camera.height(350)
    add(camera, inset: 0)
    add(
      stack(
        [
          eyebrow("ДЕМОПОТОК · УЧАСТОК \(zone.code)"), label(zone.title, 34, .regular, serif: true),
          label(
            "\(zone.people) \(plural(zone.people,"сотрудник","сотрудника","сотрудников")) в зоне\n\(zone.count) \(plural(zone.count,"объект","объекта","объектов")) в работе",
            17, .medium),
          label(
            "Так может выглядеть контекст камеры: участок, изделия и события рядом с изображением. Сейчас показана анимированная модель, видеопоток не подключён.",
            14, .regular, Palette.muted),
        ], spacing: 18))
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    camera.setPaused(true)
    camera.isPlaying = false
  }
}
final class NetworkController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Сеть Salini"
    add(
      stack(
        [
          eyebrow("ДЕМО · ОТ ПРОИЗВОДСТВА ДО САЛОНА"),
          label("Всё связано.", 38, .regular, serif: true),
          label(
            "Единый взгляд на выпуск, склад и путь изделия к партнёру.", 16, .regular, Palette.muted
          ),
        ], spacing: 15))
    for (name, desc, icon) in [
      ("Белгород", "Производство · 62 изделия в работе", "building.2"),
      ("Москва", "Склад · 146 изделий · 3 отгрузки", "shippingbox"),
      ("Партнёры", "12 демонстрационных заказов в пути", "storefront"),
    ] {
      let s = stack(
        [
          symbol(icon, size: 30), label(name, 28, .regular, serif: true),
          label(desc, 15, .regular, Palette.muted),
        ], spacing: 13
      ).inset(24)
      s.backgroundColor = .white
      s.rounded()
      add(s)
    }
    add(
      label(
        "Города соответствуют публичным данным Salini. Показатели сети демонстрационные.", 12,
        .regular, Palette.muted))
  }
}

final class CompanyOrdersController: ScrollController {
  let simulation: FactorySimulation
  init(_ simulation: FactorySimulation) {
    self.simulation = simulation
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Портфель заказов"
    add(
      stack(
        [
          eyebrow("ДЕМО · ОФИС И ПРОИЗВОДСТВО"),
          label("За каждым изделием —\nчей-то проект.", 31, .medium),
          label("18 заказов · 6 новых · 3 готовы к отправке", 14, .regular, Palette.muted),
        ], spacing: 16))
    let order = ActionButton(
      "S-2048 · Aria 190 · 4 изделия", icon: "arrow.up.right", prominent: true
    ) { [weak self] in
      guard let self else { return }
      self.navigationController?.pushViewController(
        OrderController(self.simulation, onChange: {}), animated: true)
    }
    add(order)
    for (name, detail, state) in [
      ("S-2051 · Marea", "12 раковин · S-Stone", "Контроль качества"),
      ("S-2053 · Domino", "6 мебельных комплектов", "Комплектация"),
      ("S-2057 · Душевые поддоны", "8 изделий · S-Sense", "Минеральное литьё"),
      ("S-2060 · Зеркала и аксессуары", "5 интерьерных комплектов", "Готовы к отгрузке"),
    ] {
      add(
        workspaceCard([
          label(name, 19, .semibold), label(detail, 14, .regular, Palette.muted),
          label(state, 12, .medium, UIColor(hex: 0x527E92)),
        ]))
    }
  }
}

final class DispatchController: ScrollController {
  let simulation: FactorySimulation
  let onRelease: () -> Void
  init(_ simulation: FactorySimulation, onRelease: @escaping () -> Void) {
    self.simulation = simulation
    self.onRelease = onRelease
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Рейсы сегодня"
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(
      stack(
        [
          eyebrow("ДЕМО · ДИСПЕТЧЕРСКАЯ"), label("Последние метры\nна производстве.", 32, .medium),
          label(
            "Действие меняет маршрут машины на пространственной карте.", 15, .regular, Palette.muted
          ),
        ], spacing: 17))
    add(
      workspaceCard([
        label("01 · Москва", 27, .semibold),
        label(
          "S-2039 · Aria · 4 изделия\nПогрузка завершена · документы проверены", 15, .regular,
          Palette.muted),
        label(
          simulation.dispatchReleased ? "Машина вышла на маршрут" : "Готов к выезду", 13, .semibold,
          UIColor(hex: 0x527E92)),
      ]))
    let release = ActionButton(
      simulation.dispatchReleased ? "Выезд подтверждён" : "Подтвердить выезд",
      icon: simulation.dispatchReleased ? "checkmark" : "truck.box", prominent: true
    ) { [weak self] in
      guard let self else { return }
      self.simulation.releaseDispatch()
      self.onRelease()
      self.dismiss(animated: true)
    }
    release.isEnabled = !simulation.dispatchReleased
    release.accessibilityIdentifier = "dispatch.release"
    add(release)
    add(
      workspaceCard([
        label("02 · Санкт-Петербург", 21, .medium),
        label("Раковины и мебель · 9 мест\nОжидает комплектование", 14, .regular, Palette.muted),
      ]))
    add(
      workspaceCard([
        label("03 · Партнёрский рейс", 21, .medium),
        label("Душевые поддоны · 6 мест\nПланируется погрузка", 14, .regular, Palette.muted),
      ]))
  }
}
