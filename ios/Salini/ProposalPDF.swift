import ImageIO
import QuickLook
import SceneKit
import UIKit

// MARK: - Official texts

/// Short advantages quoted from the official Salini presentation «Новинки 2026».
/// Families without published advantages get only facts from their card — nothing is composed.
enum ProposalTexts {
  static let source = "Преимущества — из официальной презентации Salini «Новинки 2026»."
  /// Properties of the chosen material, phrased from the Salini FAQ («О материалах»): only what
  /// describes the surface and structure — no care or durability promises.
  static func material(_ f: StudioFinish) -> [String] {
    switch f {
    case .stoneMatte:
      return ["Бархатистая матовая поверхность S-Stone", "Монолитная структура по всей толщине: цвет в массе"]
    case .senseGloss: return ["Высокоглянцевое покрытие Gelcoat 0,8 мм поверх мраморной основы S-Sense"]
    case .senseMatte: return ["Матовое покрытие Gelcoat 0,8 мм поверх мраморной основы S-Sense"]
    }
  }
  /// «Для вашего проекта»: up to three facts drawn only from the executions actually chosen.
  static func projectFacts(_ lines: [ProjectLine]) -> [String] {
    var out: [String] = []
    let finishes = lines.compactMap(\.variant).compactMap { StudioFinish(material: $0.material, finish: $0.finish) }
      .reduce(into: [StudioFinish]()) { if !$0.contains($1) { $0.append($1) } }
    for f in finishes {
      switch f {
      case .stoneMatte:
        out.append("S-Stone — матовый Solid Surface: однородный материал и цвет на всю толщину, без покрытия")
      case .senseGloss: out.append("S-Sense глянцевый — мраморная крошка и смола под защитным Gelcoat 0,8 мм")
      case .senseMatte: out.append("S-Sense матовый — мраморная крошка и смола под матовым Gelcoat 0,8 мм")
      }
    }
    let colours = lines.compactMap(\.colour.ral).reduce(into: [RALColour]()) { if !$0.contains($1) { $0.append($1) } }
    if !colours.isEmpty {
      let names = colours.prefix(2).map { "RAL \($0.code) · \($0.name)" }.joined(separator: ", ")
      let more = colours.count > 2 ? " и др." : ""
      out.append("\(names)\(more) — \(colours.count > 1 ? "цвета" : "цвет") из палитры Salini RAL Classic, изготавливается по запросу")
    }
    // Non-mineral items: only their own category and its warranty.
    let others = lines.filter { $0.variant != nil && $0.variant?.allowsRAL == false }.compactMap(\.product)
    for category in others.map(\.category).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
      if let p = others.first(where: { $0.category == category }) {
        out.append("\(category): гарантия \(ProposalTexts.warranty(for: p))")
      }
    }
    return Array(out.prefix(3))
  }
  /// Family advantages apply only to the category they were written for (the bath texts
  /// must not reach an Opera or Cartella washbasin).
  static let familyCategory: [String: String] = [
    "АРИЯ": "Ванны", "ОПЕРА": "Ванны", "ОПЕРЕТТА": "Ванны", "КАРТЕЛЛА": "Ванны", "ПЕРЛА": "Ванны",
    "АРИОЗА": "Ванны", "ВЕЛАСКА": "Мебель",
  ]
  static let families: [String: [String]] = [
    "АРИЯ": [
      "Установлена на скрытом подиуме",
      "Встроенная светодиодная подсветка под чашей вдоль её внутреннего края",
      "Совместима с голосовым помощником Алиса и платформой «Умный дом»",
      "Просторная чаша, продуманные изгибы и наклон бортов",
    ],
    "ОПЕРА": [
      "Для классических и неоклассических интерьеров",
      "Акцентированные архитектурные детали европейской классики",
      "Обтекаемые, массивные борта и просторная чаша",
      "Продуманная эргономика",
    ],
    "ОПЕРЕТТА": [
      "Современная классика для традиционных и эклектичных проектов",
      "Утончённый пьедестал визуально «приподнимает» ванну",
      "Деликатный кант по периметру, плавный уклон спинки",
      "Глубокая удлинённая чаша",
    ],
    "КАРТЕЛЛА": [
      "Многогранная форма: прямые линии и мягкие скругления",
      "Игра света и теней за счёт скульптурной асимметрии",
      "Возможность установки смесителя в борт",
      "Раковины-компаньоны: угловая, пристенная и накладная",
    ],
    "ПЕРЛА": [
      "Скруглённый внешний край борта с радиусом 20 мм",
      "Идеально ровные прямые борта",
      "Повышенная безопасность за счёт скруглённого борта",
      "Любой оттенок из палитры RAL Classic",
    ],
    "АРИОЗА": [
      "Премиальная встраиваемая ванна с большой глубокой чашей для двоих",
      "Широкие бортики, в том числе для монтажа смесителя",
      "Удобная обтекаемая спинка",
      "Совместима с голосовым помощником Алиса и платформой «Умный дом»",
    ],
    "ВЕЛАСКА": [
      "Универсальное решение для ванных и жилых комнат",
      "100% МДФ Egger",
      "Скрытые удобные ручки под углом 45°",
      "Обтекаемые углы для комфорта и эргономики",
    ],
  ]
  static func family(of product: CatalogProduct) -> String {
    product.siteName.split(separator: " ").first.map { String($0).uppercased() } ?? product.siteName.uppercased()
  }
  static func advantages(for product: CatalogProduct) -> [String] {
    let f = family(of: product)
    guard familyCategory[f] == product.category else { return [] }
    return families[f] ?? []
  }
  /// Warranty by product category (Salini FAQ and site texts); unknown categories are not guessed.
  static func warranty(for product: CatalogProduct) -> String {
    if product.url.contains("salini-essentials") { return "5 лет · линейка Salini Essentials" }
    switch product.category {
    case "Ванны", "Раковины", "Душевые поддоны", "Столешницы", "Унитазы и биде":
      return "10 лет при правильной установке и эксплуатации"
    case "Мебель", "Зеркала": return "2 года"
    case "Комплектующие": return "1 год"
    default: return "условия уточняет менеджер"
    }
  }
  static let contacts = ["salini-srl.com", "info@salini-srl.com", "8 (495) 249-33-49"]
}

