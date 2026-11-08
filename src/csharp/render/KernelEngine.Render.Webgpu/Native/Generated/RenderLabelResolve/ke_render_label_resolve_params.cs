using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_label_resolve_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    public ke_render_ui* ui;

    [NativeTypeName("ke_asset_resolver *")]
    public KernelEngine.Asset.Native.ke_asset_resolver* resolver;

    [NativeTypeName("ke_render_scene_resolve *")]
    public KernelEngine.Render.Native.ke_render_scene_resolve* scene;

    [NativeTypeName("const char *")]
    public sbyte* default_font;
}
