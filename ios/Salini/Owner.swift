import SceneKit
import UIKit

/// Salini Inside as the owner's working board: it opens on what needs attention now, a swipeable
/// board of business metrics sits under the scene, a tap points the camera at the live process,
/// and free manual exploration is never undone by the model.
final class OwnerController: UIViewController {
  let simulation = FactorySimulation()
  let factory = FactorySceneView()
  private let minimap = CampusOverview()
  private let header = GlassView()
  let board = InsightBoardView()
  let returnPill = UIButton(type: .system)
  private let live = label("ДЕМО · 00:00", 10, .semibold, InsideStyle.blue)
  private var lens: CampusLens = .campus
  private var trackedOrder: InsideOrderID?
  private(set) var tourIndex: Int?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var speed = 1
  private var lastRevision = -1
  private var pauseButton: UIButton!
  private var speedButton: UIButton!
  /// The card the owner chose and the focus the camera is showing. Model revisions refresh their
  /// text but never switch them: after a decision the camera does not jump on its own.
  private(set) var selectedMetric: InsideMetricID? = .decisions
  private(set) var activeFocus: InsideFocus
  private(set) var cameraManual = false

  /// Where the camera was last sent for the active subject; a change while in event/follow
  /// mode moves the camera along with the same process.
  private(set) var shownTarget: InsideTarget?

