using System.Numerics;
using Xunit;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class InputActionMapTests
{
    public enum GameAction { Jump, Move, Look }

    [Fact]
    public void AddAction_Throws_OnDuplicate()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        Assert.Throws<ArgumentException>(() => map.AddAction(GameAction.Jump, ActionType.Button));
    }

    [Fact]
    public void AddButton_WithKey_RegistersCorrectly()
    {
        var map = new InputActionMap<GameAction>();
        map.AddButton(GameAction.Jump, Key.Space);
        var actions = ((IInputActionMap)map).Actions;
        Assert.Single(actions);
        Assert.Equal((int)GameAction.Jump, actions[0].ActionId);
    }

    [Fact]
    public void AddButton_WithMouseButton_RegistersCorrectly()
    {
        var map = new InputActionMap<GameAction>();
        map.AddButton(GameAction.Jump, MouseButton.Left);
        var actions = ((IInputActionMap)map).Actions;
        Assert.Single(actions);
        Assert.Equal((int)GameAction.Jump, actions[0].ActionId);
    }

    [Fact]
    public void IsActionDown_ReturnsCorrectValue()
    {
        var map = new InputActionMap<GameAction>();
        var jump = map.AddAction(GameAction.Jump, ActionType.Button);
        
        // Mock state
        var action = ((IInputActionMap)map).Actions[0];
        action.CurrX = 1f;

        Assert.True(map.IsActionDown(GameAction.Jump));
        
        action.CurrX = 0f;
        Assert.False(map.IsActionDown(GameAction.Jump));
    }

    [Fact]
    public void WasActionPressed_ReturnsTrue_OnTransition()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        var action = ((IInputActionMap)map).Actions[0];

        action.PrevX = 0f;
        action.CurrX = 1f;
        Assert.True(map.WasActionPressed(GameAction.Jump));

        action.PrevX = 1f;
        Assert.False(map.WasActionPressed(GameAction.Jump));
    }

    [Fact]
    public void WasActionReleased_ReturnsTrue_OnTransition()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        var action = ((IInputActionMap)map).Actions[0];

        action.PrevX = 1f;
        action.CurrX = 0f;
        Assert.True(map.WasActionReleased(GameAction.Jump));

        action.PrevX = 0f;
        Assert.False(map.WasActionReleased(GameAction.Jump));
    }

    [Fact]
    public void GetAxis1D_ReturnsCorrectValue()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Axis1D);
        var action = ((IInputActionMap)map).Actions[0];

        action.CurrX = 0.75f;
        Assert.Equal(0.75f, map.GetAxis1D(GameAction.Jump));
    }

    [Fact]
    public void GetAxis2D_ReturnsCorrectValue()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Move, ActionType.Axis2D);
        var action = ((IInputActionMap)map).Actions[0];

        action.CurrX = 0.5f;
        action.CurrY = -0.5f;
        var axis = map.GetAxis2D(GameAction.Move);
        Assert.Equal(0.5f, axis.X);
        Assert.Equal(-0.5f, axis.Y);
    }

    [Fact]
    public void GetAxis3D_ReturnsCorrectValue()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Look, ActionType.Axis3D);
        var action = ((IInputActionMap)map).Actions[0];

        action.CurrX = 1f;
        action.CurrY = 2f;
        action.CurrZ = 3f;
        var axis = map.GetAxis3D(GameAction.Look);
        Assert.Equal(1f, axis.X);
        Assert.Equal(2f, axis.Y);
        Assert.Equal(3f, axis.Z);
    }
}
