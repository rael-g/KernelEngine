using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Physics;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_2d
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_vec2)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, System.Numerics.Vector2, void> set_gravity;

    [NativeTypeName("void (*)(struct ke_physics_2d *, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, float, void> step;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_type_2d, ke_vec2, ke_body_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.BodyType2D, System.Numerics.Vector2, global::KernelEngine.Physics.Body2d*, KernelEngine.Result.Native.Result> create_body;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, void> destroy_body;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_2d, ke_vec2, ke_vec2, float, float, float, float, const ke_collision_filter_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, System.Numerics.Vector2, System.Numerics.Vector2, float, float, float, float, global::KernelEngine.Physics.CollisionFilter2d*, KernelEngine.Result.Native.Result> add_box_fixture;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_2d, float, ke_vec2, float, float, float, const ke_collision_filter_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, float, System.Numerics.Vector2, float, float, float, global::KernelEngine.Physics.CollisionFilter2d*, KernelEngine.Result.Native.Result> add_circle_fixture;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, ke_body_state_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, global::KernelEngine.Physics.BodyState2d*, void> get_body_state;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, ke_vec2, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, System.Numerics.Vector2, float, void> set_body_position;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, ke_vec2)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, System.Numerics.Vector2, void> set_body_velocity;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, ke_vec2)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, System.Numerics.Vector2, void> apply_impulse;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, bool)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, bool, void> set_body_fixed_rotation;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, global::KernelEngine.Physics.Body2d, float, void> set_body_gravity_scale;
}
