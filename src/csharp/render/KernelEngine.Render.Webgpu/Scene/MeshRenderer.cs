using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Scene node that renders a mesh with a material. Set <see cref="MeshHandle"/>
/// and <see cref="MaterialHandle"/> via object-initializer syntax before calling
/// <see cref="NodeWorld.AddNode{T}"/>. The material owns the surface appearance
/// (base color + albedo); create it via <see cref="IRenderResources.CreateMaterial"/>.
/// </summary>
public class MeshRenderer : Node3D
{
    public MeshHandle     MeshHandle     { get; set; }
    public MaterialHandle MaterialHandle { get; set; }

    protected override void OnBind(NodeWorld nodeWorld)
        => nodeWorld.Set(Entity, new MeshComponent { Mesh = MeshHandle, Material = MaterialHandle });
}
