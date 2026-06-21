using KernelEngine.Framework.Legacy;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class InputBufferTests
{
    [Fact]
    public void InputBuffer_InitiallyReturnsReader_NotNull()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.NotNull(reader);
    }

    [Fact]
    public void InputBuffer_InitiallyReturnsReader_KeyNotDown()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.False(reader.IsKeyDown(0));
    }

    [Fact]
    public void InputBuffer_InitiallyReturnsReader_MousePositionZero()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.Equal(0, reader.MousePosition.X);
    }

    [Fact]
    public void InputBuffer_InitiallyReturnsReader_MouseDeltaZero()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.Equal(0, reader.MouseDelta.Y);
    }

    [Fact]
    public void InputBuffer_InitiallyReturnsReader_ScrollDeltaZero()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.Equal(0, reader.ScrollDelta.X);
    }

    [Fact]
    public void InputBuffer_InitiallyReturnsReader_MouseButtonNotDown()
    {
        var buffer = new InputBuffer();
        var reader = buffer.Consume();
        Assert.False(reader.IsMouseButtonDown(0));
    }

    [Fact]
    public void InputEventBuffer_Drain_ReturnsEmptyWhenNoEvents()
    {
        var buffer = new InputEventBuffer();
        buffer.Enqueue(ReadOnlySpan<InputEvent>.Empty);
        Assert.Empty(buffer.Drain());
    }

    [Fact]
    public void InputEventBuffer_Drain_ReturnsSingleEventWhenEnqueued()
    {
        var buffer = new InputEventBuffer();
        var evts = new[] { new InputEvent { Kind = InputEventKind.KeyDown, Key = Key.Space } };
        buffer.Enqueue(evts);
        
        var drained = buffer.Drain();
        Assert.Single(drained);
    }

    [Fact]
    public void InputEventBuffer_Drain_ReturnsCorrectEventData()
    {
        var buffer = new InputEventBuffer();
        var evts = new[] { new InputEvent { Kind = InputEventKind.KeyDown, Key = Key.Space } };
        buffer.Enqueue(evts);
        
        var drained = buffer.Drain();
        Assert.Equal(Key.Space, drained[0].Key);
    }

    [Fact]
    public void InputEventBuffer_Drain_ClearsBuffer()
    {
        var buffer = new InputEventBuffer();
        var evts = new[] { new InputEvent { Kind = InputEventKind.KeyDown, Key = Key.Space } };
        buffer.Enqueue(evts);
        buffer.Drain();
        
        Assert.Empty(buffer.Drain());
    }

    [Fact]
    public void InputEventBuffer_AccumulatesMultipleBatches_CorrectLength()
    {
        var buffer = new InputEventBuffer();
        buffer.Enqueue(new[] { new InputEvent { Key = Key.A } });
        buffer.Enqueue(new[] { new InputEvent { Key = Key.B } });
        
        var drained = buffer.Drain();
        Assert.Equal(2, drained.Length);
    }

    [Fact]
    public void InputEventBuffer_AccumulatesMultipleBatches_CorrectFirstEvent()
    {
        var buffer = new InputEventBuffer();
        buffer.Enqueue(new[] { new InputEvent { Key = Key.A } });
        buffer.Enqueue(new[] { new InputEvent { Key = Key.B } });
        
        var drained = buffer.Drain();
        Assert.Equal(Key.A, drained[0].Key);
    }

    [Fact]
    public void InputEventBuffer_AccumulatesMultipleBatches_CorrectSecondEvent()
    {
        var buffer = new InputEventBuffer();
        buffer.Enqueue(new[] { new InputEvent { Key = Key.A } });
        buffer.Enqueue(new[] { new InputEvent { Key = Key.B } });
        
        var drained = buffer.Drain();
        Assert.Equal(Key.B, drained[1].Key);
    }
}
