# 24 — Physics Node Layer

> **Status**: 📋 Architectural decision. Not implemented. This chapter freezes the design of the high-level physics-as-nodes layer that sits on top of the current `IPhysics2D` plugin contract (beta slice 4). Spec captured before implementation so when the time comes the shape is settled.

## 1. The problem the Pong example exposed

The first complete-game example (Pong, commit `c1f2e3...`) shipped against the minimal `IPhysics2D` API: `physics.CreateBody`, `physics.AddBoxFixture`, `physics.GetBodyState`, `physics.Step`. It worked, but the Program.cs needed a `PhysicsStepper` node whose entire job was `physics.Step(dt)` — because forgetting that call silently freezes the world. The game dev also had to manage body handles, sync `LocalTransform` from body state every frame, and detect paddle hits by inspecting velocity sign flips because the kernel layer has no collision events.

In short: the current API is appropriate as a **kernel contract** (kernel = primitives) but inappropriate as a **game-author surface** (framework = ergonomic). The Pong retro made the gap unambiguous; this chapter pins how the framework wraps it.

## 2. Design principles

1. **Game code never calls `physics.Step`.** The engine decides when the world advances.
2. **Game code never holds a `BodyHandle2D` or `IPhysics2D` reference.** Both are framework-internal.
3. **Body + Transform are the same thing from the game's point of view.** `node.Position = ...` and `node.LinearVelocity = ...` operate through the body.
4. **Multiple colliders per body** are first-class. A node can have a box + a circle attached.
5. **Collision events arrive as virtual methods on the node.** `protected override void OnCollisionEnter(other)`.
6. **Body type is locked at the class level.** `class Paddle : KinematicBody2D` reads better than `new RigidBody2D { Type = Kinematic }`.

## 3. Type hierarchy

```
Node                            (framework)
└─ CollisionBody2D              (abstract — owns Body + colliders)
   ├─ StaticBody2D              (zero mass, ignores forces)
   ├─ KinematicBody2D           (moved by code, doesn't react to forces)
   ├─ DynamicBody2D             (full simulation; FixedRotation, ApplyImpulse, ApplyForce)
   └─ TriggerArea2D             (sensor — emits enter/exit events, no physical response)
```

### Public surface

```csharp
public abstract class CollisionBody2D : Node
{
    // Pose (read/write via underlying body)
    public Vector2 Position        { get; set; }
    public float   Rotation        { get; set; }   // radians, Z-axis only
    public Vector2 LinearVelocity  { get; set; }
    public float   AngularVelocity { get; set; }

    // Colliders — added at Start time or runtime
    public IReadOnlyList<Collider2D> Colliders { get; }
    public void AddCollider(Collider2D collider);
    public void RemoveCollider(Collider2D collider);

    // Pose imperative
    public void Teleport(Vector2 position, float rotation = 0);  // skips interpolation

    // Collision callbacks — virtual, override in subclass
    protected virtual void OnCollisionEnter(CollisionBody2D other) { }
    protected virtual void OnCollisionExit(CollisionBody2D other)  { }

    // Framework internals
    protected abstract BodyType2D BodyType { get; }   // each concrete subclass returns its type
    protected internal BodyHandle2D Body { get; }     // accessible to systems, not game code
}

public class StaticBody2D    : CollisionBody2D { protected override BodyType2D BodyType => BodyType2D.Static; }

public class KinematicBody2D : CollisionBody2D { protected override BodyType2D BodyType => BodyType2D.Kinematic; }

public class DynamicBody2D   : CollisionBody2D
{
    protected override BodyType2D BodyType => BodyType2D.Dynamic;

    public bool FixedRotation { get; set; }
    public void ApplyImpulse(Vector2 impulse);
    public void ApplyForce(Vector2 force);
}

public class TriggerArea2D : CollisionBody2D       // sensor — no contact response
{
    protected override BodyType2D BodyType => BodyType2D.Static;
    protected virtual void OnTriggerEnter(CollisionBody2D other) { }
    protected virtual void OnTriggerExit(CollisionBody2D other)  { }
}
```

### Colliders as records

