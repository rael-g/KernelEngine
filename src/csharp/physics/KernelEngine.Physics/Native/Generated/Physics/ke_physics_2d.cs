using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_2d
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_physics_2d *, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, float, float, void> set_gravity;

    [NativeTypeName("void (*)(struct ke_physics_2d *, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, float, void> step;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_type_2d, float, float, ke_body_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, ke_body_type_2d, float, float, uint*, KernelEngine.Result.Native.ke_result> create_body;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, void> destroy_body;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_2d, float, float, float, float, float, float, float, float, const ke_collision_filter_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, float, float, float, float, float, float, float, ke_collision_filter_2d*, KernelEngine.Result.Native.ke_result> add_box_fixture;

    [NativeTypeName("ke_result (*)(struct ke_physics_2d *, ke_body_2d, float, float, float, float, float, float, const ke_collision_filter_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, float, float, float, float, float, ke_collision_filter_2d*, KernelEngine.Result.Native.ke_result> add_circle_fixture;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, ke_body_state_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, ke_body_state_2d*, void> get_body_state;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, float, float, void> set_body_position;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, float, void> set_body_velocity;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, float, void> apply_impulse;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, bool)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, bool, void> set_body_fixed_rotation;

    [NativeTypeName("void (*)(struct ke_physics_2d *, ke_body_2d, float)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, uint, float, void> set_body_gravity_scale;
}