// MARK: - Composer

/// Builds the personal proposal PDF from a project snapshot. Pure value input, no network;
/// safe to run off the main thread. Texts come only from catalogue data and official sources.
final class ProposalComposer {
  struct Study {
    let title: String
    let image: UIImage?
    let colour: UIColor
  }
  let project: SaliniProject
  let role: Audience
  let date: Date
  /// Off-screen SceneKit renders of the lead item's own USDZ; tests can switch them off.
  var rendersStudies = true
  private(set) var pageCount = 0

  init(project: SaliniProject, role: Audience, date: Date = Date()) {
    self.project = project
    self.role = role
    self.date = date
  }

  /// Every saved line, including ones whose product or execution no longer resolves: they stay
  /// in the specification with a clarification status, so the totals and the table agree.
  var lines: [ProjectLine] { project.lines }
  /// Lead item: the project's first resolvable line (the user can make any line the lead).
  var lead: ProjectLine? { lines.first { $0.product != nil } }
  /// Colour studies are offered only for a resolved, paintable execution with its own model.
  var leadPaintable: Bool { lead?.variant?.allowsRAL ?? false }
  var leadForm: StudioForm? {
    guard leadPaintable, let p = lead?.product else { return nil }
    return StudioForm.all.first { $0.product.id == p.id }
  }
  var leadFinish: StudioFinish? {
    guard let v = lead?.variant else { return nil }
    return StudioFinish(material: v.material, finish: v.finish)
  }
  var fileName: String {
    let safe = project.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
    return "Salini — \(safe.isEmpty ? "предложение" : safe).pdf"
  }

  /// Colours for the studies: the chosen one, base white and calm RAL Classic references.
  func studyColours() -> [(String, UIColor)] {
    var out: [(String, LineColour)] = []
    if let c = lead?.colour { out.append(("Выбранный · \(c.longTitle)", c)) }
    for c in [LineColour.standard, .ral("7044"), .ral("7016"), .ral("1015")] where !out.contains(where: { $0.1 == c }) {
      out.append((c.longTitle, c))
    }
    return out.prefix(4).map { ($0.0, $0.1.displayColour) }
  }

  /// Light neutral ground of the studies on the page; renders are matted onto it exactly.
  static let studyPaper = UIColor(red: 0.93, green: 0.925, blue: 0.91, alpha: 1)

  /// One prepared off-screen studio for print: print lighting and tone mapping,
  /// side key light, renderer prepared and warmed up so image-based lighting is in place.
  final class PrintStudio {
    let studio: StudioScene
    let renderer: SCNRenderer
    let finish: StudioFinish
    let size: CGSize
    init?(form: StudioForm, finish: StudioFinish, lighting: StudioScene.PrintLighting = .balanced,
          size: CGSize = CGSize(width: 1200, height: 720)) {
      guard let device = MTLCreateSystemDefaultDevice(),
        // Print keeps the accepted legacy look explicitly: its balance, rim/bounce lights and the
        // black/white difference matte were tuned on it. The live studio uses `.physical`.
        let studio = StudioScene(modelURL: form.modelURL, finish: finish, look: .legacy)
      else { return nil }
      studio.usePrintBackdrop(lighting)
      studio.aspect = size.width / size.height
      studio.frame(.form, animated: false)
      // Key light from the side: a soft gradient across the wall and into the bowl.
      studio.setLight(0.3)
      let renderer = SCNRenderer(device: device, options: nil)
      renderer.scene = studio.scene
      renderer.pointOfView = studio.camera
      renderer.prepare(studio.scene, shouldAbortBlock: nil)
      _ = renderer.snapshot(atTime: 0, with: CGSize(width: 96, height: 64), antialiasingMode: .none)
      self.studio = studio
      self.renderer = renderer
      self.finish = finish
      self.size = size
    }
    /// The study composited onto the exact page ground.
    ///
    /// Platform-independent difference matte: the same HDR frame is rendered over a black and a
    /// white background. Where the two agree the pixel is the product; where they differ by the
    /// full background difference it is empty; in between (edges, soft shadow) it is partial.
    /// Both background values are measured in the frames, not assumed, so the tone-mapped
    /// background never reaches the page — the ground is exactly `studyPaper`.
    func render(_ colour: UIColor) -> UIImage {
      studio.apply(finish: finish, colour: colour)
      let big = CGSize(width: size.width * 2, height: size.height * 2)
      studio.scene.background.contents = UIColor.black
      let overBlack = renderer.snapshot(atTime: 0, with: big, antialiasingMode: .none)
      studio.scene.background.contents = UIColor.white
      let overWhite = renderer.snapshot(atTime: 0, with: big, antialiasingMode: .none)
      let composed = Self.matte(overBlack, overWhite, onto: ProposalComposer.studyPaper) ?? overBlack
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        ProposalComposer.studyPaper.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        ctx.cgContext.interpolationQuality = .high
        composed.draw(in: CGRect(origin: .zero, size: size))
      }
    }
    static func rgba(_ image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
      guard let cg = image.cgImage else { return nil }
      let w = cg.width, h = cg.height
      var pixels = [UInt8](repeating: 0, count: w * h * 4)
      guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
      return (pixels, w, h)
    }
    static func matte(_ black: UIImage, _ white: UIImage, onto paper: UIColor) -> UIImage? {
      guard let a = rgba(black), let b = rgba(white), a.width == b.width, a.height == b.height else { return nil }
      var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0, pa: CGFloat = 0
      paper.getRed(&pr, green: &pg, blue: &pb, alpha: &pa)
      let p = [Float(pr * 255), Float(pg * 255), Float(pb * 255)]
      // Background as actually rendered (tone mapping included), from the top-left corner.
      let bgA = (0..<3).map { Float(a.pixels[$0]) }
      let bgB = (0..<3).map { Float(b.pixels[$0]) }
      let span = (0..<3).map { bgB[$0] - bgA[$0] }.reduce(0, +) / 3
      guard span > 40 else { return nil }
      var out = [UInt8](repeating: 255, count: a.pixels.count)
      var i = 0
      while i < a.pixels.count {
        var diff: Float = 0
        for c in 0..<3 { diff += Float(b.pixels[i + c]) - Float(a.pixels[i + c]) }
        let empty = min(1, max(0, diff / 3 / span))  // 1 − alpha
        for c in 0..<3 {
          // over-black = product·α + bgA·(1−α)  ⇒  on paper = over-black + (paper − bgA)·(1−α)
          let v = Float(a.pixels[i + c]) + (p[c] - bgA[c]) * empty
          out[i + c] = UInt8(min(255, max(0, v.rounded())))
        }
        out[i + 3] = 255
        i += 4
      }
      guard let provider = CGDataProvider(data: Data(out) as CFData),
        let cg = CGImage(width: a.width, height: a.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: a.width * 4,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
      else { return nil }
      return UIImage(cgImage: cg)
    }
  }

