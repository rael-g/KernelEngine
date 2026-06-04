using System.Collections.Generic;
using Xunit;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Tests;

/// <summary>
/// End-to-end tests over the new <see cref="InputActionMap{TEnum}"/> backed by the
/// <c>ke_input_actions</c> native primitive. Each test builds a snapshot directly,
/// runs the dispatcher via <see cref="IInputActionMap.Evaluate"/>, and asserts on
/// the polling surface plus the event stream.
/// </summary>
public class InputActionMapTests
{
    static InputActionMapTests()
    {
        // Tests bypass DI; wire the native backend factory directly so the parameterless
        // InputActionMap<TEnum> constructor finds a backend.
        if (FrameworkBackends.Default is null)
        {
            var factory = new NativeFrameworkBackendFactory();
            FrameworkBackends.Default  = factory;
            InputActions.CreateBackend = factory.CreateInputActions;
        }
    }

    public enum GameAction { Jump, Move, Strafe, Quit }

    private static IInputReader Snapshot(params Key[] keysDown)
    {
        var s = default(ke_input_snapshot);
        foreach (var k in keysDown)
        {
            int idx = (int)k;
            unsafe { s.keys_down[idx / 64] |= (1UL << (idx % 64)); }
        }
        return new InputSnapshotReader(s);
    }

    [Fact]
    public void AddAction_Throws_OnDuplicate()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Jump, ActionType.Button);
        Assert.Throws<ArgumentException>(() => map.AddAction(GameAction.Jump, ActionType.Button));
    }

    [Fact]
    public void AddButton_WithKey_PollsCorrectly()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddButton(GameAction.Jump, Key.Space);

        var iface = (IInputActionMap)map;
        var events = new List<InputActionEvent>();
        iface.Evaluate(Snapshot(Key.Space), events);
        Assert.True(map.IsActionDown(GameAction.Jump));
        Assert.True(map.WasActionPressed(GameAction.Jump));

        iface.Evaluate(Snapshot(Key.Space), events);
        Assert.True(map.IsActionDown(GameAction.Jump));
        Assert.False(map.WasActionPressed(GameAction.Jump));

        iface.Evaluate(Snapshot(), events);
        Assert.False(map.IsActionDown(GameAction.Jump));
        Assert.True(map.WasActionReleased(GameAction.Jump));
    }

    [Fact]
    public void AddKeyPair_DrivesAxis1D()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Strafe, ActionType.Axis1D).AddKeyPair(Key.A, Key.D);

        var iface = (IInputActionMap)map;
        var events = new List<InputActionEvent>();
        iface.Evaluate(Snapshot(Key.D), events);
        Assert.Equal(1f, map.GetAxis1D(GameAction.Strafe));

        iface.Evaluate(Snapshot(Key.A), events);
        Assert.Equal(-1f, map.GetAxis1D(GameAction.Strafe));
    }

    [Fact]
    public void AddWASD_DrivesAxis2D()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Move, ActionType.Axis2D).AddWASD();

        var iface = (IInputActionMap)map;
        var events = new List<InputActionEvent>();
        iface.Evaluate(Snapshot(Key.W, Key.D), events);
        var v = map.GetAxis2D(GameAction.Move);
        Assert.Equal(1f, v.X);
        Assert.Equal(1f, v.Y);
    }

    [Fact]
    public void Evaluate_EmitsStartedAndCanceledForButton_NoPerformed()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddButton(GameAction.Jump, Key.Space);

        var iface = (IInputActionMap)map;
        var events = new List<InputActionEvent>();

        iface.Evaluate(Snapshot(Key.Space), events); // press
        iface.Evaluate(Snapshot(Key.Space), events); // hold
        iface.Evaluate(Snapshot(), events);          // release

        Assert.Contains(events, e => e.Phase == ActionPhase.Started);
        Assert.Contains(events, e => e.Phase == ActionPhase.Canceled);
        Assert.DoesNotContain(events, e => e.Phase == ActionPhase.Performed); // Button never Performed
    }

    [Fact]
    public void Evaluate_EmitsPerformedForAxis_OnValueChange()
    {
        using var map = new InputActionMap<GameAction>();
        map.AddAction(GameAction.Strafe, ActionType.Axis1D).AddKeyPair(Key.A, Key.D);

        var iface = (IInputActionMap)map;
        var events = new List<InputActionEvent>();

        iface.Evaluate(Snapshot(Key.D), events);    // 0 -> +1 (Started)
        events.Clear();
        iface.Evaluate(Snapshot(Key.D), events);    // +1 -> +1 (no event)
        Assert.Empty(events);

        iface.Evaluate(Snapshot(Key.A), events);    // +1 -> -1 (Performed, continued active)
        Assert.Contains(events, e => e.Phase == ActionPhase.Performed);
    }
}
