import Accelerate
import CoreGraphics
import Foundation
import simd

/// Linear HDR radiance decoded from a Radiance `.hdr` (RGBE) file: real, unclipped light values,
/// not an 8-bit picture of a studio. Pixels are RGB, rows top to bottom.
struct RadianceImage {
  let width: Int
  let height: Int
  private(set) var pixels: [Float]

  init(width: Int, height: Int, pixels: [Float]) {
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// Parses the header, the resolution line and run-length or flat scanlines. Hot loops work on
  /// raw buffers so even a debug build decodes the 2K studio in a fraction of a second.
  init?(data: Data) {
    var header = 0
    var lines: [String] = []
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      // Header lines up to and including the resolution line (after the empty line).
      var start = 0
      var sawEmpty = false
      for k in 0..<min(raw.count, 4096) where raw[k] == 0x0A {
        let text = String(decoding: UnsafeRawBufferPointer(rebasing: raw[start..<k]), as: UTF8.self)
        lines.append(text)
        start = k + 1
        if sawEmpty {
          header = start
          return
        }
        if text.isEmpty { sawEmpty = true }
      }
    }
    guard header > 0, let magic = lines.first, magic.hasPrefix("#?"), let resolution = lines.last else { return nil }
    let format = lines.first { $0.hasPrefix("FORMAT=") }.map { String($0.dropFirst(7)) } ?? ""
    guard format.isEmpty || format == "32-bit_rle_rgbe" else { return nil }
    let parts = resolution.split(separator: " ")
    guard parts.count == 4, parts[0] == "-Y", parts[2] == "+X", let h = Int(parts[1]), let w = Int(parts[3]),
      w > 0, h > 0, w * h <= 16_777_216
    else { return nil }
    var out = [Float](repeating: 0, count: w * h * 3)
    let ok: Bool = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
      let n = raw.count
      guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
      let rgbe = UnsafeMutablePointer<UInt8>.allocate(capacity: w * 4)
      defer { rgbe.deallocate() }
      let scales = (0..<256).map { ldexpf(1, Int32($0) - 136) }
      return out.withUnsafeMutableBufferPointer { dst -> Bool in
        var i = header
        for y in 0..<h {
          // New-style RLE: 2, 2, width (big endian), then each of the four channels separately.
          if w >= 8, w < 32768, i + 4 <= n, bytes[i] == 2, bytes[i + 1] == 2, bytes[i + 2] & 0x80 == 0 {
            guard Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) == w else { return false }
            i += 4
            for c in 0..<4 {
              var x = 0
              while x < w {
                guard i < n else { return false }
                var count = Int(bytes[i])
                i += 1
                if count > 128 {
                  count -= 128
                  guard count <= w - x, i < n else { return false }
                  let v = bytes[i]
                  i += 1
                  var k = 0
                  while k < count { rgbe[(x + k) * 4 + c] = v; k += 1 }
                } else {
                  guard count > 0, count <= w - x, i + count <= n else { return false }
                  var k = 0
                  while k < count { rgbe[(x + k) * 4 + c] = bytes[i + k]; k += 1 }
                  i += count
                }
                x += count
              }
            }
          } else {
            // Flat scanline.
            guard i + w * 4 <= n else { return false }
            rgbe.update(from: bytes + i, count: w * 4)
            i += w * 4
          }
          let row = dst.baseAddress! + y * w * 3
          var x = 0
          while x < w {
            let e = rgbe[x * 4 + 3]
            if e != 0 {
              let f = scales[Int(e)]
              row[x * 3] = Float(rgbe[x * 4]) * f
              row[x * 3 + 1] = Float(rgbe[x * 4 + 1]) * f
              row[x * 3 + 2] = Float(rgbe[x * 4 + 2]) * f
            }
            x += 1
          }
        }
        return true
      }
    }
    guard ok else { return nil }
    self.init(width: w, height: h, pixels: out)
  }

  func luminance(_ x: Int, _ y: Int) -> Float {
    let o = (y * width + x) * 3
    return 0.2126 * pixels[o] + 0.7152 * pixels[o + 1] + 0.0722 * pixels[o + 2]
  }
  /// Solid-angle weighted mean luminance of the sphere (equirectangular rows shrink to the poles).
  var meanLuminance: Float {
    pixels.withUnsafeBufferPointer { p in
      var sum: Float = 0
      var weight: Float = 0
      for y in 0..<height {
        let w = cos((Float(y) + 0.5) / Float(height) * .pi - .pi / 2)
        var row: Float = 0
        for o in stride(from: y * width * 3, to: (y + 1) * width * 3, by: 3) {
          row += 0.2126 * p[o] + 0.7152 * p[o + 1] + 0.0722 * p[o + 2]
        }
        sum += row * w
        weight += w * Float(width)
      }
      return sum / max(weight, 1e-6)
    }
  }
  var peakLuminance: Float {
    pixels.withUnsafeBufferPointer { p in
      var peak: Float = 0
      for o in stride(from: 0, to: p.count, by: 3) { peak = max(peak, 0.2126 * p[o] + 0.7152 * p[o + 1] + 0.0722 * p[o + 2]) }
      return peak
    }
  }
  /// Rows below the horizon scaled by `factor`, blended over ±4° so no seam reflects.
  mutating func darkenFloor(_ factor: Float) {
    let (w, h) = (width, height)
    pixels.withUnsafeMutableBufferPointer { p in
      for y in 0..<h {
        let elevation = 90 - (Float(y) + 0.5) / Float(h) * 180
        let t = min(1, max(0, (4 - elevation) / 8))
        let k = 1 - t * (1 - factor)
        guard k < 1 else { continue }
        let row = p.baseAddress! + y * w * 3
        vDSP_vsmul(row, 1, [k], row, 1, vDSP_Length(w * 3))
      }
    }
  }
  /// Everything darker than `threshold` scaled by `room` (smooth over one stop): flags on walls.
  mutating func flag(room: Float, lightsAbove threshold: Float) {
    guard room < 1 else { return }
    pixels.withUnsafeMutableBufferPointer { p in
      for o in stride(from: 0, to: p.count, by: 3) {
        let l = 0.2126 * p[o] + 0.7152 * p[o + 1] + 0.0722 * p[o + 2]
        let t = min(1, max(0, (l - threshold * 0.5) / (threshold * 0.5)))
        let k = room + (1 - room) * t
        p[o] *= k
        p[o + 1] *= k
        p[o + 2] *= k
      }
    }
  }
  /// The panorama turned about the vertical axis (whole columns, so nothing is resampled).
  mutating func rotate(byDegrees degrees: Float) {
    let shift = ((Int((degrees / 360 * Float(width)).rounded()) % width) + width) % width
    guard shift != 0 else { return }
    let (w, h) = (width, height)
    var out = [Float](repeating: 0, count: pixels.count)
    pixels.withUnsafeBufferPointer { src in
      out.withUnsafeMutableBufferPointer { dst in
        // Destination column x takes source column x − shift.
        for y in 0..<h {
          let s = src.baseAddress! + y * w * 3, d = dst.baseAddress! + y * w * 3
          (d + shift * 3).update(from: s, count: (w - shift) * 3)
          d.update(from: s + (w - shift) * 3, count: shift * 3)
        }
      }
    }
    pixels = out
  }
  /// A photographer's additions to the real room: rectangular emitters in HDR radiance (× the
  /// HDRI's mean), soft-edged so their reflections end in a gradient, not a jagged line.
  struct Card: Equatable {
    var azimuth: Float  // degrees, image u × 360
    var elevation: Float  // degrees above the horizon (centre)
    var width: Float  // degrees of azimuth
    var height: Float  // degrees of elevation
    var radiance: Float  // × mean luminance
    var warmth: Float = 0  // −1 cool … +1 warm
    var soft: Float = 1.5  // edge falloff, degrees
  }
  mutating func add(_ cards: [Card], mean: Float) {
    let (w, h) = (width, height)
    pixels.withUnsafeMutableBufferPointer { p in
      for card in cards {
        let tint = SIMD3<Float>(1 + 0.06 * card.warmth, 1, 1 - 0.08 * card.warmth)
        for y in 0..<h {
          let elevation = 90 - (Float(y) + 0.5) / Float(h) * 180
          let dy = abs(elevation - card.elevation) - card.height / 2
          let wy = 1 - min(1, max(0, dy / card.soft + 0.5))
          guard wy > 0 else { continue }
          // Only the columns the card can reach (its width plus the soft edge, wrapping at 360°).
          let reach = card.width / 2 + card.soft
          let span = reach >= 180 ? w : Int((reach * 2 / 360 * Float(w)).rounded(.up)) + 2
          let first = Int(((card.azimuth - reach) / 360 * Float(w)).rounded(.down))
          for step in 0..<min(span, w) {
            let x = ((first + step) % w + w) % w
            var da = abs((Float(x) + 0.5) / Float(w) * 360 - card.azimuth)
            da = min(da, 360 - da)
            let dx = da - card.width / 2
            let wx = 1 - min(1, max(0, dx / card.soft + 0.5))
            guard wx > 0 else { continue }
            let o = (y * w + x) * 3
            let l = card.radiance * mean * wx * wy
            p[o] += l * tint.x
            p[o + 1] += l * tint.y
            p[o + 2] += l * tint.z
          }
        }
      }
    }
  }
  /// A smaller copy (box filter), e.g. for analysis.
  func downsampled(by factor: Int) -> RadianceImage {
    let w = width / factor, h = height / factor
    var out = [Float](repeating: 0, count: w * h * 3)
    let n = Float(factor * factor)
    for y in 0..<h {
      for x in 0..<w {
        for c in 0..<3 {
          var s: Float = 0
          for dy in 0..<factor { for dx in 0..<factor { s += pixels[((y * factor + dy) * width + x * factor + dx) * 3 + c] } }
          out[(y * w + x) * 3 + c] = s / n
        }
      }
    }
    return RadianceImage(width: w, height: h, pixels: out)
  }
  /// Half-float, extended linear sRGB image for SceneKit: values above 1 are kept.
  func cgImage(scale: Float = 1) -> CGImage? {
    let count = width * height
    // RGB → RGBX (scaled, X = 1), then one vectorised float → half conversion.
    var rgbx = [Float](repeating: 1, count: count * 4)
    pixels.withUnsafeBufferPointer { src in
      rgbx.withUnsafeMutableBufferPointer { dst in
        for c in 0..<3 {
          vDSP_vsmul(src.baseAddress! + c, 3, [scale], dst.baseAddress! + c, 4, vDSP_Length(count))
        }
        vDSP_vclip(dst.baseAddress!, 1, [-60000], [60000], dst.baseAddress!, 1, vDSP_Length(count * 4))
      }
    }
    var half = [UInt16](repeating: 0, count: count * 4)
    let converted: Bool = rgbx.withUnsafeMutableBufferPointer { s in
      half.withUnsafeMutableBufferPointer { d in
        var source = vImage_Buffer(data: s.baseAddress, height: 1, width: vImagePixelCount(count * 4), rowBytes: count * 16)
        var target = vImage_Buffer(data: d.baseAddress, height: 1, width: vImagePixelCount(count * 4), rowBytes: count * 8)
        return vImageConvert_PlanarFtoPlanar16F(&source, &target, vImage_Flags(kvImageNoFlags)) == kvImageNoError
      }
    }
    guard converted else { return nil }
    let data = half.withUnsafeBufferPointer { Data(buffer: $0) }
    guard let provider = CGDataProvider(data: data as CFData),
      let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    else { return nil }
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue
      | CGBitmapInfo.byteOrder16Little.rawValue)
    return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
                   space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)
  }
}

