namespace KernelEngine.Kernel;

/// <summary>
/// The clip-space (NDC) convention the active render backend expects matrices in. The engine's
/// matrix builders read this so projections are correct per backend (Vulkan/D3D vs OpenGL, etc.).
/// </summary>
/// <param name="ZeroToOneDepth">true = clip z in [0,1] (Vulkan/D3D); false = [-1,1] (OpenGL).</param>
/// <param name="YFlip">true = projection must flip Y for this backend's framebuffer origin.</param>
/// <param name="LeftHanded">true = left-handed clip space.</param>
public readonly record struct NdcConvention(bool ZeroToOneDepth, bool YFlip, bool LeftHanded)
{
    /// <summary>The engine's historical default (Vulkan-style): depth [0,1], right-handed, no Y flip.</summary>
    public static NdcConvention Default => new(ZeroToOneDepth: true, YFlip: false, LeftHanded: false);
}
