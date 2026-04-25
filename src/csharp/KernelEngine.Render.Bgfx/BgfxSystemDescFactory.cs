using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using BgfxNative = KernelEngine.Render.Bgfx.Native.NativeMethods;

namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Creates native <see cref="ke_system_desc"/> instances for each bgfx render system.
/// Lives in the Bgfx plugin layer so the Kernel layer stays unaware of bgfx internals.
/// </summary>
public static unsafe class BgfxSystemDescFactory
{
    public static ke_system_desc CreateMeshSystemDesc(uint meshCid, uint transformCid)
    {
        ke_system_desc desc;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_mesh_system_desc(meshCid, transformCid, &desc), "create_mesh_system_desc");
        return desc;
    }

    public static ke_system_desc CreateLightSystemDesc(uint lightCid, uint pointCid, uint spotCid, uint transformCid)
    {
        ke_system_desc desc;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_light_system_desc(lightCid, pointCid, spotCid, transformCid, &desc), "create_light_system_desc");
        return desc;
    }

    public static ke_system_desc CreateCameraSystemDesc(uint cameraCid, uint transformCid)
    {
        ke_system_desc desc;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_camera_system_desc(cameraCid, transformCid, &desc), "create_camera_system_desc");
        return desc;
    }

    public static ke_system_desc CreateShadowSystemDesc(uint lightCid, uint meshCid, uint transformCid)
    {
        ke_system_desc desc;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_shadow_system_desc(lightCid, meshCid, transformCid, &desc), "create_shadow_system_desc");
        return desc;
    }

    public static ke_system_desc CreateSkyboxSystemDesc(uint skyboxCid)
    {
        ke_system_desc desc;
        KernelException.ThrowIfFailed(BgfxNative.render_bgfx_create_skybox_system_desc(skyboxCid, &desc), "create_skybox_system_desc");
        return desc;
    }
}
