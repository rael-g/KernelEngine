using KernelEngine.Ecs.Flecs;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace KernelEngine.Runtime.Tests;

public class ModulePatternTests : IDisposable
{
    private readonly EnkiTaskPool _taskPool = new();
    private readonly FlecsEcsRegistry _ecs = new();

    public void Dispose()
    {
        _ecs.Dispose();
        _taskPool.Dispose();
    }

    private sealed class SimpleModule : IRuntimeModule
    {
        public bool ConfigureCalled { get; private set; }
        public bool OnLoadCalled { get; private set; }
        public int TimesRegistered { get; set; }

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

        Assert.True(module.ConfigureCalled);
        Assert.False(module.OnLoadCalled);

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

        using var runtime = new Runtime(_ecs, _taskPool);
        runtime.LoadModules(sp);

        Assert.True(module.OnLoadCalled);

        runtime.Tick(1f / 60f);
        runtime.Tick(1f / 60f);
        Assert.Equal(2, module.TimesRegistered);
    }

    private sealed class OrderedModule : IRuntimeModule
    {
        private readonly List<string> _order;
        private readonly string _name;
        public OrderedModule(List<string> order, string name) { _order = order; _name = name; }
        public void OnLoad(IRuntime runtime, IServiceProvider services) => _order.Add(_name);
    }

    [Fact]
    public void LoadModules_LoadsInRegistrationOrder()
    {
        var order = new List<string>();
        var services = new ServiceCollection()
            .Add<IRuntimeModule>(new OrderedModule(order, "B"))
            .Add<IRuntimeModule>(new OrderedModule(order, "A"));
        using var sp = services.BuildServiceProvider();

        using var runtime = new Runtime(_ecs, _taskPool);
        runtime.LoadModules(sp);

        Assert.Equal(new[] { "B", "A" }, order);
    }

    [Fact]
    public void Add_GenericContract_DiResolvesImpl()
    {
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
