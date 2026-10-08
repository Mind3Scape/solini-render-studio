import SceneKit
let s = try! SCNScene(url: URL(fileURLWithPath: CommandLine.arguments[1]))
s.rootNode.enumerateHierarchy { n, _ in
  guard let g = n.geometry else { return }
  let uv = g.sources(for: .texcoord)
  print(n.name ?? "?", "texcoord sets:", uv.count, "verts", g.sources(for: .vertex).first?.vectorCount ?? 0,
        "material", g.firstMaterial?.name ?? "-", "model", g.firstMaterial?.lightingModel.rawValue ?? "-",
        "roughness", (g.firstMaterial?.roughness.contents as? NSNumber) ?? "tex/none")
}
