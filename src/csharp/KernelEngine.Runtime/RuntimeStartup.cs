using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Runtime;

/// <summary>
/// Bootstrap helpers that drive the module lifecycle. Lives outside the
/// <see cref="Runtime"/> class so the runtime stays unaware of DI — it only
/// knows about its own <c>RegisterModule</c> API.
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

        var ordered = TopoSort(modules);
        foreach (var module in ordered)
        {
            runtime.RegisterModule(module.Name, rt => module.OnLoad(rt, services));
        }
    }

    private static List<IRuntimeModule> TopoSort(List<IRuntimeModule> modules)
    {
        var byType = modules.ToDictionary(m => m.GetType());
        var sorted = new List<IRuntimeModule>(modules.Count);
        var state  = new Dictionary<IRuntimeModule, byte>();  // 0=unseen, 1=visiting, 2=done

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
