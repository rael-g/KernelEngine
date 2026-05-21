# Graphics & Rendering

Rendering is a kernel contract (`ke_render`) implemented by the **bgfx** plugin, driven by **pure-managed C# render systems** in the framework. The split: C# systems decide *what* to draw (recording into a frame packet); the C++ plugin decides *how* (issuing bgfx draw calls on the render thread).

## Backend

- **bgfx**, targeting **Vulkan** (`RendererType::Vulkan`). bgfx itself can target D3D/Metal/GL, so the backend is portable.
- Shaders authored for bgfx, compiled to SPIR-V via `shaderc`. See [10 - Build & Tooling](10%20-%20Build%20%26%20Tooling.md).

## Record-vs-submit flow

```
ke.sim:    C# render systems  ──record──►  IFramePacket (camera, lights, draws, post-fx)
                                              │  (handed across via ke_frame_sync)
ke.render: FrameSubmitter (C++) ──reads───►  ke_frame_packet ──► bgfx draw calls
```

Render systems run on `ke.sim`, query the ECS read-only, and record semantic commands (handles, transforms, lights) into the frame packet. On `ke.render`, `FrameSubmitter` consumes the packet and issues bgfx calls. The two never share mutable state — only the packet (see [08 - Multithreading](08%20-%20Multithreading.md)).

> **History note**: the render systems were once nativized in C++ (a `ke_render_core` public contract + native System Graph). They were **migrated back to pure-managed C#** in `KernelEngine.Framework`, and the redundant `KernelEngine.Render.Core` C# assembly was deleted. `ke_render_core` survives only as an internal C++ pipeline-support library consumed by the bgfx plugin; it has no public C ABI. (Older docs that say render systems are "nativized" are stale.)

## C# render systems ✅

| System | Reads | Records |
|---|---|---|
| `CameraRenderSystem` | camera + transform | view/projection/position |
| `LightRenderSystem` | directional/point/spot light + transform | directional light + point/spot light lists |
| `MeshRenderSystem` | mesh + transform | draw commands |
| `ShadowRenderSystem` | light + meshes | shadow pass + shadow draw commands |
| `SkyboxRenderSystem` | skybox | skybox cubemap |

Each declares its `ComponentAccess` (reads/writes) so the engine can reason about parallelism. They record exclusively through the safe `IFramePacket` API — no `unsafe`, no native pointers.

## View layout (bgfx) ✅

| View | Pass |
|---|---|
| 0 | Shadow depth (R32F color + D16 depth FB) |
| 1 | Main scene → HDR RGBA16F FB (when post-processing on) or backbuffer |
| 2 | Skybox (rotation-only view, depth-test LEQUAL) → same FB as view 1 |
| 3 | Bright-pass (half-res) — bloom only |
| 4 | Blur horizontal (half-res) — bloom only |
| 5 | Blur vertical = final bloom (half-res) — bloom only |
| 6 | ACES tonemap composite → backbuffer |

## Implemented rendering features ✅

- **PBR** — GGX metallic/roughness shading.
- **Lighting** — directional, point, spot lights.
- **Clustered forward shading** — unlimited lights via a dynamic cluster grid.
- **Shadow maps** — directional, R32F + D16 framebuffer; ortho frustum derived from the first directional light. API: `create_shadow_map`, `begin_shadow_pass(lightView, lightProj)`, `submit_mesh_shadow`, `end_shadow_pass`, `set_shadow_map`, `destroy_shadow_map`. Shader uniforms `u_lightVP`, `u_shadowParams`, `s_shadowMap`.
- **IBL / Skybox** — cubemap-based image-based lighting.
- **Normal maps**.
- **Post-processing** — ACES tonemapping, bloom, SSAO.
- **Mipmaps** — CPU-generated.
- **Materials** — base color + metallic/roughness + albedo/normal textures.

Standard vertex layout: position (3f) + color0 (4×u8) + normal (3f) + texcoord0 (2f) + tangent. Built-in handles: texture `0` is a 1×1 white texture created at renderer init; `MeshNode` defaults to a quad mesh + white material.

## GPU resources

Created through `IResourceFactory` (meshes, textures, cubemaps, materials, shadow maps). From the sim thread these calls are marshaled to the render thread via the resource command queue and block until the handle comes back (see [08 - Multithreading](08%20-%20Multithreading.md)). Typed handles (`MeshHandle`, `TextureHandle`, `MaterialHandle`, `ShadowMapHandle`) use `uint.MaxValue` as `None`.

## Planned 📋

- **GPU instancing primitive + `MultiMeshRenderer` node** — draw many instances of one mesh in few draw calls. Unblocks grass, foliage, crowds, particles. This is a *capability* gap (the frame packet only does one transform per draw today), so it must extend the renderer contract, not be solved in user-land. Tracked as `[F.RC1]` in the Kanban.
- **Depth prepass (early-Z)**, **KTX2** texture support, **offline asset/texture pipeline**.
- **Selectable shading strategy — forward++ (clustered) and deferred** (deferred until the engine is complete + functional). The dev chooses what fits their project, exposed either as separate renderer plugins or one plugin with factory options (e.g. `AddBgfxRenderer(mode: ForwardPlus | Deferred)`). **No kernel/API change is required**: `ke_frame_packet` and `ke_render` already carry generic inputs (geometry, materials, lights) — forward vs deferred is an internal renderer strategy that reuses the shared clustered light-cull. Deferred adds a G-buffer (MRT) pass + lighting pass + shaders, all contained in the plugin; the one future *frame-packet* touch would be a separate transparent-draw list (for the hybrid forward pass deferred needs for transparency — orthogonal to deferred itself). Strategic note: deferred is bandwidth-heavy (poor for tiled mobile/web GPUs); forward++ is generally preferred there — so the choice is "pay the bandwidth?" not "can we build it?".
- Longer term (M5): GPU-driven rendering (indirect draw, GPU culling), real-time GI, ray tracing (would need a non-bgfx backend). See [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md).
