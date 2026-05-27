using System.Reflection;
using Tomlyn.Model;

namespace KernelEngine.Configuration;

/// <summary>
/// Reflection-based binder that copies values from a <see cref="TomlTable"/> onto an Options POCO.
/// Only public settable properties are considered. Unknown keys are ignored (forward-compat).
/// Type-mismatched values throw with a clear message identifying the property + the offending value.
///
/// <para>
/// This is the dev-build path. A source-generator equivalent is planned for AOT/mobile (chapter 16
/// §2.1, chapter 17 §8 INodeHydrator pattern). Until that exists, the binder is reflection-based.
/// </para>
/// </summary>
internal static class TomlOptionsBinder
{
    public static void Apply<TOptions>(TomlTable section, TOptions opts) where TOptions : class
    {
        var type = typeof(TOptions);
        foreach (var key in section.Keys)
        {
            var prop = type.GetProperty(key, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (prop is null || !prop.CanWrite) continue;

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