/// The studio's light: Poly Haven «Studio Small 09» (Sergej Majboroda, CC0), a real unclipped
/// HDRI, normalised so its mean luminance is 1. Loaded once, off the main thread, and shared.
enum StudioHDRI {
  static let resource = "studio_small_09_2k"
  static let attribution = "Studio Small 09 — Sergej Majboroda, Poly Haven (CC0)"
  static var url: URL? { Bundle.main.url(forResource: resource, withExtension: "hdr") ?? overrideURL }
  /// Tuning harness on macOS (no app bundle) points this at the repository file.
  static var overrideURL: URL?

  struct Loaded {
    let image: CGImage
    let width: Int
    let height: Int
    /// Mean and peak luminance before normalisation (the HDR range that survived loading).
    let sourceMean: Float
    let sourcePeak: Float
  }
  /// Our floor is dark microcement, the HDRI's is a white cyclorama: below the horizon the light
  /// is scaled to what a dark floor would bounce, or the white floor fills every form from below.
  static let groundFactor: Float = 0.12
  /// The room turned so that, at the studio's default light position, the main octabox lights
  /// the form from the camera's left (≈ 70° off the view) instead of from behind.
  static var azimuthShift: Float = -48
  /// Black flags around the set: the room's walls (below 4× mean) are dimmed to this share so the
  /// key models the form; the lights themselves keep their full measured radiance.
  static var roomFactor: Float = 0.45
  /// Image azimuth of the main octabox after the shift (measured in the file at u ≈ 0.6).
  static var keyAzimuth: Float { 216 + azimuthShift }
  static let keyElevation: Float = 25
  /// Strip softboxes and a low reflector added to the room (image azimuths; the studio's light
  /// control rotates them with the HDRI). Tuned on the A/B harness.
  static var cards: [RadianceImage.Card] = [
    // Broad, dim floor bounce card in front of the set: the flared outer wall faces down and mirrors
    // it as one long soft gradient (gloss); dim enough that a white wall keeps its shading.
    RadianceImage.Card(azimuth: 98, elevation: -50, width: 140, height: 22, radiance: 0.8, soft: 10),
    // Two tall strip boxes standing beside the bath, either side of the camera: crisp vertical
    // streaks on Gelcoat gloss, warm on the key side, cool on the other.
    RadianceImage.Card(azimuth: 53, elevation: -8, width: 4, height: 90, radiance: 5, warmth: 0.3),
    RadianceImage.Card(azimuth: 143, elevation: -8, width: 3, height: 90, radiance: 3.5, warmth: -0.2),
    // Cool rim strip behind the form and a soft top box over the camera for the bowl and rim.
    RadianceImage.Card(azimuth: 276, elevation: 35, width: 6, height: 40, radiance: 6, warmth: -0.3),
    RadianceImage.Card(azimuth: 98, elevation: 45, width: 16, height: 28, radiance: 1.5, warmth: 0.2, soft: 6),
  ]
  private static let lock = NSLock()
  private static var cached: Loaded?
  private static var failed = false
  /// Decodes on first use; later calls return the same image. Nil only if the file is missing or
  /// broken — the studio then falls back to its procedural environment.
  static func shared() -> Loaded? {
    lock.lock()
    defer { lock.unlock() }
    if let cached { return cached }
    guard !failed, let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
      var hdr = RadianceImage(data: data)
    else {
      failed = true
      return nil
    }
    let mean = hdr.meanLuminance
    let peak = hdr.peakLuminance
    guard mean.isFinite, mean > 0 else {
      failed = true
      return nil
    }
    hdr.rotate(byDegrees: azimuthShift)
    hdr.flag(room: roomFactor, lightsAbove: 4 * mean)
    hdr.darkenFloor(groundFactor)
    hdr.add(cards, mean: mean)
    guard let image = hdr.cgImage(scale: 1 / mean) else {
      failed = true
      return nil
    }
    let loaded = Loaded(image: image, width: hdr.width, height: hdr.height, sourceMean: mean, sourcePeak: peak)
    cached = loaded
    return loaded
  }
}

