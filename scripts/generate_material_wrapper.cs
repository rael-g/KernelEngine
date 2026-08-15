#!/usr/bin/env dotnet run

using System.Text.RegularExpressions;

string? material = null, template = null, output = null;

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--material": material = args[++i]; break;
        case "--template": template = args[++i]; break;
        case "--output": output = args[++i]; break;
        default:
            Console.Error.WriteLine($"Unknown argument: {args[i]}");
            return 1;
    }
}

if (material is null || template is null || output is null)
{
    Console.Error.WriteLine("Error: --material, --template and --output are required.");
    return 1;
}

var materialSrc = await File.ReadAllTextAsync(material);
var structName = FindMaterialStruct(materialSrc, material);
if (structName is null) return 1;

var moduleName = Path.GetFileNameWithoutExtension(material);

var wrapper = (await File.ReadAllTextAsync(template))
    .Replace("@MATERIAL_MODULE@", moduleName)
    .Replace("@MATERIAL_STRUCT@", structName);

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
await File.WriteAllTextAsync(output, wrapper);
return 0;

static string? FindMaterialStruct(string source, string path)
{
    var matches = Regex.Matches(source, @"^\s*struct\s+(\w+)\s*:\s*IMaterial\b", RegexOptions.Multiline);
    if (matches.Count == 0)
    {
        Console.Error.WriteLine($"{path}: no `struct <Name> : IMaterial` found — an authored " +
                                 "material must declare its IMaterial conformance.");
        return null;
    }
    if (matches.Count > 1)
    {
        var names = string.Join(", ", matches.Select(m => m.Groups[1].Value));
        Console.Error.WriteLine($"{path}: {matches.Count} IMaterial structs ({names}) " +
                                 "— one material per file, so the file name identifies it.");
        return null;
    }
    return matches[0].Groups[1].Value;
}
