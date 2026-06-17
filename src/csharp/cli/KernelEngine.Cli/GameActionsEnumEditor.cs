using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;

namespace KernelEngine.Cli;

/// <summary>
/// Locates the single enum decorated with <c>[GameActions]</c> in the project and appends a new
/// member without disturbing the rest of the file. Roslyn is used to *find* the insertion point;
/// the edit itself is a text splice so the user's hand-formatted alignment, comments, and
/// whitespace stay byte-identical outside of the inserted line.
/// </summary>
public static class GameActionsEnumEditor
{
    public sealed record Location(string FilePath, string EnumName);

    public static Location AddMember(string projectDirectory, string memberName)
    {
        var (path, text, decl) = FindEnum(projectDirectory);

        if (decl.Members.Any(m => m.Identifier.Text == memberName))
            throw new InvalidOperationException(
                $"Enum '{decl.Identifier.Text}' already declares '{memberName}'. Nothing to do.");

        var updated = InsertMember(text, decl, memberName);
        File.WriteAllText(path, updated);
        return new Location(path, decl.Identifier.Text);
    }

    private static string InsertMember(SourceText text, EnumDeclarationSyntax decl, string memberName)
    {
        var raw  = text.ToString();
        var nl   = raw.Contains("\r\n") ? "\r\n" : "\n";

        // Empty enum body — splice between the braces.
        if (decl.Members.Count == 0)
        {
            var enumLineStart = raw.LastIndexOf('\n', decl.SpanStart - 1) + 1;
            var enumIndent = raw.Substring(enumLineStart, decl.SpanStart - enumLineStart);
            var indent0 = enumIndent + "    ";
            var emptySplice = decl.CloseBraceToken.SpanStart;
            return raw.Substring(0, emptySplice) + $"{nl}{indent0}{memberName},{nl}{enumIndent}" + raw.Substring(emptySplice);
        }

        // Mirror the indentation of an existing member.
        var first = decl.Members[0];
        var firstLineStart = raw.LastIndexOf('\n', first.SpanStart - 1) + 1;
        var indent = raw.Substring(firstLineStart, first.SpanStart - firstLineStart);

        // FullSpan of the last separator (when present) includes its trailing trivia — that's the
        // line-end comment + newline after `Quit, // Button`. Splicing there means the new line
        // lands cleanly under the previous member without intruding on its comment.
        var separators = decl.Members.GetSeparators().ToList();
        int spliceAt;
        string prefix;
        if (separators.Count == decl.Members.Count)
        {
            spliceAt = separators[^1].FullSpan.End;
            prefix   = "";
        }
        else
        {
            // Last member has no trailing comma. FullSpan covers its trailing trivia (comment + nl).
            spliceAt = decl.Members[^1].FullSpan.End;
            prefix   = ","; // injected at end of the previous member's line, before its trailing newline
            // Step back over the line-terminator so the comma lands on the same line as the member.
            while (spliceAt > 0 && (raw[spliceAt - 1] == '\n' || raw[spliceAt - 1] == '\r')) spliceAt--;
        }

        var insertion = prefix == ""
            ? $"{indent}{memberName},{nl}"
            : $"{prefix}{nl}{indent}{memberName},{nl}";
        return raw.Substring(0, spliceAt) + insertion + raw.Substring(spliceAt);
    }

    private static (string path, SourceText text, EnumDeclarationSyntax decl) FindEnum(string projectDirectory)
    {
        var candidates = new List<(string path, SourceText text, EnumDeclarationSyntax decl)>();
        foreach (var file in Directory.EnumerateFiles(projectDirectory, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase)) continue;
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase)) continue;

            var raw = File.ReadAllText(file);
            if (!raw.Contains("GameActions", StringComparison.Ordinal)) continue;

            var text = SourceText.From(raw);
            var tree = CSharpSyntaxTree.ParseText(text);
            foreach (var e in tree.GetRoot().DescendantNodes().OfType<EnumDeclarationSyntax>())
            {
                if (HasGameActionsAttribute(e))
                    candidates.Add((file, text, e));
            }
        }

        return candidates.Count switch
        {
            0 => throw new InvalidOperationException(
                $"No enum marked with [GameActions] was found under {projectDirectory}. " +
                "Mark one of your enums with [GameActions] before adding actions to it."),
            1 => candidates[0],
            _ => throw new InvalidOperationException(
                $"Multiple [GameActions] enums found ({string.Join(", ", candidates.Select(c => $"{c.decl.Identifier.Text} in {c.path}"))}). " +
                "The framework supports only one — remove the extras."),
        };
    }

    private static bool HasGameActionsAttribute(EnumDeclarationSyntax e) =>
        e.AttributeLists.SelectMany(l => l.Attributes)
            .Any(a => a.Name.ToString() is "GameActions" or "GameActionsAttribute");
}
