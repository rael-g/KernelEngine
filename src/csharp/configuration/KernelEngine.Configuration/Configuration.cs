using System.Text;

using KernelEngine.Common;
using KernelEngine.Configuration.Native;

using ConfigNative = KernelEngine.Configuration.Native.NativeMethods;

namespace KernelEngine.Configuration;

public unsafe partial class Configuration
{
    /// <summary>Creates an empty store.</summary>
    public Configuration() : this(Create())
    {
    }

    private static ke_configuration_handle Create()
    {
        ke_configuration_handle handle;
        NativeResults.ThrowIfFailed(ConfigNative.configuration_create(&handle), "ke_configuration_create");
        return handle;
    }

    /// <summary>Reads <paramref name="path"/> into the store through <paramref name="io"/>. A missing file is a no-op.</summary>
    public void LoadToml(KernelEngine.Io.INativeIo io, string path)
    {
        ke_configuration_source_handle source;
        NativeResults.ThrowIfFailed(ConfigNative.configuration_toml_create(io.Native, &source), "ke_configuration_toml_create");
        try
        {
            var bytes = Encoding.UTF8.GetBytes(path + '\0');
            fixed (byte* p = bytes)
            {
                NativeResults.ThrowIfFailed(source.@ref->load(source.@ref, Handle, (sbyte*)p), "load");
            }
        }
        finally
        {
            source.destroy(source.@ref);
        }
    }
}

/// <summary>Float arrays stored as indexed scalar keys.</summary>
public static class ConfigurationArrays
{
    /// <summary>
    /// Reads <paramref name="fallback"/>.Length scalar keys named <c>key_0</c>, <c>key_1</c>, ...
    /// An index that is missing or of another type takes that index's value of
    /// <paramref name="fallback"/>.
    /// </summary>
    public static float[] GetFloatArray(this IConfiguration configuration, string section, string key, float[] fallback)
    {
        var result = new float[fallback.Length];
        for (int i = 0; i < fallback.Length; i++)
            result[i] = (float)configuration.GetDouble(section, $"{key}_{i}", fallback[i]);
        return result;
    }

    /// <summary>
    /// Writes <paramref name="values"/> as scalar keys <c>key_0</c>, <c>key_1</c>, ... An array
    /// in a TOML file is skipped when the file is loaded, so a file must author the indexed keys
    /// itself to be read back by <see cref="GetFloatArray"/>.
    /// </summary>
    public static void SetFloatArray(this IConfiguration configuration, string section, string key, float[] values)
    {
        for (int i = 0; i < values.Length; i++)
            configuration.SetDouble(section, $"{key}_{i}", values[i]);
    }
}
