import UIKit

/// A colour choice for one line: the standard white of the execution or a RAL Classic code.
/// RAL is a request for a custom-colour execution, not a guarantee; it is shown with that caveat.
enum LineColour: Codable, Hashable {
  case standard
  case ral(String)
  var title: String {
    switch self {
    case .standard: return "Базовый белый"
    case .ral(let code): return "RAL \(code)"
    }
  }
}

struct ProjectLine: Codable, Hashable, Identifiable {
  var id = UUID().uuidString
  var productId: String
  var variantKey: String?
  var quantity: Int = 1
  var colour: LineColour = .standard
  var note: String = ""

  var product: CatalogProduct? { Catalog.shared.product(productId) }
  /// nil when the saved execution no longer exists: the line needs clarification.
  var variant: CatalogVariant? { product?.variant(key: variantKey) }
  var needsClarification: Bool { variant == nil }
  /// Base (white) price × quantity, when the source has a price for the execution.
  var baseTotal: Int? { variant?.price.map { $0 * quantity } }
  var isCustomColour: Bool {
    if case .ral = colour { return true }
    return false
  }
  /// Complete only for a priced execution in its standard colour: a RAL surcharge is not
  /// published, so a coloured line is «базовая сумма + цвет по запросу», never a full total.
  var total: Int? { isCustomColour ? nil : baseTotal }
  var priceText: String {
    guard !needsClarification else { return "Исполнение требует уточнения" }
    guard let base = baseTotal else { return "Цена по запросу" }
    return isCustomColour ? "\(rubles(base)) + цвет по запросу" : rubles(base)
  }
  /// Only an article actually published on the card: the custom-colour «…F» code for RAL,
  /// otherwise the execution's own. Never the white article standing in for a colour.
  var sku: String? {
    guard let v = variant else { return nil }
    return isCustomColour ? v.customColourSku : v.sku
  }
}

struct SaliniProject: Codable, Hashable, Identifiable {
  var id = UUID().uuidString
  var name: String
  var client: String = ""
  var lines: [ProjectLine] = []
  var updated = Date()
  /// When a proposal PDF was last prepared on this device, and the project version it was built
  /// from (`updated` at that moment). Optional: projects saved before this field still decode.
  var proposalAt: Date?
  var proposalBasis: Date?
  /// A proposal exists and the project has not changed since it was prepared.
  var proposalIsCurrent: Bool {
    guard let basis = proposalBasis, proposalAt != nil else { return false }
    return updated <= basis
  }

  /// Sum of the base prices that are known (white executions; coloured lines at base price).
  var knownTotal: Int { lines.compactMap(\.baseTotal).reduce(0, +) }
  /// Lines whose final price is not known: no price, custom colour, or unresolved execution.
  var unpricedLines: Int { lines.filter { $0.total == nil }.count }
  var isTotalComplete: Bool { unpricedLines == 0 }
  var pieces: Int { lines.reduce(0) { $0 + $1.quantity } }
}

/// Local projects (Application Support). Migrates the prototype's UserDefaults project once.
final class ProjectStore {
  static let shared = ProjectStore()
  private let fileURL: URL
  private(set) var projects: [SaliniProject] = []
  /// Every public mutation is one transaction: exactly one save, so the backup always holds
  /// the version before that change.
  private var selectedId: String?
  var currentId: String? {
    get { selectedId }
    set {
      selectedId = newValue
      save()
    }
  }

  private(set) var recoveredFromBackup = false
  private(set) var quarantinedFile: URL?
  private var backupURL: URL { fileURL.deletingPathExtension().appendingPathExtension("backup.json") }