  /// Renders studies only for the lead item's own model; nil when it has no model.
  func makeStudies(progress: (Double) -> Void, isCancelled: () -> Bool) -> [Study]? {
    // The saved execution decides the surface; nothing is guessed for an unresolved one.
    guard let form = leadForm, let finish = leadFinish, rendersStudies,
      let studio = PrintStudio(form: form, finish: finish)
    else { return nil }
    let colours = studyColours()
    var studies: [Study] = []
    for (i, (title, colour)) in colours.enumerated() {
      if isCancelled() { return nil }
      studies.append(Study(title: title, image: studio.render(colour), colour: colour))
      progress(Double(i + 1) / Double(colours.count))
    }
    return studies
  }

  /// nil for an empty project: there is nothing to propose.
  func render(progress: @escaping (Double) -> Void = { _ in }, isCancelled: @escaping () -> Bool = { false }) -> Data? {
    guard !lines.isEmpty else { return nil }
    let studies = makeStudies(progress: { progress($0 * 0.6) }, isCancelled: isCancelled)
    if isCancelled() { return nil }
    let canvas = ProposalCanvas()
    let data = UIGraphicsPDFRenderer(bounds: ProposalCanvas.page, format: format()).pdfData { ctx in
      canvas.ctx = ctx
      canvas.footer = project.name
      cover(canvas)
      progress(0.7)
      solution(canvas)
      progress(0.82)
      specification(canvas)
      progress(0.9)
      colourStory(canvas, studies)
      progress(1)
    }
    pageCount = canvas.pageNumber
    return isCancelled() ? nil : data
  }

  private func format() -> UIGraphicsPDFRendererFormat {
    let f = UIGraphicsPDFRendererFormat()
    f.documentInfo = [
      kCGPDFContextTitle as String: "Salini — \(project.name)",
      kCGPDFContextCreator as String: "Salini Experience",
    ]
    return f
  }

