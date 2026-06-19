namespace KernelEngine.Kernel;

/// <summary>
/// Loads 3D models from disk into an <see cref="IModel"/> the engine can upload to the GPU.
/// Concrete implementations live in format plugins (e.g. <c>KernelEngine.Asset.Assimp</c>).
/// </summary>
public interface IAssetLoader : IDisposable
{
    /// <summary>Loads a model synchronously. Caller disposes the returned <see cref="IModel"/>.</summary>
    IModel LoadModel(string path);

    /// <summary>
    /// Loads a model asynchronously on the engine's task scheduler.
    /// Caller disposes the returned <see cref="IModel"/>.
    /// </summary>
    Task<IModel> LoadModelAsync(string path);
}
