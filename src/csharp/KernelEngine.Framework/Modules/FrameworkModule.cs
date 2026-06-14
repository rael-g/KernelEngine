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
        services.AddSingleton<World>(sp =>
        {
            var flecsEcs  = (FlecsEcs)sp.GetRequiredService<IEcs>();
            var rtRuntime = (KernelEngine.Runtime.Runtime)sp.GetRequiredService<IRuntime>();
            var alloc     = (Allocator)sp.GetRequiredService<IAllocator>();
            unsafe
            {
                ke_world_params p = default;
                p.allocator = alloc.Native;
                p.ecs       = flecsEcs.Native;
                p.runtime   = rtRuntime.Native;
                ke_world* w;
                KernelException.ThrowIfFailed(
                    Native.NativeMethods.world_create(&p, &w).ToManaged());
                return new World(w);
            }
        });

        services.AddSingleton<IEcsRegistry>(sp =>
        {
            unsafe { return new EcsRegistry(sp.GetRequiredService<World>().Ecs); }
        });

        services.AddSingleton<ComponentRegistry>(sp =>
            new ComponentRegistry(sp.GetRequiredService<IEcsRegistry>()));

        services.AddSingleton<IComponentRegistry>(sp => sp.GetRequiredService<ComponentRegistry>());
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<ComponentRegistry>();
    }
}
