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
    /// Resolves every <see cref="IRuntimeModule"/> registered with the service
    /// provider, topo-sorts by declared dependencies, and registers each one
    /// with the runtime in dependency order. The runtime's RegisterModule
    /// dispatches <see cref="IRuntimeModule.OnLoad"/> synchronously, so by the
    /// time this returns every module's OnLoad has run.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// Thrown when the dependency graph has a cycle or references a module
    /// that wasn't registered.
    /// </exception>
    public static void LoadModules(this IRuntime runtime, IServiceProvider services)
    {
        var modules = services.GetServices<IRuntimeModule>().ToList();
        if (modules.Count == 0) return;

        foreach (var module in TopoSort(modules))
        {
            runtime.RegisterModule(module.Name,
                rt => module.OnLoad(rt, services),
                rt => module.OnUnload(rt, services));
        }
    }

    private static List<IRuntimeModule> TopoSort(List<IRuntimeModule> modules)
    {
        var byType = modules.ToDictionary(m => m.GetType());
        var sorted = new List<IRuntimeModule>(modules.Count);
        var state = new Dictionary<IRuntimeModule, byte>();

        void Visit(IRuntimeModule m)
        {
            if (state.TryGetValue(m, out var s))
            {
                if (s == 2) return;
                if (s == 1) throw new InvalidOperationException(
                    $"Module dependency cycle detected involving '{m.Name}'.");
            }
            state[m] = 1;
            foreach (var depType in m.Dependencies)
            {
                if (!byType.TryGetValue(depType, out var dep))
                    throw new InvalidOperationException(
                        $"Module '{m.Name}' depends on '{depType.Name}' which is not registered.");
                Visit(dep);
            }
            state[m] = 2;
            sorted.Add(m);
        }

        foreach (var m in modules) Visit(m);
        return sorted;
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
