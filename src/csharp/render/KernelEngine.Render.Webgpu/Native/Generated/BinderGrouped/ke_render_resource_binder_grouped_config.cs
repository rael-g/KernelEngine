using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Io.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_resource_binder_grouped_config
{
    [NativeTypeName("const char *")]
    public sbyte* shader_dir;
}