#if canImport(Metal)
  import Metal
  import SceneKit

  /// The studio's own tone mapping: the scene is drawn into a half-float target and mapped once
  /// with Khronos PBR Neutral, which keeps a product's base colour (RAL hue and saturation) and
  /// only rolls off true highlights. Exposure is in stops.
  ///
  /// `pbrNeutral` is ported to Metal from KhronosGroup/ToneMapping `PBR_Neutral/pbrNeutral.glsl`
  /// (Copyright 2024 The Khronos Group, Inc., Apache-2.0); algorithm and constants unchanged.
  /// Notice and licence text ship in `Resources/third-party-notices.txt`.
  enum StudioToneMapping {
    /// Exposure is compiled in: technique symbols did not reach Metal quad passes (measured).
    static func source(exposure: Float) -> String {
      String(format: "#define SALINI_EXPOSURE_SCALE %.6f\n", exp2(exposure)) + body
    }
    private static let body = """
      #include <metal_stdlib>
      using namespace metal;
      struct QuadIn { float4 position [[attribute(0)]]; };
      struct QuadOut { float4 position [[position]]; float2 uv; };
      vertex QuadOut salini_quad(QuadIn in [[stage_in]]) {
        QuadOut o;
        o.position = in.position;
        o.uv = float2(in.position.x * 0.5 + 0.5, 0.5 - in.position.y * 0.5);
        return o;
      }
      // Khronos PBR Neutral (Apache-2.0, Copyright 2024 The Khronos Group, Inc.), ported from GLSL.
      static float3 pbrNeutral(float3 c) {
        const float start = 0.8 - 0.04;
        const float desaturation = 0.15;
        float x = min(c.r, min(c.g, c.b));
        float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
        c -= offset;
        float peak = max(c.r, max(c.g, c.b));
        if (peak < start) return c;
        const float d = 1.0 - start;
        float newPeak = 1.0 - d * d / (peak + d - start);
        c *= newPeak / peak;
        float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
        return mix(c, float3(newPeak), g);
      }
      fragment half4 salini_tonemap(QuadOut in [[stage_in]],
                                    texture2d<float, access::sample> hdrColor [[texture(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
        float4 c = hdrColor.sample(s, in.uv);
        float3 mapped = pbrNeutral(max(c.rgb, 0.0) * SALINI_EXPOSURE_SCALE);
        // Triangular dither of about one 8-bit step (in display space): smooth floor gradients
        // and soft shadows without bands.
        float2 p = in.position.xy;
        float n = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453)
                + fract(sin(dot(p, float2(39.3468, 11.1351))) * 24634.6345) - 1.0;
        float3 display = pow(clamp(mapped, 0.0, 1.0), float3(1.0 / 2.2)) + n / 255.0;
        mapped = pow(clamp(display, 0.0, 1.0), float3(2.2));
        return half4(half3(mapped), half(c.a));
      }
      """
    private static let lock = NSLock()
    private static var libraries: [Float: MTLLibrary] = [:]
    /// Compiled once per exposure and process (off the main thread, with the scene), then reused.
    static func makeLibrary(exposure: Float, device: MTLDevice?) -> MTLLibrary? {
      lock.lock()
      defer { lock.unlock() }
      if let library = libraries[exposure] { return library }
      guard let device = device ?? MTLCreateSystemDefaultDevice() else { return nil }
      let library: MTLLibrary
      do {
        library = try device.makeLibrary(source: source(exposure: exposure), options: nil)
      } catch {
        // A broken pass must be loud in development: without it the studio shows untone-mapped HDR.
        assertionFailure("Studio tone mapping failed to compile: \(error)")
        return nil
      }
      libraries[exposure] = library
      return library
    }
    static func technique(exposure: Float, device: MTLDevice? = nil) -> SCNTechnique? {
      guard let library = makeLibrary(exposure: exposure, device: device) else { return nil }
      let description: [String: Any] = [
        "passes": [
          "scene": [
            "draw": "DRAW_SCENE",
            "outputs": ["color": "hdrColor"],
            "colorStates": ["clear": true, "clearColor": "sceneBackground"],
          ],
          "tonemap": [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "salini_quad",
            "metalFragmentShader": "salini_tonemap",
            "inputs": ["hdrColor": "hdrColor"],
            "outputs": ["color": "COLOR"],
          ],
        ],
        "sequence": ["scene", "tonemap"],
        "targets": [
          "hdrColor": ["type": "color", "format": "rgba16f"],
        ],
      ]
      guard let technique = SCNTechnique(dictionary: description) else { return nil }
      technique.library = library
      return technique
    }
  }
