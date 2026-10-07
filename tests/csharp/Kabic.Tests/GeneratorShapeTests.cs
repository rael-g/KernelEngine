namespace Kabic.Tests;

public sealed class GeneratorShapeTests
{
    public static TheoryData<string> Shapes()
    {
        var data = new TheoryData<string>();
        foreach (var name in GeneratorShapeCases.All().Keys) data.Add(name);
        return data;
    }

    [Theory]
    [MemberData(nameof(Shapes))]
    public void EmitsTheDeclaredShape(string shape)
    {
        var failures = new List<string>();
        GeneratorShapeCases.All()[shape](failures);
        Assert.True(failures.Count == 0, string.Join('\n', failures));
    }
}
