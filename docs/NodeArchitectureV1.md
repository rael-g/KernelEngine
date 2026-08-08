# Node Architecture V1 — node ergonomics without an OOP engine

**Status**: Design. Nothing here is built. This document records a decision about the *shape* node scripting should take, reached in discussion, plus the concrete defects in today's code that motivated it. Every claim about what the code does today is cited `file:line`; every claim about what should exist is a proposal.

**Supersedes**: the node-ergonomics half of [`ScriptingArchitectureV3.md`](ScriptingArchitectureV3.md) §7 — specifically §7.14.4's `base:`-tagged node headers and §7.14.9's remaining items, which assume class inheritance is the composition mechanism. §7.1's framing (a domain is not done until its nodes exist in every language) is unchanged and is the reason this document exists.

**Audience**: Engine maintainer + future `kabic` backend authors.

---

## 0. The rule everything derives from

> **Every access is a parameter. A node type has no fields.**

Both halves are load-bearing and neither works alone. Everything below — the safety model, the access lists, the cross-node rules, the portability to a non-OOP language — is a consequence of these two sentences.

---

## 1. What is being replaced, and why

The current node layer uses **class inheritance as the composition mechanism**: a node type declares one component, and a node that needs two components gets them by deriving from another node type. `kabic` encodes this in the header tag `[node:MeshRenderer,base:Node3D]`, and the C# backend renders it literally as a base class ([`CSharpBackend.cs:112`](../src/csharp/kabic/Kabic.CSharpBackend/CSharpBackend.cs:112)).

Four problems, in increasing order of how much they cost:

**It produces silent-failure bugs.** A derived node binds one component per class in the chain, each with its own cid. If a generated `OnBind` fails to chain to its base, the base class's component is never bound, its cid stays 0, and every write to its properties is discarded with no error. This is not hypothetical — it happened, it blanked the geometry in several examples, and it was only found by instrumenting component values in a headless probe. A declared component *set* has no such failure mode: there is no chain to forget.

**It produces diamonds.** `Sprite2D` wants a 2D projection of the transform *and* a mesh. Mesh already hangs off `MeshRenderer`, which is a sibling of `Node2D` under `Node3D`. Single inheritance cannot express it. `Node2D` itself is already the symptom: it derives from `Node3D` without being one — it is a different *projection* of the same data, forced into a subtype relationship because that was the only available join.

**It leaks C# into the IR.** `base:` in a C header declares a C# class relationship. A Zig backend reading that IR receives `base: "Node3D"` and has nothing to do with it but reimplement class semantics. This is the defect that makes the current design fail the "another backend can render this" test, and it is the one concrete thing that must change first.

**It tells the scheduler nothing.** Behavior is a virtual method the engine calls per instance. The runtime's wave builder orders systems on declared component access; a node's `OnUpdate` declares none, so the scheduler cannot know what it touches.

Two further symptoms, visible in game code today: `Ball` caches node references in fields across frames ([`Ball.cs:48`](../examples/csharp/games/pong/scripts/Ball.cs:48), [`:49`](../examples/csharp/games/pong/scripts/Ball.cs:49), [`:60`](../examples/csharp/games/pong/scripts/Ball.cs:60)), and `Paddle` reads a component by string name — the exact thing a node layer exists to prevent.

---

## 2. Diagnosis: each engine misassigns one layer

The design below is not "a bit of each paradigm". It assigns each paradigm to the layer it is good at and forbids it from leaking into the others. The claim is falsifiable, and the evidence is that the known pain of three shipping engines each lands on one misassigned layer:

**Unity / Unreal** put data-orientation at the *identity* layer. `GetComponent<T>()` is how an object asks who it is. A component is simultaneously storage, identity, and the home of behavior. The rigidity people complain about is not aesthetic; it is one layer using the wrong tool.

**Bevy** has no identity layer at all. Everything is a query. "This specific paddle" is awkward to say, and locality of behavior is gone — you learn what a thing does by searching for systems that mention it.

**Godot** puts OOP at the *composition* layer, where it produces the diamond, and at the *contract* layer, where virtual dispatch with ambient access tells a scheduler nothing.

None of the three chose wrong; each extended one good choice too far.

---

## 3. The assignment

