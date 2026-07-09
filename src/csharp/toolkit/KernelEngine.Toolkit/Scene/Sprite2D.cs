namespace KernelEngine.Framework;

/// <summary>
/// 2D visual node. Configured entirely from the scene file via
/// <c>[entity.components.Sprite2D]</c>: mesh primitive, base color, and
/// roughness. <see cref="SceneNodesModule"/> registers the apply callback
/// that creates GPU resources and writes <see cref="MeshRendererComponent"/>.
/// </summary>
public class Sprite2D : Node
{
    protected internal override void OnBind(NodeWorld nodeWorld) { }
}
