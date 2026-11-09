using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_label_resolve_config
{
    [NativeTypeName("const char *")]
    public sbyte* default_font;
}
