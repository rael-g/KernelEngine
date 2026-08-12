#ifndef KERNEL_ENGINE_PHYSICS_PHYSICS_2D_H_
#define KERNEL_ENGINE_PHYSICS_PHYSICS_2D_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_PHYSICS_2D "ke_physics_2d"

    /** Opaque rigid-body handle owned by a ke_physics_2d instance. 0 is reserved as "invalid". */
    typedef uint32_t ke_body_2d;
#define KE_BODY_2D_INVALID ((ke_body_2d)0)

    typedef enum ke_body_type_2d
    {
        KE_BODY_TYPE_STATIC    = 0, /**< Never moves; infinite mass. Floors, walls. */
        KE_BODY_TYPE_KINEMATIC = 1, /**< Moved by code (set_position/set_velocity), unaffected by forces. */
        KE_BODY_TYPE_DYNAMIC   = 2, /**< Driven by forces, collisions, gravity. */
    } ke_body_type_2d;

    /**
     * Snapshot of a body's pose + motion at a point in time. Position is the body's local
     * origin in world space; angle is in radians.
     */
    typedef struct ke_body_state_2d
    {
        float x, y;
        float angle;             /**< radians, CCW positive */
        float velocity_x;
        float velocity_y;
        float angular_velocity;  /**< radians per second */
    } ke_body_state_2d;

    /**
     * ABI-stable vtable for a 2D rigid-body physics world. One instance == one world; a
     * game wanting multiple worlds creates multiple instances. Concrete implementations
     * come from plugins (Box2D for now). Not thread-safe — call all methods on the same
     * thread (typically ke.sim).
     */
    typedef struct ke_physics_2d
    {
        void *handle;

        /** Sets world gravity (m/s^2). Default is (0, -9.81). */
        void (*set_gravity)(struct ke_physics_2d *self, float x, float y);

        /**
         * Advances the simulation by dt seconds. Variable steps are accepted, but
         * deterministic replay requires the caller to supply a fixed one.
         */
        void (*step)(struct ke_physics_2d *self, float dt);

        /** Creates a body at the given world position. Returns KE_BODY_2D_INVALID on error. */
        ke_body_2d (*create_body)(struct ke_physics_2d *self, ke_body_type_2d type, float x, float y, ke_error **out_error);

        /** Destroys the body and all its fixtures. Safe on KE_BODY_2D_INVALID. */
        void (*destroy_body)(struct ke_physics_2d *self, ke_body_2d body);

        /**
         * Attaches a box fixture, sized by its half-extents and placed at the given offset
         * from the body origin. The offset is what lets one body carry several shapes in
         * different places — a character's feet and torso, a paddle's rounded ends.
         * @param offset_angle Radians, CCW positive, about the offset center.
         */
        bool (*add_box_fixture)(struct ke_physics_2d *self, ke_body_2d body,
                                float half_w, float half_h,
                                float offset_x, float offset_y, float offset_angle,
                                float density, float friction, float restitution, ke_error **out_error);

        /** Attaches a circle fixture at the given offset from the body origin. */
        bool (*add_circle_fixture)(struct ke_physics_2d *self, ke_body_2d body,
                                   float radius,
                                   float offset_x, float offset_y,
                                   float density, float friction, float restitution, ke_error **out_error);

        /**
         * Reads the body's current pose and motion.
         * @param out [out] Receives position, angle, and velocities.
         */
        void (*get_body_state)(struct ke_physics_2d *self, ke_body_2d body, ke_body_state_2d *out);

        /** Teleports the body. Skips collision response — prefer apply_impulse for dynamic moves. */
        void (*set_body_position)(struct ke_physics_2d *self, ke_body_2d body, float x, float y, float angle);

        /** Sets linear velocity directly (m/s). */
        void (*set_body_velocity)(struct ke_physics_2d *self, ke_body_2d body, float vx, float vy);

        /** Applies a linear impulse (kg*m/s) at the body center. */
        void (*apply_impulse)(struct ke_physics_2d *self, ke_body_2d body, float impulse_x, float impulse_y);

        /**
         * Locks or unlocks the body's rotation. A locked body keeps its current angle and
         * ignores every torque, including the one a contact imparts. Bodies start unlocked.
         * Needed by anything that must stay upright — characters, projectiles, and any box
         * whose collisions would otherwise set it spinning.
         */
        void (*set_body_fixed_rotation)(struct ke_physics_2d *self, ke_body_2d body, bool fixed);

        /**
         * Scales world gravity for this body alone. 1 leaves it at the world's value, 0
         * makes the body weightless, and a negative value makes it fall upward. What a
         * floating pickup or a balloon sets, rather than each such body needing its own
         * world.
         */
        void (*set_body_gravity_scale)(struct ke_physics_2d *self, ke_body_2d body, float scale);

    } ke_physics_2d;

    typedef struct ke_physics_2d_handle
    {
        ke_physics_2d *ref;
        void (*destroy)(ke_physics_2d *self);
    } ke_physics_2d_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_PHYSICS_PHYSICS_2D_H_