#endif

/// Procedural micro-structure for the studio surfaces (SceneKit surface shader modifier, Metal).
///
/// Coordinates are the model's own units (official USDZ are in millimetres), so sizes are real.
/// Bump is height-field based with screen derivatives (Mikkelsen's surface gradient): no UVs,
/// no seams. Each octave fades out when its wavelength gets close to the pixel footprint; the
/// slope it can no longer show is added to roughness (and the same for the Gelcoat lobe), and a
/// normal-variance term keeps thin rims from flickering (specular anti-aliasing).
enum StudioMicro {
  static let surfaceModifier = """
    #pragma arguments
    float grainSize;
    float grainSlope;
    float peelSize;
    float peelSlope;
    float waveSize;
    float waveSlope;
    float mottleSize;
    float mottleRoughness;
    float grazing;
    float hasCoat;

    #pragma declaration
    static float salini_hash(float3 p) {
      p = fract(p * 0.1031);
      p += dot(p, p.zyx + 31.32);
      return fract((p.x + p.y) * p.z);
    }
    static float salini_noise(float3 x) {
      float3 i = floor(x);
      float3 f = fract(x);
      f = f * f * (3.0 - 2.0 * f);
      float a = mix(salini_hash(i), salini_hash(i + float3(1, 0, 0)), f.x);
      float b = mix(salini_hash(i + float3(0, 1, 0)), salini_hash(i + float3(1, 1, 0)), f.x);
      float c = mix(salini_hash(i + float3(0, 0, 1)), salini_hash(i + float3(1, 0, 1)), f.x);
      float d = mix(salini_hash(i + float3(0, 1, 1)), salini_hash(i + float3(1, 1, 1)), f.x);
      return mix(mix(a, b, f.y), mix(c, d, f.y), f.z) * 2.0 - 1.0;
    }
    /// Two octaves of a height field with wavelength `size` (mm) and the given slope; octaves
    /// thinner than ~2.5 px fade out. Returns height (view units) and the slope² that faded.
    static float2 salini_field(float3 p, float size, float slope, float footprint, float viewPerMM) {
      if (size <= 0.0 || slope <= 0.0) return float2(0.0);
      float h = 0.0;
      float lost = 0.0;
      float wavelength = size;
      float amplitude = slope * size / 6.2831853;
      for (int o = 0; o < 2; o++) {
        float keep = saturate(wavelength / (footprint * 2.5) - 1.0);
        h += salini_noise(p / wavelength + float(o) * 17.0) * amplitude * keep;
        lost += (1.0 - keep) * slope * slope;
        wavelength *= 0.47;
        amplitude *= 0.47;
      }
      return float2(h * viewPerMM, lost);
    }
    /// Normal perturbed by a height field via screen-space derivatives.
    static float3 salini_bump(float3 n, float3 position, float h) {
      float3 dpdx = dfdx(position);
      float3 dpdy = dfdy(position);
      float3 r1 = cross(dpdy, n);
      float3 r2 = cross(n, dpdx);
      float det = dot(dpdx, r1);
      float3 g = sign(det) * (dfdx(h) * r1 + dfdy(h) * r2);
      return normalize(abs(det) * n - g);
    }
    static float salini_filtered(float roughness, float3 n, float lost) {
      float3 dx = dfdx(n);
      float3 dy = dfdy(n);
      float variance = 0.25 * (dot(dx, dx) + dot(dy, dy));
      float a = roughness * roughness;
      float a2 = a * a + min(2.0 * variance, 0.18) + 2.0 * lost;
      return sqrt(sqrt(saturate(a2)));
    }

    #pragma body
    float3 p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
    float footprint = max(length(dfdx(p)), length(dfdy(p))) + 1e-5;
    float viewPerMM = length((scn_node.modelViewTransform * float4(1.0, 0.0, 0.0, 0.0)).xyz);
    float mottle = mottleSize > 0.0
      ? (salini_noise(p / mottleSize) * 0.7 + salini_noise(p / (mottleSize * 0.43) + 5.0) * 0.3) * mottleRoughness
      : 0.0;
    float3 smoothNormal = _surface.normal;
    if (hasCoat > 0.5) {
      // Body: smooth under the Gelcoat. Gelcoat: grain (matte) or orange peel and waviness (gloss).
      float2 fine = salini_field(p, grainSize, grainSlope, footprint, viewPerMM);
      float2 peel = salini_field(p, peelSize, peelSlope, footprint, viewPerMM);
      float2 wave = salini_field(p, waveSize, waveSlope, footprint, viewPerMM);
      float3 coatNormal = salini_bump(smoothNormal, _surface.position, fine.x + peel.x + wave.x);
      _surface.clearCoatNormal = coatNormal;
      _surface.clearCoatRoughness = salini_filtered(max(0.02, _surface.clearCoatRoughness + mottle), coatNormal,
                                                    fine.y + peel.y + wave.y);
      _surface.roughness = salini_filtered(_surface.roughness, smoothNormal, 0.0);
    } else {
      float2 fine = salini_field(p, grainSize, grainSlope, footprint, viewPerMM);
      float3 n = salini_bump(smoothNormal, _surface.position, fine.x);
      _surface.normal = n;
      _surface.roughness = salini_filtered(saturate(_surface.roughness + mottle), n, fine.y);
    }
    if (grazing > 0.0) {
      float facing = saturate(dot(smoothNormal, normalize(_surface.view)));
      _surface.diffuse.rgb *= 1.0 + grazing * pow(1.0 - facing, 4.0);
    }
    """
}

