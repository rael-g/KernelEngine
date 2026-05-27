# KernelEngine Reference

> **What this is**: the consolidated, living technical reference for KernelEngine — *what the engine is today* **and** *what it is becoming*, organized by domain. It supersedes the former `docs/Architecture/` vision documents.
>
> **What this is NOT**: task tracking (see [`Kanban.md`](../Kanban.md)) or product milestones at a glance (see [`EngineRoadmap.md`](../EngineRoadmap.md)). The architectural decision/defect log lives in [`12 - Architecture Backlog & Decisions.md`](12%20-%20Architecture%20Backlog%20%26%20Decisions.md).

## Status legend

Every capability in this reference is tagged so that current reality and future intent live side by side:

- ✅ **Implemented** — exists and works today.
- 🚧 **Partial** — exists but incomplete, unverified, or platform-limited.
- 📋 **Planned** — designed/intended; not built yet. Cross-referenced to a Kanban card where one exists.

## What KernelEngine is

KernelEngine is a **microkernel game engine**. A small, ABI-stable C core provides primitives (memory, logging, ECS, frame handoff, vtable interfaces for renderer/window/input). Everything domain-specific — the actual renderer, window system, asset loader, scheduler — is a **replaceable plugin**. A high-level C# framework sits on top to give game developers an ergonomic, Godot-/Unity-flavored authoring experience.

The defining tension the architecture embraces: **the kernel provides building blocks; it never becomes a built block.** New features grow in plugins and in the framework, not by bloating the core.

## The four layers at a glance

```
┌──────────────────────────────────────────────────────────────┐
│  Game code (your game)                                         │
│  Uses ONLY KernelEngine.Framework + Abstractions.              │
├──────────────────────────────────────────────────────────────┤
│  Layer 4b — C# Framework  (KernelEngine.Framework)             │
│  High-level node→ECS API: Application, Scene, Node, systems.   │
│  A different paradigm from the kernel — the author's ideal,    │
│  not a mandatory layer.                                         │
├──────────────────────────────────────────────────────────────┤
│  Layer 4a — C# Managed wrappers + Abstractions                 │
│  KernelEngine.Kernel (concrete wrappers) +                     │
│  KernelEngine.Kernel.Abstractions (interfaces + POCOs).        │
├──────────────────────────────────────────────────────────────┤
│  Layer 3 — C# Native bindings  (generated, never hand-edited)  │
│  P/Invoke over the C ABI, per project under Native/Generated/. │
├──────────────────────────────────────────────────────────────┤
│  Layer 2 — C++ Plugins  (src/cpp/)                             │
│  bgfx renderer, GLFW window, Assimp loader, enkiTS scheduler…  │
│  Each exposes exactly one C factory: ke_<plugin>_create().     │
├──────────────────────────────────────────────────────────────┤
│  Layer 1 — C Kernel  (src/c/kernel/)                           │
│  ABI-stable C. Allocator, logger, ECS, world, frame packet,    │
│  vtable contracts (ke_render, ke_window…), threading prims.    │
└──────────────────────────────────────────────────────────────┘
```

Dependencies point downward only. A plugin never depends on the framework; the framework never reaches past Abstractions into the kernel concretes.

## Reading guide

| If you want to understand… | Read |
|---|---|
| Why the engine is shaped this way | [01 - Philosophy & Principles](01%20-%20Philosophy%20%26%20Principles.md) |
| ⭐ The core doctrine (Linux formula, universality, extensibility) | [13 - Extensibility & Universality](13%20-%20Extensibility%20%26%20Universality.md) |
| How the layers fit and depend | [02 - Layered Architecture](02%20-%20Layered%20Architecture.md) |
| The C core and its contracts | [03 - C Kernel](03%20-%20C%20Kernel.md) |
| How plugins work and why they're swappable | [04 - C++ Plugins](04%20-%20C%2B%2B%20Plugins.md) |
| The C# binding/wrapper/abstraction stack | [05 - C# Layers](05%20-%20C%23%20Layers.md) |
| The high-level game-authoring API | [06 - Framework](06%20-%20Framework.md) |
| Rendering pipeline and features | [07 - Graphics & Rendering](07%20-%20Graphics%20%26%20Rendering.md) |
| The threading model | [08 - Multithreading](08%20-%20Multithreading.md) |
| Asset loading and pipelines | [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md) |
| Building and tooling | [10 - Build & Tooling](10%20-%20Build%20%26%20Tooling.md) |
| Where the engine is heading | [11 - Roadmap & Vision](11%20-%20Roadmap%20%26%20Vision.md) |
| Decision/defect log | [12 - Architecture Backlog & Decisions](12%20-%20Architecture%20Backlog%20%26%20Decisions.md) |
| Editor lib, CLI, and how AI agents drive the engine | [14 - Editor, CLI & Agent Layer](14%20-%20Editor%2C%20CLI%20%26%20Agent%20Layer.md) |
| File formats (TOML), project/scene/resource schemas | [15 - Serialization & Project Files](15%20-%20Serialization%20%26%20Project%20Files.md) |
| Configuration service (IOptions plumbing, DI direction, mutability rules) | [16 - Configuration Service](16%20-%20Configuration%20Service.md) |
| Scene & Node serialization (type resolution, hydrator, class database, AOT) | [17 - Scene & Node Serialization](17%20-%20Scene%20%26%20Node%20Serialization.md) |