Colliders are immutable value types (records) — declarative, not handle-bearing. They describe shape + material; the framework attaches them to the underlying body.

```csharp
public abstract record Collider2D(float Density = 1f, float Friction = 0.3f, float Restitution = 0f);

public sealed record BoxCollider2D(
    Vector2 HalfExtents,
    float   Density     = 1f,
    float   Friction    = 0.3f,
    float   Restitution = 0f) : Collider2D(Density, Friction, Restitution);

public sealed record CircleCollider2D(
    float Radius,
    float Density     = 1f,
    float Friction    = 0.3f,
    float Restitution = 0f) : Collider2D(Density, Friction, Restitution);

// Future: PolygonCollider2D, EdgeCollider2D, ChainCollider2D — same record pattern.
```

Density/friction/restitution live on the collider (per-fixture in Box2D), not the body. This matches Box2D semantics and lets a body have heterogeneous parts (a slippery floor with a sticky platform on top).

## 4. The user-facing experience

```csharp
sealed class Paddle(Key up, Key down) : KinematicBody2D
{
    protected override void Start()
    {
        base.Start();                          // framework creates the body
        AddCollider(new BoxCollider2D(new Vector2(0.15f, 0.9f), Restitution: 1f));
    }

    protected override void Update(float dt)
    {
        var input = InputContext.Current;
        float vy = (input.IsKeyDown(up) ? 7 : 0) - (input.IsKeyDown(down) ? 7 : 0);
        LinearVelocity = new Vector2(0, vy);   // writes through to body
    }
}

sealed class Ball(IAudio audio, SoundHandle hit) : DynamicBody2D
{
    protected override void Start()
    {
        base.Start();
        AddCollider(new BoxCollider2D(new Vector2(0.15f, 0.15f), Restitution: 1f, Friction: 0f));
    }

    protected override void OnCollisionEnter(CollisionBody2D other)
        => audio.Play(hit, volume: 0.5f);
}
```

Compare with the current Pong (commit `8357944`) where game code held a `BodyHandle2D`, manually called `physics.SetBodyVelocity`, polled `physics.GetBodyState`, wrote `LocalTransform = LocalTransform with { Position = ... }`, and inferred collisions from velocity sign flips. **The framework absorbs all of that.**

Visual representation is still composition — `MeshRenderer` is added as a child:

```csharp
var paddle = app.Tree.AddNode(new Paddle(Key.W, Key.S), "PaddleLeft");
app.Tree.AddNode(new MeshRenderer { Mesh = cubeMesh, Material = whiteMat,
                                    LocalTransform = ... /* sized like the collider */ },
                 "Visual", parent: paddle);
```

The Tree's transform propagation makes the visual follow the body automatically.

## 5. Framework wiring

### `Physics2DSystem` — auto-registered

When `AddBox2D()` (or any future physics plugin) registers `IPhysics2D` in DI, `Application.InitializeSystems` detects it and adds `Physics2DSystem : ISystem` to the world automatically. Game code never instantiates it.

```csharp
internal sealed class Physics2DSystem : ISystem
{
    private readonly IPhysics2D _physics;
    private readonly Dictionary<BodyHandle2D, CollisionBody2D> _bodyToNode = new();
    private float _accumulator;
    private const float FixedTimestep = 1f / 60f;   // configurable later

    public void Update(IWorld world, float dt, IFramePacket? packet)
    {
        _accumulator += dt;
        while (_accumulator >= FixedTimestep)
        {
            _physics.Step(FixedTimestep);
            DrainCollisionEvents();
            _accumulator -= FixedTimestep;
        }
        SyncBodiesToTransforms();
    }

    internal void Register(CollisionBody2D body) => _bodyToNode[body.Body] = body;
    internal void Unregister(CollisionBody2D body) => _bodyToNode.Remove(body.Body);
    ...
}
```

`CollisionBody2D.Start` resolves `Physics2DContext.Current` (a thread-local set by Application, paralleling `InputContext.Current`), creates the body, registers itself with `Physics2DSystem`.

### Frame ordering

Application's sim loop already runs in this order, which is exactly right for physics:

```
InputContext.Set(snapshot)             — set thread-local input
Tree.DispatchInput(events)             — events fire FIRST
Tree.TickAwakeAndStart()               — bodies created on first frame
Tree.TickUpdate(dt)                    — game code sets velocities, impulses
World.Update(packet, input)            — runs ISystems including Physics2DSystem:
                                            • accumulator-loop: step + drain collisions
                                            • sync bodies → LocalTransforms
                                            • TransformSystem propagates WorldMatrix
Tree.TickLateUpdate(dt)                — game code reads post-physics positions (camera follow, etc.)
OnUpdate(writer, input)
InputContext.Set(null)
```

The game dev only sees `Update`/`LateUpdate`/`OnCollisionEnter`. The orchestration is invisible.

### Fixed timestep + accumulator

Physics steps at a fixed `1/60s` interval regardless of render frame rate. The accumulator absorbs the rendering jitter — if the renderer runs at 144Hz, physics steps roughly once every 2.4 frames; if it stutters to 30Hz, physics steps twice in one frame. Result: deterministic, frame-rate-independent simulation.

The downside is visible interpolation jitter for high-refresh displays (body position only updates at 60Hz). A later slice can add render-side interpolation between sub-steps; for MVP, raw fixed-step is fine.

## 6. Collision events

This requires extending the kernel contract:

```c
// ke_physics_2d gains:
typedef struct ke_collision_event_2d {
    ke_body_2d body_a;
    ke_body_2d body_b;
    uint8_t    kind;     // 0 = begin, 1 = end
} ke_collision_event_2d;

uint32_t (*drain_collision_events)(struct ke_physics_2d* self,
                                   ke_collision_event_2d* out, uint32_t cap);
```

Box2D plugin installs a `b2ContactListener` that pushes events into an internal queue; `drain_collision_events` empties it. C# wrapper drains each step, dispatches `OnCollisionEnter`/`OnCollisionExit` on the matched nodes via the `_bodyToNode` dict (O(1) lookup, no string Guid like Luna's pattern).

Pre-/post-solve callbacks (continuous collision response, contact-impulse readback) are real but deferred to a future slice — needed for sliding/bouncing tuning, not for "did A touch B".

## 7. Luna comparison

Luna shipped a 2D physics layer in a sibling project; I studied it before pinning the design. Highlights:

