using System.Collections.Generic;
using System.Numerics;
using KernelEngine.Framework;
using Xunit;

namespace EngineTests;

public class NodeTests
{
    [Fact]
    public void Transform_ValueTypeBehavior()
    {
        var t1 = new Transform { Position = new Vector3(1, 0, 0) };
        var t2 = t1;
        t2.Position = new Vector3(2, 0, 0);

        // Transform is a struct (value type), so t1 should be unchanged
        Assert.Equal(1, t1.Position.X);
        Assert.Equal(2, t2.Position.X);
    }

    /// <summary>
    /// Reaches the protected component walk from outside the framework assembly,
    /// which is the only way to ask a node what it is made of without standing up
    /// a native world.
    /// </summary>
    private sealed class BodyProbe : Body2D
    {
        public List<string> Components()
        {
            var into = new List<string>();
            CollectBehaviorComponents(into);
            return into;
        }
    }

    private sealed class NodeProbe : Node
    {
        public List<string> Components()
        {
            var into = new List<string>();
            CollectBehaviorComponents(into);
            return into;
        }
    }

    [Fact]
    public void NodeType_DeclaresItsOwnComponentAndEveryOneItInherits()
    {
        // The scheduler builds a behavior system's access list from this walk, so a
        // component lost here is a system that declares it does not touch memory it
        // writes every tick — a data race the wave builder cannot see.
        var components = new BodyProbe().Components();

        Assert.Contains("body2d", components);
        Assert.Contains("transform", components);
    }

    [Fact]
    public void PlainNode_HasNoTransform()
    {
        // What separates Node from Node3D: a node that is not placed in space
        // carries no transform, and nothing should be attaching one for it.
        Assert.Empty(new NodeProbe().Components());
    }
}
