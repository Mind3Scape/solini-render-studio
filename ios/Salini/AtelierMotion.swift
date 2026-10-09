import simd

/// Forklift kinematics for the shipping demonstration: paths on the ground plane (x, z) driven
/// with a physical speed profile. A counterbalance forklift steers with its rear wheels, so the
/// front (drive) axle centre is the point that never slides sideways: paths are laid for that
/// point, the heading is the path tangent and the rear steering angle follows the curvature.
struct AtelierPath {
  /// A turn from `a` (travelling along `da`) to `b` (arriving along `db`): a quintic Bézier with
  /// zero curvature at both ends; `reach` sets how far the turn swings out.
  static func turn(_ a: SIMD2<Float>, _ da: SIMD2<Float>, _ b: SIMD2<Float>, _ db: SIMD2<Float>, reach: Float) -> Piece {
    .bezier([a, a + da * reach * 0.5, a + da * reach, b - db * reach, b - db * reach * 0.5, b])
  }

  enum Piece {
    case line(SIMD2<Float>, SIMD2<Float>)
    /// Bézier of any degree (de Casteljau). A quintic whose first and last three control points
    /// are collinear with the end tangents starts and ends with zero curvature, so it joins
    /// straight lines without a steering jump.
    case bezier([SIMD2<Float>])
  }

  struct Sample {
    var point: SIMD2<Float>
    var tangent: SIMD2<Float>
    /// Signed curvature (1/m), positive when turning left (heading increasing).
    var curvature: Float
  }

  private(set) var s: [Float] = []
  private(set) var samples: [Sample] = []
  var length: Float { s.last ?? 0 }

  init(_ pieces: [Piece], step: Float = 0.01) {
    var points: [SIMD2<Float>] = []
    for piece in pieces {
      switch piece {
      case .line(let a, let b):
        let n = max(1, Int((simd_distance(a, b) / step).rounded(.up)))
        for k in 0...n where !(k == 0 && !points.isEmpty) { points.append(a + (b - a) * Float(k) / Float(n)) }
      case .bezier(let control):
        let n = 3000
        for k in 0...n where !(k == 0 && !points.isEmpty) {
          let u = Float(k) / Float(n)
          var c = control
          while c.count > 1 { c = (0..<(c.count - 1)).map { c[$0] + (c[$0 + 1] - c[$0]) * u } }
          points.append(c[0])
        }
      }
    }
    // Arclength, tangents and curvature from the dense polyline.
    var acc: Float = 0
    for (i, p) in points.enumerated() {
      if i > 0 { acc += simd_distance(points[i - 1], p) }
      s.append(acc)
    }
    for i in points.indices {
      let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
      let t = simd_normalize(b - a)
      samples.append(Sample(point: points[i], tangent: t, curvature: 0))
    }
    // Curvature over a ±5 cm window (smooth; the polyline is dense).
    for i in points.indices {
      var j0 = i, j1 = i
      while j0 > 0 && s[i] - s[j0] < 0.05 { j0 -= 1 }
      while j1 < points.count - 1 && s[j1] - s[i] < 0.05 { j1 += 1 }
      let ds = s[j1] - s[j0]
      guard ds > 1e-4 else { continue }
      let ta = samples[j0].tangent, tb = samples[j1].tangent
      // heading h = atan2(-t.z, t.x): left turn = h increasing.
      var dh = atan2(-tb.y, tb.x) - atan2(-ta.y, ta.x)
      while dh > .pi { dh -= 2 * .pi }
      while dh < -.pi { dh += 2 * .pi }
      samples[i].curvature = dh / ds
    }
  }

  func sample(at distance: Float) -> Sample {
    let d = min(max(distance, 0), length)
    var lo = 0, hi = s.count - 1
    while hi - lo > 1 {
      let mid = (lo + hi) / 2
      if s[mid] <= d { lo = mid } else { hi = mid }
    }
    let span = s[hi] - s[lo]
    let u = span > 0 ? (d - s[lo]) / span : 0
    let a = samples[lo], b = samples[hi]
    return Sample(point: a.point + (b.point - a.point) * u, tangent: simd_normalize(a.tangent + (b.tangent - a.tangent) * u),
                  curvature: a.curvature + (b.curvature - a.curvature) * u)
  }
}

