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
/// <param name="MaxSignals">Distinct signal types. Zero keeps the native default.</param>
/// <param name="MaxConnections">Live source-to-target connections. Zero keeps the native default.</param>
/// <param name="MaxEvents">Signals raised within one frame. Zero keeps the native default.</param>
/// <param name="MaxDeliveries">Deliveries queued within one frame. Zero keeps the native default.</param>
/// <param name="PayloadCapacity">Bytes of signal payload per frame. Zero keeps the native default.</param>
public readonly record struct SignalBusCapacities(uint MaxSignals = 0, uint MaxConnections = 0,
    uint MaxEvents = 0, uint MaxDeliveries = 0, uint PayloadCapacity = 0);

public sealed class FrameworkModule : IRuntimeModule
{
    private readonly SignalBusCapacities _signalCapacities;

    /// <summary>Uses the native signal-bus capacities.</summary>
    public FrameworkModule() { }

    /// <summary>
    /// Sizes the signal bus for a scene whose connection or event count exceeds what the
    /// native defaults size for.
    /// </summary>
    public FrameworkModule(SignalBusCapacities signalCapacities) => _signalCapacities = signalCapacities;

    public string Name => "Framework";

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<IEcsRegistry>(sp =>
        {
            var flecsEcs = sp.GetRequiredService<INativeEcs>();
            unsafe { return EcsRegistry.Borrow(flecsEcs.Native); }
        });

        services.AddSingleton<SignalBus>(_ =>
        {
            unsafe
            {
                ke_signal_bus_params sp = default;
                sp.max_signals      = _signalCapacities.MaxSignals;
                sp.max_connections  = _signalCapacities.MaxConnections;
                sp.max_events       = _signalCapacities.MaxEvents;
                sp.max_deliveries   = _signalCapacities.MaxDeliveries;
                sp.payload_capacity = _signalCapacities.PayloadCapacity;
                var h = KernelEngine.Framework.Native.NativeMethods.signal_bus_create(&sp, null);
                if (h.@ref == null) throw new InvalidOperationException("signal_bus_create failed");
                return new SignalBus(h);
            }
        });

        services.AddSingleton<World>(sp =>
        {
            var flecsEcs  = sp.GetRequiredService<INativeEcs>();
            var rtRuntime = (KernelEngine.Runtime.Runtime)sp.GetRequiredService<IRuntime>();
            var ecs       = sp.GetRequiredService<IEcsRegistry>();
            var runtime   = sp.GetRequiredService<IRuntime>();
            unsafe
            {
                var tree = KernelEngine.Framework.Native.NativeMethods.scene_tree_create(
                    flecsEcs.Native, ((INativeRuntime)rtRuntime).Native, null);
                if (tree.@ref == null) throw new InvalidOperationException("scene_tree_create failed");

                ke_world_params p = default;
                p.ecs        = flecsEcs.Native;
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
