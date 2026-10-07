namespace Kabic;

/// <summary>
/// The naming and shape conventions of the C ABI being compiled — everything
/// `kabic` "knows" about its consumer that is NOT intrinsic to C itself.
/// </summary>
/// <summary>A C type and the managed type that occupies the same bytes.</summary>
public sealed record ValueTypeMapping(string Managed, string[] Lanes);

/// <summary>What a scene file can write for a component field.</summary>
public enum FieldKind { Bool, Int, Float, String, Vec2, Vec3, Vec4, Quat }

/// <summary>How one kind of field is spelled in the generated table.</summary>
public sealed record FieldVariant(string Constant, string Member);

/// <summary>
/// How a component struct is described to the runtime that applies a scene file to it:
/// the entry type of the table, the header declaring it, and the spelling of every kind of
/// field. A convention without one has no field tables.
/// </summary>
public sealed record FieldTableConvention(
    string EntryType,
    string Include,
    string NameMacroPrefix,
    string NullVariant,
    IReadOnlyDictionary<string, FieldKind> ValueTypes,
    IReadOnlyDictionary<FieldKind, FieldVariant> Variants);

/// <summary>A kind of failure the ABI names, and the singleton a failure of that kind is reached by.</summary>
public sealed record ErrorKind(string Name, string Singleton);

public sealed class Convention
{
    /// <summary>Prefix every public symbol in this ABI carries (<c>ke_input</c>, <c>ke_logger_create</c>).</summary>
    public required string SymbolPrefix { get; init; }

    /// <summary>
    /// Suffix marking an owner-wrapper struct (<c>ke_input_handle{ref, destroy}</c>) — a plain
    /// lifetime holder, not a vtable a caller registers a provider or callback for.
    /// </summary>
    public required string HandleSuffix { get; init; }

    /// <summary>Suffix marking a factory function for the vtable it is named after (<c>ke_input_create</c>).</summary>
    public required string FactorySuffix { get; init; }

    /// <summary>
    /// Suffix marking a parameter bag (<c>ke_runtime_system_params</c>) — a value the caller
    /// fills in and passes by pointer to one call, never an interface. Holding a function
    /// pointer does not make it one: a registration bag carries the callback being registered
    /// (<c>execute</c>, <c>on_load</c>) right next to its plain data fields, so slot count
    /// alone cannot tell the two apart, and mistaking a bag for a vtable emits a wrapper class
    /// with <c>Borrow</c>/<c>Dispose</c> around what is not an object. The ABI guarantees this
    /// suffix for every parameter bag, which is what makes it a sound discriminator.
    /// </summary>
    public required string ParamsSuffix { get; init; }

    /// <summary>Whether a struct name marks a parameter bag rather than an interface.</summary>
    public bool IsParamsType(string structName) => structName.EndsWith(ParamsSuffix);

    /// <summary>
    /// Suffix marking an ECS component struct (<c>ke_point_light_component</c>). Stripped
    /// along with <see cref="SymbolPrefix"/> to recover the name the component is registered
    /// under at runtime (<c>point_light</c>), which is its only cross-language identity.
    /// </summary>
    public required string ComponentSuffix { get; init; }

    /// <summary>Whether a struct name marks an ECS component rather than plain value data.</summary>
    public bool IsComponentType(string structName) => structName.EndsWith(ComponentSuffix);

    /// <summary>The registered component name for a component struct (<c>ke_point_light_component</c> → <c>point_light</c>).</summary>
    public string ComponentNameFor(string structName)
    {
        var n = StripPrefix(structName);
        return n.EndsWith(ComponentSuffix) ? n[..^ComponentSuffix.Length] : n;
    }

    /// <summary>
    /// The out-parameter type spelling that makes a slot fallible. A slot returning boolean-true-on-success
    /// whose last parameter is this type reports failure through it rather than through its return value.
    /// </summary>
    public required string ErrorOutParamType { get; init; }

    /// <summary>Boolean return-type spellings that mean "succeeded", paired with <see cref="ErrorOutParamType"/>.</summary>
    public required IReadOnlyList<string> BooleanReturnTypes { get; init; }

    /// <summary>True if <paramref name="structName"/> names an owner-wrapper rather than a real vtable.</summary>
    public bool IsHandleType(string structName) => structName.EndsWith(HandleSuffix);

    /// <summary>The owner-wrapper struct name paired with a given vtable (<c>ke_window</c> → <c>ke_window_handle</c>).</summary>
    public string HandleTypeFor(string vtableName) => vtableName + HandleSuffix;

    /// <summary>The factory function name paired with a given vtable (<c>ke_input</c> → <c>ke_input_create</c>).</summary>
    public string FactoryNameFor(string vtableName) => vtableName + FactorySuffix;

    /// <summary>True if <paramref name="functionName"/> is spelled as a factory for some vtable.</summary>
    public bool IsFactoryName(string functionName) => functionName.EndsWith(FactorySuffix);

