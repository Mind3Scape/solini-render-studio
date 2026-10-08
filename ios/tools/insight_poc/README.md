# «Участок отгрузки» — Insight graphics proof kit

Reproduces `ios/Salini/InsightAssets/` (bundled as a folder resource) from Blender 5.2.2:

```
blender -b --factory-startup --python ios/tools/insight_poc/build_atelier_kit.py -- \
    ios/Salini/InsightAssets --src tmp/insight-poc-source
```

Options:
- `--no-bake` skips AO and GI (seconds instead of minutes);
- `--samples N` (AO), `--gi-samples N` (GI, default 1024);
- `--size N` (atlas, default 2048);
- `--tree-keep R` (share of tree twigs kept).

## What it builds
- `atelier_kit.usdc`:
  - `Static` holds the architecture, the yard and the downloaded props joined in, including the
    Salini Ninfea 02 basins.
  - The movable parts: `Forklift` (`Forklift_Body` + `Forklift_Carriage`), `Truck` and `Batch`.
  - `Tree` is a prototype. The app instances it at `anchor_tree_*`.
  - `anchor_*` Xforms are the only source of positions for the demo logic, the catalogue
    products (`anchor_product_<file>`) and the night lights.
- Lighting. The light model is:
  - **day** = sky (direct + indirect) + sun (indirect only) in the lightmap; the sun's direct
    light and shadows are real-time;
  - **night** = dim tinted sky + static lamps (direct + indirect) in the lightmap; real-time
    spots light only the movers (`categoryBitMask` 2);
  - specular stays live from the HDRI. The HDRI sun disc is clamped in both the bake and the
    app, because the real-time sun replaces it.

  Files:
  - `atelier_gi_day.png` and `atelier_gi_night.png` hold the baked **irradiance** on the
    second UV set «Lightmap». They are 8-bit with gamma 2.2 over 0…4, linear after decoding.
  - The app puts them in SceneKit's `selfIllumination`, which replaces only the diffuse IBL.
    Measured: specular IBL is unchanged, and the AO map does not multiply it. Nothing is lit
    twice.
  - `atelier_ao.png` is ambient occlusion on the same UVs. With selfIllumination it only
    occludes specular IBL.
- `textures/` holds the resized Poly Haven maps, always 8-bit RGB.
- `atelier_materials.json` holds:
  - material → texture maps;
  - the list of lightmapped materials;
  - the GI encoding.
- `factory_yard_1k.hdr` is the image-based light.
- `ASSETS.json` is the manifest of exactly what ships:
  - CC0 sources with URL, authors and sha256;
  - the Salini Ninfea 02 basin as a separate «rights retained» entry (not CC0).

## Sources
- Downloads stay in `tmp/insight-poc-source/`, not in Git:
  - Poly Haven: props, `tree_small_02`, ground textures, HDRI;
  - 3dassets.dev: the forklift and the seated driver;
  - Salini: Ninfea 02.
- The full download catalogue is `research/insight-poc-2026-10-08/downloaded-assets.json`.
- Catalogue bathtubs (Alda, Mona, Luce, Noemi, Sofia 150) are loaded at runtime from
  `CatalogMedia/models`. SceneKit reads them in millimetres; the app rescales each one and
  checks it against its catalogue length.

## QA launch arguments
- `-shipping-atelier` opens Profile → Salini Inside → «Отгрузка» directly. Projects and settings
  are untouched.
- Add `-shipping-atelier-night` to start at night.
