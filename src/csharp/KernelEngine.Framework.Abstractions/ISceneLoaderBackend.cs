namespace KernelEngine.Framework;

/// <summary>
/// Backend contract for the scene loader (TOML parsing + nested-scene resolution +
/// component-driven entity construction with per-language script factories). Sugar layer
/// (<c>SceneLoader</c>) consumes this; the unsafe native wrapper lives in
/// <c>KernelEngine.Framework.Native</c>.
/// </summary>
public interface ISceneLoaderBackend : IDisposable
{
    /// <summary>Loads the scene file at <paramref name="path"/> into the bound world.</summary>
    void Load(string path);

    /// <summary>
    /// Registers a script factory for entities that use
    /// <c>[entity.script] language = "<paramref name="language"/>"</c>. The loader invokes
    /// <paramref name="factory"/> with the freshly-created entity and the requested type name;
    /// the binding instantiates the wrapper (e.g. C# <c>Tree.WrapEntity</c>) and returns true
    /// on success. Replaces any previous factory for the same language.
    /// </summary>
    void RegisterScriptLanguage(string language, Func<ulong, string, bool> factory);
}
