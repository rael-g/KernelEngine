using System.Globalization;

namespace KernelEngine.Cli;

/// <summary>
/// Coerces a raw CLI argv string to the most-specific TOML scalar it can be: bool > long > double >
/// string. <c>--type</c> flag overrides the heuristic when the user wants to force "true" or "42"
/// to land as a string (rare but real — file paths starting with a digit, version strings, etc.).
/// </summary>
public static class ScalarParse
{
    public enum ScalarType { Auto, String, Int, Float, Bool }

    public static object Parse(string raw, ScalarType type)
    {
        return type switch
        {
            ScalarType.String => raw,
            ScalarType.Bool   => ParseBool(raw),
            ScalarType.Int    => long.Parse(raw, CultureInfo.InvariantCulture),
            ScalarType.Float  => double.Parse(raw, CultureInfo.InvariantCulture),
            _                 => Auto(raw),
        };
    }

    private static object Auto(string raw)
    {
        if (raw.Equals("true",  StringComparison.OrdinalIgnoreCase)) return true;
        if (raw.Equals("false", StringComparison.OrdinalIgnoreCase)) return false;
        if (long.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var i)) return i;
        if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return d;
        return raw;
    }

    private static bool ParseBool(string raw) =>
        raw.Equals("true", StringComparison.OrdinalIgnoreCase)
            ? true
            : raw.Equals("false", StringComparison.OrdinalIgnoreCase)
                ? false
                : throw new FormatException($"'{raw}' is not a valid bool (expected 'true' or 'false').");
}
