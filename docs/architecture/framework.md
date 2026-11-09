# Framework

This is a map: the pieces of the framework plugin, what each receives and what it hands on. How a
piece works inside is on the generated page of its file. Contracts are under `src/c/framework/`,
the plugin under `src/zig/framework/`, the managed projection under `src/csharp/framework/`.

## The pieces

The framework is one plugin, `ke_framework`, with one factory header per piece. A piece is reached
only through its vtable.

| piece | contract | factory | receives | hands on |
|---|---|---|---|---|
| input actions | `ke_input_actions` | `ke_input_actions_create` | a runtime, a `ke_input`, a configuration and the section it reads | named actions, evaluated once per tick by the "input.actions" system |
| scene hierarchy | `ke_scene_hierarchy` | `ke_scene_hierarchy_create` | `ke_runtime`, `ke_ecs` | world matrices, through one runtime system |
| scene tree | `ke_scene_tree` | `ke_scene_tree_create` | `ke_ecs`, `ke_runtime` | nodes as entities, and the hierarchy it owns |
| node types | `ke_node_types` | `ke_node_types_create` | `ke_runtime`, `ke_ecs`, `ke_scene_tree`, an optional `ke_input_actions` | node types and event types, each behaviour a system of its phase |
| scene files | `ke_scene_files` | `ke_scene_files_create` | `ke_ecs`, `ke_node_types`, `ke_asset_resolver`, `ke_io` | the nodes a scene file describes, and the `scene_slot` node type |
| asset resolver | `ke_asset_resolver` | `ke_asset_resolver_create` | `ke_image_loader`, `ke_font_loader`, a project root, a `ke_io` | textures, meshes, materials, fonts; render service handles |

The managed side projects each of them as a class built by its factory: `DefaultInputActions`,
`DefaultSceneTree`, `DefaultNodeTypes`, `DefaultSceneFiles`, `DefaultAssetResolver`. The C# node
SDK over `ke_node_types` is mapped in `node-types.md`.

## What ties the pieces together

**The tree is a view over the ecs.** A node is an entity carrying the hierarchy, name and world
transform components. The scene tree creates the hierarchy piece itself when it is given a
runtime, and owns it; the hierarchy is destroyed only after the runtime has finished ticking.

**A node is born from its type.** `spawn` records a node carrying its type's tag, its fields and
the components its type names in `with`, each holding the type's initial value unless the spawn
gives another. A scene file is a list of spawns: `ke_scene_files` reads it and spawns through the
node types, then writes each authored block through the component's field table.

**A field table belongs to the ecs once registered.** `component_register` copies the table, names
included, so a table only has to live for the call that registers it.

**A scene changes by a slot.** A `scene_slot` node holds a scene file path; when the path differs
from the one it last instantiated, its children are destroyed and the file at the path is
instantiated under it.

**The asset resolver holds the project root.** It is the one piece that interprets "res://"; the
scene files resolve a scene reference through it.

## What the parts agree on without a contract

- Component names: "transform", "transform2d", "world_transform", "hierarchy", "name",
  "scene_slot".
- A node type's tag is registered as "node.<name>", its fields as "<name>".
- Mesh paths: "res://primitives/quad", "plane", "cube", "sphere".
- System names: "input.actions" and "scene.propagate_transforms".