  init() {
    activeFocus = InsideFocus(
      id: "", kind: .live, subject: .zone(.office), target: .zone(.office), title: "", reason: "", decision: nil)
    super.init(nibName: nil, bundle: nil)
    activeFocus = simulation.primaryFocus
  }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = InsideStyle.canvas
    factory.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(factory)
    NSLayoutConstraint.activate([
      factory.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      factory.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      factory.topAnchor.constraint(equalTo: view.topAnchor),
      factory.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    makeHeader()
    makeBoard()
    makeMinimap()
    factory.onSelect = { [weak self] zone in self?.focusZone(zone) }
    factory.onOrderSelect = { [weak self] order in self?.locate(order) }
    factory.onStationSelect = { [weak self] zone, code in self?.open(.station(zone, code)) }
    factory.onViewport = { [weak self] camera in self?.minimap.camera = camera }
    factory.onCameraModeChange = { [weak self] mode in
      guard let self else { return }
      self.cameraManual = mode == .manual
      self.updateReturnPill()
    }
    // Opening: straight onto the top-priority focus, set before the first layout — no flight.
    shownTarget = activeFocus.target
    factory.show(activeFocus.target, animated: false)
    minimap.selectedZone = zone(of: activeFocus.target)
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
    // Reduce Motion switched on the fly: the scene holds still at once and resumes when allowed;
    // the scenario keeps advancing and its state stays visible through the board.
    observers.append(
      NotificationCenter.default.addObserver(
        forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        self.factory.setPaused(self.simulation.paused)
      })
    refresh(force: true)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let top = header.frame.maxY + 8
    let bottom = view.bounds.height - board.frame.minY + 8
    factory.mapContentInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    factory.excludedAnnotationRects = [header, minimap, board, returnPill].filter { !$0.isHidden }.map {
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
      self.live.text = self.simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · \(self.simulation.clockTime)"
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

  // MARK: Header

  private func iconButton(_ icon: String, _ name: String, action: @escaping () -> Void) -> UIButton {
    let b = insideAction("", icon: icon, action: action)
    b.accessibilityLabel = name
    b.widthAnchor.constraint(equalToConstant: 44).isActive = true
    b.height(44)
    b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    b.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    return b
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
      self.pauseButton.configuration?.image = UIImage(systemName: self.simulation.paused ? "play" : "pause")
      self.pauseButton.accessibilityLabel = self.simulation.paused ? "Продолжить демо" : "Приостановить демо"
    }
    speedButton = insideAction("×150", icon: "") { [weak self] in
      guard let self else { return }
      self.speed = self.speed == 1 ? 3 : 1
      self.speedButton.configuration?.title = "×\(self.speed * 150)"
      self.speedButton.accessibilityLabel = "Время сценария ускорено в \(self.speed * 150) раз"
      self.factory.simulationSpeed = CGFloat(self.speed)
    }
    speedButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
    speedButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var a = $0
      a.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
      return a
    }
    speedButton.widthAnchor.constraint(equalToConstant: 43).isActive = true
    speedButton.height(44)
    let more = iconButton("ellipsis", "Инструменты карты") {}
    more.showsMenuAsPrimaryAction = true
    more.accessibilityIdentifier = "insight.menu"
    more.menu = UIMenu(children: [
      UIAction(title: "Вся территория", image: UIImage(systemName: "viewfinder")) { [weak self] _ in self?.overview() },
      UIMenu(
        title: "Перейти к участку",
        children: FactoryZone.allCases.map { zone in
          UIAction(title: "\(zone.code) · \(zone.title)", image: UIImage(systemName: zone.icon)) { [weak self] _ in
            self?.focusZone(zone)
          }
        }),
      UIMenu(title: "Слой карты", children: CampusLens.allCases.map { layer in
        UIAction(title: layer.title) { [weak self] _ in
          guard let self else { return }
          self.lens = layer
          self.factory.apply(self.simulation, lens: layer, tracked: self.trackedOrder)
        }
      }),
      UIAction(title: "Открыть / закрыть крыши", image: UIImage(systemName: "square.3.layers.3d")) { [weak self] _ in
        guard let self else { return }
        self.factory.setRoof(!self.factory.roofVisible)
      },
      UIAction(title: "Маршрут Aria по этапам",
               image: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath")) { [weak self] _ in
        self?.startTour()
      },
      UIAction(title: "Журнал решений", image: UIImage(systemName: "clock.arrow.circlepath")) { [weak self] _ in
        self?.open(.events)
      },
      UIAction(title: "Начать демо заново", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
        guard let self, let nav = self.navigationController else { return }
        let next = OwnerController()
        next.hidesBottomBarWhenPushed = self.hidesBottomBarWhenPushed
        nav.setViewControllers(Array(nav.viewControllers.dropLast()) + [next], animated: false)
      },
      UIAction(title: "О модели и источниках", image: UIImage(systemName: "info.circle")) { [weak self] _ in
        self?.sheet(AboutController())
      },
    ])
    let heading = stack([back, title, UIView(), pauseButton, speedButton, more], axis: .horizontal, spacing: 0)
    heading.alignment = .center
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    header.contentView.pin(heading, inset: 4)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
    // Map zoom for VoiceOver without on-screen ± buttons (pinch remains for touch).
    factory.accessibilityCustomActions = (factory.accessibilityCustomActions ?? []) + [
      UIAccessibilityCustomAction(name: "Приблизить карту") { [weak self] _ in self?.factory.stepZoom(true); return true },
      UIAccessibilityCustomAction(name: "Отдалить карту") { [weak self] _ in self?.factory.stepZoom(false); return true },
      UIAccessibilityCustomAction(name: "Вся территория") { [weak self] _ in self?.overview(); return true },
    ]
  }

  // MARK: Board, minimap, return

  private func makeBoard() {
    board.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(board)
    NSLayoutConstraint.activate([
      board.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      board.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      board.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      // The scene keeps at least half of the screen, even with the largest text.
      board.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.5),
    ])
    board.onSelect = { [weak self] id in self?.choose(id) }
    board.onAction = { [weak self] in self?.act() }
    board.onSecondary = { [weak self] in self?.secondary() }
    var c = UIButton.Configuration.prominentGlass()
    c.title = "К событию"
    c.image = UIImage(systemName: "arrow.uturn.backward")
    c.imagePadding = 6
    c.baseBackgroundColor = InsideStyle.ink
    c.baseForegroundColor = .white
    c.cornerStyle = .capsule
    returnPill.configuration = c
    returnPill.accessibilityIdentifier = "insight.return"
    returnPill.addAction(UIAction { [weak self] _ in self?.showActiveFocus() }, for: .touchUpInside)
    returnPill.translatesAutoresizingMaskIntoConstraints = false
    returnPill.isHidden = true
    view.addSubview(returnPill)
    NSLayoutConstraint.activate([
      returnPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      returnPill.bottomAnchor.constraint(equalTo: board.topAnchor, constant: -10),
    ])
  }
  private func makeMinimap() {
    minimap.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(minimap)
    NSLayoutConstraint.activate([
      minimap.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
      minimap.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      minimap.widthAnchor.constraint(equalToConstant: 96),
      minimap.heightAnchor.constraint(equalToConstant: 84),
    ])
    minimap.onSelect = { [weak self] zone in self?.focusZone(zone) }
    minimap.onOverview = { [weak self] in self?.overview() }
  }
  private func updateReturnPill() {
    let show = cameraManual && tourIndex == nil
    returnPill.accessibilityLabel = "Вернуться к событию: \(activeFocus.title)"
    guard returnPill.isHidden == show else { return }
    returnPill.isHidden = !show
    view.setNeedsLayout()
  }

