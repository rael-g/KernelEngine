using System.Numerics;
using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Polling facade game code uses to read action state during <c>Update</c>. One reader per game
/// enum; obtained via <see cref="InputActions.Get{TEnum}"/>.
/// </summary>
public interface IInputActionReader<TEnum> where TEnum : struct, Enum
{
    /// <summary>True while <paramref name="action"/>'s combined value is currently active.</summary>
    bool IsActionDown(TEnum action);

    /// <summary>True for exactly the frame <paramref name="action"/> transitioned inactive → active.</summary>
    bool WasActionPressed(TEnum action);

    /// <summary>True for exactly the frame <paramref name="action"/> transitioned active → inactive.</summary>
    bool WasActionReleased(TEnum action);

    /// <summary>Current Axis1D value (typically in [-1, +1]). Zero when no Axis1D action is registered.</summary>
    float GetActionAxis1D(TEnum action);

    /// <summary>Current Axis2D value. Zero when no Axis2D action is registered.</summary>
    Vector2 GetActionAxis2D(TEnum action);

    /// <summary>Current Axis3D value. Zero when no Axis3D action is registered.</summary>
    Vector3 GetActionAxis3D(TEnum action);
}

/// <summary>
/// Global registry + polling access point for the action layer. Mirrors the
/// <see cref="InputContext"/> pattern: one process-wide entry point, ergonomic from any
/// <c>Node.Update</c>.
/// </summary>
/// <remarks>
/// MVP scope (Slice 1): a single map per game enum. Map stacks / context push-pop / per-device
/// pairing land in later slices (spec §6, §9).
/// </remarks>
public static class InputActions
{
    /// <summary>
    /// Backend factory delegate set by the registered native assembly (typically
    /// <c>AddNativeFramework()</c>). Used by <see cref="InputActionMap{TEnum}"/>'s
    /// parameterless constructor and by <see cref="LoadFromProject{TEnum}"/> so callers
    /// don't have to wire <see cref="IFrameworkBackendFactory"/> manually.
    /// </summary>
    public static Func<IInputActionsBackend>? CreateBackend { get; set; }

    private static readonly Dictionary<Type, IInputActionMap> s_maps = new();
    private static readonly Dictionary<Type, object>          s_readers = new();

    /// <summary>
    /// Registers <paramref name="map"/> so the engine's per-frame dispatcher evaluates it. Replaces
    /// any previously registered map for the same <typeparamref name="TEnum"/>.
    /// </summary>
    public static IInputActionReader<TEnum> Register<TEnum>(InputActionMap<TEnum> map)
        where TEnum : struct, Enum
    {
        s_maps[typeof(TEnum)] = map;
        var reader = new InputActionReader<TEnum>(map);
        s_readers[typeof(TEnum)] = reader;
        return reader;
    }

    /// <summary>
    /// Returns the polling reader for the previously-registered map of <typeparamref name="TEnum"/>.
    /// Throws when no map of that enum has been registered yet.
    /// </summary>
    public static IInputActionReader<TEnum> Get<TEnum>() where TEnum : struct, Enum
    {
        if (s_readers.TryGetValue(typeof(TEnum), out var r))
            return (IInputActionReader<TEnum>)r;
        throw new InvalidOperationException(
            $"No InputActionMap registered for {typeof(TEnum).Name}. Call InputActions.Register first.");
    }

    /// <summary>Removes all registered maps. Used by tests; game code does not call this.</summary>
    public static void Clear()
    {
        s_maps.Clear();
        s_readers.Clear();
    }

    /// <summary>
    /// Loads the action map declared in the Project file's <c>[input].actions</c> entry, registers
    /// it for <typeparamref name="TEnum"/>, and returns the polling reader. Game's one-liner at
    /// startup — bindings live in the <c>actions.input</c> file, edited via engine editor/CLI.
    /// </summary>
    /// <example>
    /// <code>
    /// // Project file:
    /// // [input]
    /// // actions = "res://actions.input"
    ///
    /// var actions = InputActions.LoadFromProject&lt;PongAction&gt;(app);
    /// </code>
    /// </example>
    /// <exception cref="InvalidOperationException">No <see cref="IProjectConfig"/> registered, or the file has no <c>[input].actions</c> entry.</exception>
    /// <exception cref="FileNotFoundException">The path resolved from <c>res://</c> does not exist.</exception>
    /// <summary>
    /// DI registration that tells <see cref="Application"/> which game enum to auto-load actions for.
    /// Use <c>services.AddInputActions&lt;PongAction&gt;()</c>; Application loads the file at startup,
    /// game code just calls <see cref="Get{TEnum}"/> from anywhere.
    /// </summary>
    internal interface IAutoLoader { void Load(Application app); }
    internal sealed class AutoLoader<TEnum> : IAutoLoader where TEnum : struct, Enum
    {
        public void Load(Application app) => LoadFromProject<TEnum>(app);
    }

    public static IInputActionReader<TEnum> LoadFromProject<TEnum>(Application app)
        where TEnum : struct, Enum
    {
        var config = app.Services.GetService<IProjectConfig>()
            ?? throw new InvalidOperationException(
                "InputActions.LoadFromProject requires a Project file. Add KernelEngine.Configuration and ensure a Project file is registered.");
        if (!config.IsLoaded)
            throw new InvalidOperationException("Project file is not loaded.");

        var input = config.GetSection("input")
            ?? throw new InvalidOperationException("Project file is missing the [input] section.");

        if (!input.TryGetValue("actions", out var raw) || raw is not string resPath)
            throw new InvalidOperationException("Project file's [input] section is missing 'actions = \"res://...\"'.");

        const string prefix = "res://";
        if (!resPath.StartsWith(prefix, StringComparison.Ordinal))
            throw new InvalidDataException($"[input] actions must start with 'res://'; got '{resPath}'.");

        var absolute = Path.Combine(AppContext.BaseDirectory, resPath[prefix.Length..]);
        if (!File.Exists(absolute))
            throw new FileNotFoundException($"Input actions file not found: {absolute}", absolute);

        var native = CreateBackend?.Invoke()
            ?? throw new InvalidOperationException(
                "No input-actions backend registered. Call services.AddNativeFramework() before LoadFromProject.");
        native.Load(absolute);
        var map = new InputActionMap<TEnum>(native);
        return Register(map);
    }

    /// <summary>Engine-internal: enumerates all registered maps for the per-frame dispatcher.</summary>
    internal static IEnumerable<IInputActionMap> AllMaps => s_maps.Values;
}

internal sealed class InputActionReader<TEnum>(InputActionMap<TEnum> map) : IInputActionReader<TEnum>
    where TEnum : struct, Enum
{
    public bool IsActionDown(TEnum action) => map.IsActionDown(action);
    public bool WasActionPressed(TEnum action) => map.WasActionPressed(action);
    public bool WasActionReleased(TEnum action) => map.WasActionReleased(action);
    public float GetActionAxis1D(TEnum action) => map.GetAxis1D(action);
    public Vector2 GetActionAxis2D(TEnum action) => map.GetAxis2D(action);
    public Vector3 GetActionAxis3D(TEnum action) => map.GetAxis3D(action);
}