  init(fileURL: URL = ProjectStore.defaultURL, defaults: UserDefaults = .standard) {
    self.fileURL = fileURL
    let fm = FileManager.default
    if let state = ProjectStore.read(fileURL) {
      projects = state.projects
      selectedId = state.currentId
    } else if fm.fileExists(atPath: fileURL.path) {
      // Unreadable file: keep it aside untouched, then fall back to the last good backup.
      let quarantine = fileURL.deletingLastPathComponent().appendingPathComponent(
        "projects.unreadable-\(Int(Date().timeIntervalSince1970)).json")
      try? fm.copyItem(at: fileURL, to: quarantine)
      quarantinedFile = quarantine
      if let state = ProjectStore.read(backupURL) {
        projects = state.projects
        selectedId = state.currentId
        recoveredFromBackup = true
      }
    } else {
      projects = [ProjectStore.migrated(from: defaults)]
      selectedId = projects.first?.id
      save()
    }
    if projects.isEmpty {
      // Nothing readable: start a new project in memory; the quarantined file stays untouched.
      projects = [SaliniProject(name: "Мой проект")]
      selectedId = projects[0].id
    }
  }
  private static func read(_ url: URL) -> State? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(State.self, from: data)
  }
  private struct State: Codable {
    var projects: [SaliniProject]
    var currentId: String?
  }
  static var defaultURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Salini/projects.json")
  }
  /// Prototype items (aria/opera/greca/opera-top + S-Stone flag) become catalogue lines.
  static func migrated(from defaults: UserDefaults) -> SaliniProject {
    let name = defaults.string(forKey: "salini.projectName") ?? "Мой проект"
    var project = SaliniProject(name: name == "Моё пространство" ? "Мой проект" : name)
    let legacy =
      (defaults.data(forKey: "salini.items").flatMap { try? JSONDecoder().decode([ProjectItem].self, from: $0) }) ?? []
    for item in legacy {
      guard let old = Product.all.first(where: { $0.id == item.productId }),
        let match = Catalog.shared.product(for: old, stone: item.stone)
      else { continue }
      project.lines.append(
        ProjectLine(productId: match.0.id, variantKey: match.1?.key, quantity: max(1, item.quantity)))
    }
    return project
  }

  var current: SaliniProject {
    get { projects.first { $0.id == selectedId } ?? projects[0] }
    set {
      var p = newValue
      p.updated = Date()
      if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p } else { projects.append(p) }
      selectedId = p.id
      save()
    }
  }
  /// Adds `quantity` (must be positive) of one execution; zero/negative input is ignored.
  @discardableResult
  func add(_ product: CatalogProduct, variantKey: String?, quantity: Int = 1, colour: LineColour = .standard)
    -> ProjectLine?
  {
    guard quantity > 0, product.variant(key: variantKey) != nil else { return nil }
    var p = current
    if let i = p.lines.firstIndex(where: {
      $0.productId == product.id && $0.variantKey == variantKey && $0.colour == colour
    }) {
      p.lines[i].quantity += quantity
      current = p
      return p.lines[i]
    }
    let line = ProjectLine(productId: product.id, variantKey: variantKey, quantity: quantity, colour: colour)
    p.lines.append(line)
    current = p
    return line
  }
  func update(_ line: ProjectLine) {
    var p = current
    guard let i = p.lines.firstIndex(where: { $0.id == line.id }) else { return }
    if line.quantity <= 0 { p.lines.remove(at: i) } else { p.lines[i] = line }
    current = p
  }
  /// The proposal's lead item (cover photo and colour studies) is the project's first line.
  func makeMain(_ lineId: String) {
    var p = current
    guard let i = p.lines.firstIndex(where: { $0.id == lineId }), i > 0 else { return }
    p.lines.insert(p.lines.remove(at: i), at: 0)
    current = p
  }
  func remove(_ lineId: String) {
    var p = current
    p.lines.removeAll { $0.id == lineId }
    current = p
  }
  /// Records that a proposal was prepared from `basis` (the project's `updated` at that moment).
  /// Does not touch `updated` itself, so the proposal stays current until the project changes.
  func recordProposal(for projectId: String, basis: Date, at date: Date = Date()) {
    guard let i = projects.firstIndex(where: { $0.id == projectId }) else { return }
    projects[i].proposalAt = date
    projects[i].proposalBasis = basis
    save()
  }
  func newProject(name: String, client: String = "") {
    current = SaliniProject(name: name, client: client)
  }
  func delete(_ id: String) {
    projects.removeAll { $0.id == id }
    if projects.isEmpty { projects = [SaliniProject(name: "Мой проект")] }
    if selectedId == id { selectedId = projects[0].id }
    save()
  }
  func reset() {
    projects = [SaliniProject(name: "Мой проект")]
    selectedId = projects[0].id
    save()
  }
  private func save() {
    let state = State(projects: projects, currentId: selectedId)
    let fm = FileManager.default
    try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(state) else { return }
    // The previous readable version becomes the backup before the atomic replace.
    if ProjectStore.read(fileURL) != nil {
      try? fm.removeItem(at: backupURL)
      try? fm.copyItem(at: fileURL, to: backupURL)
    }
    try? data.write(to: fileURL, options: .atomic)
    NotificationCenter.default.post(name: .demoChanged, object: nil)
  }
}

extension CatalogVariant {
  /// Mineral-cast executions are painted to RAL Classic on request (Salini: 216 colours).
  var allowsRAL: Bool { customColourSku != nil || StudioFinish(material: material, finish: finish) != nil }
}

extension LineColour {
  var ral: RALColour? {
    if case .ral(let code) = self { return RALPalette.colour(code) }
    return nil
  }
  var displayColour: UIColor { ral?.colour ?? StudioScene.white }
  var longTitle: String { ral.map { "RAL \($0.code) · \($0.name)" } ?? title }
}

/// Colour choice for an execution: base white or a RAL Classic code (screen approximation).
func colourMenu(selected: LineColour, change: @escaping (LineColour) -> Void) -> UIMenu {
  let base = UIAction(title: "Базовый белый", state: selected == .standard ? .on : .off) { _ in change(.standard) }
  let codes = RALPalette.colours.map { c in
    UIAction(
      title: "RAL \(c.code)", subtitle: c.name,
      image: UIImage(systemName: "circle.fill")?.withTintColor(c.colour, renderingMode: .alwaysOriginal),
      state: selected == .ral(c.code) ? .on : .off
    ) { _ in change(.ral(c.code)) }
  }
  return UIMenu(title: "Цвет · экранное приближение RAL Classic", children: [
    base, UIMenu(title: "RAL Classic", options: .displayInline, children: codes),
  ])
}