  // MARK: Model → board

  func refresh(force: Bool = false) {
    live.text = simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · \(simulation.clockTime)"
    // A followed trip can leave the site between model events: keep its line honest every tick.
    if case .follow = factory.cameraMode, !force, lastRevision == simulation.revision { renderContext() }
    guard force || lastRevision != simulation.revision else { return }
    lastRevision = simulation.revision
    factory.apply(simulation, lens: lens, tracked: trackedOrder)
    let metrics = InsideBoard(simulation: simulation).metrics
    board.update(metrics: metrics, selected: selectedMetric)
    activeFocus = refreshed(activeFocus, metrics: metrics)
    // Follow the same process as it moves; in manual exploration only the text changes.
    if activeFocus.target != shownTarget && tourIndex == nil && factory.cameraMode != .manual {
      shownTarget = activeFocus.target
      factory.show(activeFocus.target, animated: true)
      minimap.selectedZone = zone(of: activeFocus.target)
    }
    renderContext()
  }
  /// The same focus with current texts. Never a different target: the camera stays on what the
  /// owner chose; a resolved decision reads as resolved, with the order's current status.
  private func refreshed(_ focus: InsideFocus, metrics: [InsideMetric]) -> InsideFocus {
    let candidates = simulation.focuses + metrics.map(\.focus)
    if let same = candidates.first(where: { $0.id == focus.id && $0.subject == focus.subject }) { return same }
    let status: String
    switch focus.decision {
    case .order(let order)?: status = simulation.status(order)
    case .dispatch?:
      if case .trip(let trip) = focus.target { status = simulation.tripState(trip).text } else {
        status = simulation.tripState(.petersburg).text
      }
    case .zone(let zone)?: status = simulation.summary(zone)
    default: status = focus.reason
    }
    // Only a decision that disappeared reads as taken (marked once, stays marked); a process
    // keeps its own current status.
    let taken = focus.id.hasSuffix("#taken") || [.blocking, .urgent, .decision].contains(focus.kind)
    // The title follows the subject's current stage (Marea: «упаковка», not «удержана ОТК»).
    return simulation.focus(
      taken && !focus.id.hasSuffix("#taken") ? focus.id + "#taken" : focus.id, .live, focus.subject,
      simulation.stageTitle(of: focus.subject), taken ? "Решение принято · \(status)" : status, focus.decision)
  }
  private func renderContext() {
    if let index = tourIndex {
      let zone = FactoryZone.orderRoute[index]
      board.showContext(
        title: "Маршрут Aria · \(index + 1) из \(FactoryZone.orderRoute.count) · \(zone.title)",
        reason: "Схема этапов — не текущее положение заказа",
        action: index == FactoryZone.orderRoute.count - 1 ? "Завершить" : "Дальше", secondary: "Выйти")
      return
    }
    var reason = activeFocus.reason
    if case .trip(let trip) = activeFocus.target, factory.tripLeftCampus(trip) {
      reason = "\(simulation.tripState(trip).text) · за пределами территории"
    }
    let decisive = [.blocking, .urgent, .decision].contains(activeFocus.kind)
    board.showContext(
      title: activeFocus.title, reason: reason,
      action: activeFocus.decision == nil ? nil : decisive ? "Решить" : "Подробнее", secondary: nil)
  }

  // MARK: Actions

