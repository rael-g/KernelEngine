#ifndef KERNEL_ENGINE_PHYSICS_COMPONENTS_H_
#define KERNEL_ENGINE_PHYSICS_COMPONENTS_H_

#include <kernel_engine/common/math.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/spatial/transform.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [node:Body2D,components:Node3D]
    /// A 2D rigid body. Pose and motion are stored here in two dimensions because that is
    /// what the simulation owns; the composed transform is derived output, written from
    /// this component each tick by the physics plugin's own system. The same system
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

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_PHYSICS_COMPONENTS_H_
