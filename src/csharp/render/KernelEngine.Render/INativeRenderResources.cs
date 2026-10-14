namespace KernelEngine.Render;

/// <summary>
/// Exposes the render service pointer, untyped, so a native call that crosses into another plugin
/// can pass it on without a reference to the backend's own binding.
/// </summary>
public unsafe interface INativeRenderResources
{
    /// <summary>The render service pointer; it stays valid until the backend unloads.</summary>
    void* Native { get; }
}
