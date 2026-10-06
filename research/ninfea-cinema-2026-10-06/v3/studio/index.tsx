import { generate } from "@diffusionstudio/jsx";

const film = generate.video({
  model: "kling-3-pro",
  prompt: "Locked-off architectural product cinematography, one continuous live-action-looking shot, no camera movement, no zoom, no cuts. The same emerald Salini Ninfea bathtub remains completely rigid and identical in position, silhouette, rim and material throughout. From the very first second, TWO actions happen SIMULTANEOUSLY and smoothly across the entire shot: clear water gradually rises inside the bathing cavity with delicate natural surface motion, while many slender living philodendron tendrils and ferns grow organically from the stone seams and frame edges, branching and curling over the bathtub's broad wings. Several stems crawl around both sides of the body and over the rim, leaves unfold and turn toward the light, rear foliage spreads up the wall. The actions overlap continuously, never finish one action before starting another. The water and plants belong to one physically rendered world: growing leaves cast moving detailed shadows across the emerald satin body and limestone, reflections evolve naturally on the water, restrained warm bounced light and translucent leaf edges. Slow graceful botanical time-lapse, luxurious and believable material detail, unified cinematic color. Preserve the dry stone floor throughout, no water outside the bathtub and no caustic overlay on the floor. Preserve the initial architecture and fixed light direction. Arrive gradually at the supplied final garden composition, with growth easing to a quiet natural settle during the last second. Natural articulated plant growth, no flat cards, no stretching of a still image, no melting bathtub, no crossdissolve, no abrupt appearance, no slideshow, no magic particles, no artificial glow. Silent.",
  startFrame: "/Users/daviddoronin/Documents/ChatGPT/Salini/research/ninfea-cinema-2026-10-06/v3/assets/interior.png",
  endFrame: "/Users/daviddoronin/Documents/ChatGPT/Salini/research/ninfea-cinema-2026-10-06/v3/assets/garden.png",
  duration: 10,
  aspectRatio: "9:16",
  audio: false,
  seed: 3917,
});

export default function Project() {
  return <stage id="salini-stage" background="#121916">
    <scene id="ninfea-scene" name="Ninfea — living garden" width={1024} height={1536} active>
      <sequence id="ninfea-sequence">
        <video id="ninfea-film" name="Kling 3 — continuous botanical growth" src={film} width={1024} height={1536} start={0} end={10} muted />
      </sequence>
    </scene>
  </stage>;
}
