namespace KernelEngine.Framework.Legacy.Native;

public unsafe partial struct ke_input_actions
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, ke_result> load;

    [NativeTypeName("int32_t (*)(struct ke_input_actions *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, int> get_action_id;

    [NativeTypeName("int32_t (*)(struct ke_input_actions *, const char *, ke_action_type)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, sbyte*, ke_action_type, int> add_action;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, ke_key, ke_result> bind_key;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_mouse_button)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, ke_mouse_button, ke_result> bind_mouse_button;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key, ke_key)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, ke_key, ke_key, ke_result> bind_key_pair;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, int32_t, ke_key, ke_key, ke_key, ke_key)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, ke_key, ke_key, ke_key, ke_key, ke_result> bind_key_quad;

    [NativeTypeName("ke_result (*)(struct ke_input_actions *, const ke_input_snapshot *, ke_input_action_event_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, ke_input_snapshot*, delegate* unmanaged[Cdecl]<void*, ke_input_action_event, void>, void*, ke_result> evaluate;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, byte> is_action_down;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, byte> was_action_pressed;

    [NativeTypeName("bool (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, byte> was_action_released;

    [NativeTypeName("float (*)(struct ke_input_actions *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float> get_axis1d;

    [NativeTypeName("void (*)(struct ke_input_actions *, int32_t, float *, float *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float*, float*, void> get_axis2d;

    [NativeTypeName("void (*)(struct ke_input_actions *, int32_t, float *, float *, float *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, int, float*, float*, float*, void> get_axis3d;

    [NativeTypeName("void (*)(struct ke_input_actions *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, void> destroy;
}
