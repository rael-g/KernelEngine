using KernelEngine.Ecs;
using KernelEngine.TaskPool;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Runtime;

/// <summary>
/// Registers the <see cref="IRuntimeModule"/> instances of a service provider with a runtime.
/// </summary>
public static class RuntimeStartup
{
    /// <summary>
    /// Registers every <see cref="IRuntimeModule"/> of the service provider with the runtime, in
    /// the order they were added to the service collection. The runtime's RegisterModule
    /// dispatches <see cref="IRuntimeModule.OnLoad"/> synchronously, so by the time this returns
    /// every module's OnLoad has run.
    /// </summary>
    public static void LoadModules(this IRuntime runtime, IServiceProvider services)
    {
        foreach (var module in services.GetServices<IRuntimeModule>())
        {
            runtime.RegisterModule(module.Name,
                rt => module.OnLoad(rt, services),
                rt => module.OnUnload(rt, services));
        }
    }
}

/// <summary>A service created when the modules load, which a module can create earlier.</summary>
public interface IResolveOnLoad
{
    /// <summary>Creates the service now, in its order of registration.</summary>
    void Resolve(IServiceProvider services);
}

/// <summary>
/// Resolves <typeparamref name="T"/> when the modules load, for a service whose construction is
/// its work, such as a render pass that registers its systems. The container owns the instance.
/// </summary>
public sealed class ResolveOnLoadModule<T> : IRuntimeModule, IResolveOnLoad where T : notnull
{
    /// <inheritdoc/>
    public void Resolve(IServiceProvider services) => services.GetRequiredService<T>();

    /// <inheritdoc/>
    public string Name => typeof(T).FullName!;

    /// <inheritdoc/>
    public void Configure(IServiceCollection services) { }

    /// <inheritdoc/>
    public void OnLoad(IRuntime runtime, IServiceProvider services) => services.GetRequiredService<T>();
}
