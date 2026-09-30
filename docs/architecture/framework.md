# What is the framework made of, and what does each piece depend on?

The framework is one plugin, `src/zig/framework/`, built as `ke_framework` (`build.zig:140`). It
exports eight factories, one per piece. Each piece is constructed on its own from the borrowed
objects it needs; no piece is reachable except through its vtable
([layers.md](layers.md#layer-2--a-plugin-exports-one-factory-and-nothing-else)).

| piece | factory | takes |
|---|---|---|
| input actions | `ke_input_actions_create` (`input_actions_create.h:27`) | nothing |
| signal bus | `ke_signal_bus_create` (`signal_bus_create.h:42`) | a params struct of five capacities |
| script host | `ke_script_host_create` (`script_host_create.h:39`) | `ke_ecs`, `max_types` |
| scene hierarchy | `ke_scene_hierarchy_create` (`scene_hierarchy_create.h:35`) | `ke_runtime`, `ke_ecs` |
| scene tree | `ke_scene_tree_create` (`scene_tree_create.h:38`) | `ke_ecs`, `ke_runtime` |
| asset resolver | `ke_asset_resolver_create` (`asset_resolver_create.h:35`) | image loader, font loader, project root |
| world | `ke_world_create` (`world_create.h:27`) | scheduler, `ke_ecs`, `ke_runtime`, scene tree, project root, logger, signal bus |
| scene loader | `ke_scene_loader_create` (`scene_loader_create.h:36`) | a world, project root |

Every capacity a piece limits itself to is a params field with `0` selecting the default
(`ke_signal_bus_params`, `ke_script_host_params`).

## The scene tree

A node is an entity. `ke_scene_tree_create` registers five components — transform, 2D transform,
world transform, hierarchy, name — if the ECS does not have them yet, then creates one root
entity named `Root` carrying hierarchy and name (`src/zig/framework/src/scene_tree.zig:420-452`).
Parent, first child and next sibling are stored as entity ids in the hierarchy component, so
relinking is constant-time (`scene_hierarchy.h:14-16`).

When a runtime is supplied, the tree also builds a scene hierarchy by calling that piece's own
factory (`scene_tree.zig:466`). The hierarchy registers two systems: one flattens the tree into an
array ordered parents-before-children, the other turns local transforms into world matrices by
walking that array once, never recursing (`scene_hierarchy.h:14-23`). The hierarchy must be
destroyed only after the runtime has finished ticking, because its systems are registered for the
runtime's lifetime (`scene_hierarchy.h:26-28`).

## The world

`ke_world` holds seven borrowed pointers — scheduler, ecs, runtime, scene tree, project root,
logger, signal bus — and a registry mapping a component id to how a scene block fills it
(`src/zig/framework/src/world.zig:22-34`, stored at `world.zig:231-237`).

What it exposes (`world.h`, slots from line 55):

- three accessors, `ecs`, `runtime` and `scene_tree`, each tagged `[idiom]` as superseded by the
  managed property of the same name;
- `register_component_fields` / `get_component_fields`, a generated table describing a
  component's fields;
- `register_component_apply` / `get_component_apply`, a callback for what a table cannot describe.

A scene load consults the field table first, then the callback (`world.h:72-74`).

What reads the world: the scene loader takes the ecs and the scene tree through the accessors
(`scene_loader.zig:57-63`), the logger and the signal bus through functions that are not vtable
slots (`world.zig:47-56`; `scene_loader.zig:293`, `450`), and the registry. Nothing in the plugin
reads the world's stored `scheduler` or `project_root`: `grep -n 'scheduler\|project_root'
src/zig/framework/src/world.zig` shows them assigned at `world.zig:231` and `235` and nowhere else.

## The project root

A project root is passed separately to three pieces — the world, the scene loader, the asset
resolver — and each keeps its own copy: the resolver duplicates it (`asset_resolver.zig:501`), the
loader copies it into a fixed buffer (`scene_loader.zig:43`, `776-783`), the world stores the
pointer. The resolver rewrites `res://x` to `<project_root>/x` and passes any other path through
unchanged (`asset_resolver.zig:72-77`).
