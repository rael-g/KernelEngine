using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace KernelEngine.Runtime.Tests;

// Covers the IRuntimeModule pattern: Configure runs at .Add time, OnLoad runs
// at LoadModules time, topo-sort respects declared Dependencies.
public class ModulePatternTests : IDisposable
{
    private readonly MallocAllocator   _allocator      = new();
    private readonly EnkiTaskScheduler _taskScheduler;
    private readonly FlecsEcs          _ecs;

    public ModulePatternTests()
    {
        _taskScheduler = new EnkiTaskScheduler(_allocator);
        _ecs           = new FlecsEcs(_allocator);
    }

    public void Dispose()
    {
        _ecs.Dispose();
        _taskScheduler.Dispose();
        _allocator.Dispose();
    }

    private sealed class SimpleModule : IRuntimeModule
    {
        public bool ConfigureCalled { get; private set; }
        public bool OnLoadCalled    { get; private set; }
        public int  TimesRegistered { get; set; }

        public void Configure(IServiceCollection services)
        {
            ConfigureCalled = true;
            services.AddSingleton<ITrackingService, TrackingService>();
        }

        public void OnLoad(IRuntime runtime, IServiceProvider services)
        {
            OnLoadCalled = true;
            runtime.RegisterSystem("SimpleModuleTick", RuntimePhase.Update, (_, _) => TimesRegistered++);
        }
    }

    public interface ITrackingService { }
    public sealed class TrackingService : ITrackingService { }

    [Fact]
    public void Add_Instance_RunsConfigureSynchronously()
    {
        var module = new SimpleModule();
        var services = new ServiceCollection().Add<IRuntimeModule>(module);

        // Configure ran at Add time, before BuildServiceProvider.
        Assert.True(module.ConfigureCalled);
        Assert.False(module.OnLoadCalled);

        // Both the module and the contract it registered are resolvable.
        using var sp = services.BuildServiceProvider();
        Assert.Same(module, sp.GetRequiredService<IRuntimeModule>());
        Assert.IsType<TrackingService>(sp.GetRequiredService<ITrackingService>());
    }

    [Fact]
    public void LoadModules_CallsOnLoadAndRegistersSystem()
    {
        var module = new SimpleModule();
        var services = new ServiceCollection().Add<IRuntimeModule>(module);
        using var sp = services.BuildServiceProvider();

        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.LoadModules(sp);

        Assert.True(module.OnLoadCalled);

        runtime.Tick(1f / 60f);
        runtime.Tick(1f / 60f);
        Assert.Equal(2, module.TimesRegistered);
    }

    private sealed class ModuleA : IRuntimeModule
    {
        public List<string> Order { get; }
        public ModuleA(List<string> order) => Order = order;
        public void OnLoad(IRuntime runtime, IServiceProvider services) => Order.Add("A");
    }

    private sealed class ModuleB : IRuntimeModule
    {
        public List<string> Order { get; }
        public ModuleB(List<string> order) => Order = order;
        public IEnumerable<Type> Dependencies => new[] { typeof(ModuleA) };
        public void OnLoad(IRuntime runtime, IServiceProvider services) => Order.Add("B");
    }

    [Fact]
    public void LoadModules_RespectsDependencyOrder()
    {
        var order = new List<string>();
        var services = new ServiceCollection()
            .Add<IRuntimeModule>(new ModuleB(order))   // registered FIRST but depends on A
            .Add<IRuntimeModule>(new ModuleA(order));  // registered SECOND
        using var sp = services.BuildServiceProvider();

        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);
        runtime.LoadModules(sp);

        Assert.Equal(new[] { "A", "B" }, order);
    }

    private sealed class CyclicModule : IRuntimeModule
    {
        public IEnumerable<Type> Dependencies => new[] { typeof(CyclicModule) };
        public void OnLoad(IRuntime runtime, IServiceProvider services) { }
    }

    [Fact]
    public void LoadModules_RejectsDependencyCycle()
    {
        var services = new ServiceCollection().Add<IRuntimeModule>(new CyclicModule());
        using var sp = services.BuildServiceProvider();

        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.LoadModules(sp));
        Assert.Contains("cycle", ex.Message);
    }

    private sealed class MissingDepModule : IRuntimeModule
    {
        public IEnumerable<Type> Dependencies => new[] { typeof(ModuleA) };
        public void OnLoad(IRuntime runtime, IServiceProvider services) { }
    }

    [Fact]
    public void LoadModules_RejectsMissingDependency()
    {
        var services = new ServiceCollection().Add<IRuntimeModule>(new MissingDepModule());
        using var sp = services.BuildServiceProvider();

        using var runtime = new Runtime(_allocator, _ecs, _taskScheduler);

        var ex = Assert.Throws<InvalidOperationException>(() => runtime.LoadModules(sp));
        Assert.Contains("not registered", ex.Message);
    }

    [Fact]
    public void Add_GenericContract_DiResolvesImpl()
    {
        // Add<TContract, TImpl>() — the DI container constructs TImpl using
        // services already registered. Here ImplWithDep needs ITrackingService.
        var services = new ServiceCollection()
            .AddSingleton<ITrackingService, TrackingService>()
            .Add<IService, ImplWithDep>();
        using var sp = services.BuildServiceProvider();

        var resolved = sp.GetRequiredService<IService>();
        Assert.IsType<ImplWithDep>(resolved);
    }

    public interface IService { }
    public sealed class ImplWithDep : IService
    {
        public ImplWithDep(ITrackingService tracking) { }
    }
}
