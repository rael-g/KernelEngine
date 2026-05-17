using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using RenderCoreNative = KernelEngine.Render.Core.Native.NativeMethods;

namespace KernelEngine.Render.Core;

/// <summary>
/// Render systems registered by <see cref="RenderCore.RegisterDefaultSystems"/>.
/// Camera is intentionally not included — the Framework supplies a pure-managed
/// CameraRenderSystem (migration in progress; the rest will follow).
/// </summary>
public record DefaultRenderSystems(
    MeshRenderSystem Mesh,
    LightRenderSystem Light,
    ShadowRenderSystem Shadow,
    SkyboxRenderSystem Skybox);

public static unsafe class RenderCore
{
    /// <summary>
    /// Registers the (still C++) default render systems into the native world and returns their managed wrappers.
    /// Camera was ported to C# and is registered separately by <c>Application</c>.
    /// </summary>
    public static DefaultRenderSystems RegisterDefaultSystems(
        World world,
        IRenderer renderer,
        uint meshCid,
        uint transformCid,
        uint lightCid,
        uint pointCid,
        uint spotCid,
        uint skyboxCid)
    {
        ke_system_params meshParams;
        RenderCoreNative.render_core_mesh_system_describe(meshCid, transformCid, &meshParams);

        ke_system_params lightParams;
        RenderCoreNative.render_core_light_system_describe(lightCid, pointCid, spotCid, transformCid, &lightParams);

        ke_system_params shadowParams;
        RenderCoreNative.render_core_shadow_system_describe(lightCid, meshCid, transformCid, &shadowParams);

        ke_system_params skyboxParams;
        RenderCoreNative.render_core_skybox_system_describe(skyboxCid, &skyboxParams);

        var mesh = new MeshRenderSystem(meshParams);
        var light = new LightRenderSystem(lightParams);
        var shadow = new ShadowRenderSystem(shadowParams);
        var skybox = new SkyboxRenderSystem(skyboxParams);

        world.AddSystem(mesh);
        world.AddSystem(light);
        world.AddSystem(shadow);
        world.AddSystem(skybox);

        return new DefaultRenderSystems(mesh, light, shadow, skybox);
    }
}
