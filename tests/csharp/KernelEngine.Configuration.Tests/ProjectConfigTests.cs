using Xunit;
using KernelEngine.Configuration;
using Tomlyn.Model;

namespace KernelEngine.Configuration.Tests;

public class ProjectConfigTests
{
    [Fact]
    public void IsLoaded_ReturnsFalse_WhenPathIsNull()
    {
        var config = new ProjectConfig(null);
        Assert.False(config.IsLoaded);
    }

    [Fact]
    public void IsLoaded_ReturnsFalse_WhenFileDoesNotExist()
    {
        var config = new ProjectConfig("non_existent.toml");
        Assert.False(config.IsLoaded);
    }

    [Fact]
    public void IsLoaded_ReturnsTrue_WhenFileExists()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "key = \"value\"");
        try
        {
            var config = new ProjectConfig(path);
            Assert.True(config.IsLoaded);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void GetSection_ReturnsNull_WhenNotLoaded()
    {
        var config = new ProjectConfig(null);
        Assert.Null(config.GetSection("section"));
    }

    [Fact]
    public void GetSection_ReturnsNull_WhenPathIsEmpty()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "[section]\nkey = \"value\"");
        try
        {
            var config = new ProjectConfig(path);
            Assert.Null(config.GetSection(""));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void GetSection_ReturnsSection_WhenPathIsCorrect()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "[section]\nkey = \"value\"");
        try
        {
            var config = new ProjectConfig(path);
            var section = config.GetSection("section");
            Assert.NotNull(section);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void GetSection_ReturnsNestedSection_WhenPathHasDots()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "[a.b.c]\nkey = \"value\"");
        try
        {
            var config = new ProjectConfig(path);
            var section = config.GetSection("a.b.c");
            Assert.NotNull(section);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void GetSection_ReturnsNull_WhenSegmentNotFound()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "[a]\nkey = \"value\"");
        try
        {
            var config = new ProjectConfig(path);
            Assert.Null(config.GetSection("a.b"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void GetSection_ReturnsNull_WhenNotATable()
    {
        string path = Path.GetTempFileName();
        File.WriteAllText(path, "a = 1");
        try
        {
            var config = new ProjectConfig(path);
            Assert.Null(config.GetSection("a"));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