  private var dateText: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: date)
  }

  // MARK: Pages
  //
  // Adaptive: cover → «Ваше решение» (photo-led blocks, flows to more pages for big orders)
  // → specification → colour story with a short «Дальше». Body text never drops below 9 pt.

  private func cover(_ c: ProposalCanvas) {
    c.newPage(footer: false)
    // The original logo shape, tinted black.
    if let logo = ProposalCanvas.blackLogo {
      logo.draw(in: CGRect(x: c.left, y: 44, width: 84, height: 84 * logo.size.height / max(1, logo.size.width)))
    }
    c.text(dateText, at: CGPoint(x: c.left, y: 52), width: c.width, font: .systemFont(ofSize: 10), color: Palette.muted,
           align: .right)
    var y: CGFloat = 104
    if let image = ProposalCanvas.image(lead?.product, maxPixel: 2200) {
      // Natural proportion across the full width; cropped only when it would exceed the page.
      // A long project name takes height from the photograph, never from the type size.
      let title = ceil((project.name as NSString).boundingRect(
        with: CGSize(width: c.width, height: 400), options: .usesLineFragmentOrigin,
        attributes: [.font: ProposalCanvas.serif(36)], context: nil).height)
      let block = projectFactsHeight(c)
      let limit = 470 - max(0, title - 46) - max(0, block - 40)
      let height = min(limit, max(260, ProposalCanvas.page.width * image.size.height / image.size.width))
      let rect = CGRect(x: 0, y: y, width: ProposalCanvas.page.width, height: height)
      c.fill(image, in: rect, radius: 0)
      c.text("Официальное фото Salini", at: CGPoint(x: c.left, y: rect.maxY + 8), width: c.width,
             font: .systemFont(ofSize: 9), color: Palette.muted)
      y = rect.maxY + 38
    } else {
      y = 160
    }
    c.y = y
    c.eyebrow("ПЕРСОНАЛЬНОЕ ПРЕДЛОЖЕНИЕ")
    c.paragraph(project.name, font: ProposalCanvas.serif(36), spacing: 6)
    if !project.client.isEmpty {
      c.paragraph("Для: \(project.client)", font: .systemFont(ofSize: 13), color: Palette.muted, spacing: 14)
    } else {
      c.y += 8
    }
    if let lead, let p = lead.product {
      c.swatch(lead.colour.displayColour, at: CGPoint(x: c.left, y: c.y + 1), size: 14)
      let h = c.text(
        [p.name, lead.variant?.title, lead.colour.longTitle].compactMap { $0 }.joined(separator: " · "),
        at: CGPoint(x: c.left + 22, y: c.y), width: c.width - 22, font: .systemFont(ofSize: 12, weight: .medium))
      c.y += h + 6
    }
    c.paragraph(
      "\(lines.count) \(plural(lines.count, "позиция", "позиции", "позиций")) · \(project.pieces) \(plural(project.pieces, "изделие", "изделия", "изделий"))",
      font: .systemFont(ofSize: 11), color: Palette.muted, spacing: 14)
    let facts = ProposalTexts.projectFacts(lines)
    if !facts.isEmpty {
      c.eyebrow("ДЛЯ ВАШЕГО ПРОЕКТА")
      for fact in facts {
        Palette.ink.setFill()
        UIBezierPath(ovalIn: CGRect(x: c.left + 1, y: c.y + 5.5, width: 3.5, height: 3.5)).fill()
        c.y += c.text(fact, at: CGPoint(x: c.left + 12, y: c.y), width: c.width - 12, font: .systemFont(ofSize: 10.5)) + 4
      }
    }
    c.text(
      "Цены публичного каталога Salini на \(Catalog.shared.snapshotText). Не является офертой.",
      at: CGPoint(x: c.left, y: ProposalCanvas.page.height - 50), width: c.width, font: .systemFont(ofSize: 9),
      color: Palette.muted)
  }

  /// Height of the cover's «Для вашего проекта» block, so the photograph can make room for it.
  private func projectFactsHeight(_ c: ProposalCanvas) -> CGFloat {
    let facts = ProposalTexts.projectFacts(lines)
    guard !facts.isEmpty else { return 0 }
    return 32 + facts.reduce(0) { sum, fact in
      sum + ceil((fact as NSString).boundingRect(
        with: CGSize(width: c.width - 12, height: 400), options: .usesLineFragmentOrigin,
        attributes: [.font: UIFont.systemFont(ofSize: 10.5)], context: nil).height) + 6
    }
  }

  /// Useful card facts only: dimensions and weight. The archived «type» field («170 см») is noise.
  private func facts(_ line: ProjectLine) -> [String] {
    guard let p = line.product else { return [] }
    var out: [String] = []
    if let d = p.dimensions.text { out.append("Габариты \(d)") }
    if let w = line.variant?.weightKg { out.append("Вес \(kg(w))") }
    return out
  }

  private func solution(_ c: ProposalCanvas) {
    c.newPage()
    c.heading("Ваше решение", note: nil)
    let photoW: CGFloat = 250
    let photoH: CGFloat = 214
    let textX = c.left + photoW + 20
    let textW = c.width - photoW - 20
    for line in lines {
      c.ensure(photoH + 20)
      let top = c.y
      if let image = ProposalCanvas.image(line.product, maxPixel: 1100) {
        c.fill(image, in: CGRect(x: c.left, y: top, width: photoW, height: photoH), radius: 10)
      } else {
        UIColor(hex: 0xF1EFEB).setFill()
        UIBezierPath(roundedRect: CGRect(x: c.left, y: top, width: photoW, height: photoH), cornerRadius: 10).fill()
      }
      var ty = top + 2
      ty += c.text(line.product?.name ?? "Позиция недоступна в каталоге", at: CGPoint(x: textX, y: ty), width: textW,
                   font: ProposalCanvas.serif(21)) + 4
      ty += c.text(line.variant?.title ?? "исполнение требует уточнения", at: CGPoint(x: textX, y: ty), width: textW,
                   font: .systemFont(ofSize: 10.5), color: Palette.muted) + 5
      c.swatch(line.colour.displayColour, at: CGPoint(x: textX, y: ty + 1), size: 11)
      ty += c.text(line.colour.longTitle, at: CGPoint(x: textX + 17, y: ty), width: textW - 17,
                   font: .systemFont(ofSize: 10.5)) + 7
      ty += c.text("\(line.quantity) шт. · \(line.priceText)", at: CGPoint(x: textX, y: ty), width: textW,
                   font: .systemFont(ofSize: 11.5, weight: .semibold)) + 10
      // Family advantages (own category only), then what the chosen material is; card facts below.
      let family = line.product.map { Array(ProposalTexts.advantages(for: $0).prefix(3)) } ?? []
      let surface = line.variant.flatMap { StudioFinish(material: $0.material, finish: $0.finish) }
        .map(ProposalTexts.material) ?? []
      for point in (family + surface).prefix(4) {
        Palette.ink.setFill()
        UIBezierPath(ovalIn: CGRect(x: textX + 1, y: ty + 5.5, width: 3.5, height: 3.5)).fill()
        ty += c.text(point, at: CGPoint(x: textX + 11, y: ty), width: textW - 11, font: .systemFont(ofSize: 10)) + 4
      }
      let cardFacts = facts(line)
      if !cardFacts.isEmpty {
        ty += 2
        ty += c.text(cardFacts.joined(separator: " · "), at: CGPoint(x: textX, y: ty), width: textW,
                     font: .systemFont(ofSize: 9.5), color: Palette.muted)
      }
      if let p = line.product {
        ty += 4
        ty += c.text("Гарантия: " + ProposalTexts.warranty(for: p), at: CGPoint(x: textX, y: ty), width: textW,
                     font: .systemFont(ofSize: 9.5), color: Palette.muted)
      }
      c.y = max(top + photoH, ty) + 26
    }
    // Materials actually chosen, compact.
    let finishes = lines.compactMap { $0.variant }.compactMap { StudioFinish(material: $0.material, finish: $0.finish) }
      .reduce(into: [StudioFinish]()) { if !$0.contains($1) { $0.append($1) } }
    guard !finishes.isEmpty else { return }
    c.ensure(40 + CGFloat(finishes.count) * 52)
    c.rule()
    c.eyebrow("МАТЕРИАЛЫ ПРОЕКТА")
    for f in finishes {
      c.ensure(52)
      let top = c.y
      c.text(f.title, at: CGPoint(x: c.left, y: top), width: 150, font: ProposalCanvas.serif(15))
      let h = c.text(
        MaterialFacts.short(f) + " " + (f == .stoneMatte ? "Допускает лёгкую косметическую шлифовку." : "Толщина покрытия позволяет косметическую полировку."),
        at: CGPoint(x: c.left + 160, y: top + 2), width: c.width - 160, font: .systemFont(ofSize: 10), color: Palette.muted)
      c.y = top + max(22, h) + 12
    }
    c.paragraph("Уход: мягкая ткань и неабразивное средство. " + MaterialFacts.never, font: .systemFont(ofSize: 9.5),
                color: Palette.muted, spacing: 0)
  }

  /// Columns: №, item, article, quantity, unit price, sum. № fits «999» on one line.
  static let columns: [CGFloat] = [28, 205, 84, 40, 75, 75]

  private func specification(_ c: ProposalCanvas) {
    c.newPage()
    c.heading("Спецификация", note: "Цены публичного каталога Salini на \(Catalog.shared.snapshotText)")
    let head: [ProposalCanvas.Cell] = ["№", "Позиция", "Артикул", "Кол-во", "Цена", "Сумма"].enumerated().map {
      ProposalCanvas.Cell($0.element.uppercased(), font: .systemFont(ofSize: 8, weight: .semibold), color: Palette.muted,
                          align: $0.offset >= 3 ? .right : .left)
    }
    func header() { c.table(head, columns: Self.columns, rule: Palette.ink) }
    header()
    for (i, line) in lines.enumerated() {
      let v = line.variant
      var detail = [[v?.title ?? "исполнение требует уточнения", line.colour.longTitle].joined(separator: " · ")]
      let weight = [v?.weightKg.map { "вес \(kg($0))" }, v?.packedWeightKg.map { "в упаковке \(kg($0))" }].compactMap { $0 }
      if !weight.isEmpty { detail.append(weight.joined(separator: ", ")) }
      if let p = line.product, let a = p.availability.text {
        detail.append(line.isCustomColour ? "выбранный цвет — под заказ, срок уточняет менеджер" : a)
      }
      let unit: String
      if line.needsClarification { unit = "уточняется" } else if let price = v?.price {
        unit = line.isCustomColour ? "\(rubles(price))\n+ цвет" : rubles(price)
      } else { unit = "по запросу" }
      let sum: String
      if line.needsClarification { sum = "уточняется" } else if let base = line.baseTotal {
        sum = line.isCustomColour ? "\(rubles(base))\n+ цвет" : rubles(base)
      } else { sum = "по запросу" }
      let cells = [
        ProposalCanvas.Cell("\(i + 1)", font: .systemFont(ofSize: 10), color: Palette.muted),
        ProposalCanvas.Cell(line.product?.name ?? "Позиция недоступна в каталоге · требует уточнения",
                            font: .systemFont(ofSize: 10.5, weight: .medium), color: Palette.ink,
                            detail: detail.joined(separator: "\n")),
        ProposalCanvas.Cell(line.sku ?? (line.isCustomColour ? "уточняется (RAL)" : "уточняется"),
                            font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular), color: Palette.ink),
        ProposalCanvas.Cell("\(line.quantity)", font: .systemFont(ofSize: 10), color: Palette.ink, align: .right),
        ProposalCanvas.Cell(unit, font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular), color: Palette.ink, align: .right),
        ProposalCanvas.Cell(sum, font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: Palette.ink, align: .right),
      ]
      if c.ensure(c.tableHeight(cells, columns: Self.columns) + 14) { header() }
      c.table(cells, columns: Self.columns, rule: Palette.line)
    }
    c.ensure(150)
    c.y += 22
    let complete = project.isTotalComplete
    let labelText = complete ? "ИТОГО ПО ПУБЛИЧНЫМ ЦЕНАМ" : "БАЗОВАЯ СУММА ПО ПУБЛИЧНЫМ ЦЕНАМ"
    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8, weight: .semibold),
                                                .foregroundColor: Palette.muted, .kern: 1.8]
    let size = (labelText as NSString).size(withAttributes: attrs)
    (labelText as NSString).draw(at: CGPoint(x: c.left + c.width - size.width, y: c.y), withAttributes: attrs)
    c.y += 16
    c.y += c.text(rubles(project.knownTotal), at: CGPoint(x: c.left, y: c.y), width: c.width,
                  font: .systemFont(ofSize: 30, weight: .light), align: .right) + 8
    let unpriced = project.unpricedLines
    if unpriced > 0 {
      c.y += c.text(
        "Итог неполный: \(unpriced) \(plural(unpriced, "позиция", "позиции", "позиций")) с ценой по запросу — цвет RAL, нет цены или исполнение уточняется.",
        at: CGPoint(x: c.left + 160, y: c.y), width: c.width - 160, font: .systemFont(ofSize: 10, weight: .medium),
        color: Palette.clay, align: .right) + 6
    }
    c.y += c.text(
      "Доставка, монтаж и индивидуальные условия — отдельно. Наличие, сроки и цвет подтверждает менеджер. Не является офертой.",
      at: CGPoint(x: c.left + 160, y: c.y), width: c.width - 160, font: .systemFont(ofSize: 9), color: Palette.muted,
      align: .right)
  }

  private func colourStory(_ c: ProposalCanvas, _ studies: [Study]?) {
    c.newPage()
    defer { next(c) }
    guard let lead, let p = lead.product else { return }
    guard leadPaintable else {
      // Mirrors, furniture and other non-cast items: the official photograph and card facts only.
      c.heading(p.name, note: lead.variant?.title ?? "исполнение требует уточнения")
      if let image = ProposalCanvas.image(p, maxPixel: 1600) {
        let h = min(400, c.width * image.size.height / image.size.width)
        c.fill(image, in: CGRect(x: c.left, y: c.y, width: c.width, height: h), radius: 12)
        c.y += h + 14
      }
      let f = facts(lead)
      if !f.isEmpty { c.paragraph(f.joined(separator: " · "), font: .systemFont(ofSize: 10.5), spacing: 8) }
      c.paragraph("Официальное фото Salini. Отделка — по данным карточки изделия; варианты подтверждает менеджер.",
                  font: .systemFont(ofSize: 9), color: Palette.muted, spacing: 0)
      return
    }
    c.heading("Цвет · \(p.name)", note: lead.variant?.title)
    if let studies, let first = studies.first {
      // A short «Дальше» (few links) stays on this page: the large study gives up some height
      // (down to 0.46 of the width) instead of the closing block moving to an almost empty page.
      var bigHeight = c.width * 0.6
      let note = "Концептуальная визуализация по официальной 3D-модели \(p.name), не цветопроба. Экранные цвета RAL Classic приблизительны; доступность оттенка и цену подтверждает менеджер."
      let altHeight: CGFloat = studies.count > 1 ? 18 + (c.width - 24) / 3 * 0.62 + 34 : 0
      if closingLinks.count <= Self.closingLinksKept {
        let planned = c.y + bigHeight + 36 + altHeight + c.measure(note, width: c.width, font: .systemFont(ofSize: 9))
          + closingHeight(c)
        if planned > c.bottomLimit { bigHeight = max(c.width * 0.46, bigHeight - (planned - c.bottomLimit)) }
      }
      let big = CGRect(x: c.left, y: c.y, width: c.width, height: bigHeight)
      c.study(first.image, in: big)
      c.swatch(first.colour, at: CGPoint(x: c.left, y: big.maxY + 10), size: 13)
      c.text(first.title, at: CGPoint(x: c.left + 20, y: big.maxY + 9), width: c.width - 20,
             font: .systemFont(ofSize: 11, weight: .medium))
      c.y = big.maxY + 36
      let rest = Array(studies.dropFirst().prefix(3))
      if !rest.isEmpty {
        c.eyebrow("АЛЬТЕРНАТИВЫ НА ТОЙ ЖЕ ФОРМЕ")
        let w = (c.width - 24) / 3
        let h = w * 0.62
        for (i, s) in rest.enumerated() {
          let rect = CGRect(x: c.left + CGFloat(i) * (w + 12), y: c.y, width: w, height: h)
          c.study(s.image, in: rect)
          c.swatch(s.colour, at: CGPoint(x: rect.minX, y: rect.maxY + 7), size: 10)
          c.text(s.title, at: CGPoint(x: rect.minX + 15, y: rect.maxY + 5), width: w - 15, font: .systemFont(ofSize: 9))
        }
        c.y += h + 34
      }
      c.paragraph(note, font: .systemFont(ofSize: 9), color: Palette.muted, spacing: 0)
    } else {
      // No own model: the official photograph in its original colour and the chosen swatches.
      if let image = ProposalCanvas.image(p, maxPixel: 1600) {
        let h = min(360, c.width * image.size.height / image.size.width)
        c.fill(image, in: CGRect(x: c.left, y: c.y, width: c.width, height: h), radius: 12)
        c.y += h + 16
      }
      var x = c.left
      for (title, colour) in studyColours() {
        c.swatch(colour, at: CGPoint(x: x, y: c.y), size: 24)
        c.text(title, at: CGPoint(x: x, y: c.y + 30), width: 118, font: .systemFont(ofSize: 9))
        x += 127
      }
      c.y += 70
      c.paragraph(
        (leadForm == nil ? "Для этого изделия нет официальной 3D-модели: фото" : "Фото") + " показано в оригинальном цвете. Плашки — экранное приближение RAL Classic; доступность оттенка подтверждает менеджер.",
        font: .systemFont(ofSize: 9), color: Palette.muted, spacing: 0)
    }
  }

  /// A short closing block, not a page of its own.
  /// Distinct products of the project, for the closing links.
  private var closingLinks: [CatalogProduct] {
    lines.compactMap { $0.product }.reduce(into: [CatalogProduct]()) { list, p in
      if !list.contains(where: { $0.id == p.id }) { list.append(p) }
    }
  }
  /// Heading, contacts and up to this many links are kept together; a longer list flows on.
  static let closingLinksKept = 3
  private static let closingText = "Менеджер Salini подтвердит наличие, сроки, цвет и итоговую стоимость и подскажет ближайшую экспозицию."
  private func linkLine(_ p: CatalogProduct) -> String { "\(p.name) — \(p.url)" }
  /// Measured height of the closing block with its first links (same fonts as drawing).
  private func closingHeight(_ c: ProposalCanvas) -> CGFloat {
    let head: CGFloat = 18 + 14 + 18  // gap, rule, eyebrow
    let body = c.measure(Self.closingText, width: c.width, font: .systemFont(ofSize: 10.5)) + 6
      + c.measure(ProposalTexts.contacts.joined(separator: "   ·   "), width: c.width,
                  font: .systemFont(ofSize: 10.5, weight: .semibold)) + 8
    let links = closingLinks.prefix(Self.closingLinksKept).reduce(CGFloat(0)) {
      $0 + c.measure(linkLine($1), width: c.width, font: .systemFont(ofSize: 9)) + 3
    }
    return head + body + links
  }

  private func next(_ c: ProposalCanvas) {
    let links = closingLinks
    // Heading, contacts and the first links stay together; a long list flows on, link by link.
    c.ensure(closingHeight(c))
    c.y += 18
    c.rule()
    c.eyebrow("ДАЛЬШЕ")
    c.paragraph(Self.closingText, font: .systemFont(ofSize: 10.5), spacing: 6)
    c.paragraph(ProposalTexts.contacts.joined(separator: "   ·   "), font: .systemFont(ofSize: 10.5, weight: .semibold),
                spacing: 8)
    for p in links {
      let line = linkLine(p)
      c.ensure(c.measure(line, width: c.width, font: .systemFont(ofSize: 9)) + 3)
      let h = c.text(line, at: CGPoint(x: c.left, y: c.y), width: c.width, font: .systemFont(ofSize: 9),
                     color: Palette.muted)
      if let url = URL(string: p.url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? p.url) {
        UIGraphicsSetPDFContextURLForRect(url, CGRect(x: c.left, y: c.y, width: c.width, height: h))
      }
      c.y += h + 3
    }
  }
}

