# Extensibility & Universality

> This is the **core doctrine** of KernelEngine — the reason it exists and the lens through which every layer decision is made. Read it after [01 - Philosophy & Principles](01%20-%20Philosophy%20%26%20Principles.md).

## The strategic premise

KernelEngine cannot out-resource Unreal/Unity — infinite money, the industry's most experienced engineers. Competing feature-for-feature is impossible. The only axis that beats infinite money is **decentralized open-source extensibility** — the **Linux formula**:

> Linux doesn't compete with Windows as a complete OS. It is a lean **kernel** plus an **infrastructure for decentralized development**. The community builds everything else.

So KernelEngine's bet: a thin, universal kernel + an infrastructure that lets **anyone** build their own graphics/gameplay solution as a swappable plugin — without forking the core. We will never implement every graphics technique; we provide the infra so the community implements theirs.

## The doctrine

**Universality lives as a contract in the kernel. The framework and plugins are choices — never imposed.**

- The **kernel** owns universal contracts (ABI-stable C): allocator, logger, ECS, frame packet, render/window/input contracts, task scheduler, and render *extension* (below). Anything universal goes here so **no alternate framework or plugin has to reimplement it**.
- The **framework** (`KernelEngine.Framework`) and the bundled plugins (bgfx, GLFW, Assimp…) are the **author's preferred choices**, not mandatory. A consumer can replace any of them, or write their own framework, and reuse everything universal from the kernel.

### The two tests

1. **The swap test**: *"If I replace any plugin or the framework, does code that depends on it break?"* If yes, the abstraction is in the wrong place. Today, plugins are independent — swap GLFW for SDL and nothing else changes. The goal extends this to *everything*: swap the bgfx plugin for an OpenGL plugin and a user's `AddMyFXAA` plugin keeps working (at most its shaders change SPIR-V→GLSL).

2. **The rework test (litmus for kernel-vs-framework)**: *"Would another framework also need this?"* If yes → it's universal → it belongs as a **kernel contract**, so nobody reimplements it. Example: the logger is in the kernel precisely so every framework reuses it; if it lived in the framework, every alternate framework would reinvent a logger. Someone writing their own framework should only implement **framework-specifics** (their scene model, threading, node types) — never universal infrastructure.

### The support-burden reason

We cannot match Unreal's support capacity. So we deliberately **do not impose our plugins** — if we did, we'd be obligated to support them. The stable thing we commit to is the **thin kernel contract**. Everything above (framework, plugins, techniques) is the community's, swappable, and self-supported. Thin kernel = small support surface = sustainable.

### The caution: don't over-promote

The opposite failure is promoting speculative abstractions to kernel contracts too early — a bad universal contract ossifies (everyone depends on it). Promote when universality is **clear/proven** (logger, ECS, render, render-graph — every renderer has passes). Hold speculative ones (e.g. a particle system) in a plugin until the shape is mature, then promote.

## The render extensibility model

Most graphics techniques (FXAA, SSAO, bloom, TAA, SSR, DoF, color grading…) are the same shape: *a pass, with a shader, that reads some textures and writes another.* So the enabler for "total freedom" is a **composable pass system** — and, per the doctrine, **it must be a kernel contract, not a render-plugin invention** (otherwise it binds users to bgfx).

- **`ke_render_graph` (kernel contract)** — register a pass: `{ type (fullscreen | geometry | compute), reads:[named resources], writes:[named resource], shader, insertion point }`. The engine resolves the dependency graph and manages intermediate render targets. Each render backend plugin (bgfx / OpenGL / Vulkan) *implements* the contract.
- **Standardized named resources** — `scene_color`, `depth`, `normal`, `velocity`, … that **every** backend must expose. Without a portable name for "the depth buffer", a technique plugin can't be backend-agnostic.
- **Portable shader authoring** — the dev authors in the engine's shader format; the shader-compiler plugin cross-compiles per backend. The shader is the *only* thing that changes when swapping backends.
- **Capability negotiation** — `isSupported(feature)` so a technique degrades gracefully when a backend lacks something (compute, MRT, 64-bit atomics).
- **Custom materials/shaders** (Godot `ShaderMaterial` style) — per-object custom surface shaders. The simple path ("fullscreen quad + custom shader") is just a registered fullscreen pass.

