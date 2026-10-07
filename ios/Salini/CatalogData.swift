import ImageIO
import UIKit

// Offline catalogue built by ios/tools/build_catalog.py from the 06.10.2026 public-site audit.
// Unknown source values stay nil and are shown as «по запросу», never as zero.

struct CatalogColour: Codable, Hashable {
  let title: String
  let sku: String
}

struct CatalogVariant: Codable, Hashable {
  /// Stable id from the builder: material-finish-ordinal. Independent of price and article.
  let id: String
  let material: String?
  let finish: String?
  let sku: String?
  let customColourSku: String?
  let colours: [CatalogColour]
  let price: Int?
  let weightKg: Double?
  let packedWeightKg: Double?

  /// Identity saved in projects. Prices and later-published articles do not change it.
  var key: String { id }
  var materialTitle: String? {
    guard let material else { return nil }
    return [
      "sStone": "S-Stone", "sSense": "S-Sense", "mdf": "МДФ", "solidSurface": "Solid Surface",
      "gelcoat": "Gelcoat", "keramogranit": "Керамогранит", "plastik": "Пластик", "stal": "Сталь",
      "khrom": "Хром", "abs_plastik": "ABS-пластик", "stal_plastik": "Сталь и пластик",
    ][material] ?? material
  }
  var finishTitle: String? {
    switch finish {
    case "gloss": return "глянцевое"
    case "matte": return "матовое"
    default: return nil
    }
  }
  /// «S-Sense · глянцевое», «S-Stone · матовое», or nil for accessories without data.
  var title: String? {
    switch (materialTitle, finishTitle) {
    case let (m?, f?): return "\(m) · \(f)"
    case let (m?, nil): return m
    case let (nil, f?): return f.capitalized
    default: return nil
    }
  }
  var isMineral: Bool { material == "sStone" || material == "sSense" }
}

/// A card value: an exact number or a range printed on the card («1715–2015»).
enum Measure: Codable, Hashable {
  case value(Double)
  case range(Double, Double)
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let v = try? c.decode(Double.self) {
      self = .value(v)
      return
    }
    struct R: Codable { let min: Double; let max: Double }
    let r = try c.decode(R.self)
    self = .range(r.min, r.max)
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .value(let v): try c.encode(v)
    case .range(let a, let b): try c.encode(["min": a, "max": b])
    }
  }
  var text: String {
    switch self {
    case .value(let v): return formatMM(v)
    case .range(let a, let b): return "\(formatMM(a))–\(formatMM(b))"
    }
  }
  /// For filtering only exact values are used; ranges never match a length filter.
  var exact: Double? {
    if case .value(let v) = self { return v }
    return nil
  }
}

struct CatalogDimensions: Codable, Hashable {
  let length: Measure?
  let width: Measure?
  let height: Measure?
  let depth: Measure?
  let diameter: Measure?
  var text: String? {
    let parts = [length, width ?? depth, height].compactMap { $0 }.map(\.text)
    if parts.count >= 2 { return parts.joined(separator: " × ") + " мм" }
    if let diameter { return "Ø \(diameter.text) мм" }
    if parts.count == 1, let only = parts.first { return only + " мм" }
    return nil
  }
}

struct CatalogAvailability: Codable, Hashable {
  let text: String?
  let stockQuantity: Int?
  let madeToOrder: Bool
}

struct CatalogDocument: Codable, Hashable {
  let label: String
  let url: String
  /// passport · drawing · model · presentation · option · other
  let kind: String
  var isOption: Bool { kind == "option" }
}

struct CatalogProduct: Codable, Hashable, Identifiable {
  let id: String
  let legacyId: String?
  let siteName: String
  let name: String
  let category: String
  let subcategory: String?
  let isOption: Bool
  let url: String
  let description: String?
  let dimensions: CatalogDimensions
  let depthToOverflow: Double?
  let type: String?
  let variants: [CatalogVariant]
  let availability: CatalogAvailability
  let documents: [CatalogDocument]
  let image: String?
  /// Exact source URL of the card photo; `imageRole` says where it came from on the page:
  /// "gallery" — the card's own product gallery, "hero" — its unique page banner.
  let imageSource: String?
  let imageRole: String?
  /// The page's family banner, kept for editorial use only — never shown as the product.
  let editorialSource: String?
  let model: String?

