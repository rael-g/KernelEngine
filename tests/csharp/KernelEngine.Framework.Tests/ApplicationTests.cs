using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class ApplicationTests
{
    [Fact]
    public void Application_Run_CoordinatesThreadsAndShutsDown()
    {
        // Arrange
        var services = new ServiceCollection();
        
        var mockWindow = Substitute.For<IWindow>();
        var mockRenderer = Substitute.For<IRenderer>();
        
        // Use a real allocator for KernelThread creation (it needs a native pointer)
        // Note: this assumes we can create a malloc allocator in tests.
        using var allocator = new MallocAllocator();
        
        services.AddSingleton<Allocator>(allocator);
        services.AddSingleton<IAllocator>(allocator);
        services.AddSingleton<IKernelFactory, KernelFactory>();
        services.AddSingleton<IWindow>(mockWindow);
        services.AddSingleton<IRenderer>(mockRenderer);
        
        // Mock Window.ShouldClose to exit after some iterations
        int pollCount = 0;
        mockWindow.ShouldClose().Returns(_ => {
            System.Threading.Thread.Sleep(10); // Give threads time to run
            if (++pollCount > 50) return true;
            return false;
        });

        var app = new Application();
        
        // Act
        app.Run(services);

        // Assert
        mockRenderer.Received().Initialize();
        
        // At least one frame should have been rendered
        mockRenderer.Received().Frame();
        mockRenderer.Received().SubmitPacket(Arg.Any<IFramePacket>());
        
        mockWindow.Received().PollEvents();
        // NSubstitute sometimes needs explicit cast for inherited interfaces if it's confused
        ((IDisposable)mockRenderer).Received().Dispose();
        
        app.Dispose();
    }

    [Fact]
    public void Run_GpuFatal_ThrowsWithErrorMessage()
    {
        var services = new ServiceCollection();
        var mockRenderer = Substitute.For<IRenderer>();
        var allocator = new MallocAllocator();
        
        services.AddSingleton<Allocator>(allocator);
        services.AddSingleton<IAllocator>(allocator);
        services.AddSingleton<IKernelFactory, KernelFactory>();
        services.AddSingleton<IWindow>(Substitute.For<IWindow>());
        services.AddSingleton<IRenderer>(mockRenderer);

        // Frame() returns Result, so we can mock its return value
        mockRenderer.Frame().Returns(new Result(KernelResult.GpuFatal));
        mockRenderer.GetLastFatalError().Returns("Device Lost");

        var app = new Application();
        
        var ex = Assert.Throws<KernelException>(() => app.Run(services));
        Assert.Contains("Device Lost", ex.Message);
        
        allocator.Dispose();
    }

    [Fact]
    public void Application_CanBeDisposed()
    {
        var app = new Application();
        app.Dispose();
        // Should not crash
    }

    [Fact]
    public void Run_MissingRequiredServices_ThrowsInvalidOperationException()
    {
        var app = new Application();
        var services = new ServiceCollection();
        // Empty services
        
        Assert.Throws<InvalidOperationException>(() => app.Run(services));
    }
}
