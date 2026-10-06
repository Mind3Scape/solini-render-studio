import UIKit

final class ProjectsController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Мои проекты"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "square.and.pencil"),
      primaryAction: UIAction { [weak self] _ in self?.rename() })
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    render()
  }
  private func render() {
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    add(
      stack(
        [
          eyebrow("ВАШЕ ЛИЧНОЕ ПРОСТРАНСТВО"),
          label(DemoStore.shared.projectName, 37, .regular, serif: true),
          label(
            "Идеи обретают форму. Сохраняйте изделия и возвращайтесь к деталям.", 15, .regular,
            Palette.muted),
        ], spacing: 14))
    if DemoStore.shared.items.isEmpty {
      let img = photo("interior", height: 300)
      img.rounded()
      add(img)
      add(
        stack(
          [
            label("Первый штрих — за вами.", 27, .regular, serif: true),
            ActionButton("Выбрать изделие", icon: "plus", prominent: true) { [weak self] in
              self?.tabBarController?.selectedIndex = 1
            },
          ], spacing: 18))
      return
    }
    for item in DemoStore.shared.items {
      guard let p = item.product else { continue }
      let pic = photo(p.image)
      pic.widthAnchor.constraint(equalToConstant: 90).isActive = true
      pic.height(105)
      pic.rounded(15)
      let texts = stack(
        [
          label(p.name, 25, .regular, serif: true),
          label(
            item.stone ? "S-Stone · матовый" : "Базовое исполнение", 12, .regular, Palette.muted),
          label("\(item.quantity) шт. · \(rubles(item.total))", 14, .medium),
        ], spacing: 6)
      let top = stack([pic, texts], axis: .horizontal, spacing: 17)
      top.alignment = .center
      let remove = ActionButton("Убрать", icon: "minus") { [weak self] in
        DemoStore.shared.items.removeAll { $0.id == item.id }
        self?.render()
      }
      let more = ActionButton("Ещё одно", icon: "plus") { [weak self] in
        DemoStore.shared.add(p, stone: item.stone)
        self?.render()
      }
      let row = stack([remove, more], axis: .horizontal)
      row.distribution = .fillEqually
      let card = stack([top, row], spacing: 18).inset(20)
      card.backgroundColor = .white
      card.rounded()
      add(card, inset: 24)
    }
    add(
      stack(
        [
          eyebrow("СТОИМОСТЬ ПОДБОРКИ"), label(rubles(DemoStore.shared.total), 36, .medium),
          label(
            "Ориентир по публичным ценам. Доставка и индивидуальные условия рассчитываются отдельно.",
            13, .regular, Palette.muted),
          ActionButton("Поделиться спецификацией", icon: "square.and.arrow.up", prominent: true) {
            [weak self] in self?.export()
          },
        ], spacing: 15))
  }
  private func rename() {
    let a = UIAlertController(title: "Название проекта", message: nil, preferredStyle: .alert)
    a.addTextField { $0.text = DemoStore.shared.projectName }
    a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    a.addAction(
      UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak a] _ in
        let name = a?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
          DemoStore.shared.projectName = name
          self?.render()
        }
      })
    present(a, animated: true)
  }
  private func export() {
    // Rasterize the tinted source before entering a PDF context; PDF blend modes
    // otherwise turn UIImage's template tint into a solid rectangle.
    let logoSize = CGSize(width: 276, height: 112)
    let logo = UIGraphicsImageRenderer(size: logoSize).image { _ in
      UIImage(named: "salini-logo.png")?
        .withTintColor(Palette.ink, renderingMode: .alwaysOriginal)
        .draw(in: CGRect(origin: .zero, size: logoSize))
    }
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData {
      ctx in
      var y: CGFloat = 60
      func newPage() {
        ctx.beginPage()
        Palette.paper.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 595, height: 842))
        y = 60
      }
      func text(_ t: String, _ size: CGFloat, _ color: UIColor = Palette.ink) {
        let a: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: size), .foregroundColor: color,
        ]
        let rect = CGRect(x: 44, y: y, width: 507, height: 120)
        let h = (t as NSString).boundingRect(
          with: rect.size, options: .usesLineFragmentOrigin, attributes: a, context: nil
        ).height
        (t as NSString).draw(in: CGRect(x: 44, y: y, width: 507, height: h + 3), withAttributes: a)
        y += h + 18
      }
      newPage()
      logo.draw(in: CGRect(x: 44, y: y, width: 138, height: 56))
      y += 84
      text(DemoStore.shared.projectName, 24)
      text("Спецификация · демонстрационная подборка", 12, Palette.muted)
      for item in DemoStore.shared.items {
        guard let p = item.product else { continue }
        if y > 650 { newPage() }
        text("\(p.name)  /  \(p.sku(stone:item.stone))", 19)
        text(
          "\(p.dimensions) · \(item.stone ? "S-Stone" : "базовое исполнение")\n\(item.quantity) шт.  ·  \(rubles(item.total))",
          13)
      }
      if y > 650 { newPage() }
      text("Итого: \(rubles(DemoStore.shared.total))", 24)
      text(
        "Цены из публичного каталога на 06.10.2026. Это демонстрация, не подтверждённый заказ. Доставка и индивидуальные условия уточняются отдельно.",
        11, Palette.muted)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Salini-Specification.pdf")
    do {
      try data.write(to: url)
      let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      share.popoverPresentationController?.sourceView = view
      share.popoverPresentationController?.sourceRect = CGRect(
        x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
      present(share, animated: true)
    } catch { message("Не удалось создать файл", error.localizedDescription) }
  }
}
