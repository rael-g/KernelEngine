# How do Body2D and Collider2D become a simulation, and what does each tick copy between them?

Two layers. `ke_physics_2d` is a vtable over one physics world, with a Box2D implementation
(`src/c/physics/kernel_engine/physics/physics_2d.h`, `src/zig/physics/box2d/src/box2d_physics.zig`).
The **body2d module** is two runtime systems that keep ECS components and that world in agreement
(`src/zig/physics/body2d/src/body2d_module.zig`). Game code never holds a body handle; it edits
components.

## The components

`ke_body2d_component` holds a type (static, kinematic, dynamic), position, angle, linear and angular
velocity, `gravity_scale` and `fixed_rotation`, plus `body`, the handle of the world's body for this
entity (`src/c/physics/kernel_engine/physics/components.h`). `ke_collider2d_component` holds a shape
(box by `half_extents` or circle by `radius`), density, friction, restitution, a collision `layer`
and `mask`, and `attached`. Both are scene-authorable by the keys in
`src/c/physics/kernel_engine/physics/component_fields.h`; `body` is not in the field table, `attached`
is. A body entity also needs a `transform2d`: the system's query requires both
(`body2d_module.zig:221-224`). A collider is its own entity, a descendant of the body's entity, as in
`examples/csharp/games/pong/scenes/Paddle.scene.toml`.

## The world

One `ke_physics_2d` is one world. The contract says it is not thread-safe and must be called from one
thread (`physics_2d.h`, the `ke_physics_2d` doc). `step(dt)` accepts any `dt`; the Box2D plugin passes
it straight to `b2World_Step` with four sub-steps (`box2d_physics.zig:12`, `64-68`). A handle is the body's index plus one, so `0` stays `KE_BODY_2D_INVALID`; slots are not reused
(`box2d_physics.zig:44-50`, `109-117`).
The world is created and given its gravity by the managed `AddBox2D`, which reads
`[runtime.physics_2d] gravity_x/gravity_y` (`formats/project-file.md`).

## The two systems

`ke_physics_body2d_module_create` registers both in `KE_PHASE_UPDATE`, unpinned
(`body2d_module.zig:226-253`); the managed `Body2DModule` calls it in `OnLoad` and then calls
`ke_physics_register_scene_apply`, which registers the two field tables
(`src/csharp/physics/KernelEngine.Physics/Body2DModule.cs:28-52`, `body2d_module.zig:264-271`). Without that
module a `Body2D` is storage nothing advances.

`physics.body2d` reads and writes `body2d` and `transform2d`; `physics.collider2d` reads `body2d`,
`transform2d` and `hierarchy` and writes `collider2d`. They conflict on components, so the wave rule
puts them in separate waves in registration order, body first ([runtime.md](runtime.md#waves--what-may-run-concurrently)).
The collider system therefore sees, in the same tick, the handles the body system just created.

### `physics.body2d`, once per tick (`bodySystem`, `body2d_module.zig:29-92`)

1. **Create.** For each body whose `body` is invalid: if `position` is exactly (0, 0) it is first
   taken from the entity's `transform2d` position and rotation; then `create_body` is called with the
   component's type and position, and velocity, `fixed_rotation` and `gravity_scale` are applied
   (`:42-55`). A failed creation leaves `body` invalid and is retried next tick.
2. **Push.** For each body that already has a handle: if `position` or `angle` differ from the
   world's state, `set_body_position` teleports it; if `velocity` differs, `set_body_velocity`
   overwrites it (`:58-63`). This is how a script's write reaches the world: it changes the
   component, and the next tick of this system copies it in.
3. **Step.** `step(dt)` runs once, with the `dt` of the `Update` phase (`:67`), which is the tick's
   own `dt`, not the fixed step ([runtime.md](runtime.md#fixed-timestep); `runtime.zig:885`).
4. **Pull.** For each body with a handle, the world's position, angle, linear velocity and angular
   velocity overwrite the component's, and position and angle are written into the entity's
   `transform2d` (`:69-89`). The transform is set to the body's world position and angle directly; no
   parent composition is applied.

What is set only at creation: `type`, `gravity_scale`, `fixed_rotation`. Changing them in the
component later reaches nothing. `angular_velocity` is only ever read back.

### `physics.collider2d`, only while a collider is unattached (`colliderSystem`, `:105-175`)

The system returns at once unless some collider has `attached == false` (`anyUnattached`, `:93-103`; `:110`).
Otherwise it indexes every entity's parent and every body entity that has a valid handle, then for
each unattached collider:

- climbs from the collider's **parent** upward and takes the nearest ancestor that is in the body
  index (`findBody`, `:180-192`). A collider on the same entity as its body does not find it, because
  the climb starts at the parent. The climb is bounded by the parent map's size, so a cyclic
  hierarchy ends rather than hangs (`:187`).
- finds none: logs a warning that the shape "will never collide" and leaves it unattached
  (`:155-159`), so the warning repeats every tick and the index is rebuilt every tick;
- finds one: calls `add_box_fixture` or `add_circle_fixture` with the collider's own `transform2d`
  position as the offset, its rotation as the box angle (a circle takes no angle), its density,
  friction, restitution, and a `ke_collision_filter_2d` of its `layer` and `mask` (`:161-167`). The
  offset is the collider's local position; transforms of nodes between collider and body are not
  composed into it.
- sets `attached` to whether the call succeeded and logs the outcome (`:168-171`). A failed attach
  stays unattached and is retried.

Two fixtures touch only when each one's `layer` bit is in the other's `mask`
(`physics_2d.h`, `ke_collision_filter_2d`).

## What the module never does

It never calls `destroy_body`: a body whose entity is destroyed stays in the world and keeps being
stepped (`grep -rn destroy_body src --include='*.zig'` finds the plugin's own slot and test only).
It has no fixture removal, because the contract has none, and no contact or trigger output, because
the contract has none (`physics_2d.h`; card `abi/physics-2d-has-no-fixture-removal-and-no-contact-events.md`).
A game that needs to know two shapes touched reads positions after the step.

## Where a script's write meets the step

A node script's `Update` writes the body's component (for example `Velocity`,
`examples/csharp/games/pong/scripts/Paddle.cs:27-35`); that is a write to `body2d`. The behavior
systems and `physics.body2d` both write `body2d` and both run in `Update`, so they are in different
waves and which comes first is their registration order. A behavior that runs first has its write
pushed and stepped in the same tick; one that runs after is pushed on the next.
