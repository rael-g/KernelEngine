using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuTextureFormat : uint
{
    Invalid = 0,
    Rgba8Unorm,
    Rgba8Srgb,
    Bgra8Unorm,
    Rgba16Float,
    R32Float,
    R16Float,
    D16Unorm,
    D24UnormS8Uint,
    D32Float,
    D32FloatS8Uint,
    Rgba32Float,
    Rg32Float,
    R8Unorm,
    Bc1RgbaUnorm,
    Bc3RgbaUnorm,
    Bc5RgUnorm,
    Bc7RgbaUnorm,
}
