using KernelEngine.Ecs.Flecs;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// Creates the native <c>ke_world</c> aggregator and registers the ECS registry as
/// <see cref="IEcsRegistry"/> so the scene modules can resolve it without a direct
/// dependency on this assembly. Add it before any scene module, which needs the
/// interface to already be in DI.
/// </summary>
public sealed class FrameworkModule : IRuntimeModule
{
    public string Name => "Framework";

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<IEcsRegistry>(sp =>
        {
            var flecsEcs = (FlecsEcs)sp.GetRequiredService<IEcs>();
            unsafe { return EcsRegistry.Borrow(((INativeEcs)flecsEcs).Native); }
        });

        services.AddSingleton<SignalBus>(_ =>
        {
            unsafe
            {
                var h = KernelEngine.Framework.Native.NativeMethods.signal_bus_create(null, null);
                if (h.@ref == null) throw new InvalidOperationException("signal_bus_create failed");
                return new SignalBus(h);
            }
        });

        services.AddSingleton<World>(sp =>
        {
            var flecsEcs  = (FlecsEcs)sp.GetRequiredService<IEcs>();
            var rtRuntime = (KernelEngine.Runtime.Runtime)sp.GetRequiredService<IRuntime>();
            var ecs       = sp.GetRequiredService<IEcsRegistry>();
            var runtime   = sp.GetRequiredService<IRuntime>();
            unsafe
            {
                var tree = KernelEngine.Framework.Native.NativeMethods.scene_tree_create(
                    ((INativeEcs)flecsEcs).Native, ((INativeRuntime)rtRuntime).Native, null);
                if (tree.@ref == null) throw new InvalidOperationException("scene_tree_create failed");

                ke_world_params p = default;
                p.ecs        = ((INativeEcs)flecsEcs).Native;
                p.runtime    = ((INativeRuntime)rtRuntime).Native;
                p.scene_tree = tree.@ref;
                p.signal_bus = ((INativeSignalBus)sp.GetRequiredService<SignalBus>()).Native;
                p.logger     = sp.GetService<KernelEngine.Logger.INativeLogger>() is { } lg ? lg.Native : null;
                var w = KernelEngine.Framework.Native.NativeMethods.world_create(&p, null);
                if (w.@ref == null) throw new InvalidOperationException("world_create failed");
                return new World(w, tree, ecs, runtime);
            }
        });

    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<World>();
    }
}