  /// Tap on a card: choose it and look at its process. On the chosen card while exploring
  /// manually, the tap is the way back to the event. Panels open only via the explicit button.
  func choose(_ id: InsideMetricID) {
    let metrics = InsideBoard(simulation: simulation).metrics
    guard let metric = metrics.first(where: { $0.id == id }) else { return }
    if id != selectedMetric || !cameraManual {
      activeFocus = metric.focus
    }
    selectedMetric = id
    tourIndex = nil
    board.update(metrics: metrics, selected: id)
    board.reveal(id, animated: !UIAccessibility.isReduceMotionEnabled)
    showActiveFocus()
  }
  /// Sends the camera to where the chosen subject is NOW (not where it was when chosen).
  func showActiveFocus() {
    tourIndex = nil
    activeFocus = refreshed(activeFocus, metrics: InsideBoard(simulation: simulation).metrics)
    if case .order(let order) = activeFocus.subject {
      trackedOrder = order
      factory.showOrderRoute(order.route)
    } else {
      trackedOrder = nil
      factory.showRoute(false)
    }
    shownTarget = activeFocus.target
    factory.show(activeFocus.target, animated: true)
    minimap.selectedZone = zone(of: activeFocus.target)
    factory.apply(simulation, lens: lens, tracked: trackedOrder)
    renderContext()
    updateReturnPill()
  }
  private func act() {
    if let index = tourIndex {
      if index == FactoryZone.orderRoute.count - 1 { endTour() } else { nextTour() }
      return
    }
    guard let decision = activeFocus.decision else { return }
    switch decision {
    case .order(let order): open(.order(order))
    case .orders: open(.orders)
    case .dispatch: open(.dispatch)
    case .zone(let zone): open(zone == .office ? .orders : zone == .dispatch ? .dispatch : .zone(zone))
    }
  }
  private func secondary() {
    if tourIndex != nil { endTour() }
  }
  private func focusZone(_ zone: FactoryZone) {
    activeFocus = simulation.focus(
      "zone-\(zone.rawValue)", .live, .zone(zone), zone.title,
      "\(simulation.load(zone))% загрузка · \(simulation.summary(zone))", .zone(zone))
    selectedMetric = nil
    board.update(metrics: InsideBoard(simulation: simulation).metrics, selected: nil)
    showActiveFocus()
  }
  private func locate(_ order: InsideOrderID) {
    activeFocus = simulation.focus(
      "order-\(order.rawValue)", .live, .order(order), order.product,
      "\(order.rawValue) · \(simulation.status(order))", .order(order))
    selectedMetric = nil
    board.update(metrics: InsideBoard(simulation: simulation).metrics, selected: nil)
    showActiveFocus()
  }
  /// A released trip from the dispatch panel: the camera follows that truck.
  func focusTrip(_ trip: InsideTrip) {
    activeFocus = simulation.focus(
      "trip-sel-\(trip.rawValue)", .live, .trip(trip), trip.title,
      "\(simulation.tripState(trip).text) · \(trip.cargo)", .dispatch)
    selectedMetric = .road
    board.update(metrics: InsideBoard(simulation: simulation).metrics, selected: .road)
    // Chosen from the panel: bring the selected card into view, as a tap would.
    board.reveal(.road, animated: false)
    showActiveFocus()
  }
  func overview() {
    tourIndex = nil
    minimap.selectedZone = nil
    factory.resetCamera()
    factory.showRoute(false)
    renderContext()
    updateReturnPill()
  }
  private func startTour() {
    simulation.paused = true
    factory.setPaused(true)
    pauseButton.configuration?.image = UIImage(systemName: "play")
    pauseButton.accessibilityLabel = "Продолжить демо"
    trackedOrder = nil
    tourIndex = 0
    factory.focusOn(FactoryZone.orderRoute[0], mode: .tour)
    minimap.selectedZone = FactoryZone.orderRoute[0]
    factory.showOrderRoute(FactoryZone.orderRoute)
    renderContext()
    updateReturnPill()
  }
  private func nextTour() {
    guard let index = tourIndex, index < FactoryZone.orderRoute.count - 1 else { return endTour() }
    tourIndex = index + 1
    factory.focusOn(FactoryZone.orderRoute[index + 1], mode: .tour)
    minimap.selectedZone = FactoryZone.orderRoute[index + 1]
    renderContext()
  }
  private func endTour() {
    tourIndex = nil
    factory.showRoute(false)
    showActiveFocus()
  }
  private func zone(of target: InsideTarget) -> FactoryZone {
    switch target {
    case .zone(let zone): return zone
    case .trip: return .dispatch
    case .transfer: return .packing
    }
  }
  private func open(_ destination: InsideDestination) {
    let panel = InsidePanelController(destination, simulation: simulation) { [weak self] zone, order in
      guard let self else { return }
      if let order { self.locate(order) } else { self.focusZone(zone) }
    }
    panel.onTrip = { [weak self] trip in self?.focusTrip(trip) }
    let nav = UINavigationController(rootViewController: panel)
    nav.modalPresentationStyle = .pageSheet
    nav.sheetPresentationController?.detents = [.large()]
    nav.sheetPresentationController?.prefersGrabberVisible = true
    present(nav, animated: true)
  }
}
