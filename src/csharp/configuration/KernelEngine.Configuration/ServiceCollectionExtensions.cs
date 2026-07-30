using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace KernelEngine.Configuration;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="IConfiguration"/> singleton backed by the native
    /// <c>ke_configuration</c> store. With no arguments, looks for a <c>Project</c>
    /// file next to the executable (<see cref="AppContext.BaseDirectory"/>). Safe
    /// to call when the file does not exist — every reader's fallback then applies.
    /// </summary>
    /// <param name="path">
    /// Absolute or relative path to the project manifest. Relative paths resolve against
    /// <see cref="AppContext.BaseDirectory"/>. <c>null</c> means "auto-discover <c>Project</c>
    /// in the base directory".
    /// </param>
    public static IServiceCollection AddProjectConfig(this IServiceCollection services, string? path = null)
    {
        services.TryAddConfigurationSingleton(path);
        return services;
    }

    /// <summary>
    /// Registers <see cref="IConfiguration"/> if not already registered. Plugins that need
    /// config but may be composed without an explicit <see cref="AddProjectConfig"/> call
    /// (e.g. examples wiring modules directly) call this from their own <c>AddX()</c>.
    /// </summary>
    public static void TryAddConfigurationSingleton(this IServiceCollection services, string? path = null)
    {
        services.TryAddSingleton<IConfiguration>(_ =>
        {
            var cfg = new Configuration();
            cfg.LoadToml(ResolvePath(path ?? "Project")!);
            return cfg;
        });
    }

    private static string? ResolvePath(string? path)
    {
        if (path is null) return null;
        if (Path.IsPathRooted(path)) return path;
        return Path.Combine(AppContext.BaseDirectory, path);
    }
}
