namespace KernelEngine.Asset.Assimp;

/// <summary>
/// Keeps loader-owned model memory alive for as long as a caller holds it, and gives it
/// back to the loader that produced it on dispose. What the model says about itself is the
/// loader's own bytes, read through <see cref="ModelData"/>; this type adds nothing to that
/// reading and exists only to answer when the bytes are released.
/// </summary>
internal sealed unsafe class Model : IModel
{
    private readonly AssetLoader _loader;
    private ModelData* _native;

    internal Model(AssetLoader loader, ModelData* native)
    {
        _loader = loader;
        _native = native;
    }

    /// <inheritdoc/>
    public ModelData Data => _native is null
        ? throw new ObjectDisposedException(nameof(Model))
        : *_native;

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native is null) return;
        var native = _native;
        _native = null;
        _loader.FreeModel(native);
    }
}
