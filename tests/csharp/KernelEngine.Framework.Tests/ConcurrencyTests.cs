using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Framework;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class ConcurrencyTests
{
    // ── InputBuffer Tests ────────────────────────────────────────────────────

    [Fact]
    public void InputBuffer_ProduceAndConsume_ReturnsLatest()
    {
        var buffer = new InputBuffer();
        var reader1 = Substitute.For<IInputReader>();
        reader1.MousePosition.Returns(new Vector2(100, 200));

        buffer.Produce(reader1);
        var reader = buffer.Consume();

        Assert.Equal(new Vector2(100, 200), reader.MousePosition);
    }

    [Fact]
    public void InputBuffer_MultipleProduce_ReturnsOnlyLatest()
    {
        var buffer = new InputBuffer();

        var first = Substitute.For<IInputReader>();
        first.MousePosition.Returns(new Vector2(10, 0));
        var second = Substitute.For<IInputReader>();
        second.MousePosition.Returns(new Vector2(20, 0));

        buffer.Produce(first);
        buffer.Produce(second);

        var reader = buffer.Consume();
        Assert.Equal(20, reader.MousePosition.X);
    }

    // ── ResourceCommandQueue Tests ───────────────────────────────────────────

    [Fact]
    public async Task ResourceCommandQueue_EnqueueAndDrain_CallsRenderer()
    {
        var threads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(threads);
        var mockRenderer = Substitute.For<IRenderer>();

        var tcs = new TaskCompletionSource<uint>();
        var cmd = new ResourceCommand {
            Type = ResourceCommandType.CreateShadowMap,
            Data = (1024u, 1024u),
            CompletionSource = tcs
        };

        // Mock Renderer.CreateShadowMap to return success
        mockRenderer.CreateShadowMap(1024, 1024).Returns(new Result<ShadowMapHandle>(KernelResult.Ok, new ShadowMapHandle(5)));

        queue.Enqueue(cmd);
        queue.Drain(mockRenderer); // IKernelFactory.AssertCurrentThread is a no-op substitute

        mockRenderer.Received().CreateShadowMap(1024, 1024);
        Assert.True(tcs.Task.IsCompleted);
        Assert.Equal(5u, await tcs.Task);
    }

    [Fact]
    public async Task ResourceCommandQueue_Drain_HandlesErrors()
    {
        var threads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(threads);
        var mockRenderer = Substitute.For<IRenderer>();

        var tcs = new TaskCompletionSource<uint>();
        var cmd = new ResourceCommand {
            Type = ResourceCommandType.CreateShadowMap,
            Data = (1024u, 1024u),
            CompletionSource = tcs
        };

        mockRenderer.CreateShadowMap(1024, 1024).Returns(_ => throw new InvalidOperationException("GPU Full"));

        queue.Enqueue(cmd);
        queue.Drain(mockRenderer);

        Assert.True(tcs.Task.IsFaulted);
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await tcs.Task);
    }
}
