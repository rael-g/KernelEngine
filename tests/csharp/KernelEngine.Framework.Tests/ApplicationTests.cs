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
        var allocator = new MallocAllocator();
        
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
        mockRenderer.Received().SubmitPacket(Arg.Any<FramePacket>());
        
        mockWindow.Received().PollEvents();
        mockRenderer.Received().Dispose();
        
        app.Dispose();
        allocator.Dispose();
    }
}
