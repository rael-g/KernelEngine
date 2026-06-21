using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Lazily creates and caches built-in mesh primitives by name.
/// Shared across all <c>Sprite2D</c> instances so each primitive is uploaded
/// to the GPU only once. Must be accessed from the render worker.
/// </summary>
public sealed class PrimitiveCache
{
    private readonly IRenderer _renderer;
    private readonly Dictionary<string, MeshHandle> _cache = new(StringComparer.OrdinalIgnoreCase);

    public PrimitiveCache(IRenderer renderer) => _renderer = renderer;

    /// <summary>
    /// Returns the mesh handle for the named primitive, creating it on first call.
    /// Supported names: <c>"quad"</c>.
    /// </summary>
    public MeshHandle Get(string name)
    {
        if (_cache.TryGetValue(name, out var h)) return h;
        h = name.ToLowerInvariant() switch
        {
            "quad" => MeshPrimitives.Quad(_renderer),
            _      => throw new ArgumentException($"Unknown primitive '{name}'."),
        };
        _cache[name] = h;
        return h;
    }
}
