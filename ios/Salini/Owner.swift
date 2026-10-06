import SceneKit
import UIKit

final class OwnerController: UIViewController {
  let simulation = FactorySimulation()
  private let factory = FactorySceneView()
  private let minimap = CampusOverview()
  private let dock = GlassView()
  private let dockContent = UIStackView()
  private let header = GlassView()
  private let mapTools = GlassView()
  private let metrics = UIStackView()
  private let outputNumber = label("42", 31, .light, InsideStyle.ink)
  private let attentionNumber = label("2", 31, .light, InsideStyle.amber)
  private let contextLabel = label("ТЕРРИТОРИЯ · 9 УЧАСТКОВ", 10, .medium, InsideStyle.muted)
  private let live = label("ДЕМО · 00:00", 10, .semibold, InsideStyle.blue)
  private let eventText = label(
    "Два решения изменят ход этой смены", 10, .medium, InsideStyle.muted)
  private var selected: FactoryZone?
  private var trackedOrder: InsideOrderID?
  private var lens: CampusLens = .campus
  private var tourIndex: Int?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var speed = 1
  private var compactMap = false
  private var lastRevision = -1
  private var pauseButton: UIButton!
  private var speedButton: UIButton!
  private var dockProgress: UIProgressView?
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = InsideStyle.canvas
    factory.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(factory)
    makeHeader()
    makeDock()
    NSLayoutConstraint.activate([
      factory.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      factory.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      factory.topAnchor.constraint(equalTo: view.topAnchor),
      factory.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
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
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let top = metrics.isHidden ? header.frame.maxY + 28 : contextLabel.frame.maxY + 18
    let bottom = view.bounds.height - mapTools.frame.minY + 8
    factory.mapContentInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    let overlayViews: [UIView] =
      metrics.isHidden
      ? [header, minimap, mapTools, dock] : [header, metrics, contextLabel, mapTools, dock]
    factory.excludedAnnotationRects = overlayViews.filter { !$0.isHidden }.map {
      $0.convert($0.bounds, to: factory).insetBy(dx: -8, dy: -8)
    }
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
    let b = insideAction("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 10, leading: 10, bottom: 10, trailing: 10)
    b.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 17, weight: .regular)
    return b
  }
  private func compact(
    _ title: String, _ icon: String, prominent: Bool = false,
    action: @escaping () -> Void
  ) -> UIButton {
    insideAction(title, icon: icon, prominent: prominent, action: action)
  }
  private func layersMenu() -> UIMenu {
    UIMenu(
      title: "Слой карты",
      children: CampusLens.allCases.map { layer in
        UIAction(title: layer.title) { [weak self] _ in
          guard let self else { return }
          self.lens = layer
          self.factory.apply(self.simulation, lens: layer, tracked: self.trackedOrder)
          self.renderDock(animated: true)
        }
      })
  }
  private func makeHeader() {
    let back = iconButton("chevron.left", "Закрыть Salini Inside") { [weak self] in
      self?.navigationController?.popViewController(animated: true)
    }
    live.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    live.textColor = InsideStyle.muted
    let title = stack([label("Salini Inside", 17, .semibold, InsideStyle.ink), live], spacing: 3)
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
    speedButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
      top: 10, leading: 0, bottom: 10, trailing: 0)
    speedButton.configuration?.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer {
        var a = $0
        a.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        return a
      }
    speedButton.widthAnchor.constraint(equalToConstant: 43).isActive = true
    speedButton.height(44)
    let more = iconButton("ellipsis", "Инструменты карты") {}
    more.showsMenuAsPrimaryAction = true
    more.menu = UIMenu(children: [
      layersMenu(),
      UIMenu(
        title: "Перейти к участку",
        children: FactoryZone.allCases.map { zone in
          UIAction(title: "\(zone.code) · \(zone.title)", image: UIImage(systemName: zone.icon)) {
            [weak self] _ in self?.select(zone)
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
    let heading = stack(
      [back, title, UIView(), pauseButton, speedButton, more], axis: .horizontal, spacing: 0)
    heading.alignment = .center
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    header.contentView.pin(heading, inset: 4)
    metrics.isUserInteractionEnabled = false
    metrics.axis = .horizontal
    metrics.distribution = .fillEqually
    metrics.spacing = 20
    let area = label("12 000+", 28, .light, InsideStyle.ink)
    for number in [area, outputNumber, attentionNumber] {
      number.font = .monospacedDigitSystemFont(ofSize: 28, weight: .light)
      number.adjustsFontSizeToFitWidth = true
      number.minimumScaleFactor = 0.65
      number.numberOfLines = 1
    }
    for (number, caption) in [
      (area, "м² производства¹"), (outputNumber, "принято ОТК / 68"),
      (attentionNumber, "ждут решения"),
    ] {
      metrics.addArrangedSubview(
        stack([number, label(caption, 10, .regular, InsideStyle.muted)], spacing: 5))
    }
    metrics.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(metrics)
    contextLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contextLabel)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      metrics.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
      metrics.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      metrics.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      contextLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 103),
      contextLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
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
    let layers = iconButton("square.3.layers.3d", "Слой карты") {}
    layers.showsMenuAsPrimaryAction = true
    layers.menu = UIMenu(
      children: CampusLens.allCases.map { layer in
        UIAction(title: layer.title) { [weak self] _ in
          guard let self else { return }
          self.lens = layer
          self.factory.apply(self.simulation, lens: layer, tracked: self.trackedOrder)
          self.renderDock(animated: true)
        }
      })
    let tools = mapTools
    tools.rounded(22)
    let sections = iconButton("building.2", "Все участки") {}
    sections.showsMenuAsPrimaryAction = true
    sections.menu = UIMenu(
      children: FactoryZone.allCases.map { zone in
        UIAction(title: "\(zone.code) · \(zone.title)") { [weak self] _ in self?.select(zone) }
      })
    let buttons = stack([farther, closer, reset, layers, sections], axis: .horizontal, spacing: 0)
    tools.contentView.pin(buttons, inset: 0)
    tools.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tools)
    minimap.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(minimap)
    NSLayoutConstraint.activate([
      tools.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -12),
      tools.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      minimap.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
      minimap.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      minimap.widthAnchor.constraint(equalToConstant: 88),
      minimap.heightAnchor.constraint(equalToConstant: 62),
    ])
  }
  private func makeDock() {
    dock.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(dock)
    dockContent.axis = .vertical
    dockContent.spacing = 10
    dock.contentView.pin(dockContent, inset: 16)
    NSLayoutConstraint.activate([
      dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
    eventText.numberOfLines = 1
    eventText.lineBreakMode = .byTruncatingTail
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
      self.minimap.isHidden = self.selected == nil
      self.metrics.isHidden = self.selected != nil
      self.contextLabel.isHidden = self.selected != nil
      self.outputNumber.text = "\(self.simulation.completed)"
      self.attentionNumber.text = "\(self.simulation.attentionCount)"
      self.contextLabel.text =
        self.selected.map { "\($0.code) · \($0.shortTitle.uppercased())" }
        ?? "\(self.lens.title.uppercased()) · 9 УЧАСТКОВ"
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
        kicker = "СМЕНА · \(self.simulation.clockTime)"
        title =
          self.lens == .load
          ? "Загрузка участков"
          : self.lens == .orders ? "Заказы на карте" : "Вся компания"
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
      fold.height(32)
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
      let name = label(title, 22, .medium, InsideStyle.ink)
      name.numberOfLines = 1
      name.adjustsFontSizeToFitWidth = true
      name.minimumScaleFactor = 0.75
      name.accessibilityIdentifier = "owner.selectedZone"
      name.accessibilityHint = kicker
      let description = self.tourIndex != nil ? "\(kicker) · \(subtitle)" : subtitle
      let titles = stack(
        self.selected == nil
          ? [name] : [name, label(description, 12, .regular, InsideStyle.muted)], spacing: 5)
      let context = stack([titles, UIView(), fold], axis: .horizontal, spacing: 8)
      context.alignment = .center
      self.dockContent.addArrangedSubview(context)
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
      self.dockContent.addArrangedSubview(self.eventText)
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
    contextLabel.text = "ТЕРРИТОРИЯ · 9 УЧАСТКОВ"
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
