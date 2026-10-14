using KernelEngine.Ecs.Flecs;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Runtime;

namespace KernelEngine.Framework;

/// <summary>
/// Capacities of the signal bus; a zero field keeps the native default.
/// </summary>
/// <param name="MaxSignals">Distinct signal types. Zero keeps the native default.</param>
/// <param name="MaxConnections">Live source-to-target connections; zero keeps the default.</param>
/// <param name="MaxEvents">Signals raised within one frame. Zero keeps the native default.</param>
/// <param name="MaxDeliveries">Deliveries queued within one frame; zero keeps the default.</param>
/// <param name="PayloadCapacity">Bytes of signal payload per frame; zero keeps the default.</param>
public readonly record struct SignalBusCapacities(uint MaxSignals = 0, uint MaxConnections = 0,
    uint MaxEvents = 0, uint MaxDeliveries = 0, uint PayloadCapacity = 0);

/// <summary>
/// Runtime module "Framework". It registers <see cref="IEcsRegistry"/> over the native ECS, the
/// <see cref="SignalBus"/>, and the <see cref="World"/>, which owns the scene tree created with
/// it. <c>OnLoad</c> resolves the world so that it exists before any scene module runs. The
/// world is created with the ECS, the runtime, the scene tree, the signal bus and, when a
/// logger is registered, the logger.
/// </summary>
public sealed class FrameworkModule : IRuntimeModule
{
    private readonly SignalBusCapacities _signalCapacities;

    /// <summary>Uses the native signal-bus capacities.</summary>
    public FrameworkModule() { }

    /// <summary>
    /// Sizes the signal bus with <paramref name="signalCapacities"/>.
    /// </summary>
    public FrameworkModule(SignalBusCapacities signalCapacities) => _signalCapacities = signalCapacities;

    /// <summary>The module name, "Framework".</summary>
    public string Name => "Framework";

    /// <summary>
    /// Registers the ECS registry, the signal bus and the world.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// A native factory fails when the service is first requested.
    /// </exception>
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

    /// <summary>Creates the world.</summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<World>();
    }
}
