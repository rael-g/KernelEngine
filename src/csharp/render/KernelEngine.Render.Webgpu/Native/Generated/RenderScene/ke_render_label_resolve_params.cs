using KernelEngine.Common.Native;

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

    [NativeTypeName("ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;

    [NativeTypeName("ke_component_id")]
    public uint label_cid;
}