  var subtitle: String { [subcategory, category].compactMap { $0 }.first ?? category }
  var minPrice: Int? { variants.compactMap(\.price).min() }
  var priceText: String {
    guard let min = minPrice else { return "Цена по запросу" }
    let prices = Set(variants.compactMap(\.price))
    return prices.count > 1 ? "от \(rubles(min))" : rubles(min)
  }
  /// Latin family words from the official URL («noemi», «ornella»), for search.
  var slugWords: [String] {
    URL(string: url)?.pathComponents.dropFirst().map { $0.replacingOccurrences(of: "-", with: " ") } ?? []
  }
  /// The saved execution, or nil if it no longer exists — then the line needs clarification,
  /// it is never silently replaced by another execution.
  func variant(key: String?) -> CatalogVariant? {
    guard let key else { return variants.count == 1 ? variants.first : nil }
    return variants.first { $0.key == key } ?? variants.first { $0.sku == key }
  }
  var imageURL: URL? { image.flatMap { Catalog.mediaURL?.appendingPathComponent($0) } }
}

func formatMM(_ value: Double) -> String {
  value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

struct CatalogFile: Codable {
  let snapshot: String
  let source: String
  let products: [CatalogProduct]
}

final class Catalog {
  static let shared = Catalog()
  static let mediaURL = Bundle.main.url(forResource: "CatalogMedia", withExtension: nil)
  /// The four ids of the original prototype map onto official product ids.
  static let legacyIds = ["aria": "20645", "opera": "30897", "greca": "1120", "opera-top": "30919"]

  let snapshot: String
  let products: [CatalogProduct]
  private let byId: [String: CatalogProduct]
  private struct Entry {
    let product: CatalogProduct
    let text: String
    let skus: [String: String]
  }
  private struct Candidate {
    let entry: Entry
    let allowed: [CatalogVariant]
  }
  private let index: [Entry]

  init(file: CatalogFile? = Catalog.load()) {
    snapshot = file?.snapshot ?? ""
    products = file?.products ?? []
    byId = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    index = Catalog.editorialOrder(products).map { p in
      var skus: [String: String] = [:]
      for v in p.variants {
        for code in [v.sku, v.customColourSku].compactMap({ $0 }) + v.colours.map(\.sku) {
          skus[CatalogSearch.normalizeSKU(code)] = v.key
        }
      }
      let text = ([p.name, p.siteName, p.category, p.subcategory ?? "", p.type ?? ""] + p.slugWords)
        .joined(separator: " ")
      return Entry(product: p, text: CatalogSearch.fold(text), skus: skus)
    }
  }
  /// Default ("По умолчанию") order: an editorial opening across the range, not a ranking.
  /// Signature forms first, then a round-robin of expressive washbasins, furniture, mirrors and
  /// freestanding baths (one per family, with a photograph), then everything else in source order.
  /// Price and length sorts are unaffected.
  static let signatureIds = ["20645", "1361", "1120", "30897", "1139"]  // Aria, Ninfea, Greca, Opera, Noemi 170
  static func editorialOrder(_ products: [CatalogProduct]) -> [CatalogProduct] {
    let buckets: [(String, String?)] = [
      ("Раковины", "Напольные"), ("Мебель", nil), ("Зеркала", nil), ("Раковины", "Накладные"),
      ("Ванны", "Отдельностоящие"), ("Раковины", "Подвесные"),
    ]
    func family(_ p: CatalogProduct) -> String {
      "\(p.category)/\(p.subcategory ?? "")/\(p.siteName.split(separator: " ").first.map(String.init)?.uppercased() ?? p.siteName)"
    }
    var taken = Set<String>()
    var seenFamilies = Set<String>()
    var head: [CatalogProduct] = []
    for id in signatureIds {
      guard let p = products.first(where: { $0.id == id }) else { continue }
      head.append(p)
      taken.insert(p.id)
      seenFamilies.insert(family(p))
    }
    var queues: [[CatalogProduct]] = buckets.map { b in
      products.filter { p in
        p.category == b.0 && (b.1 == nil || p.subcategory == b.1) && !p.isOption && p.imageURL != nil && !taken.contains(p.id)
      }
    }
    var progressed = true
    while progressed {
      progressed = false
      for i in queues.indices {
        while let p = queues[i].first {
          queues[i].removeFirst()
          guard !seenFamilies.contains(family(p)) else { continue }
          seenFamilies.insert(family(p))
          taken.insert(p.id)
          head.append(p)
          progressed = true
          break
        }
      }
    }
    return head + products.filter { !taken.contains($0.id) }
  }
  static func load() -> CatalogFile? {
    guard let url = mediaURL?.appendingPathComponent("catalog.json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(CatalogFile.self, from: data)
  }
  var snapshotText: String {
    let parts = snapshot.split(separator: "-")
    return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : snapshot
  }
  func product(_ id: String) -> CatalogProduct? { byId[Catalog.legacyIds[id] ?? id] }
  /// Legacy prototype product → its catalogue record and the variant it represented.
  func product(for legacy: Product, stone: Bool = false) -> (CatalogProduct, CatalogVariant?)? {
    guard let p = product(legacy.id) else { return nil }
    let sku = legacy.sku(stone: stone)
    return (p, p.variants.first { $0.sku == sku } ?? p.variants.first)
  }
  var categories: [String] {
    let order = [
      "Ванны", "Раковины", "Душевые поддоны", "Столешницы", "Мебель", "Зеркала", "Унитазы и биде",
      "Комплектующие", "Аксессуары", "Уход",
    ]
    let present = Set(products.map(\.category))
    return order.filter(present.contains) + present.subtracting(order).sorted()
  }

  struct Hit: Hashable {
    let product: CatalogProduct
    /// The execution the hit stands for (exact article, or the one matching the filters).
    let variantKey: String?
    let score: Int
    /// Price shown and sorted: the represented execution's, else the product's lowest.
    var price: Int? { variantKey.flatMap { product.variant(key: $0) }.map { $0.price } ?? product.minPrice }
  }

  func search(_ query: String, filter: CatalogFilter = CatalogFilter()) -> [Hit] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [Candidate] = []
    for entry in index where filter.matchesProduct(entry.product) {
      let allowed = filter.allowedVariants(entry.product)
      if !allowed.isEmpty { candidates.append(Candidate(entry: entry, allowed: allowed)) }
    }
    // With variant-level filters the hit carries the cheapest matching execution.
    func representative(_ allowed: [CatalogVariant]) -> String? {
      guard filter.constrainsVariant else { return nil }
      return allowed.min { ($0.price ?? .max) < ($1.price ?? .max) }?.key
    }
    guard !q.isEmpty else {
      return filter.sorted(candidates.map { Hit(product: $0.entry.product, variantKey: representative($0.allowed), score: 0) })
    }
    let skuForms = CatalogSearch.skuCandidates(q)
    let words = CatalogSearch.queryForms(q)
    var hits: [Hit] = []
    for candidate in candidates {
      let entry = candidate.entry
      let allowed = candidate.allowed
      let allowedKeys = Set(allowed.map { $0.key })
      if let key = skuForms.lazy.compactMap({ entry.skus[$0] }).first {
        if allowedKeys.contains(key) { hits.append(Hit(product: entry.product, variantKey: key, score: 1000)) }
        continue
      }
      let prefixKey: String? = skuForms.lazy.filter { $0.count >= 4 }.compactMap { form -> String? in
        for (code, key) in entry.skus where code.hasPrefix(form) && allowedKeys.contains(key) { return key }
        return nil
      }.first
      if let prefixKey {
        hits.append(Hit(product: entry.product, variantKey: prefixKey, score: 600))
        continue
      }
      var best = 0
      for tokens in words {
        guard !tokens.isEmpty, tokens.allSatisfy({ entry.text.contains($0) }) else { continue }
        let name = CatalogSearch.fold(entry.product.name)
        let score = name.hasPrefix(tokens[0]) ? 400 : name.contains(tokens[0]) ? 300 : 150
        best = max(best, score)
      }
      if best > 0 { hits.append(Hit(product: entry.product, variantKey: representative(allowed), score: best)) }
    }
    let ranked = hits.sorted {
      $0.score != $1.score ? $0.score > $1.score : $0.product.name < $1.product.name
    }
    return filter.sort == .relevance ? ranked : filter.sorted(ranked)
  }
}

enum CatalogSearch {
  private static let ruToLat: [Character: Character] = [
    "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o",
    "з": "p", "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k",
    "д": "l", "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
  ]
  private static let latToCyr: [(String, String)] = [
    ("shch", "щ"), ("sch", "щ"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"), ("ch", "ч"), ("sh", "ш"),
    ("yu", "ю"), ("ya", "я"), ("yo", "ё"), ("a", "а"), ("b", "б"), ("c", "к"), ("d", "д"), ("e", "е"),
    ("f", "ф"), ("g", "г"), ("h", "х"), ("i", "и"), ("j", "й"), ("k", "к"), ("l", "л"), ("m", "м"),
    ("n", "н"), ("o", "о"), ("p", "п"), ("q", "к"), ("r", "р"), ("s", "с"), ("t", "т"), ("u", "у"),
    ("v", "в"), ("w", "в"), ("x", "кс"), ("y", "и"), ("z", "з"),
  ]
  /// Lowercase, ё→е, э→е, × and х between digits → x; accents folded.
  static func fold(_ s: String) -> String {
    var t = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "ru"))
    t = t.replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "э", with: "е")
    t = t.replacingOccurrences(of: "×", with: "x")
    t = t.replacingOccurrences(of: #"(\d)\s*[хx]\s*(\d)"#, with: "$1x$2", options: .regularExpression)
    return t
  }
  static func normalizeSKU(_ s: String) -> String {
    s.uppercased().filter { $0.isLetter || $0.isNumber }
  }
  /// The typed article, plus its reading as if typed on a Russian keyboard («1051201Ь»).
  static func skuCandidates(_ q: String) -> [String] {
    let compact = q.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    guard compact.contains(where: \.isNumber) else { return [] }
    let swapped = String(compact.map { ruToLat[$0] ?? $0 })
    return Array(Set([normalizeSKU(compact), normalizeSKU(swapped)])).filter { !$0.isEmpty }
  }
  /// Token lists to try: as typed, and Latin transliterated to Cyrillic («noemi» → «ноеми»).
  static func queryForms(_ q: String) -> [[String]] {
    let base = fold(q)
    var forms = [base]
    if base.range(of: "[a-z]", options: .regularExpression) != nil {
      var cyr = base
      for (lat, ru) in latToCyr { cyr = cyr.replacingOccurrences(of: lat, with: ru) }
      forms.append(cyr)
    }
    return forms.map { $0.split(whereSeparator: { $0 == " " }).map(String.init) }
  }
}

