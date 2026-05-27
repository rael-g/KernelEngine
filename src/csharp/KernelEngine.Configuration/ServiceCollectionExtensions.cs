using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Configuration;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="IProjectConfig"/> singleton. With no arguments, looks for a
    /// <c>Project</c> file next to the executable (<see cref="AppContext.BaseDirectory"/>).
    /// Plugins call <see cref="AddProjectConfigSection{TOptions}"/> separately to bind their
    /// section. Safe to call when the file does not exist — every plugin then sees POCO
    /// defaults (chapter 16 §2.4).
    /// </summary>
    /// <param name="path">
    /// Absolute or relative path to the project manifest. Relative paths resolve against
    /// <see cref="AppContext.BaseDirectory"/>. <c>null</c> means "auto-discover <c>Project</c>
    /// in the base directory, fall back to defaults if absent".
    /// </param>
    public static IServiceCollection AddProjectConfig(this IServiceCollection services, string? path = null)
    {
        services.AddOptions();
        services.AddSingleton<IProjectConfig>(_ => new ProjectConfig(ResolvePath(path ?? "Project")));
        return services;
    }

    /// <summary>
    /// Binds the TOML section at <paramref name="sectionPath"/> (e.g. <c>"runtime.window"</c>)
    /// onto <typeparamref name="TOptions"/>. Called from each plugin's own DI extension.
    /// If the section is missing the POCO keeps its compile-time defaults.
    /// </summary>
    public static IServiceCollection AddProjectConfigSection<TOptions>(
        this IServiceCollection services, string sectionPath) where TOptions : class
    {
        services.AddOptions<TOptions>().Configure<IProjectConfig>((opts, config) =>
        {
            var section = config.GetSection(sectionPath);
            if (section is not null) TomlOptionsBinder.Apply(section, opts);
        });
        return services;
    }

    private static string? ResolvePath(string? path)
    {
        if (path is null) return null;
        if (Path.IsPathRooted(path)) return path;
        return Path.Combine(AppContext.BaseDirectory, path);
    }
}
