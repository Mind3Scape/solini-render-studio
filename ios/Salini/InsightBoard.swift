import UIKit

extension InsideTone {
  /// Meaning colours only: teal — flowing work, cobalt — on the road, amber — risk/decision.
  var color: UIColor {
    switch self {
    case .neutral: return InsideStyle.muted
    case .teal: return UIColor(hex: 0x2F7F78)
    case .cobalt: return UIColor(hex: 0x3A5C9E)
    case .amber: return InsideStyle.amber
    }
  }
}

/// One business metric: a compact card (icon badge, value, label). A whole-card tap zone;
/// updated in place, so selection and scroll position survive every revision of the numbers.
final class InsightMetricCard: UIControl {
  let metricID: InsideMetricID
  private let badge = UIView()
  private let icon = UIImageView()
  private let titleLabel = label("", 11, .medium, InsideStyle.muted)
  private let valueLabel = UILabel()
  private let bar = UIProgressView(progressViewStyle: .bar)
  private var tone: InsideTone = .neutral
  init(_ id: InsideMetricID) {
    metricID = id
    super.init(frame: .zero)
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    badge.layer.cornerRadius = 14
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.widthAnchor.constraint(equalToConstant: 28).isActive = true
    badge.heightAnchor.constraint(equalToConstant: 28).isActive = true
    icon.contentMode = .center
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    badge.pin(icon)
    valueLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
      for: .monospacedDigitSystemFont(ofSize: 20, weight: .regular), maximumPointSize: 28)
    valueLabel.adjustsFontForContentSizeCategory = true
    valueLabel.textColor = InsideStyle.ink
    valueLabel.adjustsFontSizeToFitWidth = true
    valueLabel.minimumScaleFactor = 0.7
    titleLabel.numberOfLines = 2
    bar.trackTintColor = UIColor.black.withAlphaComponent(0.06)
    bar.layer.cornerRadius = 1
    bar.clipsToBounds = true
    bar.heightAnchor.constraint(equalToConstant: 2).isActive = true
    let texts = stack([valueLabel, titleLabel, bar], spacing: 2)
    let row = stack([badge, texts], axis: .horizontal, spacing: 10)
    row.alignment = .top
    row.isUserInteractionEnabled = false
    pin(row, inset: 10)
    widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    widthAnchor.constraint(lessThanOrEqualToConstant: 176).isActive = true
    heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    isAccessibilityElement = true
    accessibilityIdentifier = "insight.metric.\(id.rawValue)"
    accessibilityHint = "Показать на карте"
    updateSelection()
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isSelected: Bool { didSet { updateSelection() } }
  override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.75 : 1 } }
  func update(_ metric: InsideMetric) {
    tone = metric.tone
    titleLabel.text = metric.title
    valueLabel.text = metric.value
    icon.image = UIImage(systemName: metric.icon)
    icon.tintColor = metric.tone.color
    badge.backgroundColor = metric.tone.color.withAlphaComponent(0.12)
    bar.isHidden = metric.progress == nil
    bar.progress = Float(metric.progress ?? 0)
    bar.progressTintColor = metric.tone.color
    accessibilityLabel = "\(metric.title): \(metric.value). \(metric.detail)"
    accessibilityValue = metric.attention ? "Требует внимания" : nil
    updateSelection()
  }
  private func updateSelection() {
    // Selected: a light wash and a hairline in the card's own tone; others stay neutral.
    let color = tone == .neutral ? InsideStyle.ink : tone.color
    backgroundColor = isSelected ? color.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.42)
    layer.borderWidth = isSelected ? 1 : 0
    layer.borderColor = color.withAlphaComponent(0.55).cgColor
    accessibilityTraits = isSelected ? [.button, .selected] : .button
  }
}

/// Horizontal metric strip: a drag that starts on a card scrolls the strip (the card's touch is
/// cancelled) — UIScrollView keeps UIControl touches by default.
final class InsightMetricStrip: UIScrollView {
  override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// Read-only stages of the chosen subject: no buttons, no future-state navigation. One line when
/// it fits, two rows when the width is short, a vertical list for accessibility text sizes.
final class InsightRouteView: UIView {
  enum Mode { case line, twoRows, vertical }
  private let column = UIStackView()
  private var route: InsideRoute?
  private var tone: InsideTone = .neutral
  private var forceVertical = false
  private(set) var mode: Mode = .line
  private var lastWidth: CGFloat = 0
  init() {
    super.init(frame: .zero)
    column.axis = .vertical
    column.alignment = .leading
    column.spacing = 6
    column.translatesAutoresizingMaskIntoConstraints = false
    addSubview(column)
    // Hugs the leading edge: stages are never stretched across the width.
    NSLayoutConstraint.activate([
      column.topAnchor.constraint(equalTo: topAnchor),
      column.bottomAnchor.constraint(equalTo: bottomAnchor),
      column.leadingAnchor.constraint(equalTo: leadingAnchor),
      column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
    ])
    isAccessibilityElement = true
    accessibilityIdentifier = "insight.route"
    accessibilityTraits = .staticText
  }
  required init?(coder: NSCoder) { fatalError() }

