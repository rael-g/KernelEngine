using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct GpuCapabilities
{
    public uint MaxTextureDimension2d;
    public uint MaxTextureArrayLayers;
    public uint MaxBindGroups;
    public uint MaxVertexAttributes;
    public uint MaxVertexBuffers;
    public uint MaxUniformBufferSize;
    public uint MaxStorageBufferSize;
    public uint MaxComputeWorkgroupSizeX;
    public uint MaxComputeWorkgroupSizeY;
    public uint MaxComputeWorkgroupSizeZ;

    public bool SupportsBindless;

    public bool SupportsMeshShaders;

    public bool SupportsRayTracing;
    public uint CopyBytesPerRowAlignment;
}
