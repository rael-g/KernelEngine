using KernelEngine.Configuration;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>Service registration of the input action maps.</summary>
public static class InputActionsServiceCollectionExtensions
{
    /// <summary>
    /// Registers the <see cref="InputActions"/> built from the <c>input</c> section of the
    /// registered <see cref="IConfiguration"/>, or empty when none is registered. The scene
    /// evaluates it once per frame, and an <see cref="InputAction"/> field reads it.
    /// </summary>
    public static IServiceCollection AddInputActions(this IServiceCollection services)
        => services.AddSingleton(sp => new InputActions(sp.GetService<IConfiguration>() as INativeConfiguration));
}
