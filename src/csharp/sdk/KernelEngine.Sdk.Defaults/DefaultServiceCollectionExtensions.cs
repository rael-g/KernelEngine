using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine;

/// <summary>Registration of an engine of every default part.</summary>
public static class DefaultServiceCollectionExtensions
{
    /// <summary>
    /// Registers the project in <paramref name="projectDir"/>, its configuration, and a <see cref="KernelEngineHost"/>
    /// that opens the assembly of the project with the default composition, <c>defaults.composition</c>, and writes
    /// <paramref name="compose"/> into it, in order.
    /// </summary>
    /// <param name="services">The container.</param>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    /// <param name="compose">Each adds the game's parts and composition after the default ones.</param>
    public static IServiceCollection AddDefaultKernelEngine(this IServiceCollection services, string projectDir, params Action<KernelEngine.Assembly.Assembly>[] compose) =>
        services.AddDefaultKernelEngine(projectDir, "defaults.composition", compose);

    /// <summary>
    /// Registers the project in <paramref name="projectDir"/>, its configuration, and a <see cref="KernelEngineHost"/>
    /// that opens the assembly of the project with the composition the file <paramref name="composition"/> beside the
    /// executable holds, and writes <paramref name="compose"/> into it, in order.
    /// </summary>
    /// <param name="services">The container.</param>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    /// <param name="composition">The file name; see <see cref="DefaultProject.Open"/>.</param>
    /// <param name="compose">Each adds the game's parts and composition after the file's.</param>
    public static IServiceCollection AddDefaultKernelEngine(this IServiceCollection services, string projectDir, string composition, params Action<KernelEngine.Assembly.Assembly>[] compose)
    {
        services.AddSingleton(_ => new DefaultProject(projectDir));
        services.AddSingleton(sp => sp.GetRequiredService<DefaultProject>().Configuration);
        return services.AddKernelEngine(sp => sp.GetRequiredService<DefaultProject>().Open(composition), compose);
    }
}
