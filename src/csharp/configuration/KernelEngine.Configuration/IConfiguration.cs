namespace KernelEngine.Configuration;

/// <summary>
/// Thin wrapper over the native <c>ke_configuration</c> store: a format-agnostic,
/// typed (section, key) -&gt; value settings store. A missing key or a type
/// mismatch returns the given fallback — never an error, per the native
/// contract's own doctrine.
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
    /// — the store itself has no array type (see <see cref="SetFloatArray"/>). Any index
    /// missing or type-mismatched falls back to that index's <paramref name="fallback"/> value,
    /// same as a scalar get.
    /// </summary>
    float[] GetFloatArray(string section, string key, float[] fallback);

    /// <summary>
    /// Writes <paramref name="values"/> as scalar keys <c>key_0</c>, <c>key_1</c>, ... A native
    /// TOML-authored array is NOT readable this way — <c>ke_configuration_toml</c> skips array
    /// values entirely when loading a file, so a config file wanting this shape must author the
    /// indexed keys directly. This method only round-trips values set at runtime.
    /// </summary>
    void SetFloatArray(string section, string key, float[] values);
}
