using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;

using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Module.Native;
using KernelEngine.Render.Frame.Native;
using KernelEngine.Render.Native;
using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_frame_config
{
    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat color_format;

    [NativeTypeName("ke_gpu_texture_format")]
    public global::KernelEngine.Render.GpuTextureFormat depth_format;

    [NativeTypeName("ke_vec4")]
    public System.Numerics.Vector4 clear_color;
}
