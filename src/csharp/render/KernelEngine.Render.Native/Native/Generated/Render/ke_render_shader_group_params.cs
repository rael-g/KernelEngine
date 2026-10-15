using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_shader_group_params
{
    [NativeTypeName("const char *")]
    public sbyte* shader;

    [NativeTypeName("uint32_t")]
    public uint stages;

    [NativeTypeName("const char *")]
    public sbyte* block;

    [NativeTypeName("const ke_render_binding_hint *")]
    public ke_render_binding_hint* hints;

    [NativeTypeName("uint32_t")]
    public uint hint_count;
}
