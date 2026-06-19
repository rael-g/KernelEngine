using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_input_actions
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, ke_error**, ke_result> load;

    [NativeTypeName("int32_t (*)(struct ke_input_actions *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, int> get_action_id;

    [NativeTypeName("int32_t (*)(struct ke_input_actions *, const char *, ke_action_type)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, ke_action_type, int> add_action;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, KernelEngine.Input.Native.ke_key, ke_error**, ke_result> bind_key;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_mouse_button, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, KernelEngine.Input.Native.ke_mouse_button, ke_error**, ke_result> bind_mouse_button;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key, ke_key, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, KernelEngine.Input.Native.ke_key, KernelEngine.Input.Native.ke_key, ke_error**, ke_result> bind_key_pair;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key, ke_key, ke_key, ke_key, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, KernelEngine.Input.Native.ke_key, KernelEngine.Input.Native.ke_key, KernelEngine.Input.Native.ke_key, KernelEngine.Input.Native.ke_key, ke_error**, ke_result> bind_key_quad;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, const ke_input_snapshot *, ke_input_action_event_func, void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, KernelEngine.Input.Native.ke_input_snapshot*, delegate* unmanaged[Cdecl]<void*, ke_input_action_event, void>, void*, ke_error**, ke_result> evaluate;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, bool> is_action_down;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, bool> was_action_pressed;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, bool> was_action_released;

    [NativeTypeName("float (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float> get_axis1d;

    [NativeTypeName("void (*)(struct ke_input_actions *, int32_t, float *, float *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float*, float*, void> get_axis2d;

    [NativeTypeName("void (*)(struct ke_input_actions *, int32_t, float *, float *, float *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float*, float*, float*, void> get_axis3d;
}
