# Ninfea V2 — intermediate water states and separate botanical passes

6 October 2026. Mode: built-in imagegen. All seven final PNGs are saved in `assets/` beside this document. Three foliage assets preserve generated RGBA alpha. Reference and edit inputs: original Ninfea photograph, previous locked interior, previous garden composition. The water-pool frame edits the newly generated 75% frame.

## water_0

Use case: precise-object-edit. Asset: intermediate water-fill frame for a premium Salini Ninfea product film.
Image 1 is the EDIT TARGET: the locked camera interior. Image 2 is only the OFFICIAL PRODUCT GEOMETRY REFERENCE.
Edit ONLY the inside bathing cavity. Preserve every pixel outside the cavity as closely as possible: same tub, emerald satin color, broad wing rim, dark base, architecture, DRY FLOOR, lighting, crop and camera. Output portrait 1024x1536. No added vegetation, tap, hose, stream, splashes, floor water, text or props. The tub must never change shape or move. Water is crystal clear with subtle daylight reflection, a realistic meniscus where it meets the inner wall, and tiny ripples. High-end photoreal render. The tub is just TWENTY PERCENT FULL, with a LOW shallow layer of water near the bottom. Most of the inner green wall remains visibly dry above the low waterline; the large black overflow slot stays well above water. The low surface is partially occluded by the near rim and inner wall, as physically correct from this camera. This is the first moment of filling, NOT a full tub. Clearly show the water level deep down in the cavity, much LOWER than the overflow.

## water_1

Use case: precise-object-edit. Asset: intermediate water-fill frame for a premium Salini Ninfea product film.
Image 1 is the EDIT TARGET: the locked camera interior. Image 2 is only the OFFICIAL PRODUCT GEOMETRY REFERENCE.
Edit ONLY the inside bathing cavity. Preserve every pixel outside the cavity as closely as possible: same tub, emerald satin color, broad wing rim, dark base, architecture, DRY FLOOR, lighting, crop and camera. Output portrait 1024x1536. No added vegetation, tap, hose, stream, splashes, floor water, text or props. The tub must never change shape or move. Water is crystal clear with subtle daylight reflection, a realistic meniscus where it meets the inner wall, and tiny ripples. High-end photoreal render. The tub is FIFTY PERCENT FULL. Show clear water at HALF the internal depth, with a continuous visible dry green strip of inner wall from the rim to the mid-depth waterline. The black overflow slot is clearly above water. The waterline is halfway up the inner wall, not near the top. The near rim naturally occludes part of this lower water surface. This is an intermediate filling state, NOT a full tub.

## high_prompt

Use case: precise-object-edit. Edit ONLY the bathing cavity inside the green Ninfea bathtub in image 1. Image 2 is the official product geometry reference, do not copy its room.
The bathtub is now SEVENTY-FIVE PERCENT filled with crystal clear water. The horizontal waterline sits approximately 7cm below the upper rim, just BELOW the black overflow slot. A visible dry green band remains above the water along the back inner wall. Real fine ripples, reflective daylight, believable refracted green material beneath water, a crisp meniscus.
LOCK THE ENTIRE rest of the image: same exact camera, portrait 1024x1536, tub outline, broad flat wings, material color, empty warm limestone pavilion, light direction, DRY FLOOR, no plant or foliage. No new fixtures, streams or splashes. No compositional shift or change in scale. The object never changes shape. This is a precise intermediate fill level between half-full and fully filled, with the surface physically lower in the cavity than a full tub. Photoreal cinematic architectural product rendering, no text.

## pool_prompt

Use case: precise-object-edit. Use this exact image as a locked camera background plate.
Change only water: fill the same emerald Ninfea bath almost to its maximum normal level, with calm clear water just below the black overflow. Add 2cm of beautifully clear reflective water over the existing limestone floor, turning the pavilion floor into a shallow reflecting pool. Stone floor remains visible under the water; fine, delicate wavelets, optical caustics, reflections of the tub and architecture. Tiny ripples, no large wave or foam. This is a clean WATER-ONLY PASS before any garden plants appear.
Preserve the same 1024x1536 portrait composition, all camera coordinates, every bathtub edge, broad wing rim, emerald mineral material, dark recessed base, stone walls and portal, sun direction and exposure. No vegetation added anywhere inside the pavilion, no lily pads, vines, flowers, leaves, moss, debris, taps, water streams or new objects. Distant trees outside the portal remain unchanged. Photoreal expensive cinematic rendering, clean optical detail, no text.