extension StudioMicro {
  /// Restrained microcement for the cyclorama: soft cloudy value and roughness variation in
  /// scene units (≈ metres), nothing that competes with the product.
  static let floorModifier = """
    #pragma declaration
    static float salini_fhash(float3 p) {
      p = fract(p * 0.1031);
      p += dot(p, p.zyx + 31.32);
      return fract((p.x + p.y) * p.z);
    }
    static float salini_fnoise(float3 x) {
      float3 i = floor(x);
      float3 f = fract(x);
      f = f * f * (3.0 - 2.0 * f);
      float a = mix(salini_fhash(i), salini_fhash(i + float3(1, 0, 0)), f.x);
      float b = mix(salini_fhash(i + float3(0, 1, 0)), salini_fhash(i + float3(1, 1, 0)), f.x);
      float c = mix(salini_fhash(i + float3(0, 0, 1)), salini_fhash(i + float3(1, 0, 1)), f.x);
      float d = mix(salini_fhash(i + float3(0, 1, 1)), salini_fhash(i + float3(1, 1, 1)), f.x);
      return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
    }

    #pragma body
    float3 w = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float footprint = max(length(dfdx(w)), length(dfdy(w))) + 1e-5;
    float cloud = salini_fnoise(w * 1.7) * 0.6 + salini_fnoise(w * 4.3 + 3.0) * 0.4;
    float fine = salini_fnoise(w * 38.0 + 7.0) * saturate(0.026 / (footprint * 2.5) - 1.0);
    _surface.diffuse.rgb *= 0.86 + 0.22 * cloud + 0.06 * (fine - 0.5);
    _surface.roughness = saturate(_surface.roughness + 0.08 * (cloud - 0.5));
    """
}
