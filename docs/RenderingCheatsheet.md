# Rendering cheatsheet — low quality to path tracing

Sep 24, 2026 · @Israel

## Tier 0 — Foundation (what render-v2 already has)

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| G-buffer, light clustering | Forward+ PBR metallic-roughness | Physically plausible lighting, N lights |
| Environment cubemap | Direct sampling (no split-sum) | Basic IBL |
| Sun direction + cloud coverage scalar | Analytic sky model (Preetham/Hosek-Wilkie) | Cubemap reacts to weather without rebaking |

**Stage optimizations:**

- Depth pre-pass (early-Z) before forward, avoids shading hidden pixels
- Frustum+AABB per cluster in light culling, avoids a full light loop per pixel
- Batching by material/shader, reduces pipeline state switches
- Frustum culling (AABB/sphere vs. the camera's 6 planes) before any draw
- Hierarchical-Z occlusion culling using the previous frame's depth mip chain
- Discrete mesh LOD + shader LOD (cheaper material at distance)
- Mipmaps + texture atlasing + texture/mesh compression in the asset pipeline
- Draw call instancing for identical objects (vegetation, repeated props)
- Impostors/billboards for repeated, very distant objects

## Tier 1 (low → medium) — Rasterized polish, zero new infrastructure

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| BRDF LUT + prefiltered mip chain | Split-sum IBL | Correct ambient at any roughness |
| Shadow map cascades | CSM + PCF/PCSS | Directional shadow without aliasing |
| Height map (existing channel) | Simple parallax → multi-sample POM | Real surface depth |
| None (reuses albedo) | Stochastic texturing (height-based blend) | Terrain without visible tiling |
| Depth+normal from G-buffer | Simple SSAO (hemisphere) | Darkened contact/cavities |
| Depth buffer + light direction | Screen-space contact shadows (short ray-march) | Catches thin occluders shadow maps miss |
| Thickness/transmission map | Subsurface scattering (wrap lighting / pre-integrated) | Light transmission through thin surfaces (skin, foliage) |
| Cloud texture (2D) + sun direction | Cloud shadows (projected onto terrain) | Low-frequency shadowing from weather without new geometry |
| Rain wetness scalar | Wet-surface layering (thin water coat modulates specular/albedo) | Correct look during rain without new BRDF |

**Stage optimizations:**

- Texel snapping per shadow cascade, avoids shimmer when the camera moves
- Single shadow atlas instead of one render target per light
- Parallax: fewer samples at distance via heightmap mip
- SSAO at half-res + depth-guided bilateral upsample

## Tier 2 (gate) — Temporal foundation, unlocks everything after

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| Motion vectors (object + camera) | Sub-pixel jitter in the projection | Frame-to-frame reprojection |
| History buffer (double-buffer) | TAA (temporal accumulation) | Stable antialiasing |
| Reactive/composition mask | Fallback for transparents without history | Correct TAA with alpha blending |

This tier is pure infrastructure cost — no standalone visual gain. But SSGI, temporal SSR and upscaling (Tiers 3 and 7) depend on it.

**Stage optimizations:**

- Motion vector dilation on thin geometry, avoids losing pixels in reprojection
- Variance clipping / neighborhood clamping on TAA history, avoids ghosting
- History rejection via disocclusion (depth+normal) instead of always reprojecting

## Tier 3 (high) — Advanced screen-space

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| STBN 3D (spatiotemporal noise) | GTAO (horizon-based, angular bitmask) | High-quality AO |
| Mipped G-buffer radiance + Tier 2 | SSGI (extended GTAO + SH2 + reprojection) | 1-bounce on-screen GI |
| Depth+normal+Tier 2 | Temporal SSR | Accurate screen-space reflections |
| Cubemaps parallax-corrected | Reflection probes | Specular indirect without SSR |

**Stage optimizations:**

- Half/quarter res for GTAO/SSGI + depth+normal-guided bilateral upsample
- Horizon-scan direction jitter via the frame's STBN slice, fewer slices without visible noise
- SSR: hierarchical ray marching on the depth mip chain (HZB) instead of a fixed step
- Thickness heuristic in SSR, avoids false hits behind thin surfaces
- Same thickness heuristic applied to SSGI sampling, avoids indirect light leaking through thin walls
- Dedicated spatial denoiser (geometry/normal-aware recurrent blur) for SSGI/SSR, distinct from the Tier 2 temporal reprojection — removes residual per-pixel noise the history alone can't resolve
- Dynamic cubemap re-render (full real-time capture) as a costlier alternative to the static parallax-corrected probe, trades GPU cost for always-fresh reflections

## Tier 4 (ultra) — Baked/world-space extensions

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| SDF per mesh (baked) + composited scene volume | DFAO (sphere-trace toward sky in the SDF) | Ambient darkens near static occluders, on/off-screen, indoors and outdoors |
| Froxel volume (3D screen-aligned grid) | Volumetric lighting (ray-marched in-scattering + extinction) | Godrays, atmospheric scattering |

## Tier 5 (RT) — Ray tracing foundation

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| BVH (BLAS per mesh, TLAS per scene) | Ray query in compute | Ray-scene intersection |
| BVH + STBN | RTAO | AO without screen-space artifacts |
| BVH | RT shadows | Soft, correct area shadows |
| BVH (TLAS/BLAS via wgpu-native's native ray query extension) + probe grid (SH/octahedral) | DDGI (probes updated per frame via ray query) | Multi-bounce diffuse GI with dynamic occluders/emissives |
| BVH + roughness-based cone spread | RT reflections (ray-traced specular) | Accurate reflections without SSR's screen-space limits |

Real gap today: wgpu still treats ray query/acceleration structures as an experimental feature, with no stable RT pipeline. Until it matures, the route is BVH + traversal via compute shader.

**Stage optimizations:**

- Compact BLAS for static geometry, only the TLAS updates per transform each frame (refit is cheap but degrades with large deformation; full rebuild only when necessary)
- Instancing via TLAS: the same BLAS referenced N times with different transforms, without duplicating geometry
- Ray sorting/binning by direction before traversal, improves cache coherence
- DDGI: probe relocation (move probe outside geometry) + probe classification (disable redundant/inside-wall probes)

## Tier 6 (RT) — RTGI refinement & path tracing

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| Reservoir buffer (history) | ReSTIR GI/DI (spatiotemporal resampling) | 1 ray/pixel looks like N rays |
| Depth+normal+motion (Tier 2) | Spatiotemporal denoiser (SVGF-like) | Clean image at 1spp |
| Full BVH | Accumulated path tracing | Reference ceiling / photo mode |

**Stage optimizations:**

- Reservoir clamping (M-cap): limits how many candidates the temporal reservoir accumulates, avoids reinforcing bias from stale samples
- Spatial reuse with limited radius/neighbor count, cost grows fast and the gain saturates
- Firefly clamping before temporal reprojection, avoids a permanent dark smear
- Bilateral filter radius guided by accumulated variance (more filtering where there's more noise)

## Tier 7 (cross-cutting) — Upscaling and frame generation

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| None extra | FSR1 (spatial upscale) | FPS gain at any point (Tier 0+) |
| Motion vectors + jitter (Tier 2) | FSR2/3-style temporal | Render at low resolution, sharp output |
| UI mask + Tier 2 | Frame generation | Interpolated frames |

**Stage optimizations:**

- Motion vector dilation (same technique as Tier 2), error amplifies at the higher output resolution
- Reactive mask computed only on translucent/unstable pixels, not the whole screen

## Tier 8 (every stage) — Cross-cutting optimization

| Technique | Where it helps |
| --- | --- |
| GPU-driven rendering + indirect draw | Eliminates per-object CPU overhead, any tier |
| Meshlet culling (frustum/occlusion/backface) | Reduces vertex work before any shading |
| Async compute | Overlaps SSGI/GTAO/RT with shadow/gbuffer |
| Variable rate shading | Reduces shading cost in low-detail areas |
| Bindless resources | Avoids bind-group churn when stacking features (Tiers 3-6) |
| GPU-driven culling (frustum+occlusion+LOD in compute) | Moves the culling decision from CPU to GPU, generates indirect draws directly, no round-trip |

## Tier 9 (cross-cutting) — HDR output & tonemapping

| Resource (A) | Algorithm (B) | Enables (X) |
| --- | --- | --- |
| Luminance histogram/average of the HDR buffer | Auto-exposure (temporal eye adaptation) | Correct exposure across wildly different lighting, no manual per-area tuning |
| HDR-capable swapchain (scRGB/HDR10) | Native HDR output | Full display dynamic range, bypasses the SDR tonemap clamp |
