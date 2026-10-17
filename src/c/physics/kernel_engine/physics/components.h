#ifndef KERNEL_ENGINE_PHYSICS_COMPONENTS_H_
#define KERNEL_ENGINE_PHYSICS_COMPONENTS_H_

#include <kernel_engine/math/math.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/spatial/transform.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Body2D,base:Node2D]
    /// A 2D rigid body. Holds the motion of its entity; its pose is the entity's
    /// ke_transform2d_component, which the body is created at, which moves it when written,
    /// and which the simulation writes each tick. The entity is the identity of the body: a
    /// caller never acquires, passes, or releases a body handle. The body is destroyed on the
    /// first update in which the entity no longer holds the component.
    typedef struct ke_body2d_component
    {
        /// Read when the body is created; a later change does not reach it.
        ke_body_type_2d type;
        ke_vec2         velocity;
        /// Radians per second, CCW positive.
        float           angular_velocity;
        /// Multiplies world gravity for this body alone. 1 = normal, 0 = weightless. Read when
        /// the body is created.
        float           gravity_scale; ///< [default:1]
        /// Keeps the body's angle fixed against every torque, including contacts. Read when the
        /// body is created.
        bool            fixed_rotation;

        /// [idiom] The body for this entity, assigned when the component is reconciled.
        /// Callers do not write it.
        ke_body_2d      body;
    } ke_body2d_component;

    typedef enum ke_shape_kind_2d
    {
        KE_SHAPE_KIND_2D_BOX    = 0, /**< Axis-aligned box, sized by half_extents. */
        KE_SHAPE_KIND_2D_CIRCLE = 1, /**< Circle centered on the node, sized by radius. */
    } ke_shape_kind_2d;

    /// [node:Collider2D,base:Node2D]
    /// One collision fixture, attached to the nearest ancestor that carries a
    /// ke_body2d_component. The fixture is attached by reconciling this component against
    /// the hierarchy. A caller never names a body.
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
        /// Which of the 32 collision layers this shape occupies.
        uint32_t         layer; ///< [default:1]
        /// Which layers this shape tests against. Two shapes touch only when each
        /// one's layer bit is set in the other's mask.
        uint32_t         mask; ///< [default:4294967295]

        /// [idiom] Whether the fixture has been attached to its body. Set once the
        /// ancestor body exists. Callers do not write it.
        bool             attached;
    } ke_collider2d_component;

#ifdef __cplusplus
}
#endif

#endif
