using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderGbufferResources
{
    public global::KernelEngine.Ecs.ComponentId Albedo;
    public global::KernelEngine.Ecs.ComponentId Normal;
    public global::KernelEngine.Ecs.ComponentId Emissive;
}
