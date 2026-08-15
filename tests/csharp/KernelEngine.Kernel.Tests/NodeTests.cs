using System;
using System.Collections.Generic;
using System.Numerics;
using KernelEngine.Framework;
using Xunit;

namespace EngineTests;

/// <summary>
/// A node whose text property declares how much it holds. The capacity is part of the
/// component's ABI, so it is the node's to state and the engine's to enforce.
/// </summary>
public sealed partial class TextProbe : Node
{
    [NodeText(8)]
    public partial string Title { get; set; }
}

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
        Assert.Contains("transform2d", components);
        // A body is placed in a plane, so nothing must be attaching it the three
        // dimensional pose as well: two authored poses on one entity is a graph the
        // hierarchy would have to pick between.
        Assert.DoesNotContain("transform", components);
    }

    [Fact]
    public void PlainNode_HasNoTransform()
    {
        // What separates Node from Node3D: a node that is not placed in space
        // carries no transform, and nothing should be attaching one for it.
        Assert.Empty(new NodeProbe().Components());
    }

    private sealed class SpatialProbe : Node3D
    {
        public List<string> Components()
        {
            var into = new List<string>();
            CollectBehaviorComponents(into);
            return into;
        }
    }

    [Fact]
    public void TextThatFitsRoundTrips()
    {
        var probe = new TextProbe { Title = "abcdefg" };
        Assert.Equal("abcdefg", probe.Title);
    }

    [Fact]
    public void TextTooLongIsRefused_NotTruncated()
    {
        // Truncating would store a path that opens nothing, and the failure would
        // surface far from the assignment that caused it.
        var probe = new TextProbe();
        var ex = Assert.Throws<ArgumentException>(() => probe.Title = "abcdefgh");
        Assert.Contains("Title", ex.Message);
    }

    [Fact]
    public void SpatialAndPlanarNodesCarryDifferentPoses()
    {
        // The whole point of the split: neither node type can be handed the other's
        // pose, so a 2D node never receives a quaternion and a 3D one never a depth.
        Assert.Equal(["transform"], new SpatialProbe().Components());
    }
}