  func show(_ route: InsideRoute?, tone: InsideTone, vertical: Bool) {
    self.route = route
    self.tone = tone
    forceVertical = vertical
    isHidden = route == nil
    rebuild(mode: vertical ? .vertical : preferredMode(for: bounds.width))
    guard let route else { return }
    let states = route.stages.enumerated().map { i, name in
      i < route.current ? "\(name) — пройден" : i == route.current ? "\(name) — \(route.held ? "удержан" : "текущий")" : name
    }
    let progress = route.progress.map { ", выполнено \(Int(($0 * 100).rounded())) процентов" } ?? ""
    accessibilityLabel = "Этапы: " + states.joined(separator: ", ") + progress
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    // Choose the arrangement from the real width; rebuild only when the mode changes.
    guard bounds.width != lastWidth, !forceVertical else { return }
    lastWidth = bounds.width
    let wanted = preferredMode(for: bounds.width)
    if wanted != mode { rebuild(mode: wanted) }
  }
  /// One line when all stages with connectors fit; otherwise two rows.
  private func preferredMode(for width: CGFloat) -> Mode {
    guard let route, width > 0 else { return .line }
    let needed = route.stages.indices.reduce(CGFloat(0)) { $0 + stageView(at: $1, route).systemLayoutSizeFitting(
      UIView.layoutFittingCompressedSize).width } + CGFloat(route.stages.count - 1) * Self.connectorWidth
    return needed <= width ? .line : .twoRows
  }
  private static let connectorWidth: CGFloat = 10 + 2 * 6
  private func currentColor(_ route: InsideRoute) -> UIColor {
    route.held ? InsideStyle.amber : (tone == .neutral ? InsideStyle.ink : tone.color)
  }
  /// A stage: dot and name, and under the name a reserved 2 pt line for the model's progress, so
  /// the height never jumps when progress appears.
  private func stageView(at i: Int, _ route: InsideRoute) -> UIView {
    let done = i < route.current
    let isCurrent = i == route.current
    let color = currentColor(route)
    let dot = UIView()
    dot.layer.cornerRadius = 4
    dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
    dot.backgroundColor = isCurrent ? color : done ? InsideStyle.ink.withAlphaComponent(0.55) : .clear
    dot.layer.borderWidth = isCurrent || done ? 0 : 1
    dot.layer.borderColor = InsideStyle.muted.cgColor
    let name = label(route.stages[i], 11, isCurrent ? .semibold : .regular, isCurrent ? color : InsideStyle.muted)
    name.numberOfLines = 1
    name.setContentCompressionResistancePriority(.required, for: .horizontal)
    name.setContentCompressionResistancePriority(.required, for: .vertical)
    name.accessibilityIdentifier = "insight.route.stage.\(i)"
    let head = stack([dot, name], axis: .horizontal, spacing: 5)
    head.alignment = .center
    let bar = UIProgressView(progressViewStyle: .bar)
    bar.trackTintColor = isCurrent && route.progress != nil ? UIColor.black.withAlphaComponent(0.06) : .clear
    bar.progressTintColor = color
    bar.progress = Float(isCurrent ? route.progress ?? 0 : 0)
    bar.alpha = isCurrent && route.progress != nil ? 1 : 0
    // The 2 pt slot is always there; the bar sits under the name (dot 8 + spacing 5).
    let slot = UIView()
    slot.translatesAutoresizingMaskIntoConstraints = false
    slot.addSubview(bar)
    bar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      slot.heightAnchor.constraint(equalToConstant: 2),
      bar.topAnchor.constraint(equalTo: slot.topAnchor),
      bar.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
      bar.leadingAnchor.constraint(equalTo: slot.leadingAnchor, constant: 13),
      bar.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
    ])
    let stage = stack([head, slot], spacing: 3)
    stage.alignment = .fill
    return stage
  }
  private func connector() -> UIView {
    let line = UIView()
    line.backgroundColor = InsideStyle.muted.withAlphaComponent(0.35)
    line.widthAnchor.constraint(equalToConstant: 10).isActive = true
    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
    let holder = UIView()
    holder.translatesAutoresizingMaskIntoConstraints = false
    // Explicit size: as tall as a stage head, so a top-aligned row has no ambiguous height.
    holder.widthAnchor.constraint(equalToConstant: Self.connectorWidth).isActive = true
    holder.heightAnchor.constraint(equalToConstant: 13).isActive = true
    holder.addSubview(line)
    line.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      line.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
      // Level with the dots, above the reserved progress line.
      line.topAnchor.constraint(equalTo: holder.topAnchor, constant: 6),
    ])
    return holder
  }
  private func rebuild(mode: Mode) {
    self.mode = mode
    column.arrangedSubviews.forEach { $0.removeFromSuperview() }
    guard let route else { return }
    let stages = route.stages.indices.map { stageView(at: $0, route) }
    func line(_ range: Range<Int>) -> UIStackView {
      let row = UIStackView()
      row.axis = .horizontal
      row.alignment = .top
      for i in range {
        row.addArrangedSubview(stages[i])
        if i < range.upperBound - 1 { row.addArrangedSubview(connector()) }
      }
      return row
    }
    switch mode {
    case .line: column.addArrangedSubview(line(0..<stages.count))
    case .twoRows:
      let half = (stages.count + 1) / 2
      column.addArrangedSubview(line(0..<half))
      column.addArrangedSubview(line(half..<stages.count))
    case .vertical: stages.forEach { column.addArrangedSubview($0) }
    }
  }
}

