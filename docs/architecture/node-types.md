# What does the engine derive from a node type's declaration?

A node type is a managed class deriving from `Node` (`src/csharp/framework/KernelEngine.Framework/Scene/Node.cs:12`)
that stands for a **set of ECS components**. Everything the engine knows about it — which components
it owns, what it reaches, what a scene may call it — is generated from its declaration or read off
it at bind time. There are two ways to declare one, and both end in the same Roslyn generator.

## From a header: the `[node:]` tag

A component struct whose doc carries `[node:Name]` becomes a class `Name`
(`src/c/render/kernel_engine/render/components.h:14`, `[node:Camera,base:Node3D,value]`). kabic
emits it (`CSharpBackend.RenderNodeType`, `src/csharp/kabic/Kabic.CSharpBackend/CSharpBackend.cs:432`,
driven from `scripts/generate_csharp.cs:98-105`). What it writes:

- `[GeneratedNodeComponent(typeof(<state>), "<component name>")]` on a `public partial class`
  (`CSharpBackend.cs:447-448`; the attribute is `Scene/GeneratedNodeComponentAttribute.cs:17`). The
  component name is the struct name without the `ke_` prefix and the `_component` suffix
  (`Convention.ComponentNameFor`, `src/csharp/kabic/Kabic.Core/Convention.cs:46`,
  `Convention.KernelEngine` at `:126-131`): `ke_camera_component` is `"camera"`.
- A constructor that seeds the state with the projection's `Default` when any field declares
  `[default:]` (`CSharpBackend.cs:452-457`, `ComponentInit` at `:521-526`).
- One `public partial` property per field, each tagged `[NativeField("<Field>", Component = typeof(<state>))]`
  (`ComponentSurface`, `:532-546`). Fields tagged `[idiom]` get no property. It writes no accessor body.
- `base:Other` becomes the C# base class `Other`, and `Other` must itself be tagged `[node:]` in the domain's model, compose headers
  included; a name that is not, or a `+`-joined list, fails generation (`BaseNodeOf`, `:502-513`).
  Without `base:` the class derives from `Node`.
- One registrar per domain, `Add<Domain>NodeTypes`, calling `services.AddNodeType<T>()` for every
  `[node:]` struct (`RenderNodeTypeRegistrar`, `:476-495`; `scripts/generate_csharp.cs:107-117`).
  `SceneNodesModule.Configure` calls the spatial one (`Modules/SceneNodesModule.cs:53`).

The component name is the same string the native module registers the component under: the header
that tags the struct also generates `KE_COMPONENT_NAME_CAMERA "camera"`
(`src/c/render/kernel_engine/render/component_fields.h:9`), and the render module registers by that
macro (`src/zig/render/module/src/render_module.zig:142`).

## From a class: partial properties and behavior

The generator is `NodePropertyGenerator`
(`src/csharp/generators/KernelEngine.SourceGenerators/NodePropertyGenerator.cs`). It considers a
class that has a `partial` auto-property or a method named `Update` or `On` with at least one
parameter (`:14-33`), and acts only if the class derives from `Node` (`:48`). A node type that is
not itself `partial` gets nothing; one that declares an `Update(...)` while not `partial` is a
compile error, `KESG005` (`:50-57`, `:555`).

It emits one `partial` part of the class containing a **slot** per component the type owns. A slot is
a state field `_generatedStateN`, a component id `_generatedCidN` and a ref accessor
(`:114-118`, `:329-333`). Where the slots come from:

| declaration | slots |
|---|---|
| the class carries `[GeneratedNodeComponent]` (one or several) | one per attribute; the struct and the registered name come from it (`:63-83`) |
| no attribute, at least one `partial` property | one, backed by a private nested struct the generator writes from the properties; named `snake_case` of the class name, namespace dropped (`:84-86`, `:95-112`, `SnakeCase` `:384-401`) |
| no attribute, no property | none |

The attribute is read from the class's own declaration only (`classSymbol.GetAttributes()`,
`:63`). A hand-written class deriving from a generated one therefore gets its own game slot for its
own properties, and inherits the base's slots through the base's part: `Paddle : Body2D` with a
`MoveAction` property is a node of two components (`examples/csharp/games/pong/scripts/Paddle.cs:11,19`).

A property is routed to the slot whose struct declares its field; a name two slots both declare, or
one no slot declares, is `KESG002`, and `[NativeField(..., Component = typeof(...))]` pins it
(`:493-514`, `:539`). `KESG003` is a pin naming a struct the class does not carry (`:547`).

### Property storage

A property reads and writes the component's own memory. The generated accessor obtains a `ref` to the
live component through `Node.GeneratedStorage` (`Scene/Node.cs:236-248`); a write that finds no live
storage — before the node is bound, or while an attach is still queued behind a wave barrier — lands
in the node's own pre-bind state and is published with `GeneratedSet` (`NodePropertyGenerator.cs:264-285`).

