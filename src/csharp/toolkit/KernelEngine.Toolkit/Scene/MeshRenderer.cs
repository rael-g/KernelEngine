using System.Numerics;
using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Scene node that renders a mesh. Set <see cref="MeshHandle"/> plus either a
/// <see cref="MaterialHandle"/> (legacy bgfx path) or a <see cref="Color"/>
/// (v2 forward path) via object-initializer syntax before calling
/// <see cref="NodeWorld.AddNode{T}"/>.
/// </summary>
public class MeshRenderer : Node
{
    public MeshHandle     MeshHandle     { get; set; }
    public MaterialHandle MaterialHandle { get; set; }

    /// <summary>Inline base color the v2 forward pass tints the mesh with.</summary>
    public Vector4 Color { get; set; } = Vector4.One;

    protected internal override void OnBind(NodeWorld nodeWorld)
    {
        // The legacy bgfx path reads MeshRendererComponent (material-based); the
        // v2 forward pass reads the "mesh" MeshComponent (color inline). Writing
        // both lets one node drive either backend — the inactive component is
        // dead data the active backend never reads.
        nodeWorld.Set(Entity, new MeshRendererComponent { Mesh = MeshHandle, Material = MaterialHandle });
        nodeWorld.Set(Entity, new MeshComponent { Mesh = MeshHandle, Material = MaterialHandle, Color = Color });
    }
}
