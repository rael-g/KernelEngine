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

/// <summary>
/// A node whose behavior only reads one of its properties and writes the other, so
/// what it declares to the scheduler can be told apart from what it merely carries.
/// </summary>
public sealed partial class AccessProbe : Node
{
    public partial float ReadOnlyValue { get; }

    public partial float WrittenValue { get; set; }

    void Update(in View view) { }

    public List<NodeComponentUse> Uses()
    {
        var into = new List<NodeComponentUse>();
        CollectBehaviorComponents(into);
        return into;
    }
}

/// <summary>
/// A node whose behavior only reads what it carries, which is what the scheduler
/// needs told apart from writing: two readers of one component may share a wave.
/// </summary>
public sealed partial class ReadOnlyProbe : Node
{
    public partial float Observed { get; }

    void Update(in View view) { }

    public List<NodeComponentUse> Uses()
    {
        var into = new List<NodeComponentUse>();
        CollectBehaviorComponents(into);
        return into;
    }
}

/// <summary>
/// A node whose two hooks reach its transform differently: the update writes the position, the
/// fixed update only reads the scale through a helper of its own.
/// </summary>
public partial class HookProbe : Node3D
{
    void Update(in View view) => Position = Vector3.One;

    void FixedUpdate(in View view) => Inspect();

    private float Inspect() => Scale.X;

    public List<NodeComponentUse>? Uses(bool fixedStep)
    {
        var into = new List<NodeComponentUse>();
        return CollectHookComponents(into, fixedStep) ? into : null;
    }
}

/// <summary>
/// A subclass that cannot be generated for, so the hook access read on its base may not be its own.
/// </summary>
public sealed class HookProbeSubclass : HookProbe;

/// <summary>
/// A node whose update reads the position of a node it borrows and whose fixed update calls a
/// method on it, which the generator cannot read.
/// </summary>
public sealed partial class BorrowingProbe : Node3D
{
    void Update(in View view, Descendant<Node3D> target) => _ = target.Value.Position.X;

    void FixedUpdate(in View view, Descendant<Node3D> target) => target.Node?.GetHashCode();

    public List<NodeComponentUse>? Uses(bool fixedStep)
    {
        var into = new List<NodeComponentUse>();
        return CollectHookComponents(into, fixedStep) ? into : null;
    }
}

/// <summary>
/// A node whose update configures a node it creates, which is not in the world before the wave ends.
/// </summary>
public sealed partial class CreatingProbe : Node3D
{
    void Update(in View view)
    {
        var made = new Node3D { Position = Vector3.One };
        made.Scale = Vector3.One;
    }

    public List<NodeComponentUse>? Uses()
    {
        var into = new List<NodeComponentUse>();
        return CollectHookComponents(into, fixedStep: false) ? into : null;
    }
}

/// <summary>
/// A node whose update hands itself to code the generator does not read.
/// </summary>
public sealed partial class EscapingProbe : Node3D
{
    void Update(in View view) => Helper.Touch(this);

    public bool Known()
    {
        var into = new List<NodeComponentUse>();
        return CollectHookComponents(into, fixedStep: false);
    }
}

static class Helper
{
    public static void Touch(Node3D node) => node.Position = Vector3.Zero;
}

/// <summary>
/// A node built only through a constructor that takes an argument, as one depending on a
/// service is.
/// </summary>
public sealed partial class ConstructedProbe : Node2D
{
    public ConstructedProbe(float rotation) => Rotation = rotation;
}

/// <summary>
/// A node that only has fixed-step behavior.
/// </summary>
public sealed partial class FixedProbe : Node
{
    public partial float Speed { get; set; }

    void FixedUpdate(in View view) { }

    public (bool PerFrame, bool FixedStep) Hooks() => (HasBehavior, HasFixedBehavior);
}

public class NodeTests
{
    [Fact]
    public void A_node_declaring_only_FixedUpdate_has_fixed_step_behavior_and_no_per_frame_behavior()
    {
        Assert.Equal((false, true), new FixedProbe().Hooks());
    }

    [Fact]
    public void A_node_built_through_its_own_constructor_starts_from_its_component_defaults()
    {
        var node = new ConstructedProbe(0.5f);
        Assert.Equal(Vector2.One, node.Scale);
        Assert.Equal(0.5f, node.Rotation);
    }

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
            var into = new List<KernelEngine.Framework.NodeComponentUse>();
            CollectBehaviorComponents(into);
            return into.ConvertAll(u => u.Name);
        }
    }

    private sealed class NodeProbe : Node
    {
        public List<string> Components()
        {
            var into = new List<KernelEngine.Framework.NodeComponentUse>();
            CollectBehaviorComponents(into);
            return into.ConvertAll(u => u.Name);
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
            var into = new List<KernelEngine.Framework.NodeComponentUse>();
            CollectBehaviorComponents(into);
            return into.ConvertAll(u => u.Name);
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

    [Fact]
    public void ComponentWithASettableProperty_IsDeclaredAsWritten()
    {
        var uses = new AccessProbe().Uses();

        Assert.Contains(uses, u => u.Writes);
    }

    [Fact]
    public void ComponentWhoseEveryPropertyIsReadOnly_IsNotDeclaredAsWritten()
    {
        var uses = new ReadOnlyProbe().Uses();

        Assert.NotEmpty(uses);
        Assert.All(uses, u => Assert.False(u.Writes));
    }

    [Fact]
    public void A_hook_declares_only_what_its_body_reaches_and_how()
    {
        var probe = new HookProbe();

        var update = Assert.Single(probe.Uses(fixedStep: false)!);
        Assert.Equal(("transform", true, true), (update.Name, update.Writes, update.Owned));
        var fixedStep = Assert.Single(probe.Uses(fixedStep: true)!);
        Assert.Equal(("transform", false), (fixedStep.Name, fixedStep.Writes));
    }

    [Fact]
    public void A_subclass_the_generator_did_not_read_does_not_take_its_base_hook_access()
    {
        Assert.Null(new HookProbeSubclass().Uses(fixedStep: false));
    }

    [Fact]
    public void A_hook_that_hands_its_node_away_leaves_its_access_unknown()
    {
        Assert.False(new EscapingProbe().Known());
    }

    [Fact]
    public void A_borrowed_node_property_is_declared_as_reached_and_only_as_read()
    {
        var use = Assert.Single(new BorrowingProbe().Uses(fixedStep: false)!);
        Assert.Equal(("transform", false, false), (use.Name, use.Writes, use.Owned));
    }

    [Fact]
    public void A_method_called_on_a_borrowed_node_declares_every_component_of_its_type_as_written()
    {
        var use = Assert.Single(new BorrowingProbe().Uses(fixedStep: true)!);
        Assert.Equal(("transform", true, false), (use.Name, use.Writes, use.Owned));
    }

    [Fact]
    public void A_node_the_hook_creates_is_not_declared()
    {
        Assert.Empty(new CreatingProbe().Uses()!);
    }
}
