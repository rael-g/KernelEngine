# Node types

This is a map: the parts that turn a node class into components, systems and scene names, and what
each hands on. How a part works inside is on the generated page of its file. The generator is
under `src/csharp/generators/`, the managed side under `src/csharp/framework/`, the native side
under `src/zig/framework/`.

## The parts

A node type is a managed class deriving from `Node` that stands for a set of ECS components.

| part | where | receives | hands on |
|---|---|---|---|
| kabic | `src/csharp/kabic/` | a component struct tagged "[node:Name]" in a header | a `partial` class with `GeneratedNodeComponentAttribute`, and an Add<Domain>NodeTypes registrar |
| `NodePropertyGenerator` | `src/csharp/generators/` | a class deriving from `Node` with `partial` properties, `Update` or `On` | component slots, behavior overrides, signal dispatch, `RegisterSceneApply` |
| `NodeTypeRegistry` | `Scene/NodeTypeRegistry.cs` | `AddNodeType<T>` registrations | a `Type` for a name a scene wrote |
| `ScriptHost` | `Scene/ScriptHost.Idiom.cs` | a constructed `Node` and its entity | a script type registered per node class, a binding, borrows, signal deliveries |
| `SceneNodesModule` | `Modules/SceneNodesModule.cs` | the first node of a type with behavior | one runtime system for that type, and the signals of every registered type |
| `SceneRouterModule` | `Modules/SceneRouterModule.cs` | the loader's script factory call | the node, constructed with the service provider and bound |
| scene loader | `ke_scene_loader` | a scene file | entities with their blocks, then the factory call |

## What ties the parts together

**There are two ways to declare a type, and both end in a slot.** From a header, kabic emits a
class carrying `GeneratedNodeComponentAttribute`, one attribute per component. From a class,
`NodePropertyGenerator` synthesizes one backing struct for the `partial` properties, named after
the class in snake case. Either way the generator adds a slot per component: a state field, a
component id and a ref accessor. The attribute is read from the class's own declaration only.

**Component ids are resolved by name when the node binds.** A native-backed slot looks its name
up with `CidOfName`, which throws if no module registered it; a game slot registers its struct
under its name. Each slot is then seeded only if the entity does not already carry the component,
so what the scene authored wins.

**A scene reaches a node in three namespaces.** A block `[entity.<name>]` is matched exactly
against the registered component name. A `type = "<name>"` goes through the registry, which tries
the qualified name and then the short one, and fails on an unknown or ambiguous name. A signal is
matched exactly against the name the bus holds.

**Binding runs in a fixed order.** The loader creates the entity and applies its blocks, then
calls the factory. The managed factory constructs the node, then `BindNativeEntity` runs
`GeneratedBind`, the node's `OnBind`, and registers the entity with the script host. `OnReady` is
raised by `SceneRouter` after the whole file has loaded, children first; `OnUnbind` runs in
`DestroyNode`, children first.

**A game component needs its scene surface registered before the scene loads.** Its block is
applied before any node of the type exists, so the generated static `RegisterSceneApply` must be
called by a module in `OnLoad`.

**Behavior becomes one system per type.** A type with `Update(in View ...)` or an `OnUpdate`
override reports `HasBehavior`. When the first node of that type binds, `SceneNodesModule`
registers a system in `KE_PHASE_UPDATE` whose query is the owned components and whose access list
adds hierarchy and name read and the components reached through borrows, as
`CollectBehaviorComponents` reports them. The system is sliced per entity only when
`ReachesOnlyItself` is true, which it is for no hand-written `OnUpdate` and no borrow parameter.

**All access is a parameter.** A behavior reaches other nodes only through `Descendant<T>`,
`Ancestor<T>` and `Anywhere<T>`, and raises signals through `Emit<T>`. A borrow is resolved on
every call by `ScriptHost`, which asks the native script host once per script type assignable to
the requested type and answers null on none or on ambiguity. A node listens with `On(in T)`;
deliveries are made in "Scene.Signals.Deliver", and `SceneNodesModule` declares every payload
type of every registered node type before the first scene is read.

## What the parts agree on without a contract

- The component name of a header-declared node: the struct name without "ke_" and "_component".
  The native module registers the component under the same string.
- The component and key name of a game node: `SnakeCase` of the class name; its property keys are
  `SnakeCase` of the property name.
- The type name spelling: `NodeTypeRegistry.Normalize` and the native `normalizeTypeName` apply
  the same rule (snake case, "." for nesting), and a name over 128 bytes is refused natively.
- The script type name is the full name of the CLR type; its components are the owned set.
- A signal is identified by the payload type's name and its size.
- Diagnostics: "KESG001" to "KESG003" and "KESG005" to "KESG007".
