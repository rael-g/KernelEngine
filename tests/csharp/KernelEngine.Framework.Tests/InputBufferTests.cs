using KernelEngine.Framework;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class InputBufferTests
{
    [Fact]
    public void InputBuffer_InitiallyReturnsEmptyReader_Exhaustive()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        
        Assert.NotNull(reader);
        Assert.False(reader.IsKeyDown(0));
        Assert.False(reader.IsKeyPressed(0));
        Assert.False(reader.IsKeyReleased(0));
        Assert.Equal(0, reader.MousePosition.X);
        Assert.Equal(0, reader.MouseDelta.Y);
        Assert.Equal(0, reader.ScrollDelta.X);
        Assert.False(reader.IsMouseButtonDown(0));
        Assert.False(reader.IsMouseButtonPressed(0));
        Assert.False(reader.IsMouseButtonReleased(0));
    }

    [Fact]
    public void InputEventBuffer_EnqueueAndDrain_Works()
    {
        var buffer = new InputEventBuffer();
        
        // Empty enqueue
        buffer.Enqueue(ReadOnlySpan<InputEvent>.Empty);
        Assert.Empty(buffer.Drain());

        // Single event
        var evts = new[] { new InputEvent { Kind = InputEventKind.KeyDown, Key = Key.Space } };
        buffer.Enqueue(evts);
        
        var drained = buffer.Drain();
        Assert.Single(drained);
        Assert.Equal(Key.Space, drained[0].Key);
        
        // Drain clears
        Assert.Empty(buffer.Drain());
    }

    [Fact]
    public void InputEventBuffer_AccumulatesMultipleBatches()
    {
        var buffer = new InputEventBuffer();
        
        buffer.Enqueue(new[] { new InputEvent { Key = Key.A } });
        buffer.Enqueue(new[] { new InputEvent { Key = Key.B } });
        
        var drained = buffer.Drain();
        Assert.Equal(2, drained.Length);
        Assert.Equal(Key.A, drained[0].Key);
        Assert.Equal(Key.B, drained[1].Key);
    }
}
