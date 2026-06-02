using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class ApplicationTests
{
    [Fact]
    public void Tree_LazyInit_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var app = new Application();
        app.ActiveWorld = world;
        
        Assert.NotNull(app.Tree);
        Assert.Same(world, app.Tree.Root.World);
    }

    [Fact]
    public void Run_Throws_WhenRequiredServicesMissing()
    {
        var app = new Application();
        var services = new ServiceCollection();
        // Missing IWindow and IRenderer
        
        Assert.Throws<InvalidOperationException>(() => app.Run(services));
    }

    [Fact]
    public void Run_InitializesAndExits_WhenWindowShouldClose()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var app = new Application();
        app.ActiveWorld = world;
        var services = new ServiceCollection();
        
        var window = Substitute.For<IWindow>();
        window.ShouldClose().Returns(true); // Exit immediately
        
        var renderer = Substitute.For<IRenderer>();
        renderer.GetNdcConvention().Returns(new NdcConvention(true, false, false));
        
        var factory = Substitute.For<IKernelFactory>();
        factory.CreateWorld(Arg.Any<IAllocator>()).Returns(world);
        factory.CreateFrameSync(Arg.Any<IAllocator>(), Arg.Any<int>()).Returns(Substitute.For<IFrameSync>());
        
        // Mock threads to not actually start background work
        factory.CreateThread(Arg.Any<IAllocator>(), Arg.Any<string>(), Arg.Any<IDevPlatform>(), Arg.Any<Action>())
               .Returns(Substitute.For<IKernelThread>());

        services.AddSingleton(window);
        services.AddSingleton(renderer);
        services.AddSingleton(factory);
        services.AddSingleton<IAllocator>(allocator);

        app.Run(services);

        window.Received().PollEvents();
        factory.Received(1).CreateThread(Arg.Any<IAllocator>(), "ke.render", Arg.Any<IDevPlatform>(), Arg.Any<Action>());
        factory.Received(1).CreateThread(Arg.Any<IAllocator>(), "ke.sim", Arg.Any<IDevPlatform>(), Arg.Any<Action>());
    }

    [Fact]
    public void LoadProjectRenderSettings_Works_WhenConfigPresent()
    {
        var app = new Application();
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        config.IsLoaded.Returns(true);
        
        var renderSection = new Tomlyn.Model.TomlTable();
        var colorArray = new Tomlyn.Model.TomlArray { 1.0, 0.0, 0.0, 1.0 };
        renderSection["clear_color"] = colorArray;
        config.GetSection("render").Returns(renderSection);

        services.AddSingleton(config);
        typeof(Application).GetProperty("Services")!.SetValue(app, services.BuildServiceProvider());

        // Call private method via reflection
        var method = typeof(Application).GetMethod("LoadProjectRenderSettings", BindingFlags.NonPublic | BindingFlags.Instance);
        method!.Invoke(app, null);

        var cc = (System.Numerics.Vector4?)typeof(Application).GetField("_projectClearColor", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(app);
        Assert.NotNull(cc);
        Assert.Equal(1.0f, cc.Value.X);
    }

    [Fact]
    public void LoadDefaultScene_Works_WhenSceneFound()
    {
        var app = new Application();
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        config.IsLoaded.Returns(true);
        var project = new Tomlyn.Model.TomlTable { ["default_scene"] = "res://main.scene" };
        config.GetSection("project").Returns(project);
        services.AddSingleton(config);
        
        var loader = Substitute.For<ISceneLoader>();
        services.AddSingleton(loader);
        
        typeof(Application).GetProperty("Services")!.SetValue(app, services.BuildServiceProvider());

        // Setup paths
        var path = Path.Combine(AppContext.BaseDirectory, "main.scene");
        
        // Inject loader directly
        typeof(Application).GetField("_sceneLoader", BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(app, loader);
        
        // Call private method
        var method = typeof(Application).GetMethod("LoadDefaultSceneIfDeclared", BindingFlags.NonPublic | BindingFlags.Instance);
        method!.Invoke(app, null);

        loader.Received(1).LoadAsync(path);
    }

    [Fact]
    public void CheckResult_Throws_OnGpuFatal()
    {
        var app = new Application();
        var renderer = Substitute.For<IRenderer>();
        renderer.GetLastFatalError().Returns("GPU Burned");
        typeof(Application).GetProperty("Renderer")!.SetValue(app, renderer);

        var method = typeof(Application).GetMethod("CheckResult", BindingFlags.NonPublic | BindingFlags.Instance);
        
        var ex = Assert.Throws<TargetInvocationException>(() => method!.Invoke(app, new object[] { (Result)KernelResult.GpuFatal, "test" }));
        var kex = Assert.IsType<KernelException>(ex.InnerException);
        Assert.Contains("GPU Burned", kex.Message);
    }

    [Fact]
    public void Dispose_HandlesNullsGracefully()
    {
        var app = new Application();
        app.Dispose();
        // Should not throw
    }
}
