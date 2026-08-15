using System;
using KernelEngine.Framework;
using Xunit;

namespace Sports.Soccer
{
    public sealed class Ball : Node;
}

namespace Sports.Volley
{
    public sealed class Ball : Node;
}

namespace EngineTests
{

public class NodeTypeRegistryTests
{
    [Fact]
    public void QualifiedNameIsTheTypeNameInTheSpellingASceneUses()
    {
        // One convention in the file: components are snake_case, so a node type
        // beside them is too. The engine normalizes rather than asking the author
        // to remember which of the two a given line wants.
        Assert.Equal("pong.menu_controller", NodeTypeRegistry.Normalize("Pong.MenuController"));
        Assert.Equal("sprite2d", NodeTypeRegistry.Normalize("Sprite2D"));
        Assert.Equal("ui_root", NodeTypeRegistry.Normalize("UIRoot"));
    }

    [Fact]
    public void ASceneMayWriteTheNameInEitherCase()
    {
        var registry = new NodeTypeRegistry().Register<Sports.Soccer.Ball>();
        Assert.Equal(typeof(Sports.Soccer.Ball), registry.Resolve("sports.soccer.ball"));
        Assert.Equal(typeof(Sports.Soccer.Ball), registry.Resolve("Sports.Soccer.Ball"));
    }

    [Fact]
    public void ShortNameWorksWhileOneTypeAnswersToIt()
    {
        var registry = new NodeTypeRegistry().Register<Sports.Soccer.Ball>();
        Assert.Equal(typeof(Sports.Soccer.Ball), registry.Resolve("ball"));
    }

    [Fact]
    public void TwoTypesSharingAShortNameFailAtUse_NamingBoth()
    {
        // Registering both is legitimate — the qualified name tells them apart — so
        // the failure belongs to whoever writes the ambiguous one, not to startup.
        var registry = new NodeTypeRegistry()
            .Register<Sports.Soccer.Ball>()
            .Register<Sports.Volley.Ball>();

        Assert.Equal(typeof(Sports.Soccer.Ball), registry.Resolve("sports.soccer.ball"));
        Assert.Equal(typeof(Sports.Volley.Ball), registry.Resolve("sports.volley.ball"));

        var ex = Assert.Throws<InvalidOperationException>(() => registry.Resolve("ball"));
        Assert.Contains("sports.soccer.ball", ex.Message);
        Assert.Contains("sports.volley.ball", ex.Message);
    }

    [Fact]
    public void TwoTypesSharingAQualifiedNameFailAtRegistration()
    {
        // No way to tell them apart, so it is a contradiction rather than an
        // ambiguity. Silently letting the second win builds the wrong node.
        var registry = new NodeTypeRegistry().Register<Sports.Soccer.Ball>("game.ball");
        var ex = Assert.Throws<InvalidOperationException>(
            () => registry.Register<Sports.Volley.Ball>("game.ball"));
        Assert.Contains("game.ball", ex.Message);
    }

    [Fact]
    public void RegisteringTheSameTypeTwiceIsNotAConflict()
    {
        var registry = new NodeTypeRegistry()
            .Register<Sports.Soccer.Ball>()
            .Register<Sports.Soccer.Ball>();
        Assert.Equal(typeof(Sports.Soccer.Ball), registry.Resolve("ball"));
    }
}
}
