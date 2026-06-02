using Xunit;
using KernelEngine.Configuration;
using Tomlyn.Model;

namespace KernelEngine.Configuration.Tests;

public class TomlOptionsBinderTests
{
    public class TestOptions
    {
        public string Name { get; set; } = "";
        public int Age { get; set; }
        public float GravityX { get; set; }
        public TestEnum Mode { get; set; }
        public int? NullableInt { get; set; }
    }

    public enum TestEnum
    {
        None,
        Active,
        Disabled
    }

    [Fact]
    public void Apply_BindsSimpleProperty()
    {
        var table = new TomlTable { ["name"] = "Test" };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal("Test", options.Name);
    }

    [Fact]
    public void Apply_BindsSnakeCaseToPascalCase()
    {
        var table = new TomlTable { ["gravity_x"] = 9.81 };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal(9.81f, options.GravityX);
    }

    [Fact]
    public void Apply_IgnoresUnknownKeys()
    {
        var table = new TomlTable { ["unknown"] = 123 };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        // Should not crash
    }

    [Fact]
    public void Apply_ThrowsOnTypeMismatch()
    {
        var table = new TomlTable { ["age"] = "not an int" };
        var options = new TestOptions();
        Assert.Throws<InvalidOperationException>(() => TomlOptionsBinder.Apply(table, options));
    }

    [Fact]
    public void Apply_BindsEnumString()
    {
        var table = new TomlTable { ["mode"] = "Active" };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal(TestEnum.Active, options.Mode);
    }

    [Fact]
    public void Apply_BindsEnumInt()
    {
        var table = new TomlTable { ["mode"] = 2L }; // Tomlyn uses long
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal(TestEnum.Disabled, options.Mode);
    }

    [Fact]
    public void Apply_BindsNumericCoercion()
    {
        var table = new TomlTable { ["age"] = 25L };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal(25, options.Age);
    }

    [Fact]
    public void Apply_BindsNullable()
    {
        var table = new TomlTable { ["nullable_int"] = 42L };
        var options = new TestOptions();
        TomlOptionsBinder.Apply(table, options);
        Assert.Equal(42, options.NullableInt);
    }
}