**Taken (or close to):**
- Abstract `CollisionBody2D` with `Static/Kinematic/Dynamic/TriggerArea` subtypes. Type-locked at class level.
- Separate `IOnCollision` virtual surface — simplified here into virtuals on `CollisionBody2D` itself, since C# doesn't need an interface to opt in.
- `TriggerArea2D` as a distinct sensor type.
- Shape as a declarative entity (Luna's `IShape2D` → our records).

**Rejected:**
- **`UserData = Guid.ToString()` + `Tree.FindNodeByUID` lookup per contact.** String Guid lookup on every collision event is slow and allocation-heavy. We use a dedicated `BodyHandle2D → Node` dictionary populated at body creation, O(1) without strings.
- **`Tree.GetAllNodesOfType<CollisionBody2D>()` every `FixedUpdate`.** Full tree walk to find bodies is unnecessary. `Physics2DSystem` maintains its own registry, populated on `Start` / removed on destroy.
- **Physics on a separate thread** (Luna's `StartPhysicsLoopThread` + `ConcurrentDictionary` of results). Our 3-thread model already has clear ownership: physics runs on `ke.sim`, single-threaded with game logic. Determinism, debuggability, no race conditions. Box2D itself is single-threaded; parallelizing the C# wrapper buys nothing.
- **`WorldManager` singleton auto-attaching itself to `Tree.Root`** on first access. Fragile and global. Framework instead auto-registers `Physics2DSystem` via DI when `AddBox2D()` is called.

**Refactored:**
- **Luna's `CollisionBody2D.Awake` creates the body**, forcing the subclass to set `Shape` before `base.Awake()`. We move body creation to `Start` and accept colliders added either before or after — internally buffered as "pending" until `Start` runs.
- **Per-body density/friction/restitution** in Luna — these are actually per-fixture in Box2D. We move them onto the `Collider2D` record where they belong.
- **Fixed-timestep accumulator** — Luna had this on a per-WorldManager basis; we centralize on `Physics2DSystem` so all consumers share the same model.

## 7.5 World units, pixels, and Box2D's MKS sweet spot

Box2D is tuned for **meters-kilogram-second (MKS) units**. Moving shapes between 0.1 and 10 meters work best; static shapes up to ~50 m are fine; the world should fit in ~12 km. Using raw pixel coordinates as world units (a 200 px character ≈ a 45-story building to Box2D) leads to poor simulation and weird behavior. (See [Box2D manual — Units](https://box2d.org/documentation/md__d_1__git_hub_box2d_docs_hello.html#autotoc_md17).)

**Engine policy** — codified here because physics is what enforces it:

- **World units are meters.** Every `Transform`, `Position`, `LinearVelocity`, collider half-extent is in meters. Game code never sees pixels in physics or Transform.
- **Pixels are a sprite-import concern**, not a runtime concern. When `Sprite2D` (Tier B1) lands, it will read `[runtime] pixels_per_unit` from `Project` (default 100). A 64×64-pixel sprite at PPU=100 renders at 0.64 world units, and the natural physics body for it is 0.64×0.64 — automatically inside Box2D's sweet spot.
- **The conversion happens once, at asset import time**, not at every physics call. The renderer applies the scaling when drawing sprites; physics never sees pixels.

Rejected alternative — per-call `ToMeters()` / `ToPixels()` helpers (the Luna.Box2D pattern): forces every game-code line that touches physics to do conversion, spreads the unit concern across the whole game, and makes naive code (`new BoxCollider2D(new Vector2(64, 64))`) silently wrong.

## 8. What this chapter is NOT

- **Not a 3D physics design.** Different contract (`ke_physics_3d`), different backends (Jolt, PhysX). When 3D arrives, it will be a parallel chapter.
- **Not joints / constraints.** `WeldJoint`, `RevoluteJoint`, etc. are real Box2D primitives and important for serious 2D games (vehicles, ragdolls). Deferred to a later slice on top of this layer.
- **Not raycasts / queries.** `physics.Raycast(from, to)` and area queries are essential for AI / pickups / line-of-sight. Deferred; should land in the slice after collision events.
- **Not continuous collision detection (CCD) tuning.** Box2D supports bullet bodies for fast-moving objects; expose later when needed.
- **Not interpolation for render-side smoothness.** Visible at high-refresh displays; deferred.

## 9. Implementation order (when the work begins)

1. **Body/Node mapping in the kernel** — `ke_physics_2d` add `drain_collision_events`; plugin installs `b2ContactListener` that pushes to a ring buffer.
2. **`CollisionBody2D` + subtypes** in Framework. `AddCollider`, `Position`/`Rotation`/`LinearVelocity` properties. No collision events yet.
3. **`Physics2DSystem`** auto-registered. Accumulator, sync, body registry.
4. **Migrate Pong** to the new layer as the validation. ~100 line reduction expected.
5. **Collision events** wire up `OnCollisionEnter`/`OnCollisionExit`. Pong's audio-on-hit becomes a one-liner.
6. **`TriggerArea2D`** sensor support. Build a "ball entered scoring zone" example.
7. **Joints, raycasts, queries** — later slices as needs surface.

Steps 1-5 are the core. Estimated ~3-4 days. After step 5, Pong's `Program.cs` collapses by roughly half.

## 10. Cross-references

- The current low-level contract this wraps: [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md), commit `e285ead`.
- The Pong example whose retro motivated this design: `examples/csharp/games/pong/`, commit `8357944`.
- The Node lifecycle this hooks into: [06 - Framework](06%20-%20Framework.md), Tier 2 Slice 5.
- The DI auto-registration pattern (parallel to Configuration service): [16 - Configuration Service](16%20-%20Configuration%20Service.md).
- Audio plugin that established the kernel-vtable + framework-wrapper precedent: commit `54c4599`.
