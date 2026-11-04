using KernelEngine.Configuration;

using Xunit;

namespace KernelEngine.Configuration.Tests;

public class ConfigurationTests
{
    [Fact]
    public void GetInt_ReturnsFallback_WhenKeyMissing()
    {
        using var cfg = new Configuration();
        Assert.Equal(42, cfg.GetInt("section", "key", 42));
    }

    [Fact]
    public void SetInt_ThenGetInt_RoundTrips()
    {
        using var cfg = new Configuration();
        cfg.SetInt("section", "key", 7);
        Assert.Equal(7, cfg.GetInt("section", "key", 0));
    }

    [Fact]
    public void SetString_ThenGetString_RoundTrips()
    {
        using var cfg = new Configuration();
        cfg.SetString("runtime.window", "title", "Hello");
        Assert.Equal("Hello", cfg.GetString("runtime.window", "title", "fallback"));
    }

    [Fact]
    public void SetBool_ThenGetBool_RoundTrips()
    {
        using var cfg = new Configuration();
        cfg.SetBool("runtime.window", "fullscreen", true);
        Assert.True(cfg.GetBool("runtime.window", "fullscreen", false));
    }

    [Fact]
    public void SetDouble_ThenGetDouble_RoundTrips()
    {
        using var cfg = new Configuration();
        cfg.SetDouble("runtime.physics_2d", "gravity_y", -9.81);
        Assert.Equal(-9.81, cfg.GetDouble("runtime.physics_2d", "gravity_y", 0.0));
    }

}