The property type and the field type must be the same, or differ only by `bool` over `byte`
(`CoercionFor`, `:532-537`) or `string` over a char array; anything else is `KESG001` (`:571`).
A `string` property on a game slot is an inline UTF-8 buffer of `[NodeText(n)]` bytes, default 128;
a longer value throws rather than truncating (`:97-102`, `:370-375`, `:319-322`).

### Component ids, by name, at bind

Every slot's id is looked up when the node binds, in `GeneratedBind` (`:336-347`): a native-backed
slot with `scriptHost.CidOfName("<name>")`, which throws when no module registered that name
(`ScriptHost.Idiom.cs:444-447`); a game slot with `scriptHost.RegisterComponent<Data>("<name>")`,
which registers it. Then each slot is seeded with `GeneratedSeed`, which writes the pre-bind state
**only if the entity does not already carry the component** (`Node.cs:208-212`) — so a node bound to
an entity the scene loader already filled keeps what the scene authored.

## Names a scene can use for one node type

Three namespaces are involved, and they are not normalized the same way.

| what | name | where it is resolved |
|---|---|---|
| the node's own component, for a block `[entity.<name>]` | the registered component name, matched exactly | `component_lookup` in the loader (`src/zig/framework/src/scene_loader.zig:331`) |
| the node type, for `type = "<name>"` | normalized, qualified first then short | `NodeTypeRegistry.Resolve` |
| a signal, for `signal = "<name>"` | the payload struct's own name, matched exactly | `signal_lookup` (`scene_loader.zig:480`) |

A game node's own block key is `SnakeCase(class name)`; its property keys inside the block are
`SnakeCase(property name)` (`NodePropertyGenerator.cs:410`).

### Resolving a node type

`AddNodeType<T>(name = null)` registers a registrar; the `NodeTypeRegistry` singleton is built from all
registrars the first time it is requested, not when `AddNodeType` runs
(`Scene/SceneServiceCollectionExtensions.cs:12-34`). `Register<T>` files the type under two names:

- the **qualified** name, `Normalize(name ?? typeof(T).FullName)`; two types claiming one qualified
  name throw at registration (`NodeTypeRegistry.cs:22-30`);
- the **short** name, `Normalize(typeof(T).Name)`; several types may share one (`:31-34`).

`Resolve` tries the qualified name, then the short name; a short name more than one type answers to
throws, listing the qualified candidates; an unknown name throws (`:45-61`). `Normalize` turns `+`
into `.` and starts a new `_`-separated word at an uppercase letter unless the previous character is
`.`, `_`, a digit, or an uppercase letter not followed by a lowercase one (`:67-87`):
`Sprite2D` is `sprite2d`, `HTTPServer` is `http_server`.

The native loader applies the same rule to the `type` string **before** calling the factory
(`normalizeTypeName`, `scene_loader.zig:209-244`, applied in `dispatchScript`, `:246-268`; tests at
`:1898-1932`), so the factory receives `pong.ball` whichever casing the scene wrote. A name whose normalized form does not
fit in 128 bytes is refused. With no factory registered, a `type` key is ignored
(`scene_loader.zig:252`).

## What binding a typed entity does

The scene loader creates the entity, applies its component blocks, and only then calls the script
factory (`processEntity`, `scene_loader.zig:545-632`, blocks at `:608`, factory at `:615`). The
managed factory registered by `SceneRouterModule` (`Modules/SceneRouterModule.cs:49-54`):

1. resolves the type name through the registry;
2. constructs the node with `ActivatorUtilities.CreateInstance`, so constructor parameters come from
   the service provider;
3. `ScriptHost.BindNativeEntity` (`Scene/ScriptHost.Idiom.cs:341-345`): `GeneratedBind`, then the
   node's own `OnBind`, then `BindScript`.

`BindScript` registers the node's script type with the native host on first use and binds the
entity to the instance (`ScriptTypeOf`, `:273-290`; `ke_script_host.register_type`,
`src/c/framework/kernel_engine/framework/script_host.h:93`). The native type name is
`clr.FullName`; the components are the node's **owned** set and the reach is `Self` or `Any` from
`ReachesOnlyItself`. `OnReady` runs after the whole scene file has loaded, deepest node first
(`TriggerReady`, `:498-509`); `OnUnbind` runs in `DestroyNode`, children first (`:331-343`).

A game slot's block, `[entity.paddle]`, is applied *before* any node of that type exists, so its
registration cannot happen at bind. The generator emits a static
`RegisterSceneApply(world, ecs)` per game-slot class (`:413-464`) that registers the component and an
apply callback reading each supported property from the block by its `snake_case` key; a module calls
it once per type (`examples/csharp/games/pong/PongModule.cs:32-34`). Supported property types are
enums (by name, case-insensitive), `string`, `float`, `double`, `bool`, `int`/`uint`/`long`/`short`/`byte`, `Vector2/3/4`
and `Quaternion`; a property of any other type has no scene key (`:428-452`). A key whose value has
the wrong type, or an enum name that does not parse, writes nothing and does not fail the load
(`VariantReader.Claims`, `src/csharp/ecs/KernelEngine.Ecs/VariantReader.cs:30`, claims the key whatever its type).

