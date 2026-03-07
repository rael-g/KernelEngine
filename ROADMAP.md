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

---

## Debugging plan

### Problem statement

Crashes in the engine layer (native DLL) surface as silent exits with non-zero codes (e.g. `0x80000003` STATUS_BREAKPOINT from bgfx debug asserts) with no log output, making root-cause analysis very slow. The managed layer has no way to distinguish a bgfx assert from a Vulkan driver crash or an ordinary .NET exception.

### Root causes identified

| Symptom | Root cause | Status |
|---------|------------|--------|
| Exit `0x80000003`, no log | `bgfx::setBuffer()` before `bgfx::submit()` — compute-only API in draw call | **Fixed** — replaced with `setUniform` arrays |
| Silent exit from repo root | Shaders compiled on Linux, SPIRV incompatible with Windows Vulkan driver | **Fixed** — recompiled with local `shaderc.exe` |
| "Failed to load scene shaders" | Shader path resolved relative to CWD | **Fixed** — `AppContext.BaseDirectory` + `Directory.Build.targets` copies shaders |

### Plan

#### 1. bgfx callback → engine logger (Priority: High)

bgfx exposes a `bgfx::CallbackI` interface. Implement `BgfxCallback : bgfx::CallbackI` in `bgfx_render_system.cc` that forwards `fatal()` and `traceVargs()` to `ke_logger`. Pass it via `bgfx::Init::callback` in `OnInitialize()`.

- `fatal()` receives the error type and message before `debugBreak()` fires — log it as `KE_LOG_LEVEL_ERROR` and return without crashing in debug builds
- `traceVargs()` receives shader validation warnings, resource leaks, and API misuse — log as `KE_LOG_LEVEL_DEBUG`

This converts silent STATUS_BREAKPOINT crashes into logged errors with a call site.

#### 2. Vulkan validation layers in debug builds (Priority: High)

In `OnInitialize()`, when `NDEBUG` is not defined, enable Vulkan validation:
```cpp
init.debug = true;  // enables bgfx internal validation + VK_LAYER_KHRONOS_validation
```
Validation layer messages are routed through `CallbackI::traceVargs()` (see item 1), so they will appear in the engine log automatically once the callback is wired.

Requires `VK_LAYER_PATH` pointing to the Khronos validation layer SDK on the developer machine (installed with Vulkan SDK).

#### 3. Non-zero exit code propagation (Priority: High)

The C# `Application.Run()` currently does not return the engine exit code. Change it so that if any `ke_result != KE_OK` is returned from the main loop or initialization, `Environment.Exit(1)` is called. This makes the crash visible in the terminal immediately (`dotnet run` will print the non-zero exit code).

#### 4. Structured startup diagnostic (Priority: Medium)

At the start of `OnInitialize()`, log:
```
[bgfx] Renderer: Vulkan  Device: <GPU name>  Driver: <version>
[bgfx] Shader path: <resolved path>  Shaders: <count loaded>
[bgfx] Max draw calls: <caps>  Max textures: <caps>
```
This makes it immediately visible whether initialization succeeded and what resources are available.

#### 5. `ke_result` guard macro (Priority: Medium)

Add a `KE_CHECK(expr)` macro in C headers that logs the call site and result when `expr != KE_OK`, then returns the result. Use it in `bgfx_render_system.cc` at every internal call site. This ensures any internal failure emits a log line before the function returns.

#### 6. Shader compiler script (Priority: Medium)

Add `tools/compile_shaders.bat` that invokes the local `shaderc.exe` for every `.sc` source in `src/cpp/render/bgfx/shaders/`. Run it as a CMake `POST_BUILD` step on `ke_render_bgfx` so shaders are always in sync with the source. This eliminates the "SPIRV compiled on wrong platform" class of crashes.

#### 7. Example exit-code CI check (Priority: Low)

In CI, run each example headlessly for 5 seconds using a virtual framebuffer (Xvfb on Linux) and assert `$? == 0`. Any crash or non-zero exit fails the build. This catches regressions introduced by new render system changes before they reach the developer.
