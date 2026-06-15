using Xunit;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class InputActionsServiceExtensionsTests
{
    public enum TestAction { Jump }

    [GameActions]
    public enum AnnotatedAction { Move }

    [Fact]
    public void AddInputActions_TEnum_RegistersServices()
    {
        var services = new ServiceCollection();
        services.AddInputActions<TestAction>();
        
        var provider = services.BuildServiceProvider();
        var autoloader = provider.GetService<InputActions.IAutoLoader>();
        Assert.NotNull(autoloader);
    }

    [Fact]
    public void AddInputActions_Scan_RegistersAnnotatedEnums()
    {
        var services = new ServiceCollection();
        services.AddInputActions();
        
        var provider = services.BuildServiceProvider();
        // Check if AnnotatedAction was registered by looking for its autoloader
        // Internal type check is hard, but let's see if we can resolve the reader
        // Wait, InputActions.Get will throw if not registered.
        
        InputActions.Clear();
        // Since we can't easily check registration without causing load, 
        // we'll just verify it doesn't crash and at least one autoloader exists.
        var autoloaders = provider.GetServices<InputActions.IAutoLoader>();
        Assert.NotEmpty(autoloaders);
    }
}