## Behavior

A node type has behavior when its class declares `void Update(in View view, ...)` whose first
parameter is a `View`, or overrides `OnUpdate(in View)` (`NodePropertyGenerator.cs:121-129`). Declaring both is
`KESG005`; every `Update` parameter after `View` must be a borrow or `Emit<T>`, else `KESG006`
(`:131-146`, `:563`). For `Update` the generator overrides `OnUpdate` to build each argument and call
it (`:163-183`), and overrides:

- `HasBehavior` to `true`;
- `ReachesOnlyItself` to `true` only when there is no hand-written `OnUpdate` **and** no borrow
  parameter; an `Emit<T>` is a borrow parameter, so it makes the reach `Any` (`:148-161`);
- `CollectBehaviorComponents`, which calls the base first and then adds one `NodeComponentUse` per
  slot — `Owned`, `Writes` when some property routed to the slot has a setter — and, for every
  non-`Emit` borrow, the components the borrowed type declares through `[GeneratedNodeComponent]` on
  it and its bases, as written and not owned (`:289-300`, `:670-676`, `Scene/NodeComponentUse.cs`).
  A borrowed type carrying no attribute contributes nothing.

When the first node of a type binds, `ScriptHost` raises `BehaviorTypeAdded` (`ScriptHost.Idiom.cs:83-88`)
and `SceneNodesModule` registers **one runtime system per node type**, `Scene.Behaviors.<Type>`, in
the `Update` phase (`Modules/SceneNodesModule.cs:107-173`). Its access is derived from a
probe — the first bound instance — through `CollectBehaviorComponents`:

- owned components other than `hierarchy` and `name` become one query when there are one to eight of
  them, each term read or write by the aggregated `Writes` (`:123-144`); with more, they move into the
  access list instead;
- hierarchy and name are always declared read, and reached components are declared with their access
  (`:135-142`);
- `perEntity` is `ReachesOnlyItself` (`:182`), which is what lets the runtime slice the type's
  entities across workers ([runtime.md](runtime.md#dispatch)).

The system body runs on a worker. It brackets its work with `EnterSystem(ctx)` so that a node created
or destroyed from inside it is deferred to the wave barrier (`ScriptHost.Idiom.cs:57-81`; `:242`,
`:341`), and calls `OnUpdate` for each entity whose bound node is of exactly that type (`:163-180`).

## Borrows and `Emit<T>`

A behavior reaches other nodes only through its `Update` parameters. The wrappers are
`Descendant<T>`, `Ancestor<T>` and `Anywhere<T>`, `ref struct`s generated from the
`[borrow_kinds]` enum `ke_script_borrow` (`script_host.h:64-79`,
`Generated/ScriptBorrowWrappers.g.cs`); the generator recognises one by a `[NodeBorrow]` attribute,
not by name (`NodePropertyGenerator.cs:632-647`). `[NodeName("x")]` on the parameter names the node
to find; without it the borrow matches on type alone (`:174-176`).

The generated `OnUpdate` resolves every borrow on every call (`Node.Borrow`, `Node.cs:170`); nothing
is cached, and a borrow is a `ref struct` that cannot be stored. `ScriptHost.Borrow`
(`ScriptHost.Idiom.cs:121-143`) asks the native host once per script type that is `T` or derives
from it (`ScriptTypesAssignableTo`, `:114-126`; the native `resolve` matches one exact id,
`script_host.h:175`). It answers `null` when nothing matches and also when two nodes do, so an
ambiguous borrow is unbound rather than arbitrary. `Ancestor` is the nearest match walking up
(`src/zig/framework/src/script_host.zig:342-352`); with several candidate ids the walk is done
managed (`ScriptHost.Idiom.cs:125-131`).

`Emit<T>` (`Scene/Borrows.cs:24`) is the right to raise signal `T` from this node. `T` must be
`unmanaged`. The signal's name is `typeof(T).Name` and its size `sizeof(T)`
(`Generated/SignalBus.g.cs:121-128`), the pair the bus treats as identity; a second registration of
the name with another size fails (`src/zig/framework/src/signal_bus.zig:95-102`). `Send` queues the
payload on the bus; delivery happens in `PostUpdate`, in the system `Scene.Signals.Deliver`
(`SceneNodesModule.cs:97-104`).

A node listens by declaring `void On(in T e)` for an unmanaged struct `T`; the generator overrides
`GeneratedDeliverSignal` to call it (`NodePropertyGenerator.cs:592-625`), and
`CollectSignalTypes` to declare `T` (`:584-606`). Every payload type a node type emits or handles is
declared with the bus when `SceneNodesModule` loads (`SceneNodesModule.cs:202-212`), which is what
lets the loader reject a scene naming a signal nobody declared
([framework.md](framework.md#signals-are-declared-before-a-scene-loads)). That step builds a
throwaway instance of **every** registered node type with `ActivatorUtilities`, so a node's
constructor runs once unbound at load.
