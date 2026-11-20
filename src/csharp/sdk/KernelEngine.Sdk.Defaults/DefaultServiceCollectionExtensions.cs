using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine;

/// <summary>Registration of an engine of every default part.</summary>
public static class DefaultServiceCollectionExtensions
{
    /// <summary>
    /// Registers the project in <paramref name="projectDir"/>, its configuration, and a <see cref="KernelEngineHost"/>
    /// that opens the default assembly of the project and writes <paramref name="compose"/> into it, in order.
    /// </summary>
    /// <param name="services">The container.</param>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    /// <param name="compose">Each adds the game's parts and composition after the default ones.</param>
    public static IServiceCollection AddDefaultKernelEngine(this IServiceCollection services, string projectDir, params Action<KernelEngine.Assembly.Assembly>[] compose)
    {
        services.AddSingleton(_ => new DefaultProject(projectDir));
        services.AddSingleton(sp => sp.GetRequiredService<DefaultProject>().Configuration);
        return services.AddKernelEngine(sp => sp.GetRequiredService<DefaultProject>().Open(), compose);
    }
}