| Layer | Paradigm | Why it wins there |
|---|---|---|
| Identity + hierarchy | Object-oriented | A node has a name, a place in a tree, and its behavior is written where you look for it. Godot's real strength. |
| Storage | Data-oriented | Components, columns, entities. Never visible to the game author. |
| Behavior contract | Functional | The signature declares everything the method reaches. No ambient access, no hidden singletons. |
| Behavior body | Procedural | Game logic reads best as plain imperative code. |

The contract layer being functional is what makes the whole thing work: it is referential transparency *at the boundary* while the body stays imperative.

---

## 4. The node model

### 4.1 Bundles, not base classes

An engine node type is a **declared set of components** plus a property surface projecting them. `Node` is `{name, hierarchy}`. `Node3D` is `{transform}`. `Body2D` is `{transform2d, body2d}`.

Engine node types do **not** derive from each other. They compose.

**Bundles compose bundles, and each declares only its own delta.** `Body2D` does not re-list `Node2D`'s components; it references `Node2D` and adds `body2d`. `KinematicBody2D` references `Body2D` and adds its own. The full component set is the transitive union, computed at generation time — never written out by hand at any level. Composition is what removes the repetition; it is not a synonym for repeating the parts.

This is the *whole* mechanism. There is no second one: a game type composing a bundle (§4.1, `[Node(Bundle = typeof(Body2D))]`) and a bundle composing another bundle are the same declaration doing the same thing at two levels.

The only inheritance anywhere is `Node`, which every node type shares so that untyped tree traversal has a type to return (§7.1). Nothing else is a base class of anything else, in any backend.

A game node type does exactly the same thing as a bundle: it references one and adds its own state.

```csharp
[Node(Bundle = typeof(Body2D))]
public sealed partial class Paddle { /* own component-backed state */ }
```

Its component set is `Body2D`'s transitive set plus its own — it re-declares none of it, and it is not a subtype of `Body2D`. There is no virtual dispatch across game types, so nothing about this needs inheritance to exist in the target language.

`Sprite2D` and `MeshRenderer` may declare the same component set and differ only in how they project the transform (`Vector2` vs `Vector3`). That is legitimate: the node type is the *surface*, the components are the *storage*. It is precisely the Node2D/Node3D distinction, said without lying about subtyping.

### 4.2 When is it a child node, when is it a component?

> **If the part has its own transform, it is a child node. If it is an aspect of the same thing, it is a component on the same entity.**

The test of this rule is that it reproduces Godot's own layout decisions unprompted. A physics body is *where the node is* → component, which is why Godot has you inherit `CharacterBody2D` rather than parent one. A collision shape has its own offset and there may be several → child node, which is why `CollisionShape2D` is a separate node in Godot. A sprite whose scale differs from the owner's logical size → child node.

This project already composes through the tree: [`Paddle.scene`](../examples/csharp/games/pong/scenes/Paddle.scene) gives the root a `CollisionShape2D` child and a `Sprite2D` child. Only the physics body escaped, becoming an imperative handle for lack of a `Body2D` node type.

### 4.3 What `self` is

`self` is a **borrowed view over one entity's components, valid for the duration of the call**. It owns nothing and has no lifetime.

In C# it is a normal `class` with no fields — every property is component-backed. In Zig it is a struct of pointers. Neither requires inheritance, an allocation, or a per-entity managed object: a node type with no state can be **one instance reused across the iteration**, rebound per entity.

`ref struct` is *not* required for safety (see §5) and should not be used if it costs idiom. C# should look like C#.

---

## 5. The safety model

The concern is a game author caching a node reference and mutating it next frame, outside the declared access — a data race the scheduler cannot see.

The guarantee does **not** come from the type system. It comes from the data model:

- Game state lives in components.
- A component is a C-ABI data struct — copied, stored in columns, serialized into scene files. A pointer field in a component is meaningless and `kabic` must reject it.
- A node type has no fields (§0).

Therefore **there is nowhere to put a cached reference**. `_board = ...` is not forbidden by a rule; it is unwritable, because no field exists to hold it.

This is why the guarantee is portable. A `ref struct` would make C# stronger than Zig and reintroduce an asymmetry; deriving safety from the data model leaves both languages equal. C# may still get compiler help for free where it is cheap, but nothing depends on it.

