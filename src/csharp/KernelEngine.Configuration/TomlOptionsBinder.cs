using System.Reflection;
using Tomlyn.Model;

namespace KernelEngine.Configuration;

/// <summary>
/// Reflection-based binder that copies values from a <see cref="TomlTable"/> onto an Options POCO.
/// Only public settable properties are considered. TOML keys match POCO properties case-insensitively
/// after stripping underscores (so <c>console_level</c> binds to <c>ConsoleLevel</c>, <c>gravity_x</c>
/// to <c>GravityX</c>). Unknown keys are ignored (forward-compat). Type-mismatched values throw with
/// a clear message identifying the property + the offending value.
///
/// <para>
/// <b>AOT-swap path:</b> this is the dev-build path. A source generator equivalent is planned for
/// AOT/mobile (chapter 16 §2.1, chapter 17 §8 INodeHydrator pattern) — it would emit a specialized
/// binder per <c>TOptions</c> (<c>void Bind(TomlTable section, ConsoleSinkOptions opts)</c> with a
/// hand-written <c>switch</c> on key names) so the runtime carries no reflection. Until that
/// generator exists, this binder is reflection-based; the seam is the static
/// <see cref="Apply{TOptions}"/> method, replaceable wholesale.
/// </para>
/// </summary>
public static class TomlOptionsBinder
{
    public static void Apply<TOptions>(TomlTable section, TOptions opts) where TOptions : class
    {
        var type = typeof(TOptions);
        // Build a name → property index that matches snake_case TOML keys to PascalCase C# names
        // by stripping underscores and lowercasing. So `console_level` finds `ConsoleLevel`,
        // `gravity_x` finds `GravityX`, single-word `width` still finds `Width`.
        var props = type.GetProperties(BindingFlags.Public | BindingFlags.Instance);
        var lookup = new Dictionary<string, PropertyInfo>(StringComparer.Ordinal);
        foreach (var p in props) if (p.CanWrite) lookup[p.Name.Replace("_", "").ToLowerInvariant()] = p;

        foreach (var key in section.Keys)
        {
            if (!lookup.TryGetValue(key.Replace("_", "").ToLowerInvariant(), out var prop)) continue;

            var rawValue = section[key];
            try
            {
                var converted = Convert(rawValue, prop.PropertyType);
                prop.SetValue(opts, converted);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException(
                    $"Could not bind TOML value '{rawValue}' to {type.Name}.{prop.Name} ({prop.PropertyType.Name}): {ex.Message}",
                    ex);
            }
        }
    }

    private static object? Convert(object? raw, Type targetType)
    {
        if (raw is null) return null;
        // Unwrap nullable.
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;

        if (underlying.IsInstanceOfType(raw)) return raw;

        // Tomlyn surfaces integers as long, floats as double, bools as bool, strings as string.
        // Map the common numeric coercions and enums; everything else falls through to Convert.
        if (underlying.IsEnum)
        {
            return raw switch
            {
                string s => Enum.Parse(underlying, s, ignoreCase: true),
                long l => Enum.ToObject(underlying, l),
                _ => Enum.ToObject(underlying, System.Convert.ToInt64(raw)),
            };
        }

        return System.Convert.ChangeType(raw, underlying, System.Globalization.CultureInfo.InvariantCulture);
    }
}
