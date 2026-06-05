using Xunit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using KernelEngine.Configuration;

namespace KernelEngine.Configuration.Tests;

public class ServiceCollectionExtensionsTests
{
    public class TestOptions
    {
        public string Name { get; set; } = "Default";
    }

    [Fact]
    public void AddProjectConfig_RegistersSingleton()
    {
        var services = new ServiceCollection();
        services.AddProjectConfig();
        var provider = services.BuildServiceProvider();
        var config = provider.GetService<IProjectConfig>();
        Assert.NotNull(config);
    }

    [Fact]
    public void AddProjectConfigSection_RegistersOptions()
    {
        var services = new ServiceCollection();
        services.AddProjectConfigSection<TestOptions>("test");
        var provider = services.BuildServiceProvider();
        var options = provider.GetService<IOptions<TestOptions>>();
        Assert.NotNull(options);
    }

    [Fact]
    public void AddProjectConfigSection_UsesDefaults_WhenSectionMissing()
    {
        var services = new ServiceCollection();
        // Force a config that won't have the section
        services.AddSingleton<IProjectConfig>(new ProjectConfig(null));
        services.AddProjectConfigSection<TestOptions>("missing");
        
        var provider = services.BuildServiceProvider();
        var options = provider.GetRequiredService<IOptions<TestOptions>>().Value;
        
        Assert.Equal("Default", options.Name);
    }
}
