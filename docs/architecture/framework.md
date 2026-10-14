# What is the framework made of, and what does each piece depend on?

This is a map: the pieces of the framework plugin, what each receives and what it hands on. How a
piece works inside is on the generated page of its file. Contracts are under `src/c/framework/`,
the plugin under `src/zig/framework/`, the managed projection under `src/csharp/framework/`.

## The pieces

The framework is one plugin, `ke_framework`, with one factory header per piece. A piece is reached
only through its vtable.

| piece | contract | factory | receives | hands on |
|---|---|---|---|---|
| input actions | `ke_input_actions` | `ke_input_actions_create` | nothing; a `ke_input_snapshot` at each `evaluate` | named actions, polled |
| signal bus | `ke_signal_bus` | `ke_signal_bus_create` | `ke_signal_bus_params` | signal ids, connections, the deliveries of a frame |
| script host | `ke_script_host` | `ke_script_host_create` | `ke_ecs`, `ke_script_host_params` | script types, bindings, `resolve` of a borrow |
| scene hierarchy | `ke_scene_hierarchy` | `ke_scene_hierarchy_create` | `ke_runtime`, `ke_ecs` | world matrices, through one runtime system |
| scene tree | `ke_scene_tree` | `ke_scene_tree_create` | `ke_ecs`, `ke_runtime` | nodes as entities, and the hierarchy it owns |
| asset resolver | `ke_asset_resolver` | `ke_asset_resolver_create` | `ke_image_loader`, `ke_font_loader`, a project root | textures, meshes, materials, fonts; render service handles |
| world | `ke_world` | `ke_world_create` | `ke_world_params`: scheduler, ecs, runtime, scene tree, project root, logger, signal bus | the registry of how a scene fills a component |
| scene loader | `ke_scene_loader` | `ke_scene_loader_create` | a `ke_world`, a project root | nodes, components and connections built from a scene file |

The managed side mirrors them as `World`, `SceneTree`, `ScriptHost`, `SignalBus`, `SceneLoader`,
`NativeAssetResolver` and `NativeInputActions`, and composes them in three runtime modules:
`FrameworkModule` (signal bus, world and the tree it owns), `SceneNodesModule` (script host,
input, signal delivery, one behavior system per node type) and `SceneRouterModule` (scene
switching). Each depends on the one before it.

## What ties the pieces together

**The tree is a view over the ecs.** A node is an entity carrying the hierarchy, name and world
transform components. The scene tree creates the hierarchy piece itself when it is given a
runtime, and owns it; the hierarchy is destroyed only after the runtime has finished ticking.

**The world is the loader's door.** The scene loader reaches the ecs and the scene tree through
the slots of `ke_world`, and the logger and the signal bus through functions of the plugin that
are not slots. For each component the world holds a field table (`ke_component_field`) and a
callback (`ke_component_apply_fn`); a scene block is written through the table first, then the
callback gets the entries. The world stores a scheduler and a project root that nothing reads.

**A typed entity ends in a script factory.** The loader creates the entity and applies its
blocks, then hands the entity and the normalized "type" string to the `ke_script_factory_func`
registered on the loader. Without a factory the "type" key is ignored. The managed factory
builds the node and binds it to the entity in the script host.

**Bindings are structural changes.** `bind` and `unbind` change the host at once and belong to
code that no system body runs beside; `bind_deferred` and `unbind_deferred` record the change in
the `ke_ecs_commands` of the running system. The managed `ScriptHost` chooses by whether a
system context is current.

**A signal must exist before a scene names it.** The loader resolves a connection's signal with
`signal_lookup`, which never registers, and fails the load on an unknown name. The runtime that
owns the node types registers each signal with `signal_id` before the first load; the managed
side does so for every registered node type when `SceneNodesModule` loads.

**A project root is held three times.** The asset resolver, the scene loader and the world each
keep their own copy, and each interprets "res://" itself.

## What the parts agree on without a contract

- Component names: "transform", "transform2d", "world_transform", "hierarchy", "name", and
  "script_instance" for a binding.
- Node type names: the managed `NodeTypeRegistry.Normalize` and the loader's `normalizeTypeName`
  apply one rule, so the factory receives the same spelling whichever casing a scene wrote.
- Signal identity: the managed side names a signal by the payload type's name and its size; a
  second registration with another size fails.
- Scene keys: an entity's "name", "parent", "scene", "type" and "connect" array with "signal",
  "target" and "handler"; "components" and "properties" blocks are refused.
- Mesh paths: "res://primitives/quad", "plane", "cube", "sphere".
- Worker index 1: `SceneNodesModule` pins "Scene.Input" to it and `SceneRouterModule` pins its
  scene load and "Scene.Router.Flush" to it.
- Managed system names: "Scene.Input", "Scene.Signals.Clear", "Scene.Signals.Deliver",
  "Scene.Behaviors.<type>", "Scene.Router.Flush"; the hierarchy's is "scene.propagate_transforms".
- Input file: an "action" table of actions with a "type" and "bindings" of kind "key",
  "key_pair", "key_quad" or "mouse"; the managed map looks up each enum value by its name.
