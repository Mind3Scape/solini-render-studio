import SceneKit
import UIKit

final class OwnerController: UIViewController {
  let simulation = FactorySimulation()
  private let factory = FactorySceneView()
  private let minimap = CampusOverview()
  private let dock = GlassView()
  private let dockContent = UIStackView()
  private let zoneRail = UIStackView()
  private let zoneScroll = UIScrollView()
  private let lensControl = UISegmentedControl(items: CampusLens.allCases.map(\.title))
  private let contextLabel = label("12 000+ м² производства¹", 11, .medium, Palette.muted)
  private let live = label("ДЕМО · 00:00", 10, .semibold, InsideStyle.blue)
  private let eventText = label("Два решения изменят ход этой смены", 10, .medium, Palette.muted)
  private var selected: FactoryZone?
  private var trackedOrder: InsideOrderID?
  private var lens: CampusLens = .campus
  private var tourIndex: Int?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var speed = 1
  private var compactMap = false
  private var collapseButton: UIButton!
  private var lastRevision = -1
  private var pauseButton: UIButton!
  private var speedButton: UIButton!
  private var zoneButtons: [UIButton] = []
  private var dockProgress: UIProgressView?
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(hex: 0xEDF0F2)
    factory.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(factory)
    makeHeader()
    makeDock()
    NSLayoutConstraint.activate([
      factory.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      factory.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      factory.topAnchor.constraint(equalTo: lensControl.bottomAnchor, constant: 28),
      factory.bottomAnchor.constraint(equalTo: zoneScroll.topAnchor, constant: -5),
    ])
    let topFade = GradientView(colors: [UIColor(hex: 0xEDF0F2), UIColor(hex: 0xEDF0F2, alpha: 0)])
    let bottomFade = GradientView(colors: [
      UIColor(hex: 0xEDF0F2, alpha: 0), UIColor(hex: 0xEDF0F2),
    ])
    for fade in [topFade, bottomFade] {
      fade.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(fade)
      NSLayoutConstraint.activate([
        fade.leadingAnchor.constraint(equalTo: factory.leadingAnchor),
        fade.trailingAnchor.constraint(equalTo: factory.trailingAnchor),
        fade.heightAnchor.constraint(equalToConstant: 40),
      ])
    }
    topFade.topAnchor.constraint(equalTo: factory.topAnchor).isActive = true
    bottomFade.bottomAnchor.constraint(equalTo: factory.bottomAnchor).isActive = true
    makeMapControls()
    factory.onSelect = { [weak self] zone in self?.select(zone) }
    factory.onOrderSelect = { [weak self] order in self?.track(order) }
    factory.onStationSelect = { [weak self] zone, code in self?.open(.station(zone, code)) }
    factory.onExplore = { [weak self] in self?.tourIndex = nil }
    factory.onViewport = { [weak self] camera in self?.minimap.camera = camera }
    minimap.onSelect = { [weak self] zone in self?.select(zone) }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: .factoryChanged, object: simulation, queue: .main
      ) { [weak self] _ in self?.refresh() })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.stopClock() })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self, self.view.window != nil else { return }
        self.startClock()
      })
    refresh()
  }
  deinit {
    timer?.invalidate()
    observers.forEach(NotificationCenter.default.removeObserver)
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startClock()
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // A presented operations sheet shares the same running scenario.
    if isMovingFromParent || navigationController?.viewControllers.contains(self) != true {
      stopClock()
    }
  }
  private func startClock() {
    guard timer == nil else { return }
    factory.setPaused(simulation.paused)
    let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else { return }
      for _ in 0..<self.speed { self.simulation.advance() }
      self.live.text =
        self.simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · \(self.simulation.clockTime)"
    }
    RunLoop.main.add(clock, forMode: .common)
    timer = clock
  }
  private func stopClock() {
    timer?.invalidate()
    timer = nil
    factory.setPaused(true)
    factory.isPlaying = false
  }
  private func iconButton(_ icon: String, _ name: String, action: @escaping () -> Void) -> UIButton
  {
    let b = ActionButton("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 11, leading: 11, bottom: 11, trailing: 11)
    return b
  }
  private func compact(
    _ title: String, _ icon: String, prominent: Bool = false, action: @escaping () -> Void
  ) -> UIButton {
    let b = ActionButton(title, icon: icon, prominent: prominent, action: action)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 14, leading: 15, bottom: 14, trailing: 15)
    b.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var a = $0
      a.font = .systemFont(ofSize: 13, weight: .semibold)
      return a
    }
    return b
  }
  private func makeHeader() {
    let back = iconButton("chevron.left", "Закрыть Salini Inside") { [weak self] in
      self?.navigationController?.popViewController(animated: true)
    }
    let title = stack(
      [
        label("Salini Inside", 21, .semibold),
        label("Взгляд на всю компанию", 11, .regular, Palette.muted),
      ], spacing: 3)
    let more = iconButton("ellipsis", "Инструменты карты") {}
    more.showsMenuAsPrimaryAction = true
    more.menu = UIMenu(children: [
      UIMenu(
        title: "Слой карты",
        children: CampusLens.allCases.map { layer in
          UIAction(title: layer.title) { [weak self] _ in
            guard let self else { return }
            self.lensControl.selectedSegmentIndex = layer.rawValue
            self.lens = layer
            self.factory.apply(self.simulation, lens: layer, tracked: self.trackedOrder)
            self.renderDock(animated: true)
          }
        }),
      UIAction(title: "Открыть / закрыть крыши", image: UIImage(systemName: "square.3.layers.3d")) {
        [weak self] _ in
        guard let self else { return }
        self.factory.setRoof(!self.factory.roofVisible)
      },
      UIAction(
        title: "Маршрут Aria по этапам",
        image: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath")
      ) { [weak self] _ in self?.startTour() },
      UIAction(title: "Начать демо заново", image: UIImage(systemName: "arrow.counterclockwise")) {
        [weak self] _ in
        guard let self, let nav = self.navigationController else { return }
        let next = OwnerController()
        next.hidesBottomBarWhenPushed = self.hidesBottomBarWhenPushed
        nav.setViewControllers(Array(nav.viewControllers.dropLast()) + [next], animated: false)
      },
      UIAction(title: "О модели и источниках", image: UIImage(systemName: "info.circle")) {
        [weak self] _ in self?.sheet(AboutController())
      },
    ])
    let heading = stack([back, title, UIView(), more], axis: .horizontal, spacing: 12)
    heading.alignment = .center
    heading.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(heading)
    lensControl.selectedSegmentIndex = 0
    lensControl.translatesAutoresizingMaskIntoConstraints = false
    lensControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.95)
    lensControl.setTitleTextAttributes(
      [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
    lensControl.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.lens = CampusLens(rawValue: self.lensControl.selectedSegmentIndex) ?? .campus
        self.factory.apply(self.simulation, lens: self.lens, tracked: self.trackedOrder)
        self.renderDock(animated: true)
        UISelectionFeedbackGenerator().selectionChanged()
      }, for: .valueChanged)
    view.addSubview(lensControl)
    let status = stack([live, UIView(), contextLabel], axis: .horizontal)
    status.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(status)
    NSLayoutConstraint.activate([
      heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
      heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      lensControl.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 19),
      lensControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
      lensControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
      lensControl.heightAnchor.constraint(equalToConstant: 36),
      status.topAnchor.constraint(equalTo: lensControl.bottomAnchor, constant: 13),
      status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
      status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
    ])
  }
  private func makeMapControls() {
    let reset = iconButton("viewfinder", "Вся территория") { [weak self] in self?.overview() }
    let closer = iconButton("plus", "Приблизить карту") { [weak self] in
      self?.factory.stepZoom(true)
    }
    let farther = iconButton("minus", "Отдалить карту") { [weak self] in
      self?.factory.stepZoom(false)
    }
    let zoom = stack([closer, farther], spacing: 8)
    zoom.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(zoom)
    reset.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(reset)
    pauseButton = iconButton("pause", "Приостановить демо") { [weak self] in
      guard let self else { return }
      self.simulation.paused.toggle()
      self.factory.setPaused(self.simulation.paused)
      self.pauseButton.configuration?.image = UIImage(
        systemName: self.simulation.paused ? "play" : "pause")
      self.pauseButton.accessibilityLabel =
        self.simulation.paused ? "Продолжить демо" : "Приостановить демо"
    }
    speedButton = compact("×150", "") { [weak self] in
      guard let self else { return }
      self.speed = self.speed == 1 ? 3 : 1
      self.speedButton.configuration?.title = "×\(self.speed * 150)"
      self.speedButton.accessibilityLabel = "Время сценария ускорено в \(self.speed * 150) раз"
      self.factory.simulationSpeed = CGFloat(self.speed)
    }
    speedButton.configuration?.image = nil
    speedButton.height(44)
    let playback = stack([pauseButton, speedButton], axis: .horizontal, spacing: 8)
    playback.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playback)
    minimap.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(minimap)
    NSLayoutConstraint.activate([
      zoom.topAnchor.constraint(equalTo: factory.topAnchor, constant: 24),
      zoom.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      reset.bottomAnchor.constraint(equalTo: factory.bottomAnchor, constant: -13),
      reset.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      playback.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      playback.bottomAnchor.constraint(equalTo: reset.bottomAnchor),
      minimap.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      minimap.bottomAnchor.constraint(equalTo: reset.bottomAnchor),
      minimap.widthAnchor.constraint(equalToConstant: 94),
      minimap.heightAnchor.constraint(equalToConstant: 65),
    ])
  }
  private func makeDock() {
    dock.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(dock)
    dockContent.axis = .vertical
    dockContent.spacing = 13
    dock.contentView.pin(dockContent, inset: 20)
    zoneScroll.showsHorizontalScrollIndicator = false
    zoneScroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(zoneScroll)
    zoneRail.axis = .horizontal
    zoneRail.spacing = 8
    zoneRail.translatesAutoresizingMaskIntoConstraints = false
    zoneScroll.addSubview(zoneRail)
    eventText.numberOfLines = 1
    eventText.lineBreakMode = .byTruncatingTail
    eventText.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(eventText)
    NSLayoutConstraint.activate([
      dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
      dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
      dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      zoneScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      zoneScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      zoneScroll.heightAnchor.constraint(equalToConstant: 44),
      zoneScroll.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -13),
      zoneRail.leadingAnchor.constraint(
        equalTo: zoneScroll.contentLayoutGuide.leadingAnchor, constant: 18),
      zoneRail.trailingAnchor.constraint(
        equalTo: zoneScroll.contentLayoutGuide.trailingAnchor, constant: -18),
      zoneRail.topAnchor.constraint(equalTo: zoneScroll.contentLayoutGuide.topAnchor),
      zoneRail.bottomAnchor.constraint(equalTo: zoneScroll.contentLayoutGuide.bottomAnchor),
      zoneRail.heightAnchor.constraint(equalTo: zoneScroll.frameLayoutGuide.heightAnchor),
      eventText.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 25),
      eventText.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
      eventText.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
    ])
    for zone in FactoryZone.allCases {
      let button = compact(zone.shortTitle, zone.icon) { [weak self] in self?.select(zone) }
      button.configuration?.image = nil
      button.accessibilityIdentifier = "zone.\(zone.rawValue)"
      zoneRail.addArrangedSubview(button)
      zoneButtons.append(button)
    }
  }
  private func refresh() {
    live.text = simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · \(simulation.clockTime)"
    dockProgress?.setProgress(
      trackedOrder == .aria
        ? simulation.reserveProgress
        : simulation.quality == .packing
          ? simulation.packingProgress
          : simulation.quality == .loading
            ? simulation.loadingProgress : simulation.qualityProgress,
      animated: !UIAccessibility.isReduceMotionEnabled)
    guard lastRevision != simulation.revision else { return }
    lastRevision = simulation.revision
    factory.apply(simulation, lens: lens, tracked: trackedOrder)
    if let trackedOrder, tourIndex == nil {
      let current = simulation.zone(for: trackedOrder)
      if selected != current { select(current, keepingOrder: true) }
    }
    eventText.text = simulation.events.first
    renderDock(animated: view.window != nil)
  }
  private func renderDock(animated: Bool = false) {
    let update = { [self] in
      self.dockContent.arrangedSubviews.forEach { $0.removeFromSuperview() }
      self.dockProgress = nil
      for (i, b) in self.zoneButtons.enumerated() {
        b.configuration?.baseForegroundColor =
          self.selected?.rawValue == i ? InsideStyle.blue : Palette.ink
        b.configuration?.baseBackgroundColor =
          self.selected?.rawValue == i ? UIColor(hex: 0xDCE8EE) : nil
      }
      self.minimap.isHidden = self.selected == nil
      let kicker: String
      let title: String
      let subtitle: String
      if let tour = self.tourIndex, let zone = self.selected {
        kicker = "ИЗУЧЕНИЕ ЦЕПОЧКИ · \(tour + 1) ИЗ 8"
        title = zone.title
        subtitle = "Схема этапов · не текущее положение заказа"
      } else if let order = self.trackedOrder {
        kicker = "\(order.rawValue) / \(order.destination.uppercased())"
        title = order.product
        subtitle = self.simulation.status(order)
      } else if let zone = self.selected {
        kicker = "УЧАСТОК \(zone.code) / \(self.simulation.load(zone))% ЗАГРУЗКА"
        title = zone.title
        subtitle =
          "\(zone.people) \(plural(zone.people, "человек", "человека", "человек")) · \(self.simulation.summary(zone))"
      } else {
        kicker = "СМЕНА / ПРИНЯТО ОТК \(self.simulation.completed) ИЗ 68"
        title =
          self.lens == .load
          ? "Где нужен резерв"
          : self.lens == .orders ? "Каждый заказ на виду" : "Вся компания. Здесь."
        subtitle =
          self.simulation.attentionCount > 0
          ? "\(self.simulation.attentionCount) \(plural(self.simulation.attentionCount,"решение","решения","решений")) \(self.simulation.attentionCount == 1 ? "требует" : "требуют") внимания"
          : "Решения приняты · процессы продолжаются"
      }
      let fold = UIButton(type: .system)
      var foldConfig = UIButton.Configuration.plain()
      foldConfig.image = UIImage(systemName: self.compactMap ? "chevron.up" : "chevron.down")
      foldConfig.baseForegroundColor = InsideStyle.blue
      foldConfig.contentInsets = NSDirectionalEdgeInsets(
        top: 8, leading: 12, bottom: 8, trailing: 0)
      fold.configuration = foldConfig
      fold.widthAnchor.constraint(equalToConstant: 44).isActive = true
      fold.height(28)
      fold.accessibilityLabel = self.compactMap ? "Развернуть сводку" : "Больше пространства карте"
      fold.addAction(
        UIAction { [weak self] _ in
          guard let self else { return }
          self.compactMap.toggle()
          self.view.layoutIfNeeded()
          self.renderDock()
          UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.45, delay: 0,
            usingSpringWithDamping: 0.95, initialSpringVelocity: 0, options: [.allowUserInteraction]
          ) { self.view.layoutIfNeeded() }
        }, for: .touchUpInside)
      let context = stack(
        [eyebrow(kicker, color: InsideStyle.blue), UIView(), fold], axis: .horizontal, spacing: 5)
      context.alignment = .center
      self.dockContent.addArrangedSubview(context)
      let name = label(title, 25, .semibold)
      name.numberOfLines = 1
      name.adjustsFontSizeToFitWidth = true
      name.minimumScaleFactor = 0.75
      name.accessibilityIdentifier = "owner.selectedZone"
      self.dockContent.addArrangedSubview(
        stack([name, label(subtitle, 12, .regular, Palette.muted)], spacing: 6))
      if self.compactMap { return }
      let first: UIButton
      let second: UIButton
      if let index = self.tourIndex {
        first = self.compact(
          index == 7 ? "Завершить маршрут" : "Следующий этап", "arrow.right", prominent: true
        ) { [weak self] in self?.nextTour() }
        second = self.compact("К заказу", "doc.text") { [weak self] in self?.open(.order(.aria)) }
      } else if let order = self.trackedOrder {
        first = self.compact("О заказе", "arrow.up.right", prominent: true) { [weak self] in
          self?.open(.order(order))
        }
        second = self.compact("Все заказы", "square.stack") { [weak self] in self?.open(.orders) }
      } else if let zone = self.selected {
        let destination: InsideDestination =
          zone == .office ? .orders : zone == .dispatch ? .dispatch : .zone(zone)
        first = self.compact(
          zone == .office ? "Заказы" : zone == .dispatch ? "Рейсы" : "Процессы", "arrow.up.right",
          prominent: true
        ) { [weak self] in self?.open(destination) }
        let focusOrder: InsideOrderID? =
          zone == .finishing ? .aria : zone == .quality || zone == .packing ? .marea : nil
        second = self.compact(
          focusOrder != nil ? "\(focusOrder!.product)" : "Обзор смены",
          focusOrder != nil ? "location" : "chart.bar"
        ) { [weak self] in
          if let focusOrder { self?.track(focusOrder) } else { self?.open(.briefing) }
        }
      } else {
        first = self.compact("Обзор смены", "arrow.up.right", prominent: true) { [weak self] in
          self?.open(.briefing)
        }
        second = self.compact(
          self.lens == .load ? "Узкое место" : "Найти заказ",
          self.lens == .load ? "scope" : "magnifyingglass"
        ) { [weak self] in
          guard let self else { return }
          if self.lens == .load { self.select(.finishing) } else { self.open(.orders) }
        }
      }
      let actions = stack([first, second], axis: .horizontal, spacing: 9)
      actions.distribution = .fillEqually
      self.dockContent.addArrangedSubview(actions)
      if let order = self.trackedOrder,
        (order == .aria && self.simulation.reserve == .processing)
          || (order == .marea && [.checking, .packing, .loading].contains(self.simulation.quality))
      {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.progressTintColor = InsideStyle.blue
        progress.trackTintColor = UIColor(hex: 0xD8E0E4)
        self.dockProgress = progress
        progress.progress =
          order == .aria
          ? self.simulation.reserveProgress
          : self.simulation.quality == .loading
            ? self.simulation.loadingProgress
            : self.simulation.quality == .packing
              ? self.simulation.packingProgress : self.simulation.qualityProgress
        self.dockContent.addArrangedSubview(progress)
      }
    }
    if animated && !UIAccessibility.isReduceMotionEnabled {
      UIView.transition(
        with: dockContent, duration: 0.22,
        options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
    } else {
      update()
    }
  }
  private func select(_ zone: FactoryZone, keepingOrder: Bool = false) {
    if !keepingOrder {
      trackedOrder = nil
      tourIndex = nil
      factory.showRoute(false)
    }
    selected = zone
    simulation.selected = zone
    minimap.selectedZone = zone
    factory.focusOn(zone)
    factory.apply(simulation, lens: lens, tracked: trackedOrder)
    contextLabel.text = "\(zone.code) · \(zone.shortTitle)"
    zoneScroll.scrollRectToVisible(
      zoneButtons[zone.rawValue].convert(zoneButtons[zone.rawValue].bounds, to: zoneScroll).insetBy(
        dx: -18, dy: 0), animated: !UIAccessibility.isReduceMotionEnabled)
    UISelectionFeedbackGenerator().selectionChanged()
    renderDock(animated: true)
  }
  private func track(_ order: InsideOrderID) {
    trackedOrder = order
    tourIndex = nil
    select(simulation.zone(for: order), keepingOrder: true)
    factory.showOrderRoute(order.route)
  }
  private func overview() {
    selected = nil
    trackedOrder = nil
    tourIndex = nil
    minimap.selectedZone = nil
    factory.resetCamera()
    factory.showRoute(false)
    factory.apply(simulation, lens: lens, tracked: nil)
    contextLabel.text = "12 000+ м² производства¹"
    renderDock(animated: true)
  }
  private func startTour() {
    simulation.paused = true
    factory.setPaused(true)
    pauseButton.configuration?.image = UIImage(systemName: "play")
    pauseButton.accessibilityLabel = "Продолжить демо"
    trackedOrder = nil
    tourIndex = 0
    select(.office, keepingOrder: true)
    factory.showOrderRoute(FactoryZone.orderRoute)
  }
  private func nextTour() {
    guard let index = tourIndex else { return }
    guard index < 7 else {
      overview()
      return
    }
    tourIndex = index + 1
    select(FactoryZone.orderRoute[index + 1], keepingOrder: true)
  }
  private func open(_ destination: InsideDestination) {
    let panel = InsidePanelController(destination, simulation: simulation) {
      [weak self] zone, order in
      guard let self else { return }
      self.trackedOrder = order
      self.tourIndex = nil
      self.select(zone, keepingOrder: order != nil)
      if let order { self.factory.showOrderRoute(order.route) }
    }
    let nav = UINavigationController(rootViewController: panel)
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    present(nav, animated: true)
  }
}
