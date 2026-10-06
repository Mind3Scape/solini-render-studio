import SafariServices
import UIKit

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
