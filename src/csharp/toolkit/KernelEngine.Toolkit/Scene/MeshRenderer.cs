using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Scene node that renders a mesh with a material. Set <see cref="MeshHandle"/>
/// and <see cref="MaterialHandle"/> via object-initializer syntax before calling
/// <see cref="NodeWorld.AddNode{T}"/>. The material owns the surface appearance
/// (base color + albedo); create it via <see cref="IRenderResources.CreateMaterial"/>.
/// </summary>
public class MeshRenderer : Node
{
    public MeshHandle     MeshHandle     { get; set; }
    public MaterialHandle MaterialHandle { get; set; }

    protected internal override void OnBind(NodeWorld nodeWorld)
    {
        // The legacy bgfx path reads MeshRendererComponent; the v2 forward pass
        // reads the "mesh" MeshComponent. Both are {mesh, material} — writing both
        // lets one node drive either backend (handle values are per active backend;
        // the inactive component is dead data).
        nodeWorld.Set(Entity, new MeshRendererComponent { Mesh = MeshHandle, Material = MaterialHandle });
        nodeWorld.Set(Entity, new MeshComponent { Mesh = MeshHandle, Material = MaterialHandle });
    }
}
