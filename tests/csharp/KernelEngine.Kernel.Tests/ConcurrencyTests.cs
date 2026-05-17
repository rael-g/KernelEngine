using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using NSubstitute;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ConcurrencyTests
{
    // ── InputBuffer Tests ────────────────────────────────────────────────────

    [Fact]
    public void InputBuffer_ProduceAndConsume_ReturnsLatest()
    {
        var buffer = new InputBuffer();
        var snapshot = new ke_input_snapshot { mouse_x = 100, mouse_y = 200 };
        
        buffer.Produce(snapshot);
        var reader = buffer.Consume();
        
        Assert.Equal(new Vector2(100, 200), reader.MousePosition);
    }

    [Fact]
    public void InputBuffer_MultipleProduce_ReturnsOnlyLatest()
    {
        var buffer = new InputBuffer();
        
        buffer.Produce(new ke_input_snapshot { mouse_x = 10 });
        buffer.Produce(new ke_input_snapshot { mouse_x = 20 });
        
        var reader = buffer.Consume();
        Assert.Equal(20, reader.MousePosition.X);
    }

    // ── ResourceCommandQueue Tests ───────────────────────────────────────────

    [Fact]
    public async Task ResourceCommandQueue_EnqueueAndDrain_CallsRenderer()
    {
        var queue = new ResourceCommandQueue();
        var mockRenderer = Substitute.For<IRenderer>();
        
        var tcs = new TaskCompletionSource<uint>();
        var cmd = new ResourceCommand { 
            Type = ResourceCommandType.CreateShadowMap, 
            Data = (1024u, 1024u),
            CompletionSource = tcs
        };
        
        // Mock Renderer.CreateShadowMap to return success
        mockRenderer.CreateShadowMap(1024, 1024).Returns(new Result<ShadowMapHandle>(ke_result.KE_OK, new ShadowMapHandle(5)));

        queue.Enqueue(cmd);
        
        // ResourceCommandQueue.Drain asserts we are on ke.render thread
        KernelThread.SetCurrentName("ke.render");
        try {
            queue.Drain(mockRenderer);
        } finally {
            KernelThread.SetCurrentName("");
        }

        mockRenderer.Received().CreateShadowMap(1024, 1024);
        Assert.True(tcs.Task.IsCompleted);
        Assert.Equal(5u, await tcs.Task);
    }

    [Fact]
    public async Task ResourceCommandQueue_Drain_HandlesErrors()
    {
        var queue = new ResourceCommandQueue();
        var mockRenderer = Substitute.For<IRenderer>();
        
        var tcs = new TaskCompletionSource<uint>();
        var cmd = new ResourceCommand { 
            Type = ResourceCommandType.CreateShadowMap, 
            Data = (1024u, 1024u),
            CompletionSource = tcs
        };
        
        mockRenderer.CreateShadowMap(1024, 1024).Returns(_ => throw new InvalidOperationException("GPU Full"));

        queue.Enqueue(cmd);
        
        KernelThread.SetCurrentName("ke.render");
        try {
            queue.Drain(mockRenderer);
        } finally {
            KernelThread.SetCurrentName("");
        }

        Assert.True(tcs.Task.IsFaulted);
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await tcs.Task);
    }
}
