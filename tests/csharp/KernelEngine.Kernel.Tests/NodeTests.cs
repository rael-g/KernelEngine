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
        var components = new BodyProbe().Components();

        Assert.Contains("body2d", components);
        Assert.Contains("transform2d", components);
        Assert.DoesNotContain("transform", components);
    }

    [Fact]
    public void PlainNode_HasNoTransform()
    {
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
        var probe = new TextProbe();
        var ex = Assert.Throws<ArgumentException>(() => probe.Title = "abcdefgh");
        Assert.Contains("Title", ex.Message);
    }

    [Fact]
    public void SpatialAndPlanarNodesCarryDifferentPoses()
    {
        Assert.Equal(["transform"], new SpatialProbe().Components());
    }
}
