using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

public unsafe partial struct ke_input
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_input *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_input*, ke_error**, bool> update;

    [NativeTypeName("ke_bool (*)(struct ke_input *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, byte> is_key_pressed;

    [NativeTypeName("ke_bool (*)(struct ke_input *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, byte> is_key_released;

    [NativeTypeName("ke_bool (*)(struct ke_input *, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, byte> is_key_down;

    [NativeTypeName("void (*)(struct ke_input *, ke_input_snapshot *)")]
    public delegate* unmanaged[Cdecl]<ke_input*, ke_input_snapshot*, void> get_snapshot;

    [NativeTypeName("uint32_t (*)(struct ke_input *, ke_input_event *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, ke_input_event*, uint, uint> drain_events;

    [NativeTypeName("void (*)(struct ke_input *, int32_t, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, int, void> on_key;

    [NativeTypeName("void (*)(struct ke_input *, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_input*, float, float, void> on_mouse_move;

    [NativeTypeName("void (*)(struct ke_input *, int32_t, int32_t)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, int, void> on_mouse_button;

    [NativeTypeName("void (*)(struct ke_input *, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_input*, float, float, void> on_mouse_scroll;
}