**Honest residue.** Zig has globals and `@ptrCast`; a determined author escapes. The standard being applied is the one `std` itself holds: *the idiomatic path is safe and escaping requires visibly leaving the model.* This document does not claim memory safety in a language that never promised it.

---

## 6. Behavior is a system, not a hook

A node's `update` is not a virtual method the engine calls per instance. It is a **system**, and the generator lifts the iteration out of it:

1. The method's **signature** is the access list — parameters, never body analysis.
2. The generator emits one system per node type, registered with that access list.
3. The system iterates the query view and invokes the body once per entity.

The author writes per-instance code (ergonomic); the scheduler sees a declared, batched system (correct). Body analysis is never used: inference is partial by nature, and a partial access list is a silent data race, which is the worst failure this engine can produce.

The hook-discovery half of this is already backend-neutral by accident: [`NodePropertyGenerator.cs:99`](../src/csharp/generators/KernelEngine.SourceGenerators/NodePropertyGenerator.cs:99) finds `OnUpdate` structurally at compile time by inspecting symbol members, not by reflection. The Zig equivalent is `@hasDecl` — same shape, same phase, different dialect.

---

## 7. Reaching other nodes

### 7.1 Reading and writing another node's data

A typed borrow, obtained as a parameter: `Child<AudioPlayer>`, `Ref<Scoreboard>`, `Parent<Body2D>`. The borrow's type determines which components are reachable, exactly as a typed field would in any language, and it feeds the access list.

Untyped traversal survives through the shared `Node` base: `FindByName` returns a `Node`, and a `Node` exposes only the components every node has (name, hierarchy). This is the analogue of `object` — you can walk the tree without knowing types, and you narrow with a typed request when you want data.

### 7.2 Calling another node's behavior

**Nothing prohibits it, and it is not blocked by a rule.** `audioPlayer.Play()` works, because `Play()` touches only `AudioPlayer`'s own components and the caller declared `Child<AudioPlayer>`.

What is *impossible* is calling a method whose arguments you cannot produce. Because every access is a parameter (§0), a method's total reach is its signature. `Scoreboard.RecordGoal` needs `Child<Label>` borrows to update its labels; a caller who did not declare them cannot supply them, so the call does not compile. If the caller declares them, the access list is correct and the call is allowed.

The model never says "no". It says **declare it, or you have no way to call it.**

This is why transitive access lists compose without any analyzer walking method bodies: to call you must pass, to pass you must hold, to hold you must have declared. Passing borrows down to helper methods is not verbosity to be sugared away — **it is the mechanism that makes the access list sound.** Any sugar that lets a helper's requirements be inferred rather than passed destroys the property.

### 7.3 A fat parameter list is a design smell, not a cost of the model

The obvious objection to §7.2 is that a caller ends up declaring borrows it should not have to know about. If `Scoreboard.RecordGoal` updates the two `Label` children that display the score, then its signature is `RecordGoal(bool, Child<Label>, Child<Label>)`, and a `Ball` that just wants to report a goal has to declare — and therefore know about — the scoreboard's internal structure.

That is real, and the fix is not machinery. `RecordGoal` is doing two things at two different layers: mutating state (the counters) and updating presentation (the labels). They are only fused because OOP with a stored reference lets them fuse. Split, the reach collapses:

```csharp
public sealed partial class Scoreboard
{
    public int Left  { get; set; }
    public int Right { get; set; }

    void RecordGoal(bool leftScored) { if (leftScored) Left++; else Right++; }
}
```

`RecordGoal`'s reach is now `{scoreboard}`. The caller declares `Ref<Scoreboard>` and nothing else. Writing the labels becomes a method of `Scoreboard` itself, declaring `Child<Label>` borrows and running as its own system — **the borrow that reaches further belongs to the owner of those children, not to a stranger passing through.**

This is not a workaround invented to dodge the objection; it is the pattern the engine already uses everywhere native. `render.ui.labels` derives glyph quads from label data. `mesh_resolve` fills handles from what the scene authored. `scene.propagate_transforms` derives world matrices from the hierarchy. In each, data is mutated by whoever owns it and presentation is derived by a system. A method reaching directly into another node's children to update a view is the exception, and it exists by inherited style rather than necessity.

