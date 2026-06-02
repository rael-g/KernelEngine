using Xunit;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class InputActionsLoaderTests
{
    public enum GameAction { Jump, Move, Look }

    [Fact]
    public void LoadFromToml_ValidInput_ReturnsPopulatedMap()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [
    { kind = ""key"", key = ""Space"" }
]

[action.Move]
type = ""Axis2D""
bindings = [
    { kind = ""key_quad"", up = ""W"", down = ""S"", left = ""A"", right = ""D"" }
]
";
        var map = InputActionsLoader.LoadFromToml<GameAction>(toml);

        Assert.Equal(2, ((IInputActionMap)map).Actions.Count);
        
        var jumpAction = ((IInputActionMap)map).Actions.First(a => a.ActionId == (int)GameAction.Jump);
        Assert.Single(jumpAction.Bindings);
        Assert.Equal(ActionType.Button, jumpAction.Type);

        var moveAction = ((IInputActionMap)map).Actions.First(a => a.ActionId == (int)GameAction.Move);
        Assert.Single(moveAction.Bindings);
        Assert.Equal(ActionType.Axis2D, moveAction.Type);
    }

    [Fact]
    public void LoadFromFile_Works()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ { kind = ""key"", key = ""Space"" } ]
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            var map = InputActionsLoader.LoadFromFile<GameAction>(path);
            Assert.Single(((IInputActionMap)map).Actions);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void LoadFromFile_Throws_WhenMissing()
    {
        Assert.Throws<FileNotFoundException>(() => InputActionsLoader.LoadFromFile<GameAction>("missing.input"));
    }

    [Fact]
    public void LoadFromToml_AllBindingKinds_Work()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [
    { kind = ""key"", key = ""Space"" },
    { kind = ""mouse"", button = ""Left"" }
]

[action.Move]
type = ""Axis1D""
bindings = [
    { kind = ""key_pair"", negative = ""A"", positive = ""D"" }
]

[action.Look]
type = ""Axis2D""
bindings = [
    { kind = ""key_quad"", up = ""W"", down = ""S"", left = ""Q"", right = ""E"" }
]
";
        var map = InputActionsLoader.LoadFromToml<GameAction>(toml);
        var actions = ((IInputActionMap)map).Actions;
        
        Assert.Equal(3, actions.Count);
        Assert.Equal(2, actions.First(a => a.ActionId == (int)GameAction.Jump).Bindings.Count);
        Assert.Single(actions.First(a => a.ActionId == (int)GameAction.Move).Bindings);
        Assert.Single(actions.First(a => a.ActionId == (int)GameAction.Look).Bindings);
    }

    [Fact]
    public void LoadFromToml_Throws_WhenActionEntryNotTable()
    {
        string toml = "action = { Jump = 123 }";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void LoadFromToml_Throws_WhenActionTypeInvalid()
    {
        string toml = @"
[action.Jump]
type = ""InvalidType""
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void LoadFromToml_Throws_WhenBindingsNotArray()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = {}
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void LoadFromToml_Throws_WhenBindingEntryNotTable()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ 123 ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void BuildBinding_Throws_WhenKindMissing()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ {} ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void ParseKey_Throws_WhenKeyFieldMissing()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ { kind = ""key"" } ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void ParseKey_Throws_WhenKeyValueInvalid()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ { kind = ""key"", key = ""NotAKey"" } ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void ParseMouseButton_Throws_WhenButtonFieldMissing()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ { kind = ""mouse"" } ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }

    [Fact]
    public void ParseMouseButton_Throws_WhenButtonValueInvalid()
    {
        string toml = @"
[action.Jump]
type = ""Button""
bindings = [ { kind = ""mouse"", button = ""NotAButton"" } ]
";
        Assert.Throws<InvalidDataException>(() => InputActionsLoader.LoadFromToml<GameAction>(toml));
    }
}
