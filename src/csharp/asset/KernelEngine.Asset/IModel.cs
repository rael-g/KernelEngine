namespace KernelEngine.Asset;

/// <summary>
/// The ownership of a model loaded by an <see cref="IAssetLoader"/>. Disposing returns the
/// decoded mesh, material and texture memory to the loader that produced it. Everything the
/// model says about itself is read through <see cref="Data"/>, which stays valid only until
/// this instance is disposed.
/// </summary>
public interface IModel : IDisposable
{
    /// <summary>The loader-owned data this instance is keeping alive.</summary>
    ModelData Data { get; }
}
