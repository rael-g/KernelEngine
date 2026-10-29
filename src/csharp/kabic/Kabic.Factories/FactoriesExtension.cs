using System.Text;

using Kabic.Bindings;
using Kabic.CSharp;
using Kabic.Pipeline;

namespace Kabic.Factories;

/// <summary>
/// One factory of a bindings project, read from its header: the function, its config struct when
/// it takes one, the contract its handle belongs to, and the names the managed class is spelled with.
/// </summary>
public sealed record Factory(
    BindingJob Job,
    string ProjectDir,
    string ManagedNamespace,
    ApiFunction Function,
    ApiStruct? Config,
    DomainModel Contract,
    string ContractClass,
    string ClassName,
    string HandleType,
    IReadOnlyList<FactoryArgument> Arguments);

/// <summary>
/// A dependency of a factory, or a field of its config struct, as the constructor argument it
/// becomes; <see cref="Field"/> is the config field it fills, null for a dependency.
/// </summary>
public sealed record FactoryArgument(string? Doc, string? Field, string Name, string ManagedType, string Assign, bool IsString);

/// <summary>
/// Projects the factory of each bindings project its manifest section names into a partial class
/// deriving from the class of the contract the factory's handle belongs to, constructed from the
/// factory's dependencies, then the fields of its config struct. Section: <c>{"bindings": ["&lt;binding name&gt;", ...]}</c>.
/// </summary>
public sealed class FactoriesExtension : IKabicExtension
{
    /// <inheritdoc/>
    public string Name => "factories";

    /// <summary>
    /// The factories of every bindings project the section of <paramref name="context"/> names. A
    /// factory that cannot be projected is reported through the context and left out.
    /// </summary>
    public static IReadOnlyList<Factory> Read(ExtensionContext context)
    {
        var names = context.Options?["bindings"]?.AsArray().Select(n => n!.GetValue<string>()).ToList() ?? [];
        if (names.Count == 0) return [];
        var jobs = BindingsPlanner.Plan(context.Root, context.ManifestPath).ToDictionary(j => j.Name);
        var factories = new List<Factory>();
        foreach (var name in names)
        {
            if (!jobs.TryGetValue(name, out var job))
            {
                context.Report($"factories: no bindings entry is called '{name}'");
                continue;
            }
            if (Of(context, job) is { } factory) factories.Add(factory);
        }
        return factories;
    }

    /// <inheritdoc/>
    public void Run(ExtensionContext context)
    {
        foreach (var f in Read(context))
            context.Emit(Path.Combine(Path.GetRelativePath(context.Root, f.ProjectDir), "Generated", $"{f.ClassName}.g.cs").Replace('\\', '/'), Render(f, context.Convention));
    }

    private static Factory? Of(ExtensionContext context, BindingJob job)
    {
        string Full(string p) => Path.GetFullPath(Path.Combine(job.NativeDir, p));
        var convention = context.Convention;
        var model = context.ReadHeaders(job.Traverse.Select(Full), job.IncludeDirectories.Select(Full), []);
        var functions = model.Functions.Where(f => convention.IsFactoryName(f.Name)).ToList();
        if (functions.Count != 1)
        {
            context.Report($"factories: {job.Name} declares {functions.Count} factories; one is projected");
            return null;
        }
        var function = functions[0];
        if (function.Params is not [.., var outParam] || !convention.IsHandleType(Bare(outParam.Type)))
        {
            context.Report($"factories: {function.Name} does not end in a <handle>* out; it is not projected");
            return null;
        }
        var handleType = Bare(outParam.Type);
        var contractName = handleType[..^convention.HandleSuffix.Length];
        var contract = context.Domains.FirstOrDefault(d => d.Model.Structs.Any(s => s.Name == contractName && !s.External));
        if (contract is null)
        {
            context.Report($"factories: {function.Name} makes a {contractName}, which no domain declares");
            return null;
        }
        var arguments = new List<FactoryArgument>();
        ApiStruct? config = null;
        foreach (var param in function.Params.Take(function.Params.Count - 1))
        {
            if (config is not null)
            {
                context.Report($"factories: {function.Name} takes {param.Name} after its config; it is not projected");
                return null;
            }
            if (Dependency(context, param) is { } dependency)
                arguments.Add(dependency);
            else if (model.Structs.FirstOrDefault(s => s.Name == Bare(param.Type)) is { } configStruct && param.Type.Contains('*'))
            {
                config = configStruct;
                foreach (var field in configStruct.Fields)
                {
                    if (Argument(context, field) is { } argument) arguments.Add(argument);
                    else context.Report($"factories: {configStruct.Name}.{field.Name} ({field.Type}) has no projection");
                }
            }
            else
            {
                context.Report($"factories: {function.Name}'s {param.Name} ({param.Type}) is neither a contract nor a config; it is not projected");
                return null;
            }
        }
        var contractClass = Idioms.TypeName(contractName, convention);
        var stem = convention.StripPrefix(function.Name)[..^convention.FactorySuffix.Length];
        var contractStem = convention.StripPrefix(contractName);
        var plugin = stem.StartsWith(contractStem + "_", StringComparison.Ordinal) ? stem[(contractStem.Length + 1)..] : stem;
        var projectDir = Path.GetDirectoryName(job.NativeDir.TrimEnd('/', '\\'))!;
        var managedNamespace = job.Namespace.EndsWith(".Native", StringComparison.Ordinal) ? job.Namespace[..^".Native".Length] : job.Namespace;
        return new Factory(job, projectDir, managedNamespace, function, config, contract,
            $"{contract.Spec.Namespace}.{contractClass}", Idioms.Pascal(plugin) + contractClass, handleType, arguments);
    }