/// The owner's board: the chosen event first (status, title with a compact action, full reason,
/// read-only stages), then a swipeable strip of compact metrics. One glass, nothing glassy inside.
final class InsightBoardView: UIView {
  private let glass = GlassView()
  /// Vertical scroll only when the content (large text) is taller than the board may be.
  private let bodyScroll = UIScrollView()
  let scroller = InsightMetricStrip()
  private let row = UIStackView()
  private(set) var cards: [InsideMetricID: InsightMetricCard] = [:]
  private let titleRow = UIStackView()
  private let statusDot = UIView()
  private let statusLabel = label("", 11, .semibold, InsideStyle.muted)
  private let statusRow = UIStackView()
  private let focusTitle = label("", 16, .semibold, InsideStyle.ink)
  private let focusReason = label("", 13, .regular, InsideStyle.muted)
  private let route = InsightRouteView()
  private var lastRoute: InsideRoute?
  private var lastTone: InsideTone = .neutral
  let actionButton = insideAction("Решить", icon: "arrow.up.right", prominent: true) {}
  let secondaryButton = insideAction("", icon: nil) {}
  var onSelect: ((InsideMetricID) -> Void)?
  var onAction: (() -> Void)?
  var onSecondary: (() -> Void)?

  init() {
    super.init(frame: .zero)
    pin(glass)
    scroller.showsHorizontalScrollIndicator = false
    scroller.alwaysBounceHorizontal = true
    scroller.canCancelContentTouches = true
    scroller.delaysContentTouches = true
    scroller.accessibilityIdentifier = "insight.board"
    row.axis = .horizontal
    row.spacing = 8
    row.alignment = .fill
    row.translatesAutoresizingMaskIntoConstraints = false
    scroller.addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: 10),
      row.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -10),
      row.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
    ])
    for id in InsideMetricID.allCases {
      let card = InsightMetricCard(id)
      card.addAction(UIAction { [weak self] _ in
        UISelectionFeedbackGenerator().selectionChanged()
        self?.onSelect?(id)
      }, for: .touchUpInside)
      cards[id] = card
      row.addArrangedSubview(card)
    }
    // Status eyebrow: a small dot and words in the meaning colour.
    statusDot.layer.cornerRadius = 3
    statusDot.widthAnchor.constraint(equalToConstant: 6).isActive = true
    statusDot.heightAnchor.constraint(equalToConstant: 6).isActive = true
    statusLabel.numberOfLines = 0
    statusLabel.accessibilityIdentifier = "insight.focus.status"
    statusRow.addArrangedSubview(statusDot)
    statusRow.addArrangedSubview(statusLabel)
    statusRow.spacing = 6
    statusRow.alignment = .center
    focusTitle.numberOfLines = 0
    focusTitle.accessibilityIdentifier = "insight.focus.title"
    // The reason is never truncated: reading it matters more than height.
    focusReason.numberOfLines = 0
    focusReason.accessibilityIdentifier = "insight.focus.reason"
    actionButton.accessibilityIdentifier = "insight.action"
    actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
    secondaryButton.accessibilityIdentifier = "insight.secondary"
    secondaryButton.addAction(UIAction { [weak self] _ in self?.onSecondary?() }, for: .touchUpInside)
    for b in [actionButton, secondaryButton] {
      // Visually compact, but the hit target stays at least 44 pt tall.
      b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
      b.configuration?.imagePadding = 6
      b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      b.setContentHuggingPriority(.required, for: .horizontal)
      b.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    focusTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let buttons = stack([secondaryButton, actionButton], axis: .horizontal, spacing: 6)
    titleRow.addArrangedSubview(focusTitle)
    titleRow.addArrangedSubview(buttons)
    titleRow.spacing = 10
    let context = stack([statusRow, titleRow, focusReason, route], spacing: 4)
    context.setCustomSpacing(8, after: focusReason)
    let divider = UIView()
    divider.backgroundColor = InsideStyle.ink.withAlphaComponent(0.08)
    divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    let body = stack([context.inset(4), divider, scroller], spacing: 10)
    bodyScroll.showsVerticalScrollIndicator = false
    bodyScroll.alwaysBounceVertical = false
    glass.contentView.pin(bodyScroll)
    body.translatesAutoresizingMaskIntoConstraints = false
    bodyScroll.addSubview(body)
    // The board hugs its content, just below the content's own compression resistance (750):
    // at the half-screen cap the frame stops growing and the content keeps its height and
    // scrolls, instead of a tie that squeezed the labels (ambiguous content height).
    let hug = bodyScroll.heightAnchor.constraint(equalTo: body.heightAnchor, constant: 20)
    hug.priority = UILayoutPriority(UILayoutPriority.defaultHigh.rawValue - 1)
    for text in [statusLabel, focusTitle, focusReason] {
      text.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.topAnchor, constant: 10),
      body.bottomAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.bottomAnchor, constant: -10),
      // Content width = frame width: only vertical scrolling, no ambiguous content width.
      body.leadingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.leadingAnchor, constant: 10),
      body.trailingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.trailingAnchor, constant: -10),
      bodyScroll.contentLayoutGuide.widthAnchor.constraint(equalTo: bodyScroll.frameLayoutGuide.widthAnchor),
      hug,
    ])
    scroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    // The closure gets the board as a parameter: no capture, the board is not retained.
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (board: Self, _) in board.adaptToTextSize() }
    adaptToTextSize()
  }
  required init?(coder: NSCoder) { fatalError() }

  private var large: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }
  /// Large text: the action takes its own line under the title; stages become a vertical list.
  private func adaptToTextSize() {
    titleRow.axis = large ? .vertical : .horizontal
    titleRow.alignment = large ? .leading : .center
    route.show(lastRoute, tone: lastTone, vertical: large)
  }

  func update(metrics: [InsideMetric], selected: InsideMetricID?) {
    for metric in metrics {
      cards[metric.id]?.update(metric)
      cards[metric.id]?.isSelected = metric.id == selected
    }
  }
  func showContext(
    status: InsideStatus?, title: String, reason: String, route stages: InsideRoute?, action: String?,
    secondary: String?
  ) {
    statusRow.isHidden = status == nil
    statusLabel.text = status?.text.uppercased()
    statusLabel.textColor = status.map { $0.tone == .neutral ? InsideStyle.muted : $0.tone.color } ?? InsideStyle.muted
    statusDot.backgroundColor = status?.tone.color
    focusTitle.text = title
    focusReason.text = reason
    lastRoute = stages
    lastTone = status?.tone ?? .neutral
    route.show(stages, tone: lastTone, vertical: large)
    actionButton.isHidden = action == nil
    actionButton.configuration?.title = action
    actionButton.accessibilityLabel = action.map { "\($0): \(title)" }
    secondaryButton.isHidden = secondary == nil
    secondaryButton.configuration?.title = secondary
  }
  func reveal(_ id: InsideMetricID, animated: Bool) {
    guard let card = cards[id] else { return }
    scroller.layoutIfNeeded()
    let rect = card.convert(card.bounds, to: scroller)
    scroller.scrollRectToVisible(rect.insetBy(dx: -12, dy: 0), animated: animated)
  }
}
