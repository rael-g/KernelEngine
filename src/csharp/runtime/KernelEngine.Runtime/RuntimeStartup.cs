using System.Runtime.CompilerServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;

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

        // Remember the load order so UnloadModules can reverse it. Weak ref
        // means we don't keep the runtime alive past its natural lifetime.
        s_loadOrder.AddOrUpdate(runtime, ordered);
    }

    /// <summary>
    /// Calls <see cref="IRuntimeModule.OnUnload"/> on every module previously
    /// loaded via <see cref="LoadModules"/>, in reverse order. Modules that own
    /// thread-affine resources (renderer, audio device, etc.) are expected to
    /// dispatch their disposal to the correct worker in OnUnload; the runtime
    /// only fires the callback synchronously on the calling thread.
    /// </summary>
    /// <remarks>
    /// Idempotent — calling twice runs OnUnload once. Game code should call
    /// this after the tick loop and before <c>IServiceProvider.Dispose</c>;
    /// disposing services without unloading risks thread-affinity violations
    /// on native resources created by pinned systems.
    /// </remarks>
    public static void UnloadModules(this IRuntime runtime, IServiceProvider services)
    {
        if (!s_loadOrder.TryGetValue(runtime, out var ordered)) return;
        s_loadOrder.Remove(runtime);

        for (int i = ordered.Count - 1; i >= 0; i--)
            ordered[i].OnUnload(runtime, services);
    }

    private static readonly ConditionalWeakTable<IRuntime, List<IRuntimeModule>> s_loadOrder = new();

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
