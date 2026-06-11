using KernelEngine.Kernel;
using NSubstitute;
using Xunit;
using System.Numerics;

namespace KernelEngine.Framework.Legacy.Tests;

public class InputActionsTests
{
    private enum TestActions { Action1, Action2 }

    [Fact]
    public void Register_CreatesReader_ThatDelegatesToMap()
    {
        var backend = Substitute.For<IInputActionsBackend>();
        backend.GetActionId("Action1").Returns(10);
        backend.GetActionId("Action2").Returns(20);

        var map = new InputActionMap<TestActions>(backend);
        
        backend.WasActionPressed(10).Returns(true);
        backend.GetAxis1D(20).Returns(0.75f);
        
        var reader = InputActions.Register(map);
        
        Assert.True(reader.WasActionPressed(TestActions.Action1));
        Assert.Equal(0.75f, reader.GetActionAxis1D(TestActions.Action2));
    }

    [Fact]
    public void Get_ReturnsRegisteredReader()
    {
        InputActions.Clear();
        var backend = Substitute.For<IInputActionsBackend>();
        var map = new InputActionMap<TestActions>(backend);
        var reader = InputActions.Register(map);
        
        Assert.Same(reader, InputActions.Get<TestActions>());
    }

    [Fact]
    public void Get_Throws_WhenNotRegistered()
    {
        InputActions.Clear();
        Assert.Throws<InvalidOperationException>(() => InputActions.Get<TestActions>());
    }
}
