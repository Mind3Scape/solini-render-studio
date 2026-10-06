import UIKit

final class ProfileController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Профиль"
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    content.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let role = DemoStore.shared.role
    add(
      stack(
        [
          eyebrow("SALINI"), label(role.title, 40, .regular, serif: true),
          label(role.detail, 16, .regular, Palette.muted),
          ActionButton("Режимы на главной", icon: "arrow.left.arrow.right") { [weak self] in
            self?.tabBarController?.selectedIndex = 0
          },
        ], spacing: 15))
    let owner = UIView()
    owner.backgroundColor = Palette.ink
    owner.rounded(28)
    let image = photo("production", height: 175)
    image.alpha = 0.8
    let inside = ActionButton("Открыть Salini Inside", icon: "arrow.up.right") { [weak self] in
      let vc = OwnerController()
      vc.hidesBottomBarWhenPushed = true
      self?.navigationController?.pushViewController(vc, animated: true)
    }
    inside.accessibilityIdentifier = "owner.open"
    inside.configuration?.baseForegroundColor = .white
    let copy = stack(
      [
        eyebrow("ДЕМО ДЛЯ ВЛАДЕЛЬЦА", color: Palette.lime),
        label("Ваш бизнес.\nВ одном взгляде.", 32, .regular, .white, serif: true),
        label(
          "От первой формы до отгрузки.\nУвидьте, как живёт производство.", 15, .regular,
          .white.withAlphaComponent(0.75)), inside,
      ], spacing: 17
    ).inset(24)
    owner.pin(stack([image, copy], spacing: 0))
    add(owner)
    add(
      stack(
        [
          eyebrow("О ПРИЛОЖЕНИИ"), label("Salini / Experience 01", 23, .regular, serif: true),
          label(
            "Нативная концепция для iOS 27. Изображения и изделия — Salini. Проекты хранятся на этом устройстве. Производство и события в Salini Inside — интерактивная демонстрация.",
            14, .regular, Palette.muted),
          ActionButton("Источники и данные", icon: "info.circle") { [weak self] in
            self?.sheet(AboutController())
          },
        ], spacing: 15))
  }
}
final class AboutController: ScrollController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "О демонстрации"
    add(
      stack(
        [
          eyebrow("SALINI EXPERIENCE"),
          label("Реальный бренд.\nНовый опыт.", 34, .regular, serif: true),
          label("Каталог и изображения", 20, .semibold),
          label(
            "Официальный сайт salini-srl.com, снимок от 6 октября 2026. В прототипе — четыре изделия из кураторской подборки. Цены не обновляются из 1С.",
            15, .regular, Palette.muted), line(), label("Salini Inside", 20, .semibold),
          label(
            "Модель процесса: литьё → обработка → контроль → упаковка → склад → отгрузка. Планировка, люди, заказы, показатели и камеры — демонстрационные. Нажатия меняют только состояние демо на устройстве.",
            15, .regular, Palette.muted), line(), label("Ваши проекты", 20, .semibold),
          label(
            "Избранное, состав и название проекта сохраняются локально. Входы показывают три продуктовых сценария и не авторизуют реальный аккаунт.",
            15, .regular, Palette.muted),
        ], spacing: 18))
  }
}
