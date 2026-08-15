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
