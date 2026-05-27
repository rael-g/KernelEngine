using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace KernelEngine.Configuration;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="IProjectConfig"/> singleton that loads the given Project.toml.
    /// Plugins call <see cref="AddProjectConfigSection{TOptions}"/> separately to bind their
    /// section. Safe to call when <paramref name="tomlPath"/> does not exist — every plugin
    /// then sees POCO defaults (chapter 16 §2.4).
    /// </summary>
    /// <param name="tomlPath">
    /// Absolute or relative path to the Project.toml. When relative, the runtime resolves
    /// it against <see cref="AppContext.BaseDirectory"/>; <c>null</c> means "no file —
    /// every plugin uses POCO defaults".
    /// </param>
    public static IServiceCollection AddProjectConfig(this IServiceCollection services, string? tomlPath = null)
    {
        services.AddOptions();
        services.AddSingleton<IProjectConfig>(_ => new ProjectConfig(ResolvePath(tomlPath)));
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
