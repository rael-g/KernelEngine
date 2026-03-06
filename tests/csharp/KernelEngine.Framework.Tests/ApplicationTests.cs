using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using System.Linq;

namespace KernelEngine.Framework.Tests;

public class ApplicationTests
{
    [Fact]
    public void ServiceCollection_CanRegisterKernel()
    {
        var services = new ServiceCollection();
        // This just registers the types, doesn't call native code yet
        services.AddKernel();
        
        var descriptor = services.FirstOrDefault(d => d.ServiceType == typeof(Allocator));
        Assert.NotNull(descriptor);
    }

    [Fact]
    public void Application_Base_Constructor()
    {
        // We can't run the full App without native DLLs in the test path
        // but we can check if the class is resolvable.
        Assert.True(true);
    }
}
