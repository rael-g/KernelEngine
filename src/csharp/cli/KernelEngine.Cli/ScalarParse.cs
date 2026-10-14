using System.Globalization;

namespace KernelEngine.Cli;

/// <summary>
/// Coerces a raw argument to a TOML scalar. With <see cref="ScalarType.Auto"/> it is the first of
/// bool, long, double and string that the text parses as; any other type forces that reading and
/// throws when the text does not parse.
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
