# Collection worlds — 7 October 2026

Work in progress. Generated keyframes are direction assets, not completed films or shipped replacements.

The user asked to redesign the environments so that visible motion is inherent in the composition. Large water fields, foliage and fabric must continue through the final frame, with a genuinely repeating ending. The bathtub must remain rigid and identifiable as the original Salini product.

## Greca — tidal island, keyframe v2

Generated with the built-in imagegen tool, using `ios/Salini/Resources/greca.jpg` and `greca-editorial.jpg` as product identity references. Saved as `greca-tidal-keyframe-v2.png`. This is an imagined campaign environment, not a real installation or a measured CAD render.

Prompt:

> Use case: product-mockup. Create a new photoreal cinematic campaign keyframe for the premium Salini GRECA bathtub, vertical 3:4 composition. Both input photographs are product identity references, not backgrounds to reproduce. Preserve EXACT product: elongated oval bowl, broad flat thick white rim with squared lip, curved tapered turquoise outer body, low separate ivory oval pedestal; keep geometry, proportions and overflow opening. New environment: the bath stands on a shallow pale limestone monolith island barely above a vast sheltered Mediterranean tidal pool. Calm teal water occupies the whole lower half of the frame and surrounds the island on every side, with very clearly modeled overlapping low ripples, broken sun glints and a long physically correct reflection of the bath. A distant dark monumental limestone coastal wall to the left, an empty pale warm sky over the horizon to the right. Minimal, sculptural, one flawless manufactured hero, intimate but monumental. Not a bathroom, not a furniture showroom. Three-quarter eye level just high enough to see the interior, camera locked, hero fully visible and filling 65% of frame width, centered at 49% image height; top 18% quiet negative space. Late afternoon lateral sunlight, complex specular highlights on water, subtle caustic bounce on low stone island, restrained ivory / petrol / mineral palette. Ultra realistic high-end C4D Redshift architectural product campaign, physically plausible weight and contact. Create water caught in mid-flow, NOT flat mirror water. The scene is designed to become a living seamless film: broad water field and reflections will move while bath and stone remain perfectly rigid. No people, plants, curtains, faucets, text, logos, foam, splashes, motion blur or exaggerated fantasy. No deformation or invented ornament on bath.

Visual review: the keyframe provides a much larger moving water region than the earlier narrow channel. A film must preserve the broad white rim, separate pedestal, solid contact and empty sky, without moving or warping the product. Animation acceptance remains pending.


## Ninfea — living lily garden

`ninfea-lily-garden-keyframe-v2.png` uses the official Ninfea photograph as its identity reference: the broad wing rim and emerald body remain the recognizable product. Mature leaves occupy the foreground, middle and background, while pond and bath water provide connected motion. A vine reaches the rim from established vegetation rather than appearing as an isolated seedling.

Film direction: the entrance should develop simultaneously from both edges, water and foliage moving together. The vine reaches the rim later within that same continuous action. The established end world becomes a separate ambient take: leaves breathe in overlapping phases, water ripples and reflections continue. Never loop the growth event or reverse a growing vine.

## Aria — wind pavilion

`aria-wind-pavilion-keyframe-v2.png` retains Aria's suspended white body and dark curved supports. Travertine and a pale horizon frame large translucent linen sails. The moving area is intentionally large enough to remain readable at phone scale.

Film direction: one slow wind field moves the cloth through different phases, with coherent changes in transmission and shadows. No curtain-opening event followed by a stop. Fabric remains clear of the product silhouette and the camera remains locked.

## Opera — light court

`opera-light-court-keyframe-v2.png` retains the rolled rim and stepped moldings in a monumental warm stone loggia. Oxblood recesses give the ivory form depth. The foreground pool supplies visible movement and physically related light on the walls.

Film direction: overlapping water rings, moving reflected light on the right-hand stone wall and slower leaf shadows on the arches. No generic curtain solution. The product, platform and architecture must stay rigid; avoid broad exposure pulsing disguised as caustics.

## Motion acceptance

- All four images are campaign concepts, not verified CAD renders or completed films. Exact prompts and the rejected video request are retained in `generation.json`.
- First judge a continuous, naturally moving take, then find a compatible loop interval. A matching first/last still alone is not evidence of a living loop: forcing identical endpoints previously damped the motion.
- At the actual phone crop, motion must be evident throughout the take and the final seconds. Inspect at least three loop cycles in the native player; reject a visible reset, frozen tail, camera drift, warped product, flicker or geometry discontinuity.
- Water, leaves, fabric and lighting must move as one scene, with no independently sliding image cutouts. Do not ship still-image distortion or an opacity crossfade as the requested film.
- Do not overwrite the current bundled clips until a replacement passes visual review. Existing looping playback remains implemented, but the current four endings still fail the intended visible-motion quality bar.

## Current dependency

On 7 October 2026, Kling 3.0 Pro quoted 12 credits for the new 8-second Greca ambient take, then rejected the request with `Out of credits on plus (monthly) plan in Private workspace`. Balance returned 1 standard credit and 100 trial credits; the service did not apply the trial allowance to that generation. No job was created and no new film has been generated in this pass. No subscription or purchase was changed. The user was asked whether another connected video service or a refreshed allowance is available. Native material engineering continues independently.

## Local video fallback research

The current Mac is an M4 Pro with 24 GB unified memory. Local inference is possible in principle, but no local film was rendered in this pass and no quality/performance claim is established.

- [Official LTX Desktop](https://github.com/Lightricks/LTX-Desktop) supports local Apple Silicon image-to-video; its launcher requires at least 15 GB **free** RAM. Newer model downloads may require Hugging Face sign-in and license acceptance. This is not a zero-setup substitute for the rejected cloud job.
- [ltx-2-mlx](https://github.com/dgrauet/ltx-2-mlx) documents a roughly 12 GB int4 LTX-2.3 pack and low-RAM streaming. Its own guidance is a useful starting point for a short, reduced-resolution test, not evidence that an 8-second premium campaign film will render well on this machine.
- [MLX-Video](https://github.com/Blaizzy/mlx-video) also exposes Apple Silicon LTX/Wan image-to-video workflows. Model quality, silhouette stability and the loop seam still require scene-specific validation.

Do not launch memory-heavy inference alongside the release build and simulator QA or close unrelated user applications to make it fit. A later isolated render can use the approved keyframe and the same motion acceptance criteria; interpolation alone cannot invent the required connected water/foliage dynamics.