The generalisation is worth stating as a rule:

> **A signature growing fat with borrows means the method is doing two things at different layers.**

The parameter list is a coupling gauge. What OOP hides behind a reference stored in a field, this model surfaces in the type. That is a property of the design, not a tax on it.

**The mechanical alternative, and why it is not the default.** `Ref<T>` *could* be defined as "T plus everything T's methods reach", computed statically by unioning T's own signatures — no body analysis required. It works, and it removes the leak. But it widens the caller's access list to cover components the caller never touches, so the caller serialises against them; and the widening is silent — the day someone gives `T` a method that reaches further, every caller of `T` loses parallelism without being edited. It should stay available for a genuinely composite operation and never become the default, because the moment it is the default the coupling gauge stops measuring.

### 7.4 Where signals fit

Signals are the *ergonomic* choice for decoupling when a caller does not want to carry another subsystem's borrows — the same role they play in Godot. They are not structurally mandatory. (§7.14.3 of [`ScriptingArchitectureV3.md`](ScriptingArchitectureV3.md) already has them queued; this document does not change their design, only their justification.)

---

## 8. `kabic`'s role

### 8.1 The IR must be free of OOP

`kabic` describes *what a node is*, never *how a language should present it*. Concretely:

- The IR says **component set**: `[node:MeshRenderer,components:transform+mesh]`.
- The IR never says **base class**. The current `base:` tag is a C#-ism in a language-neutral contract and must be removed.

Each backend then chooses its rendering. C# may render a bundle as a base class, keeping the Godot-flavoured ergonomics the author wants. Zig may render it as an embedded struct or as flattened accessors. Neither choice is visible in the header.

Multi-component-per-node therefore stops being an implementation convenience and becomes an **IR requirement**.

### 8.2 `kabic` is not in the loop for game scripts

Header → IR → generated bindings is for **engine domains**. Game code (`Ball`, `Paddle`) is authored in the target language, and the language's own facility does the equivalent job locally: Roslyn source generators in C#, `comptime` in Zig. What must match across languages is the *shape* — component set, signature-as-access-list, no fields — not the generator.

### 8.3 What a backend must be able to render

A backend is complete when it can render, idiomatically:

- a node type as a component set plus a property surface,
- a game type composing one bundle plus its own component-backed state,
- a behavior method whose parameters are the access list,
- typed borrows (`Child`/`Parent`/`Ref`) with call-scoped validity,
- the system registration that lifts iteration out of the method.

### 8.4 Zig is the proving backend

Zig is the engine's implementation language and the next scripting target, so it is not a "nice to have second backend" — it is the test. Anything that only works because C# has classes, `ref struct`, or reflection is disqualified by construction. The §11 worked example exists to be checked against this.

---

## 9. What this design costs

**Physics and audio must stop being imperative handles.** `IPhysics2D` is a hand-written C# interface — the `O(languages × domains)` problem §7.1 of the scripting doc exists to eliminate, and the one domain that escaped the rule. A `Body2D` node type requires a `ke_body2d_component` in the physics domain's own contract header plus a native system inside the box2d plugin that syncs body and transform. `kabic` never learns that box2d exists; it reads a header like any other. This is real work, separable from everything else here, and it is where the largest ergonomic win lives — most of the noise in `Paddle` and `Ball` today is the physics side-channel, not inheritance.

**Cached node references in game code must go.** What is stored is an entity id in a component; the borrow is re-resolved per tick from a declared parameter. Costs a lookup, buys the absence of dangling references and a correct access list.

**`View` must stop exposing `NodeWorld`.** [`View.cs:16`](../src/csharp/framework/KernelEngine.Framework/Scene/View.cs:16) documents itself as the funnel that script code cannot smuggle world access past — but it exposes `NodeWorld` as a class property ([`:22`](../src/csharp/framework/KernelEngine.Framework/Scene/View.cs:22)), which a caller can store and use to reach anything. The guarantee the comment claims is defeated by the type's own surface. This is a fix, not a workaround.

**Property access indirection.** Today each property read/write round-trips through `TryGetByCid`/`SetByCid`. Under §4.3, `self` holds borrowed component pointers for the call, so access is a direct dereference and the round-trip disappears. This is a consequence of the model, not a separate optimization.

