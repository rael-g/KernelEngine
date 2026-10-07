using Kabic.Numerics;

namespace Kabic.Tests;

public sealed class NumericsPackTests
{
    static readonly NumericsPack Pack = new();

    static ApiModel ModelWith(string name, string[] tags, params string[] floats)
    {
        var m = new ApiModel();
        m.Structs.Add(new ApiStruct(name, null, tags, floats.Select(l => new ApiField(l, "float", [], null)).ToList(), []));
        return m;
    }

    [Fact]
    public void AStructIsAVectorOnlyWhenTheHeaderSaysSo()
    {
        Assert.Null(Pack.Recognize(ModelWith("my_color", [], "r", "g", "b"), "my_color"));

        var shape = Pack.Recognize(ModelWith("my_point", ["vector"], "x", "y", "z"), "my_point");
        Assert.Equal(NumericsPack.Vector, shape!.Kind);
        Assert.Equal(["x", "y", "z"], shape.Lanes);
    }

    [Fact]
    public void ATaggedStructOfFourFloatsCanBeAQuaternion()
    {
        var shape = Pack.Recognize(ModelWith("my_rot", ["quaternion"], "x", "y", "z", "w"), "my_rot")!;

        Assert.Equal("Quaternion", Pack.Project(Languages.CSharp, shape));
        Assert.Equal("quat", Pack.Project(Languages.FieldTable, shape));
    }

    [Fact]
    public void ABareFloatArrayOfTwoToFourIsAVector()
    {
        var shape = Pack.Recognize(new ApiModel(), "float[3]")!;

        Assert.Equal("Vector3", Pack.Project(Languages.CSharp, shape));
        Assert.Null(Pack.Recognize(new ApiModel(), "float[5]"));
    }

    [Fact]
    public void ALanguageThePackDoesNotKnowKeepsThePlainStruct()
    {
        var shape = Pack.Recognize(new ApiModel(), "float[2]")!;

        Assert.Null(Pack.Project("zig", shape));
        Assert.Empty(Pack.Imports("zig"));
        Assert.Equal(["System.Numerics"], Pack.Imports(Languages.CSharp));
    }

    [Fact]
    public void ParametersTaggedAsAVectorFormOneGroup()
    {
        var first = new ApiParam("x", "float", ["vector2:position"], null);

        var group = Pack.GroupOf(first)!;

        Assert.Equal("position", group.Name);
        Assert.Equal(2, group.Shape.Lanes.Count);
        Assert.Null(Pack.GroupOf(new ApiParam("n", "float", [], null)));
    }

    [Fact]
    public void AConventionWithoutThePackNamesNoShape()
    {
        var without = new ConventionBuilder().Build();
        var with = new ConventionBuilder().UseNumerics().Build();

        Assert.Null(without.Project(Languages.CSharp, new ApiModel(), "float[3]"));
        Assert.Equal("Vector3", with.Project(Languages.CSharp, new ApiModel(), "float[3]"));
    }
}
