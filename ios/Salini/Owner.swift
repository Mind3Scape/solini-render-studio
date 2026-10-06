import SceneKit
import UIKit

final class OwnerController: ScrollController {
  let simulation = FactorySimulation()
  private let factory = FactorySceneView()
  private let inspector = UIStackView()
  private let events = UIStackView()
  private let completed = label("42", 28, .medium)
  private let liveLabel = eyebrow("ДЕМО · В ЭФИРЕ", color: Palette.ink)
  private var timer: Timer?
  private var chips: [UIButton] = []
  private var progress: UIProgressView?
  private var status = label("", 12, .regular, Palette.muted)
  private var pause: UIBarButtonItem!
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Salini Inside"
    navigationItem.largeTitleDisplayMode = .never
    pause = UIBarButtonItem(
      image: UIImage(systemName: "pause"),
      primaryAction: UIAction { [weak self] _ in self?.togglePause() })
    pause.accessibilityLabel = "Приостановить демо"
    pause.accessibilityIdentifier = "owner.pause"
    navigationItem.rightBarButtonItem = pause
    let top = stack(
      [
        stack(
          [liveLabel, UIView(), label("28 на смене", 12, .medium, Palette.muted)], axis: .horizontal
        ), label("Пульс Salini.", 37, .regular, serif: true),
        label("Белгород · производственный комплекс", 14, .regular, Palette.muted),
      ], spacing: 11)
    add(top, inset: 24)
    let metrics = stack(
      [
        metric("В РАБОТЕ", label("62", 28, .medium), "изделия"),
        metric("ГОТОВО", completed, "за смену"),
        metric("В СРОК", label("96%", 28, .medium), "заказов"),
      ], axis: .horizontal, spacing: 10)
    metrics.distribution = .fillEqually
    add(metrics, inset: 24)
    let scene = UIView()
    scene.height(380)
    scene.pin(factory)
    factory.onSelect = { [weak self] zone in self?.openZone(zone) }
    let reset = ActionButton("", icon: "viewfinder") { [weak self] in self?.factory.resetCamera() }
    reset.accessibilityLabel = "Общий вид производства"
    reset.translatesAutoresizingMaskIntoConstraints = false
    scene.addSubview(reset)
    let guide = GlassView()
    let caption = label("Нажмите на участок", 11, .medium)
    guide.contentView.pin(caption, inset: 12)
    guide.translatesAutoresizingMaskIntoConstraints = false
    scene.addSubview(guide)
    NSLayoutConstraint.activate([
      reset.trailingAnchor.constraint(equalTo: scene.trailingAnchor, constant: -20),
      reset.bottomAnchor.constraint(equalTo: scene.bottomAnchor, constant: -16),
      guide.leadingAnchor.constraint(equalTo: scene.leadingAnchor, constant: 24),
      guide.bottomAnchor.constraint(equalTo: scene.bottomAnchor, constant: -16),
    ])
    add(scene, inset: 0)
    let buttons = FactoryZone.allCases.map { z -> UIView in
      let b = ActionButton(z.title) { [weak self] in self?.openZone(z) }
      b.accessibilityIdentifier = "zone.\(z.rawValue)"
      b.configuration?.contentInsets = NSDirectionalEdgeInsets(
        top: 12, leading: 15, bottom: 12, trailing: 15)
      chips.append(b)
      return b
    }
    add(horizontal(buttons, width: 123, height: 45), inset: 16)
    inspector.axis = .vertical
    inspector.spacing = 16
    let panel = inspector.inset(22)
    panel.backgroundColor = .white
    panel.rounded(28)
    add(panel, inset: 24)
    let insight = stack(
      [
        eyebrow("ВНИМАНИЕ К ДЕТАЛЯМ"),
        label("Контроль поверхности Aria", 28, .regular, serif: true),
        label("Для партии запланирована дополнительная проверка.", 14, .regular, Palette.muted),
        ActionButton("Посмотреть участок", icon: "arrow.up.right") { [weak self] in
          self?.openZone(.quality)
        },
      ], spacing: 14
    ).inset(22)
    insight.backgroundColor = UIColor(hex: 0xEDEFF3)
    insight.rounded(26)
    add(insight, inset: 24)
    events.axis = .vertical
    events.spacing = 16
    add(stack([eyebrow("ПРОИСХОДИТ СЕЙЧАС"), events], spacing: 20))
    add(
      ActionButton("Площадки и логистика", icon: "point.3.connected.trianglepath.dotted") {
        [weak self] in self?.sheet(NetworkController())
      })
    add(
      label(
        "Интерактивное демо · схема цеха и все операционные данные смоделированы. Камеры и 1С пока не подключены.",
        11, .regular, Palette.muted))
    select(.casting)
    refreshEvents()
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startTimer()
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    timer?.invalidate()
    timer = nil
    factory.setPaused(true)
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    factory.setPaused(simulation.paused)
  }
  private func metric(_ name: String, _ value: UILabel, _ unit: String) -> UIView {
    let s = stack([eyebrow(name), value, label(unit, 11, .regular, Palette.muted)], spacing: 5)
      .inset(14)
    s.backgroundColor = UIColor.white.withAlphaComponent(0.7)
    s.rounded(21)
    return s
  }
  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      guard let self, !self.simulation.paused else { return }
      self.simulation.advance()
      self.completed.text = "\(self.simulation.completed)"
      self.progress?.setProgress(self.simulation.progress, animated: true)
      self.status.text = "Обновлено сейчас · событие \(self.simulation.tick)"
      self.refreshEvents()
    }
  }
  private func togglePause() {
    simulation.paused.toggle()
    factory.setPaused(simulation.paused)
    liveLabel.text = simulation.paused ? "ДЕМО · ПАУЗА" : "ДЕМО · В ЭФИРЕ"
    pause.image = UIImage(systemName: simulation.paused ? "play" : "pause")
    pause.accessibilityLabel = simulation.paused ? "Продолжить демо" : "Приостановить демо"
  }
  func select(_ zone: FactoryZone) {
    simulation.selected = zone
    factory.select(zone)
    UISelectionFeedbackGenerator().selectionChanged()
    for (i, b) in chips.enumerated() {
      b.configuration?.baseBackgroundColor = i == zone.rawValue ? Palette.ink : .clear
      b.configuration?.baseForegroundColor = i == zone.rawValue ? .white : Palette.ink
      if i == zone.rawValue {
        var c = UIButton.Configuration.prominentGlass()
        c.title = zone.title
        c.baseBackgroundColor = Palette.ink
        c.baseForegroundColor = .white
        c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)
        b.configuration = c
      } else {
        var c = UIButton.Configuration.glass()
        c.title = FactoryZone(rawValue: i)!.title
        c.baseForegroundColor = Palette.ink
        c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)
        b.configuration = c
      }
    }
    inspector.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let title = label(zone.title, 30, .regular, serif: true)
    title.accessibilityIdentifier = "owner.selectedZone"
    let count = eyebrow(
      "\(zone.count) \(zone == .dispatch ? plural(zone.count, "МАШИНА", "МАШИНЫ", "МАШИН") : plural(zone.count, "ИЗДЕЛИЕ", "ИЗДЕЛИЯ", "ИЗДЕЛИЙ"))",
      color: Palette.ink)
    let row = stack([title, UIView(), count], axis: .horizontal)
    row.alignment = .center
    inspector.addArrangedSubview(row)
    inspector.addArrangedSubview(label(zone.state, 14, .regular, Palette.muted))
    inspector.addArrangedSubview(line())
    let order = label(
      zone == .dispatch ? "Москва · рейс М-104" : "S-2048 · Aria 190", 19, .semibold)
    inspector.addArrangedSubview(
      stack(
        [
          eyebrow(zone == .warehouse ? "БЛИЖАЙШИЙ РЕЗЕРВ" : "В ФОКУСЕ"), order,
          label(
            zone == .dispatch
              ? "3 заказа · отправление в 14:30" : "4 изделия · S-Stone · белый матовый", 13,
            .regular, Palette.muted),
        ], spacing: 7))
    let p = UIProgressView(progressViewStyle: .default)
    p.progressTintColor = Palette.ink
    p.trackTintColor = Palette.line
    p.progress = simulation.progress
    p.height(5)
    inspector.addArrangedSubview(p)
    progress = p
    status = label(
      "\(zone.people) \(plural(zone.people,"сотрудник","сотрудника","сотрудников")) · обновлено сейчас",
      12, .regular, Palette.muted)
    inspector.addArrangedSubview(status)
    let camera = ActionButton("Камера \(zone.code)", icon: "video") { [weak self] in
      self?.sheet(CameraController(zone))
    }
    camera.accessibilityIdentifier = "owner.camera"
    let job = ActionButton("Заказ", icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      self.sheet(
        OrderController(self.simulation, onChange: { [weak self] in self?.refreshEvents() }))
    }
    job.accessibilityIdentifier = "owner.order"
    let actions = stack([camera, job], axis: .horizontal, spacing: 10)
    actions.distribution = .fillEqually
    inspector.addArrangedSubview(actions)
    if zone == .quality {
      let resolve = ActionButton(
        simulation.resolved ? "Контроль назначен" : "Назначить контроль",
        icon: simulation.resolved ? "checkmark" : "person.badge.plus"
      ) { [weak self] in
        self?.simulation.resolve()
        self?.select(.quality)
        self?.refreshEvents()
      }
      resolve.isEnabled = !simulation.resolved
      inspector.addArrangedSubview(resolve)
    }
  }
  private func openZone(_ zone: FactoryZone) {
    select(zone)
    sheet(
      ZoneController(
        zone, simulation: simulation,
        onChange: { [weak self] in
          self?.select(zone)
          self?.refreshEvents()
        }))
  }
  private func refreshEvents() {
    events.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (i, event) in simulation.events.prefix(4).enumerated() {
      let dot = symbol(
        i == 0 ? "circle.inset.filled" : "circle", size: 10,
        color: i == 0 ? Palette.ink : Palette.muted)
      let row = stack(
        [dot, label(event, 14, .regular, i == 0 ? Palette.ink : Palette.muted)], axis: .horizontal,
        spacing: 12)
      row.alignment = .top
      events.addArrangedSubview(row)
    }
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
    title = "Участок \(zone.code)"
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
        label("S-2048 · Aria 190", 21, .semibold),
        label("4 изделия · S-Stone · белый матовый", 13, .regular, Palette.muted),
      ], spacing: 14)
    add(heading)
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