struct CatalogFilter: Equatable {
  enum Finish: String, CaseIterable {
    case stoneMatte, senseMatte, senseGloss
    var title: String {
      switch self {
      case .stoneMatte: return "S-Stone · матовое"
      case .senseMatte: return "S-Sense · матовое"
      case .senseGloss: return "S-Sense · глянцевое"
      }
    }
    func matches(_ v: CatalogVariant) -> Bool {
      switch self {
      case .stoneMatte: return v.material == "sStone"
      case .senseMatte: return v.material == "sSense" && v.finish == "matte"
      case .senseGloss: return v.material == "sSense" && v.finish == "gloss"
      }
    }
  }
  enum Sort: String, CaseIterable {
    case relevance, priceAscending, priceDescending, length
    var title: String {
      switch self {
      case .relevance: return "По умолчанию"
      case .priceAscending: return "Сначала дешевле"
      case .priceDescending: return "Сначала дороже"
      case .length: return "По длине"
      }
    }
  }
  var category: String?
  var subcategories: Set<String> = []
  var finishes: Set<Finish> = []
  var lengthRange: ClosedRange<Double>?
  var maxPrice: Int?
  var inStockOnly = false
  var withModelOnly = false
  var includeOptions = false
  var favoritesOnly: Set<String>?
  var sort: Sort = .relevance

