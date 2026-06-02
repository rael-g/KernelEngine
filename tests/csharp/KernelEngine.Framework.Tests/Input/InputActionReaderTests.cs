using System.Numerics;
using Xunit;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class InputActionReaderTests
{
    public enum GameAction { Jump, Move }

    [Fact]
    public void IsActionDown_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        var reader = new InputActionReader<GameAction>(map);
        
        ((IInputActionMap)map).Actions[0].CurrX = 1f;
        Assert.True(reader.IsActionDown(GameAction.Jump));
    }

    [Fact]
    public void WasActionPressed_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        var reader = new InputActionReader<GameAction>(map);
        
        var action = ((IInputActionMap)map).Actions[0];
        action.PrevX = 0f;
        action.CurrX = 1f;
        Assert.True(reader.WasActionPressed(GameAction.Jump));
    }

    [Fact]
    public void WasActionReleased_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        var reader = new InputActionReader<GameAction>(map);
        
        var action = ((IInputActionMap)map).Actions[0];
        action.PrevX = 1f;
        action.CurrX = 0f;
        Assert.True(reader.WasActionReleased(GameAction.Jump));
    }

    [Fact]
    public void GetActionAxis1D_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Axis1D);
        var reader = new InputActionReader<GameAction>(map);
        
        ((IInputActionMap)map).Actions[0].CurrX = 0.5f;
        Assert.Equal(0.5f, reader.GetActionAxis1D(GameAction.Jump));
    }

    [Fact]
    public void GetActionAxis2D_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Move, ActionType.Axis2D);
        var reader = new InputActionReader<GameAction>(map);
        
        var action = ((IInputActionMap)map).Actions[0];
        action.CurrX = 1f;
        action.CurrY = -1f;
        var axis = reader.GetActionAxis2D(GameAction.Move);
        Assert.Equal(1f, axis.X);
        Assert.Equal(-1f, axis.Y);
    }

    [Fact]
    public void GetActionAxis3D_DelegatesToMap()
    {
        var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Move, ActionType.Axis3D);
        var reader = new InputActionReader<GameAction>(map);
        
        var action = ((IInputActionMap)map).Actions[0];
        action.CurrX = 1f;
        action.CurrY = 2f;
        action.CurrZ = 3f;
        var axis = reader.GetActionAxis3D(GameAction.Move);
        Assert.Equal(1f, axis.X);
        Assert.Equal(2f, axis.Y);
        Assert.Equal(3f, axis.Z);
    }
}
