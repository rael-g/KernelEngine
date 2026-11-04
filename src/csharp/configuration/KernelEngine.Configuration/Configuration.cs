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