/// One drive along a path, forwards or in reverse, with a speed profile: constant acceleration
/// and braking, a cruise speed, lateral-acceleration limits in curves and slow zones (forks
/// entering a pallet, the dock and the trailer). The natural profile is scaled uniformly to fit
/// its time window, so the shape (and the physics' proportions) is kept.
struct AtelierDrive {
  struct Zone {
    var range: ClosedRange<Float>
    var speed: Float
  }

  /// How a profile shorter than its window sits in it (a longer one is always fitted).
  enum Align { case fit, start, end }

  let path: AtelierPath
  let reverse: Bool
  /// The interval the vehicle actually moves in.
  private(set) var start: Double
  private(set) var end: Double
  private var times: [Double] = []
  /// Natural duration of the profile before fitting into the window (seconds).
  private(set) var natural: Double = 0

  init(_ path: AtelierPath, reverse: Bool = false, from start: Double, to end: Double, cruise: Float,
       acceleration: Float = 0.7, lateral: Float = 0.5, zones: [Zone] = [], align: Align = .fit,
       wheelbase: Float = 1.25, steerRate: Float = 1.5)
  {
    self.path = path
    self.reverse = reverse
    self.start = start
    self.end = end
    let n = path.s.count
    var v = [Float](repeating: cruise, count: n)
    for i in 0..<n {
      let k = abs(path.samples[i].curvature)
      if k > 1e-3 { v[i] = min(v[i], (lateral / k).squareRoot()) }
      for z in zones where z.range.contains(path.s[i]) { v[i] = min(v[i], z.speed) }
    }
    // The steering wheel turns at most `steerRate` (rad/s): slower where the curvature changes.
    let angle = path.samples.map { atan(wheelbase * $0.curvature) }
    for i in 1..<(n - 1) {
      let ds = path.s[i + 1] - path.s[i - 1]
      let rate = abs(angle[i + 1] - angle[i - 1]) / max(ds, 1e-4)
      if rate > 1e-3 { v[i] = min(v[i], steerRate / rate) }
    }
    v[0] = 0
    v[n - 1] = 0
    for i in 1..<n {                                           // accelerate
      let ds = path.s[i] - path.s[i - 1]
      v[i] = min(v[i], (v[i - 1] * v[i - 1] + 2 * acceleration * ds).squareRoot())
    }
    for i in stride(from: n - 2, through: 0, by: -1) {         // brake
      let ds = path.s[i + 1] - path.s[i]
      v[i] = min(v[i], (v[i + 1] * v[i + 1] + 2 * acceleration * ds).squareRoot())
    }
    var t: Double = 0
    times = [0]
    for i in 1..<n {
      let ds = Double(path.s[i] - path.s[i - 1])
      let mean = Double(v[i - 1] + v[i]) / 2
      t += mean > 1e-6 ? ds / mean : 0
      times.append(t)
    }
    natural = t
    if t < end - start {
      switch align {
      case .fit: break
      case .start: self.end = start + t
      case .end: self.start = end - t
      }
    }
  }

  /// Distance driven along the path at a time (clamped to the window).
  func distance(at time: Double) -> Float {
    guard natural > 0 else { return 0 }
    let u = min(max((time - start) / (end - start), 0), 1) * natural
    var lo = 0, hi = times.count - 1
    while hi - lo > 1 {
      let mid = (lo + hi) / 2
      if times[mid] <= u { lo = mid } else { hi = mid }
    }
    let span = times[hi] - times[lo]
    let f = span > 0 ? Float((u - times[lo]) / span) : 0
    return path.s[lo] + (path.s[hi] - path.s[lo]) * f
  }

  /// Signed speed (m/s, negative in reverse) by a central difference.
  func speed(at time: Double) -> Float {
    let h = 0.02
    let d = distance(at: time + h) - distance(at: time - h)
    return (reverse ? -d : d) / Float(2 * h)
  }
}
