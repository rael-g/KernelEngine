using KernelEngine.Framework.Nodes;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace KernelEngine;

/// <summary>What <see cref="ServiceCollectionExtensions.AddKernelEngine"/> builds the engine from.</summary>
public sealed class EngineOptions
{
    /// <summary>The directory holding the project file; the application's base directory unless set.</summary>
    public string ProjectDir { get; set; } = AppContext.BaseDirectory;

    /// <summary>Replaces parts of the engine before it is built.</summary>
    public Action<EngineBuilder>? Configure { get; set; }
}

/// <summary>Registration of an engine into a service collection.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="Engine"/>, built at its first resolution from the registered
    /// <see cref="EngineOptions"/> and logging to the registered <see cref="ILoggerFactory"/> when
    /// there is one, and its <see cref="NodeWorld"/>.
    /// </summary>
    public static IServiceCollection AddKernelEngine(this IServiceCollection services, Action<EngineOptions>? configure = null)
    {
        var options = services.AddOptions<EngineOptions>();
        if (configure is not null) options.Configure(configure);
        services.AddSingleton(sp =>
        {
            var given = sp.GetRequiredService<IOptions<EngineOptions>>().Value;
            var builder = Engine.Builder(given.ProjectDir);
            if (sp.GetService<ILoggerFactory>() is { } logging) builder.WithLogging(logging);
            given.Configure?.Invoke(builder);
            return builder.Build();
        });
        services.AddSingleton(sp => sp.GetRequiredService<Engine>().Nodes);
        return services;
    }
}
