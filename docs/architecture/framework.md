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
The hierarchy component holds five entity ids — parent, first child, last child, next sibling and
previous sibling (`components.h:12-18`) — as an intrusive list, so relinking is constant-time
(`scene_hierarchy.h:14-16`).

### Child order

A new node is **appended**: it is linked after its parent's `last_child`, and becomes `first_child`
when the parent had none (`populateNode`, `src/zig/framework/src/scene_tree.zig:104-142`, link at
`:133-141`). Walking `first_child` and then `next_sibling` therefore visits children in the order they
were created, which `next_sibling` states as a guarantee (`scene_tree.h:58`; test
`scene_tree.zig:755`). `last_child` and `prev_sibling` are what keep an append and an unlink
constant-time (`destroySubtree`, `:263-282`).

A parent of `KE_ENTITY_INVALID` means the root (`scene_tree.zig:169`). A node created through a system
context gets its id at once but is linked when the deferred command is applied
(`cbCreateNode`, `:152-156`; `vtCreateNode`, `:158-195`). `find_node` with a bare name searches
depth-first from the root and returns the first match in child order; a name containing `/` is walked
one segment at a time from the root (`findByName`, `childBySegment`, `vtFindNode`, `:198-247`).

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

## What a node type declares to the script host

`ke_script_host` is the language-neutral record of which entities a scripting runtime has bound an
object to (`script_host.h:15-28`). The object is an opaque pointer the host never reads; the binding
is stored as a component, `script_instance`, on the entity itself
(`src/zig/framework/src/script_host.zig:44`, `bind` at `:202-242`), so a lookup is one component read
and a query can match scripted entities.

A runtime declares a **script type** with `register_type(name, components, reach)`
(`script_host.h:93`, `script_host.zig:94-161`). The declaration is the access a type's instances have:

- `components` is the set of components an instance carries, read back by `type_components`; a host
  turns it into the type's query and access list ([node-types.md](node-types.md#behavior));
- `reach` is `KE_SCRIPT_REACH_SELF` when an instance touches only its own entity, so two instances
  cannot overlap and the runtime may slice them across workers, or `KE_SCRIPT_REACH_ANY` when it
  reaches entities it was not handed. Anything unproven is declared `ANY`, and an unknown type id
  reads as `ANY` (`script_host.h:37-48`, `script_host.zig:195-200`).

Registering a name twice returns the same id when the description matches and fails with
`already_exists` when the components or the reach differ (`:126-140`). A name is at most 95 bytes, a
type declares at most 16 components, and the table holds `max_types` types, default 64; past any of
these registration fails (`:9`, `:14`, `:16`, `:113-120`, `:142-145`).

`bind` refuses an entity that already carries an instance (`:223`); `unbind` is constant-time by
swapping the last entity of the type into the vacated slot (`:244-261`), so `instances` is not in
binding order once anything has been unbound.

`resolve(owner, type, name, reach)` answers a borrow: the one entity of that type, optionally of that
name, found **below** the owner depth-first, **above** it nearest-first, or **anywhere** the type is
bound. When two entities qualify it returns none and reports `KE_SCRIPT_RESOLVE_AMBIGUOUS`; the ancestor
walk returns the nearest and so never reports it (`script_host.zig:299-366`).

## Signals are declared before a scene loads

`ke_signal_bus` has two ways to turn a signal name into an id, and a scene uses only one of them.
`signal_id(name, payload_size)` registers the name on first use; the payload size is part of its
identity, and a later registration with a different size fails (`signal_bus.h:52-63`,
`src/zig/framework/src/signal_bus.zig:71-117`; `KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN` leaves the size to be
fixed by the first caller that knows it, `:95-100`). `signal_lookup(name)` only looks; it never
registers (`signal_bus.zig:119-134`).

The scene loader resolves `signal = "..."` of a `[[entity.connect]]` with `signal_lookup`
(`scene_loader.zig:480`), and a name that was not registered fails the load. A signal therefore exists
for a scene only if some runtime called `signal_id` for it **before** the scene is read. The managed
layer does that for every signal a node type emits or handles when `SceneNodesModule` loads
([node-types.md](node-types.md#borrows-and-emitt)); a runtime in another language must do the same
before its first `load`.

A signal name is at most 63 bytes (`signal_bus.zig:10`, `:88`).
