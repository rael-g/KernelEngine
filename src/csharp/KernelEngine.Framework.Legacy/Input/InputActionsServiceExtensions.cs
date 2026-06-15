using System.Reflection;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Legacy;

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

    /// <summary>
    /// Scans loaded assemblies for <c>[GameActions]</c>-decorated enums and registers each via
    /// <see cref="AddInputActions{TEnum}"/>. Lets game code declare action enums declaratively
    /// (one attribute on the enum) without touching <c>Program.cs</c> — the goal being that the
    /// bootstrap is generic and project specifics live in their natural places (Project file,
    /// scenes, enum decls).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Only scans currently-loaded assemblies; types from assemblies not yet referenced (lazy
    /// load) are not discovered. For the typical case where the action enum lives in the entry
    /// assembly (e.g. a Pong-like game), this is enough — the entry assembly is always loaded.
    /// </para>
    /// <para>
    /// <b>AOT-swap path:</b> the reflection + <c>MakeGenericMethod</c> here is the only piece in
    /// this slice that AOT publishing would flag. A source generator scanning game assemblies at
    /// build time emits a partial replacement of this method body with the explicit calls
    /// (<c>services.AddInputActions&lt;PongAction&gt;(); services.AddInputActions&lt;UIAction&gt;();</c>);
    /// callers do not change. Until that generator exists, the scan stays — the seam is one
    /// method, not threaded through callers.
    /// </para>
    /// </remarks>
    [System.Diagnostics.CodeAnalysis.RequiresUnreferencedCode(
        "Scans loaded assemblies for [GameActions]-decorated enums via reflection. " +
        "Will be replaced by a source generator for AOT publishing; until then, the trimmer keeps the enum metadata because game code references it directly.")]
    public static IServiceCollection AddInputActions(this IServiceCollection services)
    {
        var openGeneric = typeof(InputActionsServiceExtensions)
            .GetMethod(nameof(AddInputActions), 1, [typeof(IServiceCollection)])
            ?? throw new InvalidOperationException("Could not locate the generic AddInputActions<TEnum> overload.");

        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            Type[] types;
            try { types = asm.GetTypes(); }
            catch (ReflectionTypeLoadException ex) { types = ex.Types.Where(t => t is not null).ToArray()!; }

            foreach (var t in types)
            {
                if (t is null || !t.IsEnum) continue;
                if (t.GetCustomAttribute<GameActionsAttribute>(inherit: false) is null) continue;
                openGeneric.MakeGenericMethod(t).Invoke(null, [services]);
            }
        }
        return services;
    }
}
