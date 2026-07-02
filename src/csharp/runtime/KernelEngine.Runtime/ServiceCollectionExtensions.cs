
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;

namespace KernelEngine.Runtime;

/// <summary>
/// Uniform DI registration verb for runtime infrastructure and modules. Two
/// overloads cover every case:
/// <list type="bullet">
///   <item><c>Add&lt;TContract, TImpl&gt;()</c> — DI resolves TImpl via its constructor.</item>
///   <item><c>Add&lt;TContract&gt;(instance)</c> — caller provides a pre-built instance
///         (carries per-impl config). If the instance is an <see cref="IRuntimeModule"/>,
///         its <see cref="IRuntimeModule.Configure"/> runs synchronously here so the
///         module can register its own implementations under public contracts.</item>
/// </list>
/// Both overloads map directly to <c>IServiceCollection.AddSingleton</c>; no
/// magic, no hidden side effects beyond the documented Configure call.
/// </summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers <typeparamref name="TImpl"/> as a singleton under
    /// <typeparamref name="TContract"/>. The DI container resolves
    /// <typeparamref name="TImpl"/>'s constructor parameters from other
    /// registered services. Use when the impl has no per-instance config
    /// (e.g. <c>EnkiScheduler</c> just needs the allocator from DI).
    /// </summary>
    public static IServiceCollection Add<TContract, TImpl>(this IServiceCollection services)
        where TContract : class
        where TImpl     : class, TContract
    {
        return services.AddSingleton<TContract, TImpl>();
    }

    /// <summary>
    /// Registers <paramref name="instance"/> as the singleton for
    /// <typeparamref name="TContract"/>. Use when the impl carries config that
    /// only the caller knows (e.g. <c>new WebgpuRenderModule(clearColor: ...)</c>).
    /// If the instance also implements <see cref="IRuntimeModule"/>, its
    /// <see cref="IRuntimeModule.Configure"/> runs immediately so the module can
    /// register its own contracts before the service provider is built.
    /// </summary>
    public static IServiceCollection Add<TContract>(this IServiceCollection services, TContract instance)
        where TContract : class
    {
        if (instance is IRuntimeModule module) module.Configure(services);
        return services.AddSingleton(instance);
    }
}