    /// <summary>True if this parameter is the trailing error out-parameter that makes a slot fallible.</summary>
    public bool IsErrorOutParam(ApiParam p) =>
        p.Type.Replace(" ", "").Contains(ErrorOutParamType.Replace(" ", ""));

    /// <summary>
    /// True if a slot reports failure through a trailing error out-parameter — whatever
    /// it returns. A boolean-returning slot signals failure with the return value; one
    /// returning a value signals it by writing the out-param (which stays NULL on
    /// success), so both are fallible and neither should expose the parameter.
    /// </summary>
    public bool IsFallible(string returns, IReadOnlyList<ApiParam> parameters) =>
        parameters.Count > 0 && IsErrorOutParam(parameters[^1]);

    /// <summary>True if this slot signals failure through its boolean return rather than by writing the error out-param.</summary>
    public bool SignalsFailureByReturn(string returns) => BooleanReturnTypes.Contains(returns);

    /// <summary>
    /// Explicit target-language type names for ABI symbols whose derived name is
    /// unusable — chiefly a vtable whose name matches its own namespace's last
    /// segment (<c>ke_ecs</c> in <c>KernelEngine.Ecs</c> would derive to
    /// <c>Ecs</c>, forcing every reference to be fully qualified).
    /// </summary>
    public IReadOnlyDictionary<string, string> TypeNameOverrides { get; init; } =
        new Dictionary<string, string>();

    /// <summary>Strips <see cref="SymbolPrefix"/> from a symbol, leaving the rest untouched.</summary>
    public string StripPrefix(string name) =>
        name.StartsWith(SymbolPrefix) ? name[SymbolPrefix.Length..] : name;

    /// <summary>Prefix of a parameter the callee writes back (<c>out_size</c>), which must carry the <c>[out]</c> tag.</summary>
    public string OutParamPrefix { get; init; } = "out_";

    /// <summary>Name of the directory under which a public header lives (<c>kernel_engine/audio/audio.h</c>), so a header is addressed without its install prefix.</summary>
    public string IncludeDirectoryName { get; init; } = "kernel_engine";

    /// <summary>Namespace of the raw bindings every other binding assembly takes its shared types from.</summary>
    public string CommonBindingsNamespace { get; init; } = "";

    /// <summary>Class that holds the raw P/Invoke methods of a binding assembly.</summary>
    public string BindingsMethodsClass { get; init; } = "NativeMethods";

    /// <summary>The C typedef for a boolean that crosses the ABI as one byte (<c>ke_bool</c>), which the managed side widens to <c>bool</c>.</summary>
    public string ByteBoolType { get; init; } = "";

    /// <summary>The C struct a failed call reports through (<c>ke_error</c>).</summary>
    public string ErrorType { get; init; } = "";

    /// <summary>How component structs are described as field tables, or null when this ABI has none.</summary>
    public FieldTableConvention? FieldTable { get; init; }

    /// <summary>The C struct that names the kind of a failure (<c>ke_error_type</c>).</summary>
    public string ErrorKindType { get; init; } = "";

    /// <summary>The exported function that asks whether a failure is of a kind (<c>ke_error_is</c>).</summary>
    public string ErrorIsFunction { get; init; } = "";

    /// <summary>The singleton a failure reads as when no kind matched.</summary>
    public string ErrorGeneralSingleton { get; init; } = "";

    /// <summary>The kinds the error hierarchy names, in the order a projection declares them.</summary>
    public IReadOnlyList<ErrorKind> ErrorKinds { get; init; } = [];

    /// <summary>Zig declarations of the error ABI, written by hand because no description owns them.</summary>
    public string ZigErrorAbi { get; init; } = "";

    /// <summary>The managed class that raises a failure from the native struct and back (<c>ThrowIfFailed</c>, <c>FromNative</c>, <c>ToNative</c>).</summary>
    public string ErrorHelperClass { get; init; } = "";

    /// <summary>Managed namespace the generated projections import for the shared types, beside the bindings namespace.</summary>
    public string CommonManagedNamespace { get; init; } = "";

    /// <summary>C vector types and the managed type that occupies the same bytes, with the lanes of the C struct in order.</summary>
    public IReadOnlyDictionary<string, ValueTypeMapping> VectorTypes { get; init; } = new Dictionary<string, ValueTypeMapping>();

    /// <summary>C matrix types and the managed type that occupies the same bytes.</summary>
    public IReadOnlyDictionary<string, string> MatrixTypes { get; init; } = new Dictionary<string, string>();

    /// <summary>C owner-wrapper handle types and the managed type a caller holds instead.</summary>
    public IReadOnlyDictionary<string, string> HandleTypes { get; init; } = new Dictionary<string, string>();

