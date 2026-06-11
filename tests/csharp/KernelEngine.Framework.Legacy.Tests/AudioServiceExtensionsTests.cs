using Xunit;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class AudioServiceExtensionsTests
{
    [Fact]
    public void AddAudioFramework_RegistersIAudioService()
    {
        var services = new ServiceCollection();
        var backend = Substitute.For<IAudio>();
        services.AddSingleton(backend);
        
        services.AddAudioFramework();
        
        var provider = services.BuildServiceProvider();
        var service = provider.GetService<IAudioService>();
        Assert.NotNull(service);
    }
}
