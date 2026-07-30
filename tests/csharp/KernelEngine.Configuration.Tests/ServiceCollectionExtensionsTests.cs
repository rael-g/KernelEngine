using Xunit;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Configuration;

namespace KernelEngine.Configuration.Tests;

public class ServiceCollectionExtensionsTests
{
    [Fact]
    public void AddProjectConfig_RegistersSingleton()
    {
        var services = new ServiceCollection();
        services.AddProjectConfig();
        var provider = services.BuildServiceProvider();
        var config = provider.GetService<IConfiguration>();
        Assert.NotNull(config);
    }

    [Fact]
    public void AddProjectConfig_MissingFile_FallsBackToDefaults()
    {
        var services = new ServiceCollection();
        services.AddProjectConfig("non_existent.toml");
        var provider = services.BuildServiceProvider();
        var config = provider.GetRequiredService<IConfiguration>();
        Assert.Equal(1280, config.GetInt("runtime.window", "width", 1280));
    }

    [Fact]
    public void TryAddConfigurationSingleton_DoesNotDuplicateRegistration()
    {
        var services = new ServiceCollection();
        services.AddProjectConfig();
        services.TryAddConfigurationSingleton();

        Assert.Single(services, d => d.ServiceType == typeof(IConfiguration));
    }
}
