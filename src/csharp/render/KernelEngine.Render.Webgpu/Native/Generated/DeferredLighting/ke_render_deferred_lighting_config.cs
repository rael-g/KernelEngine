using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct ke_render_deferred_lighting_config
{
    public bool ibl_enabled;

    [NativeTypeName("ke_render_gbuffer_resources")]
    public global::KernelEngine.Render.RenderGbufferResources gbuffer;

    [NativeTypeName("ke_render_shadow_resources")]
    public global::KernelEngine.Render.RenderShadowResources shadow;

    [NativeTypeName("ke_render_cluster_resources")]
    public global::KernelEngine.Render.RenderClusterResources clusters;
}
