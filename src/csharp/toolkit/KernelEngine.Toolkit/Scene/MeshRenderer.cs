using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Scene node that renders a mesh with a material. Set <see cref="MeshHandle"/>
/// and <see cref="MaterialHandle"/> via object-initializer syntax before
/// calling <see cref="Tree.AddNode"/>.
/// </summary>
public class MeshRenderer : Node
{
    public MeshHandle     MeshHandle     { get; set; }
    public MaterialHandle MaterialHandle { get; set; }

    protected internal override void OnBind(NodeWorld nodeWorld)
        => nodeWorld.Set(Entity, new MeshRendererComponent { Mesh = MeshHandle, Material = MaterialHandle });
}
