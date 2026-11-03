using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

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
    /// Registers the ECS registry, the signal bus and the world. The framework library logs to the
    /// registered <see cref="KernelEngine.Logger.ILogger"/> once the world is created, or to stderr
    /// when there is none.
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
                SignalBusParams sp = default;
                sp.MaxSignals = _signalCapacities.MaxSignals;
                sp.MaxConnections = _signalCapacities.MaxConnections;
                sp.MaxEvents = _signalCapacities.MaxEvents;
                sp.MaxDeliveries = _signalCapacities.MaxDeliveries;
                sp.PayloadCapacity = _signalCapacities.PayloadCapacity;
                ke_signal_bus_handle h;
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.signal_bus_create(&sp, &h), "ke_signal_bus_create");
                return new SignalBus(h);
            }
        });

        services.AddSingleton<World>(sp =>
        {
            var flecsEcs = sp.GetRequiredService<INativeEcs>();
            var rtRuntime = (KernelEngine.Runtime.Runtime)sp.GetRequiredService<IRuntime>();
            unsafe
            {
                if (sp.GetService<KernelEngine.Logger.ILogger>() is { } logger)
                    KernelEngine.Framework.Native.NativeMethods.framework_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
                ke_scene_tree_handle tree;
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.scene_tree_create(
                    flecsEcs.Native, ((INativeRuntime)rtRuntime).Native, &tree), "ke_scene_tree_create");

                ke_world_params p = default;
                p.ecs = flecsEcs.Native;
                p.runtime = ((INativeRuntime)rtRuntime).Native;
                p.scene_tree = tree.@ref;
                p.signal_bus = ((INativeSignalBus)sp.GetRequiredService<SignalBus>()).Native;
                ke_world_handle w;
                var made = KernelEngine.Framework.Native.NativeMethods.world_create(&p, &w);
                if (made != KernelEngine.Result.Native.Result.Ok)
                {
                    tree.destroy(tree.@ref);
                    KernelEngine.NativeResults.ThrowIfFailed(made, "ke_world_create");
                }
                return new World(w, tree);
            }
        });

    }

    /// <summary>Creates the world.</summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<World>();
    }
}
