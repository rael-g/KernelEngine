using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderClusterResources
{
    public global::KernelEngine.Ecs.ComponentId Tag;
    public global::KernelEngine.Ecs.ComponentId PointLights;
    public global::KernelEngine.Ecs.ComponentId SpotLights;
    public global::KernelEngine.Ecs.ComponentId PointIndices;
    public global::KernelEngine.Ecs.ComponentId PointCounts;
    public global::KernelEngine.Ecs.ComponentId SpotIndices;
    public global::KernelEngine.Ecs.ComponentId SpotCounts;
    public global::KernelEngine.Ecs.ComponentId Grid;
}
