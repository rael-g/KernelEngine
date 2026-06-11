using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Renderable mesh node. <see cref="MeshHandle"/> defaults to handle 0 = bgfx's
/// built-in unit quad; <see cref="MaterialHandle"/> defaults to handle 0 =
/// white. Game code typically sets at least <see cref="MaterialHandle"/>.
/// </summary>
public sealed class MeshRenderer : Node
{
    public MeshHandle     MeshHandle     { get; set; } = default;
    public MaterialHandle MaterialHandle { get; set; } = default;

    protected internal override void OnBind(Tree tree)
    {
        tree.SetMeshRenderer(Entity, new MeshRendererComponent
        {
            Mesh     = MeshHandle,
            Material = MaterialHandle,
        });
    }
}
