#ifndef KERNEL_ENGINE_PHYSICS_COMPONENTS_H_
#define KERNEL_ENGINE_PHYSICS_COMPONENTS_H_

#include <kernel_engine/common/math.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/spatial/transform.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Body2D,base:Node2D]
    /// A 2D rigid body. Pose and motion are stored here because the simulation owns them
    /// between ticks; the node's own transform2d is written back from this component each
    /// tick by the physics plugin's own system, so what a script reads and what the
    /// hierarchy composes are the same two dimensions the body moves in. The same system
    /// creates and destroys the underlying body by reconciling this component against the
    /// world, so the entity is the identity and a script never acquires, threads, or
    /// releases a handle.
    typedef struct ke_body2d_component
    {
        ke_body_type_2d type;
        ke_vec2         position;
        /// Radians, CCW positive.
        float           angle;
        ke_vec2         velocity;
        /// Radians per second, CCW positive.
        float           angular_velocity;
        /// Multiplies world gravity for this body alone. 1 = normal, 0 = weightless.
        float           gravity_scale; ///< [default:1]
        /// Keeps the body's angle fixed against every torque, including contacts. What
        /// anything that must stay upright sets — characters, projectiles.
        bool            fixed_rotation;

        /// [idiom] The plugin's body for this entity, assigned when it reconciles the
        /// component. Authoring it would name a body the world does not own.
        ke_body_2d      body;
    } ke_body2d_component;

#define KE_COMPONENT_NAME_BODY_2D "body2d"

    typedef enum ke_shape_kind_2d
    {
        KE_SHAPE_KIND_2D_BOX    = 0, /**< Axis-aligned box, sized by half_extents. */
        KE_SHAPE_KIND_2D_CIRCLE = 1, /**< Circle centered on the node, sized by radius. */
    } ke_shape_kind_2d;

    /// [node:Collider2D,base:Node2D]
    /// One collision fixture, attached to the nearest ancestor that carries a
    /// ke_body2d_component. Named for what it holds — a kind, extents, density,
    /// friction, restitution — rather than for a shape it is not. It is a node of
    /// its own rather than a field on the body because it has an offset the body
    /// does not, and because a body may carry several. The physics plugin's own system attaches the fixture by reconciling
    /// this component against the hierarchy, so a script never names a body.
    typedef struct ke_collider2d_component
    {
        ke_shape_kind_2d kind;
        /// Half-width and half-height from the node's origin. Read for a box shape.
        ke_vec2          half_extents; ///< [default:0.5 0.5]
        /// Read for a circle shape.
        float            radius; ///< [default:0.5]
        /// Mass per unit area. Drives the owning body's mass and inertia.
        float            density; ///< [default:1]
        /// Coulomb friction against other fixtures. 0 is frictionless.
        float            friction; ///< [default:0.3]
        /// Bounciness. 0 absorbs the impact, 1 returns all of it.
        float            restitution;

        /// [idiom] Whether the fixture has been attached to its body. Set by the
        /// plugin once the ancestor body exists; authoring it would claim a fixture
        /// the world does not have.
        bool             attached;
    } ke_collider2d_component;

#define KE_COMPONENT_NAME_COLLIDER_2D "collider2d"

#ifdef __cplusplus
}
#endif

#endif