A technique plugin (`AddMyFXAA`) depends only on the kernel render-graph contract → it survives a backend swap. Built-in effects (bloom, SSAO, tonemap) should be registered through the *same* mechanism (dogfooding), which also removes the current hardcoded view chain.

## Validation exercise — could a dev implement Nanite without touching the core?

Nanite (Unreal's virtualized geometry) is the most demanding technique imaginable — a deliberate stress test. It comprises: (1) **offline baking** of meshes into a hierarchical cluster DAG; (2) **GPU-driven cluster culling** (compute, per-view, per-pixel-error LOD); (3) **software rasterization** of tiny triangles (compute → visibility buffer via atomics) + hardware raster for large ones; (4) a **visibility buffer → deferred material resolve**; (5) **streaming** of cluster data; sometimes **mesh shaders**.

**What our infra (as designed) handles — the structure, all as plugins, no core fork:**
- The **asset importer** is pluggable → a `AddNaniteImporter` produces the cluster DAG offline.
- The **render-graph** lets the dev register the Nanite passes (cull → raster → vis-buffer → material resolve) and *replace* the standard geometry pass for Nanite objects — without modifying the core renderer.
- A **custom node type** (`NaniteMeshNode`) routes its objects to the Nanite passes instead of the standard draw list.

**What the exercise REVEALS the infra still lacks (honest gaps):**
1. **GPU-compute & buffer primitives in the universal render contract.** The current `ke_render` is mesh/material/draw-oriented. Nanite (and *any* GPU-driven technique: GPU particles, GPU culling, virtual texturing) needs **structured/storage buffers, compute dispatch (incl. indirect), writable storage images, atomics (incl. 64-bit), GPU-driven indirect draw**. These must be **universal kernel contracts** (every modern backend expresses them) — without them, GPU-driven techniques are impossible regardless of the pass graph. This is the single biggest addition required for "total freedom" to include cutting-edge rendering.
2. **Custom GPU resource types.** Nanite's cluster buffers aren't a mesh/texture/material — the resource model must allow opaque/custom buffers, not just the three fixed handle types.
3. **Bounded by backend feature exposure.** If the chosen render backend (bgfx) doesn't expose, say, 64-bit atomics or mesh shaders, the dev either degrades or — the ultimate escape hatch the architecture *does* allow — **writes their own render backend plugin** implementing `ke_render` with those features. Freedom includes swapping the backend itself.

**Verdict:** the *orchestration* infra (render-graph, custom passes, custom nodes, asset importers, all as plugins) is **structurally sufficient** — a dev plugs Nanite in without forking the core. The required addition is the **universal GPU-compute/buffer/indirect/atomic primitive layer** in the render contract. Once that exists as a kernel contract, even Nanite is a community plugin. This is exactly the [01b escape-hatch principle](01%20-%20Philosophy%20%26%20Principles.md): a missing *capability* (GPU compute) is fixed by extending a *universal contract*, never by feature-specific core code.

Most techniques need far less than Nanite — FXAA/TAA/SSR/DoF need only passes + targets + shaders (the render-graph alone). GPU particles/culling need the compute layer. Nanite needs all of it; it usefully maps the full primitive set required.

## Implications / tracked work

- **Render-graph as a kernel contract** + standardized named resources + capability negotiation — Kanban (render extensibility).
- **GPU-compute/buffer/indirect/atomic primitives** in the render contract — prerequisite for GPU-driven techniques.
- **Periodic framework audits**: hunt for universal capabilities hiding in `KernelEngine.Framework` and promote them to kernel contracts (apply the rework test).
