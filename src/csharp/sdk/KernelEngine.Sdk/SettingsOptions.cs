using System.Diagnostics.CodeAnalysis;
using System.Text;

namespace KernelEngine;

/// <summary>Reads a section of a configuration into the properties of an options object.</summary>
static class SettingsOptions
{
    public static T Read<[DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicProperties | DynamicallyAccessedMemberTypes.PublicParameterlessConstructor)] T>(Configuration.Configuration configuration, string section) where T : class, new()
    {
        var options = new T();
        foreach (var property in typeof(T).GetProperties())
        {
            if (!property.CanWrite || !property.CanRead) continue;
            var key = SnakeCase(property.Name);
            var current = property.GetValue(options);
            object? read = property.PropertyType switch
            {
                var t when t == typeof(string) => configuration.GetString(section, key, (string?)current ?? ""),
                var t when t == typeof(bool) => configuration.GetBool(section, key, (bool)current!),
                var t when t == typeof(int) => (int)configuration.GetInt(section, key, (int)current!),
                var t when t == typeof(long) => configuration.GetInt(section, key, (long)current!),
                var t when t == typeof(float) => (float)configuration.GetDouble(section, key, (float)current!),
                var t when t == typeof(double) => configuration.GetDouble(section, key, (double)current!),
                _ => null,
            };
            if (read is not null) property.SetValue(options, read);
        }
        return options;
    }

    static string SnakeCase(string name)
    {
        var text = new StringBuilder(name.Length + 4);
        for (var i = 0; i < name.Length; i++)
        {
            if (char.IsUpper(name[i]) && i > 0) text.Append('_');
            text.Append(char.ToLowerInvariant(name[i]));
        }
        return text.ToString();
    }
}
