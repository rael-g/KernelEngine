using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class ResourceQueueTests
{
    [Fact]
    public async Task Factory_CreateMesh_EnqueuesAndReturnsHandleAfterDrain()
    {
        var mockThreads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(mockThreads);
        var factory = new ResourceCommandFactory(queue);
        var mockRenderer = Substitute.For<IRenderer>();
        
        mockRenderer.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>())
                    .Returns(new Result<MeshHandle>(KernelResult.Ok, new MeshHandle(42)));

        // Run factory call in background Task because it blocks until Drain
        var createTask = Task.Run(() => factory.CreateMesh(new Vertex[3], new ushort[3]));

        // Wait a bit to ensure it's enqueued
        await Task.Delay(50);

        // Drain on "ke.render" thread
        mockThreads.When(t => t.AssertCurrentThread("ke.render")).Do(_ => { });
        queue.Drain(mockRenderer);

        var handle = await createTask;
        Assert.Equal(42u, handle.Value);
        mockRenderer.Received(1).CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>());
    }

    [Fact]
    public async Task Factory_CreateTexture_EnqueuesAndReturnsHandle()
    {
        var mockThreads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(mockThreads);
        var factory = new ResourceCommandFactory(queue);
        var mockRenderer = Substitute.For<IRenderer>();
        
        mockRenderer.CreateTexture(Arg.Any<uint>(), Arg.Any<uint>(), Arg.Any<byte[]>())
                    .Returns(new Result<TextureHandle>(KernelResult.Ok, new TextureHandle(7)));

        var createTask = Task.Run(() => factory.CreateTexture(2, 2, new byte[16]));
        await Task.Delay(50);
        queue.Drain(mockRenderer);

        var handle = await createTask;
        Assert.Equal(7u, handle.Value);
    }

    [Fact]
    public async Task Factory_CreateMaterial_EnqueuesAndReturnsHandle()
    {
        var mockThreads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(mockThreads);
        var factory = new ResourceCommandFactory(queue);
        var mockRenderer = Substitute.For<IRenderer>();
        
        mockRenderer.CreateMaterial(Arg.Any<Vector4>(), Arg.Any<TextureHandle>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<TextureHandle>())
                    .Returns(new Result<MaterialHandle>(KernelResult.Ok, new MaterialHandle(13)));

        var createTask = Task.Run(() => factory.CreateMaterial(Vector4.One));
        await Task.Delay(50);
        queue.Drain(mockRenderer);

        var handle = await createTask;
        Assert.Equal(13u, handle.Value);
    }

    [Fact]
    public async Task Drain_HandlesMultipleCommands()
    {
        var mockThreads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(mockThreads);
        var factory = new ResourceCommandFactory(queue);
        var mockRenderer = Substitute.For<IRenderer>();

        var task1 = Task.Run(() => factory.DestroyMesh(new MeshHandle(1)));
        var task2 = Task.Run(() => factory.DestroyTexture(new TextureHandle(2)));
        
        await Task.Delay(50);
        queue.Drain(mockRenderer);

        await Task.WhenAll(task1, task2);
        mockRenderer.Received(1).DestroyMesh(Arg.Is<MeshHandle>(h => h.Value == 1));
        mockRenderer.Received(1).DestroyTexture(Arg.Is<TextureHandle>(h => h.Value == 2));
    }

    [Fact]
    public async Task Extensions_UseEnqueueAsync_WhenFactoryIsRCF()
    {
        var mockThreads = Substitute.For<IKernelFactory>();
        var queue = new ResourceCommandQueue(mockThreads);
        var factory = new ResourceCommandFactory(queue);
        var mockRenderer = Substitute.For<IRenderer>();
        
        mockRenderer.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>())
                    .Returns(new Result<MeshHandle>(KernelResult.Ok, new MeshHandle(123)));

        var task = factory.CreateMeshAsync(new Vertex[1], new ushort[1]);
        
        await Task.Delay(50);
        queue.Drain(mockRenderer);

        var handle = await task;
        Assert.Equal(123u, handle.Value);
    }
}
