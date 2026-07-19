using KernelEngine.Render;

namespace KernelEngine.Framework;

// Everything the render core itself reads — camera, mesh, the three light
// kinds, ambient and skybox — is render-layer vocabulary mirroring the kernel's
// render/components.h, and lives in KernelEngine.Render.Abstractions so that
// raw-ECS games can express it without taking a framework dependency. Consume
// those through `using KernelEngine.Render`.

// Framework component vocabulary — POD structs stored in the ECS. Node
// subclasses write into these during OnBind; contributors read them each frame.

/// <summary>Renderable mesh + material pair on an entity.</summary>
public struct MeshRendererComponent
{
    public MeshHandle     Mesh;
    public MaterialHandle Material;
}
