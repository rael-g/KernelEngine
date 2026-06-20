using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ServiceCollectionTests
{
    [Fact]
    public void AddKernel_RegistersRequiredServices()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<IKernelFactory>());
    }

    [Fact]
    public void AddLogger_RegistersLogger()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        services.AddLogger();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Logger>());
        Assert.NotNull(provider.GetService<ILogger>());
    }

    [Fact]
    public void AddInput_RegistersInput()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        services.AddInput();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Input>());
        Assert.NotNull(provider.GetService<IInput>());
    }
}
