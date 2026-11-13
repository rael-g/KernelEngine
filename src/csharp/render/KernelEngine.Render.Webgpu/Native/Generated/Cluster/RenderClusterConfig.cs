using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct RenderClusterConfig
{
    [NativeTypeName("uint32_t")]
    public uint GridX;

    [NativeTypeName("uint32_t")]
    public uint GridY;

    [NativeTypeName("uint32_t")]
    public uint GridZ;

    [NativeTypeName("uint32_t")]
    public uint MaxLightsPerCluster;
}
