#include <metal_stdlib>
using namespace metal;

struct CinemaVertex { float4 position [[position]]; float2 uv; };
struct CinemaUniforms {
  float time;
  float water;
  float garden;
  float dissolve;
  float aspect;
  float zoom;
  float motion;
  float padding;
};

vertex CinemaVertex cinemaVertex(uint id [[vertex_id]]) {
  float2 p = float2((id << 1) & 2, id & 2);
  return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}

float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float softNoise(float2 p) {
  float2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
             mix(hash21(i + float2(0, 1)), hash21(i + 1), f.x), f.y);
}

fragment float4 cinemaFragment(CinemaVertex in [[stage_in]],
  constant CinemaUniforms &u [[buffer(0)]],
  texture2d<float> interior [[texture(0)]], texture2d<float> water [[texture(1)]],
  texture2d<float> garden [[texture(2)]]) {
  constexpr sampler s(address::clamp_to_edge, filter::linear);
  // Aspect-fill from the SAME locked portrait camera for all three keyframes.
  float2 uv = in.uv - 0.5;
  const float imageAspect = 2.0 / 3.0;
  if (u.aspect > imageAspect) uv.y *= imageAspect / u.aspect;
  else uv.x *= u.aspect / imageAspect;
  uv = uv / u.zoom + 0.5;

  // Water displacement is confined to the pool and the bathing water, never the product.
  float2 basin = uv - float2(0.501, 0.486);
  basin.y -= basin.x * 0.055;
  float insideBasin = 1.0 - smoothstep(0.80, 1.0, length(basin / float2(0.325, 0.027)));
  float floorWater = smoothstep(0.75, 0.81, uv.y);
  float waterMask = max(insideBasin, floorWater);
  float2 ripple = float2(
    sin(uv.y * 127.0 + uv.x * 16.0 - u.time * 0.8),
    sin(uv.x * 83.0 - uv.y * 43.0 + u.time * 0.65)) * 0.00085;
  float2 wetUV = uv + ripple * waterMask * u.motion;

  // Plants unfurl from the two lower edges. A soft irregular frontier travels up the
  // sides instead of cross-fading the whole image. Product pixels retain their camera.
  float growthDistance = (1.0 - uv.y) * 0.74 + min(uv.x, 1.0 - uv.x) * 0.16;
  growthDistance += (softNoise(uv * float2(19, 29)) - 0.5) * 0.055;
  float growth = smoothstep(growthDistance - 0.085, growthDistance + 0.085,
                           mix(-0.12, 0.95, u.garden));
  float leftLeaves = (1.0 - smoothstep(0.27, 0.48, uv.x)) * (1.0 - smoothstep(0.40, 0.48, uv.y));
  float rightLeaves = smoothstep(0.82, 0.99, uv.x) * smoothstep(0.56, 0.72, uv.y);
  float foliage = max(leftLeaves, rightLeaves);
  float2 leafUV = wetUV + float2(sin(u.time * 0.61 + uv.y * 9.0),
                               cos(u.time * 0.43 + uv.x * 7.0))
                              * 0.00085 * foliage * growth * u.motion;
  float4 dry = interior.sample(s, uv);
  float4 wet = water.sample(s, wetUV);
  float4 lush = garden.sample(s, leafUV);
  // A gentle bottom-to-top fill; the basin and floor settle at slightly different times.
  float waterArrival = mix(0.13, 0.0, smoothstep(0.45, 0.91, uv.y));
  float fill = smoothstep(waterArrival, 0.86 + waterArrival, u.water);
  float4 color = mix(dry, wet, fill);
  color = mix(color, lush, growth);
  color = mix(color, dry, u.dissolve);
  return float4(color.rgb, 1.0);
}