// MARK: - Canvas

/// A4 page flow with a cursor, automatic page breaks and a footer.
final class ProposalCanvas {
  static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
  var ctx: UIGraphicsPDFRendererContext?
  var footer = ""
  var y: CGFloat = 0
  private(set) var pageNumber = 0
  let left: CGFloat = 44
  var width: CGFloat { Self.page.width - left * 2 }
  private let bottom: CGFloat = 790

  /// The original logo shape in black. A tinted template drawn straight into a PDF context
  /// fills its whole rectangle, so the tint is rasterised first through the PNG's own alpha.
  static let blackLogo: UIImage? = {
    guard let source = UIImage(named: "salini-logo.png") else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    format.opaque = false
    return UIGraphicsImageRenderer(size: source.size, format: format).image { ctx in
      let rect = CGRect(origin: .zero, size: source.size)
      source.draw(in: rect)
      ctx.cgContext.setBlendMode(.sourceIn)
      Palette.ink.setFill()
      ctx.cgContext.fill(rect)
    }
  }()
  static func serif(_ size: CGFloat) -> UIFont {
    let base = UIFont.systemFont(ofSize: size)
    return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
  }

  func newPage(footer showFooter: Bool = true) {
    ctx?.beginPage()
    pageNumber += 1
    y = 56
    if showFooter {
      text(
        "Salini · \(footer) · \(pageNumber)", at: CGPoint(x: left, y: Self.page.height - 34), width: width,
        font: .systemFont(ofSize: 8), color: Palette.muted)
    }
  }
  /// Starts a new page when `height` does not fit; true when it did.
  @discardableResult
  func ensure(_ height: CGFloat) -> Bool {
    guard y + height > bottom else { return false }
    newPage()
    return true
  }
  @discardableResult
  func text(
    _ string: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor = Palette.ink,
    align: NSTextAlignment = .left
  ) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = font.pointSize > 20 ? 0 : 1.5
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    let h = ceil((string as NSString).boundingRect(
      with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height)
    (string as NSString).draw(
      with: CGRect(x: point.x, y: point.y, width: width, height: h + 2), options: .usesLineFragmentOrigin, attributes: attrs,
      context: nil)
    return h
  }
  /// Height `text(_:at:width:font:)` will take — same attributes, so layout can plan ahead.
  func measure(_ string: String, width: CGFloat, font: UIFont) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = font.pointSize > 20 ? 0 : 1.5
    return ceil((string as NSString).boundingRect(
      with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin,
      attributes: [.font: font, .paragraphStyle: style], context: nil).height)
  }
  var bottomLimit: CGFloat { bottom }
  func paragraph(_ string: String, font: UIFont, color: UIColor = Palette.ink, spacing: CGFloat) {
    let probe = (string as NSString).boundingRect(
      with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil).height
    ensure(ceil(probe) + 4)
    y += text(string, at: CGPoint(x: left, y: y), width: width, font: font, color: color) + spacing
  }
  func eyebrow(_ string: String) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: Palette.muted, .kern: 1.8,
    ]
    ensure(20)
    (string as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attrs)
    y += 18
  }
  func heading(_ title: String, note: String?) {
    y += text(title, at: CGPoint(x: left, y: y), width: width, font: Self.serif(28)) + 6
    if let note { y += text(note, at: CGPoint(x: left, y: y), width: width, font: .systemFont(ofSize: 10), color: Palette.muted) }
    y += 22
  }
  func bullets(_ items: [String]) {
    for item in items {
      ensure(18)
      let h = text(item, at: CGPoint(x: left + 14, y: y), width: width - 14, font: .systemFont(ofSize: 10.5))
      Palette.ink.setFill()
      UIBezierPath(ovalIn: CGRect(x: left + 2, y: y + 5.5, width: 4, height: 4)).fill()
      y += h + 5
    }
  }
  func swatch(_ colour: UIColor, at point: CGPoint, size: CGFloat = 12) {
    let r = CGRect(x: point.x, y: point.y, width: size, height: size)
    colour.setFill()
    UIBezierPath(ovalIn: r).fill()
    Palette.line.setStroke()
    UIBezierPath(ovalIn: r).stroke()
  }
  func rowHeight(_ cells: [String], columns: [CGFloat], font: UIFont) -> CGFloat {
    zip(cells, columns).map { cell, w in
      ceil((cell as NSString).boundingRect(
        with: CGSize(width: w - 6, height: 2000), options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil
      ).height) * 1.12
    }.max() ?? 0
  }
  func row(_ cells: [String], columns: [CGFloat], font: UIFont, color: UIColor, rule: Bool) {
    var x = left
    var h: CGFloat = 0
    for (cell, w) in zip(cells, columns) {
      h = max(h, text(cell, at: CGPoint(x: x, y: y), width: w - 6, font: font, color: color))
      x += w
    }
    y += h + 6
    if rule {
      Palette.line.setFill()
      UIRectFill(CGRect(x: left, y: y, width: width, height: 0.5))
    }
    y += 6
  }
  func rule() {
    Palette.line.setFill()
    UIRectFill(CGRect(x: left, y: y, width: width, height: 0.5))
    y += 14
  }
  struct Cell {
    let text: String
    let font: UIFont
    let color: UIColor
    let align: NSTextAlignment
    let detail: String?
    init(_ text: String, font: UIFont, color: UIColor, align: NSTextAlignment = .left, detail: String? = nil) {
      self.text = text
      self.font = font
      self.color = color
      self.align = align
      self.detail = detail
    }
  }
  private func cellHeight(_ cell: Cell, width w: CGFloat) -> CGFloat {
    func h(_ s: String, _ f: UIFont) -> CGFloat {
      ceil((s as NSString).boundingRect(with: CGSize(width: w, height: 2000), options: .usesLineFragmentOrigin,
                                        attributes: [.font: f], context: nil).height) + 2
    }
    return h(cell.text, cell.font) + (cell.detail.map { h($0, Self.detailFont) * 1.08 + 3 } ?? 0)
  }
  static let detailFont = UIFont.systemFont(ofSize: 9)
  func tableHeight(_ cells: [Cell], columns: [CGFloat]) -> CGFloat {
    zip(cells, columns).map { cellHeight($0, width: $1 - 8) }.max() ?? 0
  }
  func table(_ cells: [Cell], columns: [CGFloat], rule colour: UIColor) {
    var x = left
    let height = tableHeight(cells, columns: columns)
    y += 8
    for (cell, w) in zip(cells, columns) {
      let cw = w - 8
      let cx = cell.align == .right ? x + 8 : x
      var cy = y + text(cell.text, at: CGPoint(x: cx, y: y), width: cw, font: cell.font, color: cell.color, align: cell.align)
      if let detail = cell.detail {
        cy += 3
        text(detail, at: CGPoint(x: cx, y: cy), width: cw, font: Self.detailFont, color: Palette.muted, align: cell.align)
      }
      x += w
    }
    y += height + 8
    colour.setFill()
    UIRectFill(CGRect(x: left, y: y, width: width, height: colour == Palette.ink ? 0.8 : 0.5))
  }
  static func image(_ product: CatalogProduct?, maxPixel: CGFloat) -> UIImage? {
    guard let url = product?.imageURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
      ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cg)
  }
  /// Aspect-fill without letterboxing; the photograph is never recoloured.
  func fill(_ image: UIImage, in rect: CGRect, radius: CGFloat) {
    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let g = UIGraphicsGetCurrentContext()
    g?.saveGState()
    UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
    image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    g?.restoreGState()
  }
  func study(_ image: UIImage?, in rect: CGRect) {
    ProposalComposer.studyPaper.setFill()
    UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
    if let image { fill(image, in: rect, radius: 10) }
  }
  /// The official photograph, whole (aspect-fit) on a neutral field; never recoloured.
  func photo(_ product: CatalogProduct?, in rect: CGRect, maxPixel: CGFloat, rounded: CGFloat = 0) {
    let path = UIBezierPath(roundedRect: rect, cornerRadius: rounded)
    UIColor(hex: 0xEDEEF0).setFill()
    path.fill()
    guard let url = product?.imageURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
      ] as CFDictionary)
    else { return }
    let image = UIImage(cgImage: cg)
    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let g = UIGraphicsGetCurrentContext()
    g?.saveGState()
    path.addClip()
    image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    g?.restoreGState()
  }
}

