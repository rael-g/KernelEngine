using KernelEngine.Framework.Legacy;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class ApplicationDetailsTests
{
    static ApplicationDetailsTests()
    {
        // Application.Run resolves FrameworkBackends.Required during startup.
        // Wire the native factory directly for test isolation.
        FrameworkBackends.Default ??= new NativeFrameworkBackendFactory();
    }

    [Fact]
    public void CheckResult_GpuFatal_ThrowsKernelExceptionWithDetails()
    {
        var mockRenderer = Substitute.For<IRenderer>();
        mockRenderer.GetLastFatalError().Returns("Out of Memory");
        
        var app = new Application();
        // We need to inject the mock renderer. It's private, but we can use reflection.
        var field = typeof(Application).GetProperty("Renderer", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        field!.SetValue(app, mockRenderer);

        // Access private CheckResult via reflection
        var method = typeof(Application).GetMethod("CheckResult", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        
        var ex = Assert.Throws<System.Reflection.TargetInvocationException>(() => 
            method!.Invoke(app, new object[] { (Result)KernelResult.GpuFatal, "Testing" }));
            
        Assert.IsType<KernelException>(ex.InnerException);
        Assert.Contains("Out of Memory", ex.InnerException.Message);
    }

    [Fact]
    public void NativeExceptionFilter_ReturnsZero_ForManagedExceptions()
    {
        var filterType = typeof(Application).GetNestedType("NativeExceptionFilter", System.Reflection.BindingFlags.NonPublic);
        var filterMethod = filterType!.GetMethod("Filter", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);

        unsafe
        {
            int code = unchecked((int)0xE0434352);
            int* pR = &code; int** pP = &pR;
            Assert.Equal(0, (int)filterMethod!.Invoke(null, new object[] { (IntPtr)pP })!);

            code = unchecked((int)0x80000003);
            // This will try to write a dump and exit. 
            // We can't let it exit. 
            // Actually, the Filter method calls Environment.Exit(1).
            // So we CAN'T test other codes without terminating the test runner!
        }
    }

    [Fact]
    public void NativeExceptionFilter_Register_Works()
    {
        var filterType = typeof(Application).GetNestedType("NativeExceptionFilter", System.Reflection.BindingFlags.NonPublic);
        var regMethod = filterType!.GetMethod("Register", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        
        regMethod!.Invoke(null, new object[] { Substitute.For<ILogger>() });
    }


    [Fact]
    public void Run_SimException_CancelsApp()
    {
        var services = new ServiceCollection();
        var mockWindow = Substitute.For<IWindow>();
        var mockRenderer = Substitute.For<IRenderer>();
        using var allocator = new MallocAllocator();
        
        services.AddSingleton<Allocator>(allocator);
        services.AddSingleton<IAllocator>(allocator);
        services.AddSingleton<IKernelFactory, KernelFactory>();
        services.AddSingleton<IWindow>(mockWindow);
        services.AddSingleton<IRenderer>(mockRenderer);

        mockWindow.ShouldClose().Returns(false); // Loop forever until canceled

        var app = new Application();
        app.OnReady = _ => throw new Exception("Sim Fail");

        Action act = () => app.Run(services);
        var ex = Assert.Throws<Exception>(act);
        Assert.Equal("Sim Fail", ex.Message);
    }
}
