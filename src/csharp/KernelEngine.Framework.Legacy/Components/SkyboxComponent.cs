using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// ECS component holding the active skybox cubemap handle.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct SkyboxComponent
{
    /// <summary>GPU cubemap handle. Use <see cref="TextureHandle.None"/> to disable rendering this skybox.</summary>
    public TextureHandle CubemapHandle;
}
