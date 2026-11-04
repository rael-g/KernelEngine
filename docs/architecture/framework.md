# Framework

This is a map: the pieces of the framework plugin, what each receives and what it hands on. How a
piece works inside is on the generated page of its file. Contracts are under `src/c/framework/`,
the plugin under `src/zig/framework/`, the managed projection under `src/csharp/framework/`.

## The pieces

The framework is one plugin, `ke_framework`, with one factory header per piece. A piece is reached
only through its vtable.

| piece | contract | factory | receives | hands on |
|---|---|---|---|---|
| input actions | `ke_input_actions` | `ke_input_actions_create` | a `ke_io`; a `ke_input_snapshot` at each `evaluate` | named actions, polled |
| signal bus | `ke_signal_bus` | `ke_signal_bus_create` | `ke_signal_bus_params` | signal ids, connections, the deliveries of a frame |
| script host | `ke_script_host` | `ke_script_host_create` | `ke_ecs`, `ke_script_host_params` | script types, bindings, `resolve` of a borrow |
| scene hierarchy | `ke_scene_hierarchy` | `ke_scene_hierarchy_create` | `ke_runtime`, `ke_ecs` | world matrices, through one runtime system |
| scene tree | `ke_scene_tree` | `ke_scene_tree_create` | `ke_ecs`, `ke_runtime` | nodes as entities, and the hierarchy it owns |
| asset resolver | `ke_asset_resolver` | `ke_asset_resolver_create` | `ke_image_loader`, `ke_font_loader`, a project root, a `ke_io` | textures, meshes, materials, fonts; render service handles |
| component registry | `ke_component_registry` | `ke_component_registry_create` | `ke_ecs` | how a scene fills a component, and the short names a scene may write |
| scene loader | `ke_scene_loader` | `ke_scene_loader_create` | `ke_ecs`, `ke_scene_tree`, an optional `ke_signal_bus`, `ke_component_registry`, `ke_asset_resolver`, `ke_io` | nodes, components and connections built from a scene file |

The managed side mirrors them as `ComponentRegistry`, `SceneTree`, `ScriptHost`, `SignalBus`, `SceneLoader`,
`AssetResolver` and `InputActions`, and composes them in three runtime modules:
`FrameworkModule` (signal bus, scene tree, component registry), `SceneNodesModule` (script host,
input, signal delivery, one behavior system per node type) and `SceneRouterModule` (scene
switching), which loads the initial scene in the startup phase, once every module has loaded.

## What ties the pieces together

**The tree is a view over the ecs.** A node is an entity carrying the hierarchy, name and world
transform components. The scene tree creates the hierarchy piece itself when it is given a
runtime, and owns it; the hierarchy is destroyed only after the runtime has finished ticking.

**The registry describes, the loader writes.** The scene loader is given the ecs, the scene tree,
the signal bus and the component registry it works on. For each component the registry holds a
field table (`ke_component_field`) and a callback (`ke_component_apply_fn`); a scene block is
written through the table first, then the callback gets the entries.

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

**The asset resolver holds the project root.** It is the one piece that interprets "res://"; the
loader resolves a scene reference through it.

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