## rear_prompt

Use case: background-extraction. Create a TRANSPARENT RGBA botanical render pass for compositing over this exact photograph. Portrait canvas EXACTLY 1024x1536, same framing and object coordinates as the attached image.

KEEP ONLY the lush planted wall at the LEFT BACK of the attached garden scene: the hanging vines at upper-left, large glossy philodendron leaves on the left, branching ferns and their small stems growing from lower left up the left border. Preserve photographic detail, warm upper-left daylight, green translucency, tiny leaf veins, realistic soft shading. Preserve exactly the locations and sizes of those plants within the full canvas. The main leaves remain at approximately x 0..330 and y 0..670. The rear planting continues in a narrow band at the far left down to y 1000. Keep the upper-middle and right of canvas empty.

REMOVE the entire bathtub, the architecture, floor, water, reflections, right-side foreground foliage, and bottom water lilies. Wherever the bathtub formerly occluded the rear foliage, leave transparency: the tub is a holdout silhouette. Do not reconstruct hidden foliage across the tub. The result must be an accurately registered independent rear foliage layer, not a new composition. Background must be true alpha transparency, not black, white, grey or a checkerboard picture. No captions, no logos, no objects other than this rear plant group. Crisp natural alpha edges and no pale halo. Photorealistic botanical render, not illustration or painted grass.

## front_prompt

Use case: background-extraction. Asset: independent FOREGROUND BOTANICAL PASS, true transparent RGBA.
Use the attached photograph as the exact camera and placement reference. Output 1024x1536 portrait, same full canvas, no crop, no repositioning.

Keep ONLY: (1) the glossy photoreal large philodendron group at the lower-right, with real stems, fine fern fronds and folded leaves, approximately x=690..1024 y=820..1280; (2) the water lilies at the bottom-left and bottom of the image, with their round waxy pads and two ivory blossoms, approximately x=0..590 y=1140..1536. Include the small water droplets and fine edge details. Preserve the exact warm daylight, realistic veins, varied deep green tones and photographic material detail from the reference.

Remove EVERYTHING ELSE: no bath, no room, no distant plants, no water or floor, no sky, no shadows baked onto an opaque surface, no right portal or background trees. Leave the original spaces between individual leaves transparent. Center region where bathtub was is completely clear alpha. The top half is completely transparent. Preserve the original coordinates and realistic depth, no rescaling. Photoreal separate render pass intended for compositing over the original environment. True transparent background, no checkerboard painted in, no black rectangle or green fog, no text, no illustration, no cheap grass texture.

## vine_prompt

Use case: compositing. Asset: a photorealistic CLIMBING VINE foreground render pass with TRUE ALPHA TRANSPARENCY, portrait 1024x1536 canvas.

The attached emerald Salini Ninfea bathtub photograph is ONLY a positional and lighting guide. DO NOT include the tub or room in the output. Render ONLY one slender living climbing philodendron vine with 9-12 small heart-shaped leaves in the precise screen positions described below, as if it is climbing the front of that tub and curling over its broad rim. Everything else must be transparent. No green fog, no backing rectangle, no ground.

The main stem starts at pixel (815,1140), at the bathtub's front-right base. It follows a graceful irregular S curve up-left through (805,1045), (730,982), (700,915), (640,865), (630,823), then crosses the broad front rim at (600,808), curls LEFT along the rim through (535,790), (485,770) and terminates in a tiny curled growing tendril at (468,745). Keep these canvas positions, do not center, crop, enlarge or rearrange the vine. It occupies ONLY the region x=420..880 y=715..1180. The entire upper 45 percent and all left of x=390 are completely transparent.

A realistic slender 4-7-pixel green-brown stem, tiny gripping rootlets, individual leaf petioles. Alternate leaves 35-75 pixels long along the stem, each anatomically connected. Photographic leaves with fine veins, varied olive and deep forest green, young curled copper-green shoot at the tip, satin wax, translucent sunlit edges. Leaves close to the top bend from vertical to horizontal as they lie over the broad tub rim; lower leaves lie against its convex vertical front face. Upper-left warm natural light, subtle self-shadowing, gorgeous botanical macro detail, cinema-quality 3D render pass. Use the guide tub as invisible geometry to shape the vine in three dimensions, but output NO bathtub pixels, NO architecture, NO water, NO opaque shadows. Realistic clean alpha edges, no halo, no text, no illustration.

