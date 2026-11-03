using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuBindingType : uint
{
    Buffer,
    Sampler,
    Texture,
    StorageBuffer,
    StorageTexture,
    ReadonlyStorageBuffer,
    DepthTexture,
}
