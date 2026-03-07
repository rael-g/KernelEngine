# KernelEngine — Graphics Roadmap

## Rendering features — status

| Feature | Status |
|---------|--------|
| Camera (FoV, near/far, view/proj matrix) | Done |
| Mesh resource (VBO/IBO, ke_vertex with tangent) | Done |
| Material (albedo color + texture, metallic, roughness, normal map) | Done |
| Directional light (PBR Cook-Torrance GGX) | Done |
| Point lights — Clustered Forward | Done |
| Spot lights — Clustered Forward | Done |
| Clustered Forward Shading (dynamic grid, unlimited lights) | Done |
| Texture loading (RGBA8, CPU mipmaps via box filter) | Done |
| Normal maps (TBN, tangent-space) | Done |
| PBR shader (metallic/roughness workflow, F0, GGX BRDF) | Done |
| IBL / Skybox (cubemap, diffuse + specular split-sum) | Done |
| Shadow maps (depth pass, PCF bias) | Done |
| HDR Tonemapping (ACES, exposure, gamma) | Done |
| Bloom (bright-pass + Gaussian blur) | Done |
| SSAO (G-buffer prepass, hemisphere kernel, blur) | Done |
| Asset loader (Assimp glTF/OBJ + stb_image textures) | Done |
| MeshRendererComponent in C kernel | Done |
| Depth prepass (early-Z, overdraw reduction) | Pending |
| KTX2 / compressed textures | Pending |
| glTF binary bake (offline asset pipeline) | Pending |

---

## Examples

Examples live in `examples/csharp/`. Each one is an E2E test with two goals:
- **Visual feedback** for the developer (what is rendered on screen)
- **Log feedback** for automated review (what the engine reports at runtime)

Each example must log at startup: active features, resource counts, and any initialization errors.
Each example must log per-frame (every 5 s): FPS, entity count, light count.

### Complexity ladder

| # | Name | What it tests | Expected visual | Expected logs |
|---|------|---------------|-----------------|---------------|
| 01 | `01_window_scene` | Window, clear color, main loop, spinning node | Cycling background color, rotating orange quad | SpinnerNode started, frame delta |
| 02 | `02_textured_quad` | Texture loading (PNG), albedo material, UV mapping | Quad with a PNG image | Texture handle created, image dimensions |
| 03 | `03_pbr_directional` | PBR shader, directional light, camera orbit | Lit sphere/cube with specular highlight moving with light | Light direction, metallic/roughness values |
| 04 | `04_normal_map` | Normal map pipeline, TBN, tangent-space | Brick-like surface with depth illusion from a flat quad | Normal map handle created, u_normalParams active |
| 05 | `05_skybox_ibl` | Cubemap loading, skybox rendering, IBL reflections | Reflective sphere inside a skybox | Cubemap faces loaded, IBL active |
| 06 | `06_shadow_map` | Shadow map pass, depth bias, shadow receiving | Hard shadow cast by a box onto a ground plane | Shadow map dimensions, light VP matrix |
| 07 | `07_point_lights` | Clustered Forward with N point lights | Multiple colored point lights illuminating a scene | Cluster grid config, light count, FPS with N=64 |
| 08 | `08_spot_lights` | Spot lights with inner/outer cone falloff | Flashlight-style cone illumination | Spot count, cosInner/cosOuter values |
| 09 | `09_many_lights` | Clustered scaling — 256 point lights | Dense field of colored lights with no visible cap | Light count=256, cluster culling active, stable FPS |
| 10 | `10_postfx` | HDR tonemapping + bloom | Bright emissive areas bleeding into surrounding pixels | Tonemapping enabled, exposure/gamma, bloom threshold |
| 11 | `11_ssao` | SSAO prepass, hemisphere kernel, AO blending | Ambient occlusion darkening crevices and corners | SSAO radius/bias/strength, kernel size |
| 12 | `12_asset_loader` | Assimp glTF load, texture deduplication, mesh upload | A glTF model (e.g. DamagedHelmet) rendered with PBR materials | Model path, mesh count, material count, texture count |
| 13 | `13_full_scene` | Everything combined | glTF model inside a skybox, shadow, 32 point lights, SSAO, bloom | All feature flags active, FPS >= 30 at 1080p |

### Log contract (all examples)

At startup each example must print:
```
[KernelEngine] Example: <name>
[KernelEngine] Renderer: bgfx/Vulkan
[KernelEngine] Features: <comma-separated list of active features>
```

Every 5 seconds:
```
[KernelEngine] FPS: <value>  Entities: <count>  Lights: <point>p <spot>s <dir>d
```

On error (any ke_result != KE_OK):
```
[KernelEngine] ERROR: <function> returned <code>
```

---

## Remaining tasks

- Depth prepass (early-Z): always-on geometry pass before main scene, share depth with HDR framebuffer for DEPTH_TEST_EQUAL optimization
- KTX2 support: GPU-compressed textures with embedded mipmaps (BC7/ASTC)
- Offline asset pipeline: bake glTF + PNG → engine binary format at build time
