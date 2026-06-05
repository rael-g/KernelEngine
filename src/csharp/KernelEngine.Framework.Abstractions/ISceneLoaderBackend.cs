namespace KernelEngine.Framework;

/// <summary>
/// Backend contract for the scene loader (TOML parsing + nested-scene resolution + node
/// instantiation through the registered <see cref="INodeTypeRegistry"/>). Sugar layer
/// (<c>SceneLoader</c>) consumes this; the unsafe native wrapper lives in
/// <c>KernelEngine.Framework.Native</c>.
/// </summary>
public interface ISceneLoaderBackend : IDisposable
{
    /// <summary>Loads the scene file at <paramref name="path"/> into the bound world.</summary>
    void Load(string path);
}
