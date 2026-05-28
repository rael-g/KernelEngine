using KernelEngine.Kernel;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Loads an <c>actions.input</c> file (TOML schema) into a strongly-typed
/// <see cref="InputActionMap{TEnum}"/>. Keeps game code free of binding declarations — devs edit
/// bindings via the engine editor/CLI (which mutates this file), the game just reads it at startup.
/// </summary>
/// <remarks>
/// <para>
/// Schema (TOML 1.0):
/// </para>
/// <code>
/// [action.Jump]
/// type = "Button"
/// bindings = [
///     { kind = "key",    key = "Space" },
///     { kind = "mouse",  button = "Left" },
/// ]
///
/// [action.Move]
/// type = "Axis2D"
/// bindings = [
///     { kind = "key_quad", up = "W", down = "S", left = "A", right = "D" },
/// ]
/// </code>
/// <para>
/// Action names map to <typeparamref name="TEnum"/> values by <see cref="EnumNameResolver{TEnum}"/>
/// (case-sensitive). Unknown action names and unknown binding kinds throw with a human-readable
/// list of valid options. Enum values declared in <typeparamref name="TEnum"/> but missing from
/// the file are allowed — they exist as actions but stay inactive (no binding ever fires them).
/// </para>
/// </remarks>
public static class InputActionsLoader
{
    /// <summary>
    /// Reads the file at <paramref name="absolutePath"/> and returns a populated map.
    /// Does not register; caller passes the map to <see cref="InputActions.Register"/>.
    /// </summary>
    public static InputActionMap<TEnum> LoadFromFile<TEnum>(string absolutePath)
        where TEnum : struct, Enum
    {
        if (!File.Exists(absolutePath))
            throw new FileNotFoundException($"Input actions file not found: {absolutePath}");

        return LoadFromToml<TEnum>(File.ReadAllText(absolutePath), absolutePath);
    }

    /// <summary>
    /// Parses TOML text directly (useful for tests). <paramref name="origin"/> is included in
    /// error messages so the user can locate the offending file.
    /// </summary>
    public static InputActionMap<TEnum> LoadFromToml<TEnum>(string toml, string origin = "<inline>")
        where TEnum : struct, Enum
    {
        var doc = Toml.ToModel(toml);
        var map = new InputActionMap<TEnum>();

        if (!doc.TryGetValue("action", out var rawActions) || rawActions is not TomlTable actions)
            return map; // empty file is valid — game can run with no bindings.

        foreach (var (rawName, rawEntry) in actions)
        {
            if (rawEntry is not TomlTable entry)
                throw new InvalidDataException($"{origin}: [action.{rawName}] is not a table.");

            TEnum actionValue;
            try
            {
                actionValue = EnumNameResolver<TEnum>.Parse(rawName);
            }
            catch (ArgumentException ex)
            {
                throw new InvalidDataException($"{origin}: {ex.Message}", ex);
            }

            var typeStr = GetString(entry, "type") ?? throw new InvalidDataException(
                $"{origin}: [action.{rawName}] missing 'type' (one of Button, Axis1D, Axis2D, Axis3D).");
            if (!Enum.TryParse<ActionType>(typeStr, ignoreCase: false, out var actionType))
                throw new InvalidDataException(
                    $"{origin}: [action.{rawName}] type '{typeStr}' is not a known ActionType (Button, Axis1D, Axis2D, Axis3D).");

            var builder = map.AddAction(actionValue, actionType);

            if (!entry.TryGetValue("bindings", out var rawBindings)) continue;
            if (rawBindings is not TomlArray bindingsArray)
                throw new InvalidDataException($"{origin}: [action.{rawName}].bindings must be an array.");

            foreach (var rawBinding in bindingsArray)
            {
                if (rawBinding is not TomlTable b)
                    throw new InvalidDataException($"{origin}: [action.{rawName}] binding entry must be a table.");
                builder.AddBinding(BuildBinding(b, origin, rawName));
            }
        }

        return map;
    }

    // ── Binding factory ──────────────────────────────────────────────────────

    private static InputBinding BuildBinding(TomlTable b, string origin, string actionName)
    {
        var kind = GetString(b, "kind") ?? throw new InvalidDataException(
            $"{origin}: binding for [action.{actionName}] missing 'kind' (one of: key, mouse, key_pair, key_quad).");

        return kind switch
        {
            "key"      => new KeyBinding(ParseKey(b, "key", origin, actionName)),
            "mouse"    => new MouseButtonBinding(ParseMouseButton(b, "button", origin, actionName)),
            "key_pair" => new KeyPairAxis1DBinding(
                            ParseKey(b, "negative", origin, actionName),
                            ParseKey(b, "positive", origin, actionName)),
            "key_quad" => new KeyQuadAxis2DBinding(
                            up:    ParseKey(b, "up",    origin, actionName),
                            down:  ParseKey(b, "down",  origin, actionName),
                            left:  ParseKey(b, "left",  origin, actionName),
                            right: ParseKey(b, "right", origin, actionName)),
            _ => throw new InvalidDataException(
                $"{origin}: binding for [action.{actionName}] has unknown kind '{kind}' (valid: key, mouse, key_pair, key_quad).")
        };
    }

    private static Key ParseKey(TomlTable b, string field, string origin, string actionName)
    {
        var s = GetString(b, field) ?? throw new InvalidDataException(
            $"{origin}: binding for [action.{actionName}] missing '{field}'.");
        if (!Enum.TryParse<Key>(s, ignoreCase: false, out var k))
            throw new InvalidDataException(
                $"{origin}: binding for [action.{actionName}] field '{field}' value '{s}' is not a known Key.");
        return k;
    }

    private static MouseButton ParseMouseButton(TomlTable b, string field, string origin, string actionName)
    {
        var s = GetString(b, field) ?? throw new InvalidDataException(
            $"{origin}: binding for [action.{actionName}] missing '{field}'.");
        if (!Enum.TryParse<MouseButton>(s, ignoreCase: false, out var btn))
            throw new InvalidDataException(
                $"{origin}: binding for [action.{actionName}] field '{field}' value '{s}' is not a known MouseButton.");
        return btn;
    }

    private static string? GetString(TomlTable t, string key)
        => t.TryGetValue(key, out var v) ? v as string : null;
}