  var activeCount: Int {
    [!subcategories.isEmpty, !finishes.isEmpty, lengthRange != nil, maxPrice != nil, inStockOnly,
     withModelOnly, includeOptions].filter { $0 }.count
  }
  /// Filters that apply to an execution (material/finish, price) must hold for the SAME variant.
  var constrainsVariant: Bool { !finishes.isEmpty || maxPrice != nil }
  func allowedVariants(_ p: CatalogProduct) -> [CatalogVariant] {
    p.variants.filter { v in
      (finishes.isEmpty || finishes.contains { $0.matches(v) })
        && (maxPrice.map { max in (v.price ?? .max) <= max } ?? true)
    }
  }
  func matches(_ p: CatalogProduct) -> Bool { matchesProduct(p) && !allowedVariants(p).isEmpty }
  /// Product-level conditions only (category, type, length, stock, model, options, favourites).
  func matchesProduct(_ p: CatalogProduct) -> Bool {
    if let category, p.category != category { return false }
    if !includeOptions && p.isOption && subcategories.isEmpty { return false }
    if !subcategories.isEmpty && !subcategories.contains(p.subcategory ?? "") { return false }
    if let r = lengthRange {
      guard let l = p.dimensions.length?.exact, r.contains(l) else { return false }
    }
    if inStockOnly && (p.availability.stockQuantity ?? 0) == 0 { return false }
    if withModelOnly && p.model == nil { return false }
    if let favoritesOnly, !favoritesOnly.contains(p.id) { return false }
    return true
  }
  func sorted(_ hits: [Catalog.Hit]) -> [Catalog.Hit] {
    switch sort {
    case .relevance: return hits
    case .priceAscending:
      return hits.sorted { ($0.price ?? .max) < ($1.price ?? .max) }
    case .priceDescending:
      return hits.sorted { ($0.price ?? -1) > ($1.price ?? -1) }
    case .length:
      return hits.sorted {
        ($0.product.dimensions.length?.exact ?? .greatestFiniteMagnitude)
          < ($1.product.dimensions.length?.exact ?? .greatestFiniteMagnitude)
      }
    }
  }
}

/// Downsampled, cached product photographs; decoding happens off the main thread.
final class CatalogImages {
  static let shared = CatalogImages()
  private let cache = NSCache<NSString, UIImage>()
  private let queue = DispatchQueue(label: "salini.catalog.images", qos: .userInitiated, attributes: .concurrent)
  init() { cache.totalCostLimit = 80 * 1024 * 1024 }
  func image(for product: CatalogProduct, maxPixel: CGFloat, completion: @escaping (UIImage?) -> Void) {
    guard let url = product.imageURL else { return completion(nil) }
    let key = "\(product.id)@\(Int(maxPixel))" as NSString
    if let hit = cache.object(forKey: key) { return completion(hit) }
    queue.async { [cache] in
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
      ]
      var image: UIImage?
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      {
        image = UIImage(cgImage: cg)
        cache.setObject(image!, forKey: key, cost: cg.bytesPerRow * cg.height)
      }
      DispatchQueue.main.async { completion(image) }
    }
  }
}
