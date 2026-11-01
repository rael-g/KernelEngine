using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_shader_layout_params
{
    [NativeTypeName("const char *")]
    public sbyte* shader;

    [NativeTypeName("uint32_t")]
    public uint stages;

    [NativeTypeName("const ke_render_binding_hint *")]
    public RenderBindingHint* hints;

    [NativeTypeName("uint32_t")]
    public uint hint_count;
}
