using System.Text;
using KernelEngine.Common.Native;
using ConfigNative = KernelEngine.Configuration.Native.NativeMethods;

namespace KernelEngine.Configuration;

/// <summary>
/// Owns a native <c>ke_configuration</c> store. Created empty; <see cref="LoadToml"/>
/// populates it from a Project file (missing file is not an error — every getter's
/// fallback then applies, per the native contract's doctrine).
/// </summary>
public sealed unsafe class Configuration : IConfiguration, IDisposable
{
    private KernelEngine.Configuration.Native.ke_configuration* _native;
    private readonly delegate* unmanaged[Cdecl]<KernelEngine.Configuration.Native.ke_configuration*, void> _destroy;

    public Configuration()
    {
        ke_error* err = null;
        var handle = ConfigNative.configuration_create(&err);
        if (handle.@ref == null) throw KernelError.FromNative(err, "configuration_create");
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    /// <summary>Reads <paramref name="path"/> into the store. A missing file is a no-op.</summary>
    public void LoadToml(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + '\0');
        fixed (byte* p = bytes)
        {
            ke_error* err = null;
            if (!ConfigNative.configuration_toml_load(_native, (sbyte*)p, &err))
                throw KernelError.FromNative(err, "configuration_toml_load");
        }
    }

    public long GetInt(string section, string key, long fallback)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
            return _native->get_int(_native, (sbyte*)sp, (sbyte*)kp, fallback);
    }

    public double GetDouble(string section, string key, double fallback)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
            return _native->get_double(_native, (sbyte*)sp, (sbyte*)kp, fallback);
    }

    public bool GetBool(string section, string key, bool fallback)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
            return _native->get_bool(_native, (sbyte*)sp, (sbyte*)kp, fallback);
    }

    public string GetString(string section, string key, string fallback)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        var f = Ansi(fallback);
        fixed (byte* sp = s, kp = k, fp = f)
        {
            var result = _native->get_string(_native, (sbyte*)sp, (sbyte*)kp, (sbyte*)fp);
            return System.Runtime.InteropServices.Marshal.PtrToStringAnsi((nint)result) ?? fallback;
        }
    }

    public void SetInt(string section, string key, long value)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
        {
            ke_error* err = null;
            if (!_native->set_int(_native, (sbyte*)sp, (sbyte*)kp, value, &err))
                throw KernelError.FromNative(err, "configuration set_int");
        }
    }

    public void SetDouble(string section, string key, double value)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
        {
            ke_error* err = null;
            if (!_native->set_double(_native, (sbyte*)sp, (sbyte*)kp, value, &err))
                throw KernelError.FromNative(err, "configuration set_double");
        }
    }

    public void SetBool(string section, string key, bool value)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        fixed (byte* sp = s, kp = k)
        {
            ke_error* err = null;
            if (!_native->set_bool(_native, (sbyte*)sp, (sbyte*)kp, value, &err))
                throw KernelError.FromNative(err, "configuration set_bool");
        }
    }

    public void SetString(string section, string key, string value)
    {
        var s = Ansi(section);
        var k = Ansi(key);
        var v = Ansi(value);
        fixed (byte* sp = s, kp = k, vp = v)
        {
            ke_error* err = null;
            if (!_native->set_string(_native, (sbyte*)sp, (sbyte*)kp, (sbyte*)vp, &err))
                throw KernelError.FromNative(err, "configuration set_string");
        }
    }

    public float[] GetFloatArray(string section, string key, float[] fallback)
    {
        var result = new float[fallback.Length];
        for (int i = 0; i < fallback.Length; i++)
            result[i] = (float)GetDouble(section, $"{key}_{i}", fallback[i]);
        return result;
    }

    public void SetFloatArray(string section, string key, float[] values)
    {
        for (int i = 0; i < values.Length; i++)
            SetDouble(section, $"{key}_{i}", values[i]);
    }

    private static byte[] Ansi(string s) => Encoding.ASCII.GetBytes(s + '\0');

    public void Dispose()
    {
        if (_native != null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
