namespace KernelEngine.Render;

/// <summary>
/// Exposes the raw native render-core pointer (untyped — the C ABI passes it
/// opaquely to sibling plugins that never dereference its vtable directly, e.g.
/// the framework's asset-resolver cached-load calls). Implemented by render
/// backends (e.g. WebgpuRenderModule) so callers can reach it without depending
/// on a specific render backend's own generated binding.
/// </summary>
public unsafe interface INativeRenderResources
{
    void* Native { get; }
}