    /// <summary>Name of the trailing failure lane, which is never a projected parameter.</summary>
    public string ErrorLaneName { get; init; } = "out_error";

    /// <summary>Reads the <c>convention</c> object of a manifest.</summary>
    public static Convention FromJson(System.Text.Json.Nodes.JsonObject json, string zigErrorAbi = "")
    {
        static string Text(System.Text.Json.Nodes.JsonObject o, string key) =>
            o[key]?.GetValue<string>() ?? throw new InvalidOperationException($"the convention declares no '{key}'");

        var overrides = new Dictionary<string, string>();
        foreach (var (symbol, name) in json["typeNameOverrides"]?.AsObject() ?? [])
            overrides[symbol] = name!.GetValue<string>();

        return new Convention
        {
            SymbolPrefix = Text(json, "symbolPrefix"),
            HandleSuffix = Text(json, "handleSuffix"),
            FactorySuffix = Text(json, "factorySuffix"),
            ComponentSuffix = Text(json, "componentSuffix"),
            ParamsSuffix = Text(json, "paramsSuffix"),
            ErrorOutParamType = Text(json, "errorOutParamType"),
            BooleanReturnTypes = (json["booleanReturnTypes"]?.AsArray() ?? throw new InvalidOperationException("the convention declares no 'booleanReturnTypes'"))
                .Select(n => n!.GetValue<string>()).ToList(),
            OutParamPrefix = json["outParamPrefix"]?.GetValue<string>() ?? "out_",
            ErrorLaneName = json["errorLaneName"]?.GetValue<string>() ?? "out_error",
            ByteBoolType = Text(json, "byteBoolType"),
            ErrorType = Text(json, "errorType"),
            FieldTable = json["fieldTable"] is System.Text.Json.Nodes.JsonObject table ? ReadFieldTable(table) : null,
            ErrorKindType = Text(json, "errorKindType"),
            ErrorIsFunction = Text(json, "errorIsFunction"),
            ErrorGeneralSingleton = Text(json, "errorGeneralSingleton"),
            ErrorKinds = (json["errorKinds"]?.AsArray() ?? []).Select(k => new ErrorKind(k!["name"]!.GetValue<string>(), k["singleton"]!.GetValue<string>())).ToList(),
            ZigErrorAbi = zigErrorAbi,
            ErrorHelperClass = Text(json, "errorHelperClass"),
            CommonManagedNamespace = Text(json, "commonManagedNamespace"),
            VectorTypes = (json["vectorTypes"]?.AsObject() ?? []).ToDictionary(
                kv => kv.Key,
                kv => new ValueTypeMapping(kv.Value!["managed"]!.GetValue<string>(),
                    kv.Value!["lanes"]!.AsArray().Select(l => l!.GetValue<string>()).ToArray())),
            MatrixTypes = (json["matrixTypes"]?.AsObject() ?? []).ToDictionary(kv => kv.Key, kv => kv.Value!.GetValue<string>()),
            HandleTypes = (json["handleTypes"]?.AsObject() ?? []).ToDictionary(kv => kv.Key, kv => kv.Value!.GetValue<string>()),
            IncludeDirectoryName = json["includeDirectoryName"]?.GetValue<string>() ?? "kernel_engine",
            CommonBindingsNamespace = json["commonBindingsNamespace"]?.GetValue<string>() ?? "",
            BindingsMethodsClass = json["bindingsMethodsClass"]?.GetValue<string>() ?? "NativeMethods",
            TypeNameOverrides = overrides,
        };
    }

    static FieldTableConvention ReadFieldTable(System.Text.Json.Nodes.JsonObject table)
    {
        static FieldKind Kind(string name) => Enum.Parse<FieldKind>(name, ignoreCase: true);

        return new FieldTableConvention(
            table["entryType"]!.GetValue<string>(),
            table["include"]!.GetValue<string>(),
            table["nameMacroPrefix"]!.GetValue<string>(),
            table["nullVariant"]!.GetValue<string>(),
            (table["valueTypes"]?.AsObject() ?? []).ToDictionary(kv => kv.Key, kv => Kind(kv.Value!.GetValue<string>())),
            table["variants"]!.AsObject().ToDictionary(
                kv => Kind(kv.Key),
                kv => new FieldVariant(kv.Value!["constant"]!.GetValue<string>(), kv.Value["member"]!.GetValue<string>())));
    }

    /// <summary>Reads the <c>convention</c> object of the manifest at <paramref name="manifestPath"/>.</summary>
    public static Convention Load(string manifestPath)
    {
        var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject()["convention"]?.AsObject()
            ?? throw new InvalidOperationException($"{manifestPath} has no 'convention' object");
        var abiFile = json["zigErrorAbiFile"]?.GetValue<string>();
        var abi = abiFile is null ? "" : File.ReadAllText(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(manifestPath))!, abiFile));
        return FromJson(json, abi);
    }
}
