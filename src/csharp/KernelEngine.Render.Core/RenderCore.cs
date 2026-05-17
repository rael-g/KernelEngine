using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using RenderCoreNative = KernelEngine.Render.Core.Native.NativeMethods;

namespace KernelEngine.Render.Core;

/// <summary>
/// Render systems registered by <see cref="RenderCore.RegisterDefaultSystems"/>.
/// Camera, Light, Mesh, and Skybox were ported to pure-managed C# implementations in
/// <c>KernelEngine.Framework</c>. Shadow is the last C++ system pending migration.
/// </summary>
public record DefaultRenderSystems(ShadowRenderSystem Shadow);

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
        uint lightCid)
    {
        ke_system_params shadowParams;
        RenderCoreNative.render_core_shadow_system_describe(lightCid, meshCid, transformCid, &shadowParams);

        var shadow = new ShadowRenderSystem(shadowParams);
        world.AddSystem(shadow);

        return new DefaultRenderSystems(shadow);
    }
}