**Deep user hierarchies with overridden behavior are gone.** Game types compose a bundle and declare hooks; they do not override each other's behavior. This is what makes the model expressible in a language without inheritance, and it is a real restriction relative to Godot.

---

## 10. Order of work

1. **Multi-component per node type.** One cid/state pair per declared component instead of one per class. Prerequisite for bundles and for `node.h`'s `Name`/`Parent`/`Children`, and additive — the single-component path keeps working while it lands.
2. **Remove `base:` from the IR** (§1, §8.1). Replaced by a component set that may reference other bundles. The C# backend renders a flat property surface with `Node` as the only base.
3. **`Body2D`** (§9) — the physics domain gets a component and a native sync system; `IPhysics2D` stops being a hand-written per-language surface. Separable from 1 and 2, and where the largest ergonomic win is.

Toolkit work that assumed `base:` — `Sprite2D`, `node2d.h` — stops until step 2 lands, rather than being built on the mechanism being removed. `Groups` and `Signals` are unaffected by any of this and can proceed independently.

---

## 11. Worked example — `Ball`

The hardest node in the pong example: it crosses the hierarchy, caches node references, drives audio children, and reports to a `Scoreboard` that is not its parent.

### 11.1 Today

Physics is an imperative side-channel (`_physics.GetBodyState`, `SetBodyVelocity`), node references are cached in fields and lazily resolved with a null check every frame, `OnReady` exists only to find two `AudioPlayer` children, and `OnUpdate` declares no component access. See [`Ball.cs`](../examples/csharp/games/pong/scripts/Ball.cs).

### 11.2 Proposed — C#

```csharp
[Node(Bundle = typeof(Body2D))]
public sealed partial class Ball
{
    public Vector2 LastVelocity   { get; set; }
    public bool    AwaitingLaunch { get; set; }
    public float   InitialSpeed   { get; set; }

    void Update(ref View view, Child<AudioPlayer> hit, Child<AudioPlayer> sfx, Emit<GoalScored> goal)
    {
        if (view.IsJustPressed(PongAction.Launch) && AwaitingLaunch) Launch();
        if (AwaitingLaunch) return;

        if (MathF.Sign(Velocity.X) != MathF.Sign(LastVelocity.X) && LastVelocity.X != 0) hit.Play();
        LastVelocity = Velocity;

        if (MathF.Abs(Position.X) > Field.HalfW + GoalLineMargin) Score(Position.X > 0, goal, sfx);
    }

    void Score(bool leftScored, Emit<GoalScored> goal, Child<AudioPlayer> sfx)
    {
        goal.Send(new GoalScored(leftScored));
        sfx.Play();
        Position = Velocity = LastVelocity = Vector2.Zero;
        AwaitingLaunch = true;
    }
}
```

### 11.3 Proposed — Zig, from the same shape

```zig
pub const Ball = ke.Node(.{
    .bundle = ke.Body2D,
    .state = struct {
        last_velocity:   ke.Vec2 = .{ 0, 0 },
        awaiting_launch: bool    = true,
        initial_speed:   f32     = 6,
    },
});

pub fn update(
    self: *Ball,
    view: *ke.View,
    hit:  ke.Child(AudioPlayer),
    sfx:  ke.Child(AudioPlayer),
    goal: ke.Emit(GoalScored),
) void {
    if (view.isJustPressed(.launch) and self.awaiting_launch) launch(self);
    if (self.awaiting_launch) return;

    if (std.math.sign(self.velocity[0]) != std.math.sign(self.last_velocity[0])
        and self.last_velocity[0] != 0) hit.play();
    self.last_velocity = self.velocity;

    if (@abs(self.position[0]) > Field.half_w + goal_line_margin)
        score(self, self.position[0] > 0, goal, sfx);
}
```

No inheritance, no `ref struct`, no per-entity managed object, no reflection — and neither rendering needed an exception in the IR. That is the bar any future backend has to clear.

### 11.4 What disappeared

The body-to-transform copy every frame (now a native system inside the physics plugin), the `_board is null` lazy-init, the cached `Find<T>()` results, and the `OnReady` whose only job was locating two children.
