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
/// <see cref="SignalBus"/>, the <see cref="SceneTree"/> and the <see cref="ComponentRegistry"/>.
/// <c>OnLoad</c> resolves the tree and the registry so that they exist before any scene module
/// runs.
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
    /// Registers the ECS registry, the signal bus, the scene tree and the component registry. The
    /// framework library logs to the registered <see cref="KernelEngine.Logger.ILogger"/> once the
    /// scene tree is created, or to stderr when there is none.
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

        services.AddSingleton<SceneTree>(sp =>
        {
            var flecsEcs = sp.GetRequiredService<INativeEcs>();
            var runtime = (INativeRuntime)sp.GetRequiredService<IRuntime>();
            unsafe
            {
                if (sp.GetService<KernelEngine.Logger.ILogger>() is { } logger)
                    KernelEngine.Framework.Native.NativeMethods.framework_set_log_callback(KernelEngine.Logger.LogCallbackNative.Pointer, KernelEngine.Logger.LogCallbackNative.Pin(logger.Log));
                ke_scene_tree_handle tree;
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.scene_tree_create(
                    flecsEcs.Native, runtime.Native, &tree), "ke_scene_tree_create");
                var sceneTree = new SceneTree(tree);
                sceneTree.Hold(flecsEcs.Owner);
                sceneTree.Hold(runtime.Owner);
                return sceneTree;
            }
        });

        services.AddSingleton<ComponentRegistry>(sp =>
        {
            var flecsEcs = sp.GetRequiredService<INativeEcs>();
            _ = sp.GetRequiredService<SceneTree>();
            unsafe
            {
                ke_component_registry_handle registry;
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.component_registry_create(
                    flecsEcs.Native, &registry), "ke_component_registry_create");
                var componentRegistry = new ComponentRegistry(registry);
                componentRegistry.Hold(flecsEcs.Owner);
                return componentRegistry;
            }
        });
    }

    /// <summary>Creates the scene tree and the component registry.</summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<SceneTree>();
        _ = services.GetRequiredService<ComponentRegistry>();
    }
}
