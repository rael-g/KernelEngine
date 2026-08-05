using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// Base class for nodes with a 3D world-space transform — meshes, lights, cameras.
/// The transform component itself is attached natively by every entity <see cref="NodeWorld"/>
/// creates; this class only provides managed access to it.
/// </summary>
public class Node3D : Node
{
    private TransformComponent _transform = TransformComponent.Identity;

    public TransformComponent LocalTransform
    {
        get
        {
            if (!IsBound) return _transform;
            return NodeWorld!.TryGet<TransformComponent>(Entity, out var v) ? v : TransformComponent.Identity;
        }
        set
        {
            _transform = value;
            if (IsBound) NodeWorld!.Set(Entity, value);
        }
    }

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.Set(Entity, _transform);

    /// <summary>
    /// Called by <see cref="NodeWorld.BindNativeEntity"/> before the entity is bound so
    /// that the native scene loader's pre-applied transform is reflected in
    /// <see cref="LocalTransform"/> when <see cref="Node.OnBind"/> runs.
    /// </summary>
    internal void SetInitialTransform(TransformComponent tc) => _transform = tc;
}
