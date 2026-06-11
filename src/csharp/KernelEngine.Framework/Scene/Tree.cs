using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Scene-graph facade matching the legacy Tree API. Game code uses
/// <see cref="AddNode{T}"/> to spawn entities + attach the node's components.
/// Under the hood, every node is an entity in the runtime's flecs world; the
/// Tree just packages spawn + component setup + naming behind one call.
/// </summary>
public sealed class Tree
{
    internal EcsAdapter        Ecs        { get; }
    internal ComponentRegistry Components { get; }

    /// <summary>
    /// Direct access to the renderer for creating GPU resources (textures,
    /// materials, meshes). Setup callbacks run on the render worker, so calls
    /// to <c>tree.Renderer.CreateTexture</c> etc. are safe with respect to
    /// bgfx's thread affinity.
    /// </summary>
    public IRenderer Renderer { get; }

    internal Tree(EcsAdapter ecs, ComponentRegistry components, IRenderer renderer)
    {
        Ecs        = ecs;
        Components = components;
        Renderer   = renderer;
    }

    /// <summary>
    /// Registers a node in the tree: creates an entity, binds the node to it,
    /// and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "") where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a tree.");
        var entity = Ecs.CreateEntity();
        node.Name = name;
        node.BindToTree(this, entity);
        return node;
    }

    // ── Component access helpers (used by Node subclasses) ──────────────────

    internal void SetTransform(ulong entity, in TransformComponent value)
        => Ecs.Add(entity, Components.TransformCid, value);

    internal TransformComponent GetTransform(ulong entity)
        => Ecs.TryGet<TransformComponent>(entity, Components.TransformCid, out var v) ? v : TransformComponent.Identity;

    internal void SetMeshRenderer(ulong entity, in MeshRendererComponent value)
        => Ecs.Add(entity, Components.MeshRendererCid, value);

    internal void SetCamera(ulong entity, in CameraComponent value)
        => Ecs.Add(entity, Components.CameraCid, value);

    internal void SetDirectionalLight(ulong entity, in DirectionalLightComponent value)
        => Ecs.Add(entity, Components.DirectionalLightCid, value);
}
