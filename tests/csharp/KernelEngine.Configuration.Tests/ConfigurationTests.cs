using Xunit;
using KernelEngine.Configuration;

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

    [Fact]
    public void SetFloatArray_ThenGetFloatArray_RoundTrips()
    {
        using var cfg = new Configuration();
        cfg.SetFloatArray("render", "clear_color", [0.04f, 0.04f, 0.08f, 1.0f]);
        var result = cfg.GetFloatArray("render", "clear_color", [0f, 0f, 0f, 0f]);
        Assert.Equal([0.04f, 0.04f, 0.08f, 1.0f], result);
    }

    [Fact]
    public void GetFloatArray_ReturnsFallback_WhenKeyMissing()
    {
        using var cfg = new Configuration();
        var result = cfg.GetFloatArray("render", "clear_color", [0.1f, 0.2f, 0.3f, 1.0f]);
        Assert.Equal([0.1f, 0.2f, 0.3f, 1.0f], result);
    }

    [Fact]
    public void LoadToml_MissingFile_IsNoOp()
    {
        using var cfg = new Configuration();
        cfg.LoadToml("non_existent.toml");
        Assert.Equal(1280, cfg.GetInt("runtime.window", "width", 1280));
    }

    [Fact]
    public void LoadToml_PopulatesStore_FromDottedSections()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "[runtime.window]\nwidth = 800\ntitle = \"Test\"\nfullscreen = true\n");
        try
        {
            using var cfg = new Configuration();
            cfg.LoadToml(path);
            Assert.Equal(800, cfg.GetInt("runtime.window", "width", 0));
            Assert.Equal("Test", cfg.GetString("runtime.window", "title", ""));
            Assert.True(cfg.GetBool("runtime.window", "fullscreen", false));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
