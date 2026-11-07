using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace EngineTests;

public class ServiceCollectionTests
{
    [Fact]
    public void AddInput_RegistersInput()
    {
        var services = new ServiceCollection();
        services.AddInput();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Input>());
        Assert.NotNull(provider.GetService<IInput>());
    }
}
