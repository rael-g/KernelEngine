namespace KernelEngine.Render;

/// <summary>
/// The clip-space convention the active render backend expects matrices in.
/// </summary>
/// <param name="ZeroToOneDepth">true = clip z in [0,1] (Vulkan/D3D); false = [-1,1] (OpenGL).</param>
/// <param name="YFlip">true = projection must flip Y for this backend's framebuffer origin.</param>
public readonly record struct NdcConvention(bool ZeroToOneDepth, bool YFlip)
{
    /// <summary>Depth in zero to one, no Y flip.</summary>
    public static NdcConvention Default => new(ZeroToOneDepth: true, YFlip: false);
}
