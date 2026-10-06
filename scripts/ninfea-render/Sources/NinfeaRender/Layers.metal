#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; float2 uv; };
struct U { float time; float zoom; float padding0; float padding1; };
constexpr sampler s(address::clamp_to_edge, filter::linear);
constexpr sampler alphaSampler(address::clamp_to_zero, filter::linear);

vertex V layerVertex(uint id [[vertex_id]]) {
  float2 p = float2((id << 1) & 2, id & 2);
  return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}
float ease(float start, float end, float t) { return smoothstep(start, end, t); }
float4 clean(float4 p) {
  // Source PNGs have true alpha. Suppress weak background matte contamination
  // while retaining a narrow antialiased edge. RGB is premultiplied on upload.
  float a = smoothstep(0.22, 0.91, p.a);
  return float4(p.rgb / max(p.a, 0.001) * a, a);
}
float3 over(float3 background, float4 foreground, float amount = 1.0) {
  return background * (1.0 - foreground.a * amount) + foreground.rgb * amount;
}
float rect(float2 p, float2 lo, float2 hi, float feather) {
  float2 a = smoothstep(lo, lo + feather, p);
  float2 b = 1.0 - smoothstep(hi - feather, hi, p);
  return a.x * a.y * b.x * b.y;
}
float tubHoldout(float2 p) {
  // Screen-space silhouette of the locked Ninfea photograph. This holdout is
  // used only for plant occlusion; no generated layer can replace the product.
  const float2 points[] = {
    float2(.061,.462),float2(.247,.433),float2(.325,.431),float2(.923,.479),
    float2(.975,.490),float2(.976,.504),float2(.842,.532),float2(.839,.700),
    float2(.818,.725),float2(.763,.740),float2(.694,.745),float2(.243,.687),
    float2(.186,.665),float2(.172,.646),float2(.170,.505),float2(.067,.474)
  };
  bool inside = false;
  float d = 10.0;
  for (int i = 0, j = 15; i < 16; j = i++) {
    float2 a = points[i], b = points[j], ab = b - a;
    float h = clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0);
    d = min(d,length(p-a-ab*h));
    if ((a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
  }
  return smoothstep(-0.002, 0.002, inside ? d : -d);
}

float vineStemX(float y) {
  const float2 nodes[] = {
    float2(.878,.891),float2(.840,.833),float2(.829,.793),float2(.794,.686),
    float2(.740,.634),float2(.685,.575),float2(.676,.515),float2(.640,.480),
    float2(.541,.466),float2(.416,.445),float2(.373,.416)
  };
  for (int i=0; i<10; ++i) {
    if (y >= nodes[i+1].y) {
      float t=clamp((nodes[i].y-y)/(nodes[i].y-nodes[i+1].y),0.0,1.0);
      return mix(nodes[i].x,nodes[i+1].x,t);
    }
  }
  return nodes[10].x;
}
float4 vineLayer(texture2d<float> tex, float2 uv, float time) {
  float progress = 1.22 * ease(15.0,25.0,time);
  if (progress < 0.0001) return 0;
  // Register the separately rendered vine on the front face and over the rim.
  float2 q = (uv - float2(.20,.261)) / float2(.69,.55);
  float arrival = clamp((.891-q.y)/.475,0.0,1.06);
  float unfurl = ease(arrival+.015,arrival+.16,progress);
  float stem = vineStemX(q.y);
  q.x = stem + (q.x-stem) / mix(.07,1.0,unfurl);
  q.x += sin(time*.67 + q.y*19.0)*.0012*unfurl;
  float tip = ease(arrival-.006,arrival+.006,progress);
  return clean(tex.sample(alphaSampler,q)) * tip;
}

fragment float4 layerFragment(V in [[stage_in]], constant U &u [[buffer(0)]],
  texture2d<float> dry [[texture(0)]], texture2d<float> filled [[texture(1)]],
  texture2d<float> pool [[texture(2)]], texture2d<float> rear [[texture(3)]],
  texture2d<float> front [[texture(4)]], texture2d<float> vine [[texture(5)]]) {
  float2 uv = (in.uv-.5)/u.zoom+.5;
  float3 color = dry.sample(s,uv).rgb;
  float holdout = tubHoldout(uv);
  float2 basin = uv - float2(.505,.484);
  basin.y -= basin.x*.069;
  float bowl = 1.0-smoothstep(.97,1.045,length(basin/float2(.344,.036)));
  float wet = ease(2.0,9.0,u.time);
  float2 ripple = float2(sin(uv.y*125.0+uv.x*19.0-u.time),
                        sin(uv.x*88.0-uv.y*43.0+u.time*.8))*.0007*wet;
  float3 bath = filled.sample(s,uv+ripple*bowl).rgb;
  color = mix(color,bath,bowl);

  // The pool spreads out from the foot of the bathtub with an actual moving edge.
  float distance = length((uv-float2(.56,.68))*float2(.75,1.0));
  float spread = mix(-.03,.78,ease(8.6,14.0,u.time));
  float poolMask = (1.0-smoothstep(spread-.018,spread+.018,distance))
                * ease(.407,.434,uv.y) * (1.0-holdout);
  float3 poolColor = pool.sample(s,uv+ripple*ease(.73,.79,uv.y)).rgb;
  color = mix(color,poolColor,poolMask);

  // Edge-rooted canopy unfolds into the room. Keep cropped texture boundaries
  // outside the image throughout growth, so a rectangular card never appears.
  float rearGrowth = ease(10.0,18.0,u.time);
  if (rearGrowth > 0) {
    float arrival = 10.0 + 1.6 * abs(uv.y-.64);
    float unfold = ease(arrival,18.0,u.time);
    float2 q=float2(uv.x/max(.0001,unfold),uv.y);
    q.x += sin(u.time*.48+q.y*11.0)*.0022*rearGrowth*uv.x;
    float4 plants = clean(rear.sample(alphaSampler,q));
    float4 shade = clean(rear.sample(alphaSampler,q-float2(.004,.003)));
    color *= 1.0 - shade.a*.075*(1.0-holdout);
    color = over(color,plants,1.0-holdout);
  }

  // Stem advances first; every leaf unfolds behind its growing tip. Shadow attaches
  // the vine to the convex body and to the upper wing, rather than floating over it.
  float4 climbing = vineLayer(vine,uv,u.time);
  float shadow = vineLayer(vine,uv-float2(.0035,.004),u.time).a;
  color *= 1.0-shadow*.30*holdout;
  color = over(color,climbing);

  // Near leaves and floating lilies are two independently moving render layers.
  float fg = ease(13.0,22.0,u.time);
  if (fg > 0) {
    float2 anchor = float2(1,1);
    float2 q = (uv-anchor)/float2(max(.001,fg),max(.001,fg))+anchor;
    q.x += sin(u.time*.56+q.y*13.0)*.0023*fg*(1.0-uv.x);
    float4 near = clean(front.sample(alphaSampler,q));
    near *= smoothstep(.58,.64,q.x);
    float4 shade = clean(front.sample(alphaSampler,q-float2(.006,.004)));
    color *= 1.0-shade.a*.18*smoothstep(.58,.64,q.x)*holdout;
    color = over(color,near);
  }
  float lily = ease(11.0,20.0,u.time);
  if (lily > 0) {
    float2 anchor=float2(0,1);
    float2 q=(uv-anchor)/max(.001,lily)+anchor;
    q += float2(sin(u.time*.38)*uv.x,cos(u.time*.53)*(1.0-uv.y))*.0014*lily;
    float4 leaves=clean(front.sample(alphaSampler,q));
    leaves *= (1.0-smoothstep(.58,.64,q.x))*ease(.70,.77,q.y);
    color = over(color,leaves);
  }
  return float4(color,1);
}
