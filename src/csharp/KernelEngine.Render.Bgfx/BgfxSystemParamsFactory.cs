using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using BgfxNative = KernelEngine.Render.Bgfx.Native.NativeMethods;

namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Creates native <see cref="ke_system_params"/> instances for each bgfx render system.
/// Lives in the Bgfx plugin layer so the Kernel layer stays unaware of bgfx internals.
/// </summary>
public static unsafe class BgfxSystemParamsFactory
{
    public static ke_system_params CreateMeshSystemParams(uint meshCid, uint transformCid)
    {
        ke_system_params @params;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_mesh_system_params(meshCid, transformCid, &@params), "create_mesh_system_params");
        return @params;
    }

    public static ke_system_params CreateLightSystemParams(uint lightCid, uint pointCid, uint spotCid, uint transformCid)
    {
        ke_system_params @params;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_light_system_params(lightCid, pointCid, spotCid, transformCid, &@params), "create_light_system_params");
        return @params;
    }

    public static ke_system_params CreateCameraSystemParams(uint cameraCid, uint transformCid)
    {
        ke_system_params @params;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_camera_system_params(cameraCid, transformCid, &@params), "create_camera_system_params");
        return @params;
    }

    public static ke_system_params CreateShadowSystemParams(uint lightCid, uint meshCid, uint transformCid)
    {
        ke_system_params @params;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_shadow_system_params(lightCid, meshCid, transformCid, &@params), "create_shadow_system_params");
        return @params;
    }

    public static ke_system_params CreateSkyboxSystemParams(uint skyboxCid)
    {
        ke_system_params @params;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_skybox_system_params(skyboxCid, &@params), "create_skybox_system_params");
        return @params;
    }
}
