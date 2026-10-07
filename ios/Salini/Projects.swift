import UIKit

/// The current project: real catalogue executions, quantities and colours, stored on the device.
final class ProjectsController: ScrollController {
  private var store: ProjectStore { .shared }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = DemoStore.shared.role == .atelier ? "Проекты" : "Проект"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "ellipsis.circle"), menu: projectMenu())
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .demoChanged, object: nil)
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    render()
  }
  @objc private func changed() {
    guard viewIfLoaded?.window != nil else { return }
    render()
  }
  private func projectMenu() -> UIMenu {
    UIMenu(children: [
      UIDeferredMenuElement.uncached { [weak self] done in
        guard let self else { return done([]) }
        let switches = self.store.projects.map { p in
          UIAction(title: p.name, subtitle: "\(p.lines.count) поз.", state: p.id == self.store.currentId ? .on : .off) {
            [weak self] _ in
            self?.store.currentId = p.id
            self?.render()
          }
        }
        done([
          UIMenu(title: "Проекты", options: .displayInline, children: switches),
          UIAction(title: "Переименовать", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.edit() },
          UIAction(title: "Новый проект", image: UIImage(systemName: "plus")) { [weak self] _ in self?.create() },
          UIAction(title: "Удалить проект", image: UIImage(systemName: "trash"), attributes: .destructive) {
            [weak self] _ in self?.confirmDelete()
          },
        ])
      }
    ])
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let project = store.current
    let header = stack(
      [
        eyebrow(
          DemoStore.shared.role == .atelier
            ? (project.client.isEmpty ? "СПЕЦИФИКАЦИЯ ОБЪЕКТА" : "СПЕЦИФИКАЦИЯ · ДЛЯ: \(project.client.uppercased())")
            : (project.client.isEmpty ? "ТЕКУЩИЙ ПРОЕКТ" : "ДЛЯ: \(project.client.uppercased())")),
        label(project.name, 37, .regular, serif: true),
      ], spacing: 12)
    add(header)
    if project.lines.isEmpty {
      let img = photo("interior", height: 300)
      img.rounded()
      add(img)
      add(
        stack(
          [
            label("Начните с изделия.", 27, .regular, serif: true),
            label("Выберите форму и исполнение в каталоге — они появятся здесь со спецификацией.", 15, .regular, Palette.muted),
            ActionButton("Помочь выбрать", icon: "checklist", prominent: true) { [weak self] in
              self?.navigationController?.pushViewController(ChooseController(), animated: true)
            },
            ActionButton("Открыть каталог", icon: "square.grid.2x2") { [weak self] in
              self?.tabBarController?.selectedIndex = MainTabs.catalogTabIndex
            },
          ], spacing: 16))
      return
    }
    for line in project.lines { add(card(for: line), inset: 20) }
    let unpriced = project.unpricedLines
    var totals: [UIView] = [
      eyebrow(project.isTotalComplete ? "СТОИМОСТЬ ПО ПУБЛИЧНЫМ ЦЕНАМ" : "БАЗОВАЯ СУММА ПО ПУБЛИЧНЫМ ЦЕНАМ"),
      label(rubles(project.knownTotal), 36, .medium),
    ]
    if unpriced > 0 {
      totals.append(
        label("+ \(unpriced) \(plural(unpriced, "позиция", "позиции", "позиций")) с ценой по запросу (цвет RAL, нет цены или исполнение уточняется). Итог неполный.", 14, .medium, Palette.clay))
    }
    totals.append(
      label("Цены сайта Salini на \(Catalog.shared.snapshotText). Доставка, монтаж и индивидуальные условия — отдельно.", 13, .regular, Palette.muted))
    totals.append(
      ActionButton("Персональное предложение PDF", icon: "doc.richtext", prominent: true) { [weak self] in
        self?.export()
      })
    totals.append(
      label("Главное изделие первой строки задаёт обложку и цветовые этюды. Сменить — меню «⋯» у позиции.", 12, .regular, Palette.muted))
    add(stack(totals, spacing: 12))
  }
  private func card(for line: ProjectLine) -> UIView {
    let pic = UIImageView()
    pic.contentMode = .scaleAspectFill
    pic.backgroundColor = UIColor(hex: 0xECEDEF)
    pic.rounded(16)
    pic.widthAnchor.constraint(equalToConstant: 92).isActive = true
    pic.height(108)
    if let p = line.product { CatalogImages.shared.image(for: p, maxPixel: 300) { pic.image = $0 } }
    let name = line.product?.name ?? "Изделие недоступно в каталоге"
    let v = line.variant
    let detail = [
      v?.title ?? "исполнение требует уточнения", line.colour.title,
      line.sku.map { "арт. \($0)" } ?? (line.isCustomColour ? "артикул цвета уточняется" : nil),
    ].compactMap { $0 }.joined(separator: " · ")
    let total = line.priceText
    let texts = stack(
      [label(name, 23, .regular, serif: true), label(detail, 12, .regular, Palette.muted), label("\(line.quantity) шт. · \(total)", 15, .medium)],
      spacing: 6)
    let top = stack([pic, texts], axis: .horizontal, spacing: 16)
    top.alignment = .center
    let stepper = UIStepper()
    stepper.minimumValue = 0
    stepper.maximumValue = 99
    stepper.value = Double(line.quantity)
    stepper.accessibilityLabel = "Количество \(name)"
    stepper.addAction(UIAction { [weak stepper] _ in
      var l = line
      l.quantity = Int(stepper?.value ?? 1)
      ProjectStore.shared.update(l)
    }, for: .valueChanged)
    let open = ActionButton("Изделие", icon: "arrow.up.right") { [weak self] in
      guard let p = line.product else { return }
      self?.navigationController?.pushViewController(CatalogProductController(p, variantKey: line.variantKey), animated: true)
    }
    var more = UIButton.Configuration.plain()
    more.image = UIImage(systemName: "ellipsis.circle")
    more.baseForegroundColor = Palette.ink
    let menu = UIButton(configuration: more)
    menu.showsMenuAsPrimaryAction = true
    menu.accessibilityLabel = "Действия: \(name)"
    var actions: [UIMenuElement] = []
    if line.variant?.allowsRAL == true {
      actions.append(UIMenu(title: "Цвет: \(line.colour.longTitle)", image: UIImage(systemName: "paintpalette"), children: [
        colourMenu(selected: line.colour) { c in
          var l = line
          l.colour = c
          ProjectStore.shared.update(l)
        }
      ]))
    }
    if store.current.lines.first?.id != line.id {
      actions.append(UIAction(title: "Сделать главным в предложении", image: UIImage(systemName: "star")) { _ in
        ProjectStore.shared.makeMain(line.id)
      })
    }
    actions.append(UIAction(title: "Удалить позицию", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
      ProjectStore.shared.remove(line.id)
    })
    menu.menu = UIMenu(children: actions)
    let row = stack([open, UIView(), menu, stepper], axis: .horizontal, spacing: 12)
    row.alignment = .center
    let card = stack([top, row], spacing: 16).inset(18)
    card.backgroundColor = .white
    card.rounded()
    card.accessibilityElements = [texts, open, menu, stepper]
    return card
  }
  private func edit() {
    let a = UIAlertController(title: "Проект", message: "Название и клиент для спецификации", preferredStyle: .alert)
    a.addTextField { $0.text = self.store.current.name; $0.placeholder = "Название проекта" }
    a.addTextField { $0.text = self.store.current.client; $0.placeholder = "Клиент (необязательно)" }
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak a] _ in
      guard let self else { return }
      var p = self.store.current
      let name = a?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !name.isEmpty { p.name = name }
      p.client = a?.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.store.current = p
      self.render()
    })
    present(a, animated: true)
  }
  private func create() {
    let a = UIAlertController(title: "Новый проект", message: nil, preferredStyle: .alert)
    a.addTextField { $0.placeholder = "Название проекта" }
    a.addTextField { $0.placeholder = "Клиент (необязательно)" }
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(UIAlertAction(title: "Создать", style: .default) { [weak self, weak a] _ in
      let name = a?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self?.store.newProject(name: name.isEmpty ? "Новый проект" : name, client: a?.textFields?[1].text ?? "")
      self?.render()
    })
    present(a, animated: true)
  }
  private func confirmDelete() {
    let a = UIAlertController(title: "Удалить «\(store.current.name)»?", message: "Проект хранится только на этом устройстве.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
      guard let self else { return }
      self.store.delete(self.store.current.id)
      self.render()
    })
    present(a, animated: true)
  }
  /// Personal proposal: generated on the device with progress, previewed, then shared.
  private func export() {
    present(ProposalController(project: store.current, role: DemoStore.shared.role), animated: true)
  }
}
