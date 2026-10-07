import UIKit

/// One business metric on the board. A whole-card tap zone; updated in place, so selection and
/// scroll position survive every revision of the numbers.
final class InsightMetricCard: UIControl {
  let metricID: InsideMetricID
  private let titleLabel = label("", 11, .semibold, InsideStyle.muted)
  private let valueLabel = UILabel()
  private let detailLabel = label("", 11, .regular, InsideStyle.muted)
  private let dot = UIView()
  init(_ id: InsideMetricID) {
    metricID = id
    super.init(frame: .zero)
    layer.cornerRadius = 18
    layer.cornerCurve = .continuous
    valueLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
      for: .monospacedDigitSystemFont(ofSize: 22, weight: .regular), maximumPointSize: 30)
    valueLabel.adjustsFontForContentSizeCategory = true
    valueLabel.textColor = InsideStyle.ink
    valueLabel.adjustsFontSizeToFitWidth = true
    valueLabel.minimumScaleFactor = 0.7
    detailLabel.numberOfLines = 2
    dot.backgroundColor = InsideStyle.amber
    dot.layer.cornerRadius = 4
    dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
    let spacer = UIView()
    spacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    let top = stack([titleLabel, spacer, dot], axis: .horizontal, spacing: 6)
    top.alignment = .center
    let content = stack([top, valueLabel, detailLabel], spacing: 4)
    content.isUserInteractionEnabled = false
    pin(content, inset: 12)
    widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
    widthAnchor.constraint(lessThanOrEqualToConstant: 176).isActive = true
    heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
    isAccessibilityElement = true
    accessibilityIdentifier = "insight.metric.\(id.rawValue)"
    accessibilityHint = "Показать на карте"
    updateSelection()
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isSelected: Bool { didSet { updateSelection() } }
  override var isHighlighted: Bool {
    didSet { alpha = isHighlighted ? 0.75 : 1 }
  }
  func update(_ metric: InsideMetric) {
    titleLabel.text = metric.title.uppercased()
    valueLabel.text = metric.value
    detailLabel.text = metric.detail
    dot.isHidden = !metric.attention
    accessibilityLabel = "\(metric.title): \(metric.value). \(metric.detail)"
    accessibilityValue = metric.attention ? "Требует внимания" : nil
  }
  private func updateSelection() {
    // Selected: an opaque card with a hairline, not a heavy frame.
    backgroundColor = isSelected ? UIColor.white : UIColor.white.withAlphaComponent(0.42)
    layer.borderWidth = isSelected ? 1 : 0
    layer.borderColor = InsideStyle.ink.withAlphaComponent(0.28).cgColor
    accessibilityTraits = isSelected ? [.button, .selected] : .button
  }
}

/// Horizontal metric strip: a drag that starts on a card scrolls the strip (the card's touch is
/// cancelled) — UIScrollView keeps UIControl touches by default.
final class InsightMetricStrip: UIScrollView {
  override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// The owner's board: swipe through metrics (camera stays), tap one to look at its live
/// process, read the reason, act with an explicit button.
final class InsightBoardView: UIView {
  private let glass = GlassView()
  /// Vertical scroll only when the content (large text) is taller than the board may be.
  private let bodyScroll = UIScrollView()
  let scroller = InsightMetricStrip()
  private let row = UIStackView()
  private(set) var cards: [InsideMetricID: InsightMetricCard] = [:]
  private let titleRow = UIStackView()
  private let focusTitle = label("", 15, .semibold, InsideStyle.ink)
  private let focusReason = label("", 13, .regular, InsideStyle.muted)
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
      row.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: 12),
      row.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -12),
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
    focusTitle.numberOfLines = 0
    focusTitle.accessibilityIdentifier = "insight.focus.title"
    // The reason may take two (or more, with large text) lines: reading it matters more than height.
    focusReason.numberOfLines = 0
    focusReason.accessibilityIdentifier = "insight.focus.reason"
    actionButton.accessibilityIdentifier = "insight.action"
    actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
    secondaryButton.accessibilityIdentifier = "insight.secondary"
    secondaryButton.addAction(UIAction { [weak self] _ in self?.onSecondary?() }, for: .touchUpInside)
    // Title with a compact action on its right; the reason below takes the full width.
    for b in [actionButton, secondaryButton] {
      b.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
      b.configuration?.imagePadding = 6
      b.setContentHuggingPriority(.required, for: .horizontal)
      b.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    focusTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let buttons = stack([secondaryButton, actionButton], axis: .horizontal, spacing: 6)
    titleRow.addArrangedSubview(focusTitle)
    titleRow.addArrangedSubview(buttons)
    titleRow.spacing = 10
    let context = stack([titleRow, focusReason], spacing: 4)
    let body = stack([scroller, context.inset(4)], spacing: 10)
    bodyScroll.showsVerticalScrollIndicator = false
    bodyScroll.alwaysBounceVertical = false
    glass.contentView.pin(bodyScroll)
    body.translatesAutoresizingMaskIntoConstraints = false
    bodyScroll.addSubview(body)
    let hug = bodyScroll.heightAnchor.constraint(equalTo: body.heightAnchor, constant: 20)
    hug.priority = .defaultHigh
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.topAnchor, constant: 10),
      body.bottomAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.bottomAnchor, constant: -10),
      // Content width = frame width: only vertical scrolling, no ambiguous content width.
      body.leadingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.leadingAnchor, constant: 10),
      body.trailingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.trailingAnchor, constant: -10),
      bodyScroll.contentLayoutGuide.widthAnchor.constraint(equalTo: bodyScroll.frameLayoutGuide.widthAnchor),
      hug,
    ])
    scroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
    // The closure gets the board as a parameter: no capture, the board is not retained.
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (board: Self, _) in board.adaptToTextSize() }
    adaptToTextSize()
  }
  required init?(coder: NSCoder) { fatalError() }

  /// Large text: the action leaves the title row and takes its own line under the title.
  private func adaptToTextSize() {
    let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    titleRow.axis = large ? .vertical : .horizontal
    titleRow.alignment = large ? .leading : .center
  }

  func update(metrics: [InsideMetric], selected: InsideMetricID?) {
    for metric in metrics {
      cards[metric.id]?.update(metric)
      cards[metric.id]?.isSelected = metric.id == selected
    }
  }
  func showContext(title: String, reason: String, action: String?, secondary: String?) {
    focusTitle.text = title
    focusReason.text = reason
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
