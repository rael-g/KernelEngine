using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Creates the native <c>ke_world</c> aggregator and registers the ECS registry +
/// component registry as <see cref="IEcsRegistry"/> and <see cref="IComponentRegistry"/>
/// so Toolkit's <c>SceneRenderModule</c> can resolve them without a direct
/// dependency on this assembly.
/// </summary>
/// <remarks>
/// Add this module before <c>SceneRenderModule</c>. It must run first so the
/// interfaces are in DI before the scene infrastructure tries to resolve them.
/// </remarks>
public sealed class FrameworkModule : IRuntimeModule
{
    public string Name => "Framework";

    public void Configure(IServiceCollection services)
    {
        // IEcsRegistry is registered first because World's constructor borrows it.
        services.AddSingleton<IEcsRegistry>(sp =>
        {
            var flecsEcs = (FlecsEcs)sp.GetRequiredService<IEcs>();
            unsafe { return new EcsRegistry(((INativeEcs)flecsEcs).Native); }
        });

        services.AddSingleton<World>(sp =>
        {
            var flecsEcs  = (FlecsEcs)sp.GetRequiredService<IEcs>();
            var rtRuntime = (KernelEngine.Runtime.Runtime)sp.GetRequiredService<IRuntime>();
            var ecs       = sp.GetRequiredService<IEcsRegistry>();
            var runtime   = sp.GetRequiredService<IRuntime>();
            unsafe
            {
                var tree = KernelEngine.Framework.Native.NativeMethods.scene_tree_create(((INativeEcs)flecsEcs).Native, null);
                if (tree.@ref == null) throw new InvalidOperationException("scene_tree_create failed");

                ke_world_params p = default;
                p.ecs        = ((INativeEcs)flecsEcs).Native;
                p.runtime    = ((INativeRuntime)rtRuntime).Native;
                p.scene_tree = tree.@ref;
                var w = KernelEngine.Framework.Native.NativeMethods.world_create(&p, null);
                if (w.@ref == null) throw new InvalidOperationException("world_create failed");
                return new World(w, tree, ecs, runtime);
            }
        });

        services.AddSingleton<ComponentRegistry>(sp =>
        {
            // World (and its scene_tree) must be fully initialized before ComponentRegistry
            // so that kernel components like "transform" are registered at their native C
            // sizes (104 bytes) before this registry re-registers them at framework sizes
            // (40 bytes). If scene_tree runs second, flecs stores transform at 40 bytes
            // and C writes of ke_transform_component (104 bytes) corrupt adjacent heap.
            // This guarantee must live in the factory so it holds no matter who triggers
            // ComponentRegistry first (e.g. BgfxRenderModule resolving IFrameContributors).
            _ = sp.GetRequiredService<World>();
            return new ComponentRegistry(sp.GetRequiredService<IEcsRegistry>());
        });

        services.AddSingleton<IComponentRegistry>(sp => sp.GetRequiredService<ComponentRegistry>());
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<World>();
        _ = services.GetRequiredService<ComponentRegistry>();
    }
}
