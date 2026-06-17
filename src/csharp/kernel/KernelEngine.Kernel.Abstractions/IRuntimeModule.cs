using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

/// <summary>
/// A pluggable unit of engine functionality registered with the runtime.
/// </summary>
/// <remarks>
/// Maps 1:1 to the C ABI <c>ke_runtime_module_params</c> at the
/// <see cref="OnLoad"/> boundary — the runtime never sees this interface;
/// it sees an opaque user_data pointer + an on_load callback. Configure
/// is C#-only sugar for participating in <see cref="IServiceCollection"/>;
/// other language bindings provide their own dependency-wiring story.
/// </remarks>
public interface IRuntimeModule
{
    /// <summary>
    /// Optional dependency order. Modules in the dependency list must be
    /// loaded first. Empty by default; topo-sort happens at runtime startup.
    /// </summary>
    IEnumerable<Type> Dependencies => Array.Empty<Type>();

    /// <summary>
    /// Display name used for diagnostics and the C ABI module record.
    /// Defaults to the module's runtime type name.
    /// </summary>
    string Name => GetType().Name;

    /// <summary>
    /// Optional DI participation. Called at <c>services.Add&lt;IRuntimeModule&gt;(instance)</c>
    /// time, BEFORE the service provider is built. Use this to register the
    /// module's implementations under their public contracts
    /// (e.g. <c>services.AddSingleton&lt;IRender&gt;(...)</c>).
    /// Default: no-op.
    /// </summary>
    void Configure(IServiceCollection services) { }

    /// <summary>
    /// Required runtime participation. Called once at startup AFTER the runtime
    /// exists and dependencies are loaded. Maps to <c>ke_runtime_module_params.on_load</c>
    /// at the C ABI level (services parameter is C#-only sugar that lets the
    /// module resolve dependencies it registered during Configure).
    /// Register systems, components, and resources here.
    /// </summary>
    void OnLoad(IRuntime runtime, IServiceProvider services);

    /// <summary>
    /// Symmetric teardown hook. Called once during <c>runtime.UnloadModules</c>
    /// in REVERSE registration order — last-loaded module unloads first. Use
    /// this to release resources that <see cref="OnLoad"/> acquired, especially
    /// those with thread affinity (e.g. dispatch the release to the worker the
    /// resource was created on).
    /// </summary>
    /// <remarks>
    /// Default is a no-op so modules without teardown needs don't pay the
    /// ceremony. Modules that own thread-affine native handles (renderer
    /// destroy on bgfx-init thread, audio device close on its mixer thread,
    /// etc.) MUST override to dispatch their disposal to the right worker —
    /// the runtime calls OnUnload on the main thread.
    /// </remarks>
    void OnUnload(IRuntime runtime, IServiceProvider services) { }
}
