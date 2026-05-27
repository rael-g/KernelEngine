using Tomlyn.Model;

namespace KernelEngine.Configuration;

/// <summary>
/// Read-only access to a parsed Project.toml. Singleton, registered by
/// <see cref="ServiceCollectionExtensions.AddProjectConfig"/> and consumed
/// by plugins to hydrate their Options POCOs.
///
/// <para>
/// Missing file or missing section return <c>null</c> — callers fall back
/// to their POCO defaults (chapter 16 §2.4).
/// </para>
/// </summary>
public interface IProjectConfig
{
    /// <summary>
    /// True when a Project.toml was loaded; false when none was found and
    /// every consumer is operating on POCO defaults.
    /// </summary>
    bool IsLoaded { get; }

    /// <summary>
    /// Returns the table at the given dotted path (e.g. <c>"runtime.window"</c>),
    /// or <c>null</c> if the section is missing.
    /// </summary>
    TomlTable? GetSection(string path);
}
