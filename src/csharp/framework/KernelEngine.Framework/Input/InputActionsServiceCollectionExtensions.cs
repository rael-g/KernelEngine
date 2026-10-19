using KernelEngine.Configuration;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>Service registration of the input action map.</summary>
public static class InputActionsServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="InputActionMap{TEnum}"/> built from the TOML file at
    /// <paramref name="path"/> (default <c>actions.input</c>, a relative path resolved against
    /// the application base directory) as itself, as <see cref="IInputActionMap{TEnum}"/> and as
    /// <see cref="IActionEvaluator"/>. The file is loaded when the map is first requested.
    /// </summary>
    public static IServiceCollection AddInputActions<TEnum>(
        this IServiceCollection services, string? path = null)
        where TEnum : struct, Enum
    {
        var resolvedPath = path is null
            ? Path.Combine(AppContext.BaseDirectory, "actions.input")
            : (Path.IsPathRooted(path) ? path : Path.Combine(AppContext.BaseDirectory, path));

        services.AddSingleton(_ => InputActionMap<TEnum>.LoadFromFile(resolvedPath));
        services.AddSingleton<IInputActionMap<TEnum>>(sp => sp.GetRequiredService<InputActionMap<TEnum>>());
        services.AddSingleton<IActionEvaluator>(sp => sp.GetRequiredService<InputActionMap<TEnum>>());
        return services;
    }
}
