namespace KernelEngine.Configuration;

/// <summary>
/// A typed (section, key) to value store. A getter returns the given fallback for a missing key or
/// a value of another type, and never fails.
/// </summary>
public interface IConfiguration
{
    long GetInt(string section, string key, long fallback);
    double GetDouble(string section, string key, double fallback);
    bool GetBool(string section, string key, bool fallback);
    string GetString(string section, string key, string fallback);

    void SetInt(string section, string key, long value);
    void SetDouble(string section, string key, double value);
    void SetBool(string section, string key, bool value);
    void SetString(string section, string key, string value);

    /// <summary>
    /// Reads <paramref name="fallback"/>.Length scalar keys named <c>key_0</c>, <c>key_1</c>, ...
    /// An index that is missing or of another type takes that index's value of
    /// <paramref name="fallback"/>.
    /// </summary>
    float[] GetFloatArray(string section, string key, float[] fallback);

    /// <summary>
    /// Writes <paramref name="values"/> as scalar keys <c>key_0</c>, <c>key_1</c>, ... An array
    /// in a TOML file is skipped when the file is loaded, so a file must author the indexed keys
    /// itself to be read back by <see cref="GetFloatArray"/>.
    /// </summary>
    void SetFloatArray(string section, string key, float[] values);
}
