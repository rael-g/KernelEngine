using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

[Collection("InputActions")]
public class InputActionDispatcherTests
{
    public enum GameAction { Jump, Move }

    private class MockBinding : InputBinding
    {
        public override ActionType Type { get; }
        public float X, Y, Z;

        public MockBinding(ActionType type) { Type = type; }

        public override void Sample(IInputReader reader, out float x, out float y, out float z)
        {
            x = X; y = Y; z = Z;
        }
    }

    [Fact]
    public void Evaluate_EmitsStarted_WhenPressed()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        var builder = map.AddAction(GameAction.Jump, ActionType.Button);
        var binding = new MockBinding(ActionType.Button);
        builder.AddBinding(binding);
        InputActions.Register(map);

        var dispatcher = new InputActionDispatcher();
        var reader = Substitute.For<IInputReader>();

        // Frame 1: Pressed
        binding.X = 1f;
        
        var events = dispatcher.Evaluate(reader);
        
        Assert.Single(events);
        Assert.Equal(ActionPhase.Started, events[0].Phase);
        Assert.Equal((int)GameAction.Jump, events[0].ActionId);
    }

    [Fact]
    public void Evaluate_EmitsCanceled_WhenReleased()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        var builder = map.AddAction(GameAction.Jump, ActionType.Button);
        var binding = new MockBinding(ActionType.Button);
        builder.AddBinding(binding);
        InputActions.Register(map);

        var dispatcher = new InputActionDispatcher();
        var reader = Substitute.For<IInputReader>();

        // Frame 1: Pressed
        binding.X = 1f;
        dispatcher.Evaluate(reader);

        // Frame 2: Released
        binding.X = 0f;
        var events = dispatcher.Evaluate(reader);

        Assert.Single(events);
        Assert.Equal(ActionPhase.Canceled, events[0].Phase);
    }

    [Fact]
    public void Evaluate_EmitsPerformed_WhenValueChanged()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        var builder = map.AddAction(GameAction.Move, ActionType.Axis1D);
        var binding = new MockBinding(ActionType.Axis1D);
        builder.AddBinding(binding);
        InputActions.Register(map);

        var dispatcher = new InputActionDispatcher();
        var reader = Substitute.For<IInputReader>();

        // Frame 1: Started (0.5)
        binding.X = 0.5f;
        dispatcher.Evaluate(reader);

        // Frame 2: Performed (0.8)
        binding.X = 0.8f;
        var events = dispatcher.Evaluate(reader);

        Assert.Single(events);
        Assert.Equal(ActionPhase.Performed, events[0].Phase);
        Assert.Equal(0.8f, events[0].ValueX);
    }

    [Fact]
    public void Evaluate_UsesMaxMagnitude_ForMultipleBindings()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        var builder = map.AddAction(GameAction.Move, ActionType.Axis1D);
        var b1 = new MockBinding(ActionType.Axis1D);
        var b2 = new MockBinding(ActionType.Axis1D);
        builder.AddBinding(b1);
        builder.AddBinding(b2);
        InputActions.Register(map);

        var dispatcher = new InputActionDispatcher();
        var reader = Substitute.For<IInputReader>();

        b1.X = -0.8f;
        b2.X = 0.5f;

        dispatcher.Evaluate(reader);

        var readerActions = InputActions.Get<GameAction>();
        Assert.Equal(-0.8f, readerActions.GetActionAxis1D(GameAction.Move));
    }
}
