# How do Body2D and Collider2D become a simulation, and what does each tick copy between them?

This is a map: the parts of the 2D physics domain, what each receives and what it hands on. How a
part works inside is on the generated page of its file. Contracts are under `src/c/physics/`,
plugins under `src/zig/physics/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| world | `ke_physics_2d` | box2d | gravity, body and fixture requests | body ids, body state after a step |
| components | `ke_body2d_component`, `ke_collider2d_component` | none | scene fields, script writes | the description of a body and of a shape |
| module | none; `ke_physics_body2d_module_create` | body2d | `ke_runtime`, `ke_ecs`, `ke_physics_2d` | two runtime systems |
| scene registration | none; `ke_physics_register_scene_apply` | body2d | `ke_ecs`, `ke_world` | the field tables of both components |
| managed | `IPhysics2D`, `Body2DModule` | `KernelEngine.Physics` | the host's service collection | the world and the module in a host |

**Game code edits components, never handles.** A body is an entity with a `ke_body2d_component`
and a transform; a shape is its own entity, a descendant of the body's entity, with a
`ke_collider2d_component` and a transform. The body id the world returns is stored in the `body`
field of the component and is the only link between the two sides.

**The module is two systems.** `ke_physics_body2d_module_create` registers "physics.body2d" and
"physics.collider2d", both in `KE_PHASE_UPDATE` and not pinned. The first reads and writes
"body2d" and "transform2d"; the second writes "collider2d" and reads "body2d", "transform2d" and
"hierarchy". They conflict on "body2d", so the runtime separates them into waves in registration
order, body first.

**A tick copies in four directions.** For each body, "physics.body2d" creates the body when the
component has none, pushes the component's position, angle and velocity into the world when they
differ from it, steps the world with the `dt` it is given, and pulls position, angle and
velocities back into the component and the position and angle into "transform2d". The collider
system attaches a fixture to the nearest ancestor of the shape's entity that has a body, and sets
`attached`; it does nothing while every collider is attached.

**The world is one thread's.** One `ke_physics_2d` is one world; its handles are the body's index
plus one, with `KE_BODY_2D_INVALID` as zero. The managed `AddBox2D` creates it with the gravity of
"runtime.physics_2d"; `Body2DModule` creates the module in `OnLoad` and calls
`ke_physics_register_scene_apply` when a `World` is registered.

## What the parts agree on without a contract

- The system names "physics.body2d" and "physics.collider2d", and the log tags "box2d" and
  "physics.body2d".
- The keys "gravity_x" and "gravity_y" under "runtime.physics_2d".
- Two fixtures touch only when each one's `layer` bit is in the other's `mask`; the module builds
  the `ke_collision_filter_2d` from those two fields of the collider.
- Which fields of the body component are read only when the body is created is a rule of the
  module (`type`, `gravity_scale`, `fixed_rotation`).