    private static FactoryArgument? Dependency(ExtensionContext context, ApiParam param)
    {
        var type = param.Type.Replace("const ", "").Replace("struct ", "").Trim();
        if (!type.EndsWith('*')) return null;
        var target = type.TrimEnd('*', ' ');
        var domain = context.Domains.FirstOrDefault(d => d.Model.Structs.Any(s => s.Name == target && !s.External && s.IsVtable));
        if (domain is null) return null;
        var name = Idioms.Ident(param.Name ?? target);
        return new FactoryArgument(param.Doc, null, name, $"{domain.Spec.Namespace}.{Idioms.NativeInterface(target, context.Convention)}", $"{name}.Native", false);
    }

    private static FactoryArgument? Argument(ExtensionContext context, ApiField field)
    {
        var name = Idioms.Ident(field.Name);
        var type = field.Type.Replace("const ", "").Replace("struct ", "").Trim();
        if (field.Has("provider") && type.EndsWith('*'))
        {
            var target = type.TrimEnd('*', ' ');
            var domain = context.Domains.FirstOrDefault(d => d.Model.Structs.Any(s => s.Name == target && !s.External));
            if (domain is null) return null;
            var iface = $"{domain.Spec.Namespace}.{Idioms.NativeInterface(target, context.Convention)}";
            return new FactoryArgument(field.Doc, field.Name, name, iface, $"{name}.Native", false);
        }
        if (field.Has("utf8") && type == "char *")
            return new FactoryArgument(field.Doc, field.Name, name, "string?", "", true);
        if (type.Contains('*')) return null;
        return new FactoryArgument(field.Doc, field.Name, name, Idioms.CsPrimitive(type, context.Convention), name, false);
    }

    private static string Bare(string cType) => cType.Replace("const ", "").Replace("struct ", "").Trim().TrimEnd('*', ' ');

    private static string Render(Factory f, Convention convention)
    {
        var o = new StringBuilder();
        o.Append("// <auto-generated/>\n// Derived from the factory header. Do not edit; edit the header instead.\n\n#nullable enable\n\n");
        o.Append($"namespace {f.ManagedNamespace};\n\n");
        o.Append($"/// <summary>{Xml(f.Function.Doc)}</summary>\n");
        o.Append($"public sealed unsafe partial class {f.ClassName} : {f.ContractClass}\n{{\n");
        o.Append($"    /// <summary>{Xml(f.Function.Doc)}</summary>\n");
        foreach (var a in f.Arguments)
            o.Append($"    /// <param name=\"{a.Name}\">{Xml(a.Doc)}</param>\n");
        o.Append($"    public {f.ClassName}({Parameters(f)}) : base(Create({Names(f)}))\n    {{\n    }}\n\n");
        o.Append($"    private static {f.Contract.Spec.NativeNamespace}.{f.HandleType} Create({Parameters(f, withDefaults: false)})\n    {{\n");
        foreach (var a in f.Arguments.Where(a => a.ManagedType.Contains(".INative")))
            o.Append($"        ArgumentNullException.ThrowIfNull({a.Name});\n");
        foreach (var a in f.Arguments.Where(a => a.IsString))
            o.Append($"        var {a.Name}Bytes = {a.Name} is null ? null : System.Text.Encoding.UTF8.GetBytes({a.Name} + \"\\0\");\n");
        foreach (var a in f.Arguments.Where(a => a.IsString))
            o.Append($"        fixed (byte* {a.Name}Ptr = {a.Name}Bytes)\n");
        var strings = f.Arguments.Any(a => a.IsString);
        var pad = strings ? "            " : "        ";
        if (strings) o.Append("        {\n");
        if (f.Config is not null)
        {
            o.Append($"{pad}{f.Job.Namespace}.{f.Config.Name} config = default;\n");
            foreach (var a in f.Arguments.Where(a => a.Field is not null))
                o.Append($"{pad}config.{a.Field} = {(a.IsString ? $"(sbyte*){a.Name}Ptr" : a.Assign)};\n");
        }
        o.Append($"{pad}{f.Contract.Spec.NativeNamespace}.{f.HandleType} handle;\n");
        var call = f.Arguments.Where(a => a.Field is null).Select(a => a.Assign).Concat(f.Config is null ? [] : ["&config"]).Append("&handle");
        o.Append($"{pad}{convention.ResultHelperClass}.ThrowIfFailed({f.Job.Namespace}.{f.Job.MethodsClass}.{convention.StripPrefix(f.Function.Name)}({string.Join(", ", call)}), \"{f.Function.Name}\");\n");
        o.Append($"{pad}return handle;\n");
        if (strings) o.Append("        }\n");
        o.Append("    }\n}\n");
        return o.ToString();
    }

    /// <summary>
    /// The constructor's parameter list. A scalar or a string defaults to zero, which selects the
    /// factory's default, unless a provider, which has no default, comes after it.
    /// </summary>
    public static string Parameters(Factory f, bool withDefaults = true)
    {
        var lastProvider = f.Arguments.ToList().FindLastIndex(a => a.ManagedType.Contains(".INative"));
        return string.Join(", ", f.Arguments.Select((a, i) =>
            $"{a.ManagedType} {a.Name}{(withDefaults && i > lastProvider ? " = default" : "")}"));
    }

    /// <summary>The constructor's argument names, in order.</summary>
    public static string Names(Factory f) => string.Join(", ", f.Arguments.Select(a => a.Name));

    private static string Xml(string? text) =>
        (text ?? "").Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\n", " ").Trim();
}
