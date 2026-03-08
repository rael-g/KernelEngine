using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class ApplicationTests
{
    [Fact]
    public void Application_CanBeInstantiated()
    {
        using var app = new Application();
        Assert.NotNull(app);
    }
}