// MARK: - Progress, preview and share

/// Thread-safe cancellation flag shared by the UI and the background render.
final class ProposalCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
}

/// Owns its file: the preview stays valid after the progress sheet is gone.
final class ProposalPreviewController: QLPreviewController, QLPreviewControllerDataSource {
  let fileURL: URL
  init(fileURL: URL) {
    self.fileURL = fileURL
    super.init(nibName: nil, bundle: nil)
    dataSource = self
  }
  required init?(coder: NSCoder) { fatalError() }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    fileURL as NSURL
  }
}

/// Generates the proposal off the main thread with visible progress and cancellation,
/// then opens a QuickLook preview whose share button sends the file. Nothing leaves the device.
final class ProposalController: UIViewController {
  private let composer: ProposalComposer
  private let progress = UIProgressView(progressViewStyle: .default)
  private let status = label("Готовим этюды и страницы…", 14, .regular, Palette.muted)
  private let cancellation = ProposalCancellation()

  init(project: SaliniProject, role: Audience) {
    composer = ProposalComposer(project: project, role: role)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    sheetPresentationController?.detents = [.custom { _ in 220 }]
    sheetPresentationController?.prefersGrabberVisible = true
    isModalInPresentation = true
  }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Palette.paper
    progress.tintColor = Palette.ink
    progress.accessibilityLabel = "Готовность предложения"
    let cancel = ActionButton("Отменить", icon: "xmark") { [weak self] in
      self?.cancellation.cancel()
      self?.dismiss(animated: true)
    }
    let body = stack([label("Персональное предложение", 24, .regular, serif: true), status, progress, cancel], spacing: 14)
    view.pin(body.inset(24))
    let composer = composer
    let cancellation = cancellation
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let data = composer.render(
        progress: { value in DispatchQueue.main.async { self?.progress.setProgress(Float(value), animated: true) } },
        isCancelled: { cancellation.isCancelled })
      DispatchQueue.main.async { self?.finish(data) }
    }
  }

  private func finish(_ data: Data?) {
    guard !cancellation.isCancelled else { return }
    guard let data else {
      status.text = "Добавьте изделия в проект — без позиций предложение не создаётся."
      return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(composer.fileName)
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      status.text = "Не удалось сохранить файл: \(error.localizedDescription)"
      return
    }
    UIAccessibility.post(notification: .announcement, argument: "Предложение готово, \(composer.pageCount) страниц")
    let preview = ProposalPreviewController(fileURL: url)
    let presenter = presentingViewController
    dismiss(animated: true) { presenter?.present(preview, animated: true) }
  }
}
