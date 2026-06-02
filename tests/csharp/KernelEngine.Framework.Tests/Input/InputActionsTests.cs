using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using KernelEngine.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Tests;

[Collection("InputActions")]
public class InputActionsTests
{
    public enum GameAction { Jump, Move }

    [Fact]
    public void Register_And_Get_Work()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        InputActions.Register(map);

        var reader = InputActions.Get<GameAction>();
        Assert.NotNull(reader);
    }

    [Fact]
    public void Get_Throws_WhenNotRegistered()
    {
        InputActions.Clear();
        Assert.Throws<InvalidOperationException>(() => InputActions.Get<GameAction>());
    }

    [Fact]
    public void LoadFromProject_Throws_WhenNoConfig()
    {
        var services = new ServiceCollection().BuildServiceProvider();
        var app = new Application();
        typeof(Application).GetProperty("Services")!.SetValue(app, services);
        
        Assert.Throws<InvalidOperationException>(() => InputActions.LoadFromProject<GameAction>(app));
    }

    [Fact]
    public void LoadFromProject_Throws_WhenSectionMissing()
    {
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        config.IsLoaded.Returns(true);
        config.GetSection("input").Returns((Tomlyn.Model.TomlTable?)null);
        services.AddSingleton(config);
        
        var app = new Application();
        typeof(Application).GetProperty("Services")!.SetValue(app, services.BuildServiceProvider());

        Assert.Throws<InvalidOperationException>(() => InputActions.LoadFromProject<GameAction>(app));
    }

    [Fact]
    public void LoadFromProject_Throws_WhenKeyMissing()
    {
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        config.IsLoaded.Returns(true);
        config.GetSection("input").Returns(new Tomlyn.Model.TomlTable());
        services.AddSingleton(config);
        
        var app = new Application();
        typeof(Application).GetProperty("Services")!.SetValue(app, services.BuildServiceProvider());

        Assert.Throws<InvalidOperationException>(() => InputActions.LoadFromProject<GameAction>(app));
    }

    [Fact]
    public void LoadFromProject_Throws_WhenPrefixInvalid()
    {
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        config.IsLoaded.Returns(true);
        var input = new Tomlyn.Model.TomlTable { ["actions"] = "invalid://path" };
        config.GetSection("input").Returns(input);
        services.AddSingleton(config);
        
        var app = new Application();
        typeof(Application).GetProperty("Services")!.SetValue(app, services.BuildServiceProvider());

        Assert.Throws<InvalidDataException>(() => InputActions.LoadFromProject<GameAction>(app));
    }

    [Fact]
    public void AutoLoader_CallsLoadFromProject()
    {
        var autoloader = new InputActions.AutoLoader<GameAction>();
        var app = new Application();
        var services = new ServiceCollection().BuildServiceProvider();
        typeof(Application).GetProperty("Services")!.SetValue(app, services);

        // Since LoadFromProject will throw (no config), we just verify the call chain by catching it
        Assert.Throws<InvalidOperationException>(() => autoloader.Load(app));
    }

    [Fact]
    public void AllMaps_ReturnsRegisteredMaps()
    {
        InputActions.Clear();
        var map = new InputActionMap<GameAction>();
        InputActions.Register(map);
        
        Assert.Contains(map, InputActions.AllMaps);
    }
}
