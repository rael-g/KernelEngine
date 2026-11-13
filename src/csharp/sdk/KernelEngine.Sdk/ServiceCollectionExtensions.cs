using KernelEngine.Framework.Nodes;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine;

/// <summary>Registration of an engine into a service collection.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="Engine"/>, made at its first resolution from the parts registered under their
    /// contracts, and its <see cref="NodeWorld"/>.
    /// </summary>
    public static IServiceCollection AddKernelEngine(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Engine(sp));
        services.AddSingleton(sp => sp.GetRequiredService<Engine>().Nodes);
        return services;
    }
}
