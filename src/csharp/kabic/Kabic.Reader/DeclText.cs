
using System.Text.RegularExpressions;

namespace Kabic.Reader;

/// <summary>
/// Reads the parameter names of a function-pointer field from the bytes of its header.
/// </summary>
public static class DeclText
{
    /// <summary>
    /// Returns the parameter names of the function-pointer field <paramref name="fieldName"/>,
    /// read from <paramref name="sourceBytes"/>, in declaration order. Returns an empty list when
    /// no such declarator is found.
    /// </summary>
    public static List<string?> FnPtrParamNames(byte[] sourceBytes, string fieldName)
    {
        var text = System.Text.Encoding.UTF8.GetString(sourceBytes);
        var m = Regex.Match(text, @"\(\s*\*\s*" + Regex.Escape(fieldName) + @"\s*\)\s*\(");
        if (!m.Success) return [];
        return ParamsFrom(text, m.Index + m.Length - 1);
    }

    /// <summary>
    /// Splits a balanced-parens argument list starting right after `(` at `openParen`,
    /// pulling the trailing identifier off each comma-separated parameter.
    /// </summary>
    static List<string?> ParamsFrom(string text, int openParen)
    {
        var depth = 0;
        var start = -1;
        for (var i = openParen; i < text.Length; i++)
        {
            if (text[i] == '(') { depth++; if (start < 0) start = i + 1; }
            else if (text[i] == ')') { depth--; if (depth == 0) return SplitParams(text[start..i]); }
        }
        return [];
    }

    static readonly Regex TrailingIdent = new(@"([A-Za-z_]\w*)\s*(\[\s*\w*\s*\])?\s*$");

    static List<string?> SplitParams(string inner)
    {
        var result = new List<string?>();
        var depth = 0;
        var cur = "";
        foreach (var ch in inner + ",")
        {
            if (ch == ',' && depth == 0)
            {
                var m = TrailingIdent.Match(cur.Trim());
                result.Add(m.Success ? m.Groups[1].Value : null);
                cur = "";
            }
            else
            {
                if (ch is '(' or '[') depth++;
                if (ch is ')' or ']') depth--;
                cur += ch;
            }
        }
        return result;
    }
}
