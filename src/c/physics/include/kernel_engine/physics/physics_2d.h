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

    /// @brief Opaque rigid-body handle owned by a ke_physics_2d instance. 0 is reserved as "invalid".
    typedef uint32_t ke_body_2d;
#define KE_BODY_2D_INVALID ((ke_body_2d)0)

    typedef enum ke_body_type_2d
    {
        KE_BODY_TYPE_STATIC    = 0, ///< Never moves; infinite mass. Floors, walls.
        KE_BODY_TYPE_KINEMATIC = 1, ///< Moved by code (set_position/set_velocity), unaffected by forces.
        KE_BODY_TYPE_DYNAMIC   = 2, ///< Driven by forces, collisions, gravity.
    } ke_body_type_2d;

    /// @brief Snapshot of a body's pose + motion at a point in time. Position is the body's
    ///        local origin in world space; angle is in radians.
    typedef struct ke_body_state_2d
    {
        float x, y;
        float angle;             ///< radians, CCW positive
        float velocity_x;
        float velocity_y;
        float angular_velocity;  ///< radians per second
    } ke_body_state_2d;

    /// @brief ABI-stable vtable for a 2D rigid-body physics world. One instance == one world;
    ///        a game wanting multiple worlds creates multiple instances. Concrete implementations
    ///        come from plugins (Box2D for now). Not thread-safe — call all methods on the same
    ///        thread (typically ke.sim).
    typedef struct ke_physics_2d
    {
        void *handle;

        /// @brief Sets world gravity (m/s^2). Default is (0, -9.81).
        void (*set_gravity)(struct ke_physics_2d *self, float x, float y);

        /// @brief Advances the simulation by @p dt seconds. Variable time steps are accepted but
        ///        deterministic replay (chapter 14 §5.1) needs a fixed step from the caller.
        void (*step)(struct ke_physics_2d *self, float dt);

        /// @brief Creates a body at the given world position. Returns KE_BODY_2D_INVALID on error.
        ke_body_2d (*create_body)(struct ke_physics_2d *self, ke_body_type_2d type, float x, float y, ke_error **out_error);

        /// @brief Destroys the body and all its fixtures. Safe on KE_BODY_2D_INVALID.
        void (*destroy_body)(struct ke_physics_2d *self, ke_body_2d body);

        /// @brief Attaches an axis-aligned box fixture (half-extents from body origin).
        bool (*add_box_fixture)(struct ke_physics_2d *self, ke_body_2d body,
                                float half_w, float half_h,
                                float density, float friction, float restitution, ke_error **out_error);

        /// @brief Attaches a circle fixture centered at the body origin.
        bool (*add_circle_fixture)(struct ke_physics_2d *self, ke_body_2d body,
                                   float radius,
                                   float density, float friction, float restitution, ke_error **out_error);

        /// @brief Reads the body's current pose and motion into @p out.
        void (*get_body_state)(struct ke_physics_2d *self, ke_body_2d body, ke_body_state_2d *out);

        /// @brief Teleports the body. Skips collision response — prefer apply_impulse for dynamic moves.
        void (*set_body_position)(struct ke_physics_2d *self, ke_body_2d body, float x, float y, float angle);

        /// @brief Sets linear velocity directly (m/s).
        void (*set_body_velocity)(struct ke_physics_2d *self, ke_body_2d body, float vx, float vy);

        /// @brief Applies a linear impulse (kg*m/s) at the body center.
        void (*apply_impulse)(struct ke_physics_2d *self, ke_body_2d body, float impulse_x, float impulse_y);

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
