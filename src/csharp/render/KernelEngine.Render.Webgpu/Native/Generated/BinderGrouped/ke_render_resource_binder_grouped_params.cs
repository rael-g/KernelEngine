using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Io.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_resource_binder_grouped_params
{
    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("const char *")]
    public sbyte* shader_dir;

    [NativeTypeName("ke_io *")]
    public KernelEngine.Io.Native.ke_io* io;
}
