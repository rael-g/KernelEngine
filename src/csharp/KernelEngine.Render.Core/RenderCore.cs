using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using RenderCoreNative = KernelEngine.Render.Core.Native.NativeMethods;

namespace KernelEngine.Render.Core;

/// <summary>
/// Render systems registered by <see cref="RenderCore.RegisterDefaultSystems"/>.
/// Camera, Light, and Mesh were ported to pure-managed C# implementations in
/// <c>KernelEngine.Framework</c>. The rest will follow.
/// </summary>
public record DefaultRenderSystems(
    ShadowRenderSystem Shadow,
    SkyboxRenderSystem Skybox);

public static unsafe class RenderCore
{
    /// <summary>
    /// Registers the (still C++) default render systems into the native world and returns their managed wrappers.
    /// </summary>
    public static DefaultRenderSystems RegisterDefaultSystems(
        World world,
        IRenderer renderer,
        uint meshCid,
        uint transformCid,
        uint lightCid,
        uint skyboxCid)
    {
        ke_system_params shadowParams;
        RenderCoreNative.render_core_shadow_system_describe(lightCid, meshCid, transformCid, &shadowParams);

        ke_system_params skyboxParams;
        RenderCoreNative.render_core_skybox_system_describe(skyboxCid, &skyboxParams);

        var shadow = new ShadowRenderSystem(shadowParams);
        var skybox = new SkyboxRenderSystem(skyboxParams);

        world.AddSystem(shadow);
        world.AddSystem(skybox);

        return new DefaultRenderSystems(shadow, skybox);
    }
}
