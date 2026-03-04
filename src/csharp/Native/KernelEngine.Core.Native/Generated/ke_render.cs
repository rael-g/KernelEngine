namespace KernelEngine.Core.Native;

public unsafe partial struct ke_render
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_render *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_render*, bool, ke_result> set_orthographic;

    [NativeTypeName("ke_result (*)(struct ke_render *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, float, ke_result> clear_color;

    [NativeTypeName("ke_result (*)(struct ke_render *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void*, ke_result> draw_node;

    [NativeTypeName("ke_result (*)(struct ke_render *, void *, int)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void*, int, ke_result> set_node_shape;

    [NativeTypeName("ke_result (*)(struct ke_render *, void *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void*, float, float, float, float, ke_result> set_node_color;
}
