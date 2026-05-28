using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public static class InputActionsServiceExtensions
{
    /// <summary>
    /// Registers <typeparamref name="TEnum"/> as the game's action enum. <see cref="Application"/>
    /// auto-loads <c>actions.input</c> (path from the Project file's <c>[input].actions</c>) before
    /// <c>OnReady</c> runs, so game code can call <c>InputActions.Get&lt;TEnum&gt;()</c> from
    /// anywhere without doing the load itself.
    /// </summary>
    public static IServiceCollection AddInputActions<TEnum>(this IServiceCollection services)
        where TEnum : struct, Enum
    {
        services.AddSingleton<InputActions.IAutoLoader, InputActions.AutoLoader<TEnum>>();
        // Resolve the polling reader lazily — AutoLoader runs before any node that needs it is
        // constructed, so InputActions.Get<TEnum>() is populated by the time the factory fires.
        services.AddSingleton<IInputActionReader<TEnum>>(_ => InputActions.Get<TEnum>());
        return services;
    }
}
