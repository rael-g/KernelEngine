using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_binding_hint
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("uint32_t")]
    public uint flags;
}
