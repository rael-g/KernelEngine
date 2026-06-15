using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public static class InputActionsServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="IInputActionMap{TEnum}"/> singleton built from the TOML
    /// file at <paramref name="path"/> (defaults to <c>actions.input</c> next to the
    /// executable). Loaded eagerly so missing-file or parse errors surface at startup.
    /// </summary>
    public static IServiceCollection AddInputActions<TEnum>(
        this IServiceCollection services, string? path = null)
        where TEnum : struct, Enum
    {
        var resolvedPath = path is null
            ? Path.Combine(AppContext.BaseDirectory, "actions.input")
            : (Path.IsPathRooted(path) ? path : Path.Combine(AppContext.BaseDirectory, path));

        services.AddSingleton<IInputActionMap<TEnum>>(_ => InputActionMap<TEnum>.LoadFromFile(resolvedPath));
        return services;
    }
}
