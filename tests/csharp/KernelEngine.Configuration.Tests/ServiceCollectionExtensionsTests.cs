using KernelEngine.Configuration;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Pool;
using KernelEngine.TaskPool.Enki;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace KernelEngine.Configuration.Tests;

public class ServiceCollectionExtensionsTests
{
    private static IServiceCollection WithIo() =>
        new ServiceCollection().AddEnkiTaskPool().AddStdFileSystem().AddPoolIo();

    [Fact]
    public void AddProjectConfig_RegistersSingleton()
    {
        var services = WithIo();
        services.AddProjectConfig();
        using var provider = services.BuildServiceProvider();
        var config = provider.GetService<IConfiguration>();
        Assert.NotNull(config);
    }

    [Fact]
    public void AddProjectConfig_MissingFile_FallsBackToDefaults()
    {
        var services = WithIo();
        services.AddProjectConfig("non_existent.toml");
        using var provider = services.BuildServiceProvider();
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

    [Fact]
    public void AddProjectConfig_AfterAnImplicitRegistration_ReadsItsOwnFile()
    {
        var file = Path.Combine(Path.GetTempPath(), $"ke_config_{Guid.NewGuid():N}.toml");
        File.WriteAllText(file, "[runtime.window]\nwidth = 640\n");
        try
        {
            var services = WithIo();
            services.TryAddConfigurationSingleton();
            services.AddProjectConfig(file);

            Assert.Single(services, d => d.ServiceType == typeof(IConfiguration));
            using var provider = services.BuildServiceProvider();
            var config = provider.GetRequiredService<IConfiguration>();
            Assert.Equal(640, config.GetInt("runtime.window", "width", 1280));
        }
        finally
        {
            File.Delete(file);
        }
    }
}
