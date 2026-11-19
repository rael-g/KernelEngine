using KernelEngine.Common;
using KernelEngine.Framework.Nodes;
using KernelEngine.Physics;

namespace Pong;

/// <summary>A node carrying <c>transform2d</c>.</summary>
abstract class Node2D : Node
{
    /// <summary>The <c>transform2d</c> of the node a behaviour is visiting.</summary>
    protected ref Transform2DComponent Transform2D => ref Component<Transform2DComponent>("transform2d");

    /// <inheritdoc/>
    protected override IEnumerable<NodeWith> With => [.. base.With, NodeWith.Of("transform2d", EngineNodeTypes.Transform2DNodeInitial)];
}

/// <summary>A node carrying <c>transform2d</c> and <c>body2d</c>.</summary>
abstract class Body2D : Node2D
{
    /// <summary>The <c>body2d</c> of the node a behaviour is visiting.</summary>
    protected ref Body2DComponent Body => ref Component<Body2DComponent>("body2d");

    /// <inheritdoc/>
    protected override IEnumerable<NodeWith> With => [.. base.With, NodeWith.Of("body2d", EngineNodeTypes.Body2DNodeInitial)];
}
