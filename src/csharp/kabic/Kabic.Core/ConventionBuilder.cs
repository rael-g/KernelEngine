namespace Kabic;

/// <summary>
/// Builds the <see cref="Convention"/> of an ABI by declaring what it names, one call per fact.
/// Every list is open: an ABI adds as many failure kinds, vector types or handle types as it has.
/// </summary>
public sealed class ConventionBuilder
{
    string symbolPrefix = "", handleSuffix = "", factorySuffix = "", componentSuffix = "", paramsSuffix = "";
    string outParamPrefix = "out_", errorLaneName = "out_error";
    string byteBoolType = "";
    string includeDirectoryName = "", commonBindingsNamespace = "", bindingsMethodsClass = "NativeMethods";
    string commonManagedNamespace = "";
    string errorType = "", errorKindType = "", errorIsFunction = "", errorGeneral = "";
    string errorHelperClass = "", errorHelperNamespace = "", errorKindsOut = "", errorAbiHeader = "";
    IReadOnlyList<string> errorAbiIncludeDirs = [];
    FieldTableConvention? fieldTable;
    readonly List<ErrorKindSpec> errors = [];
    readonly Dictionary<string, string> handleTypes = [], typeNames = [];

    /// <summary>The spellings that mark what a symbol is: its prefix and the suffix of a handle, a factory, a component and a parameter bag.</summary>
    public ConventionBuilder Symbols(string prefix, string handle, string factory, string component, string parameters)
    {
        (symbolPrefix, handleSuffix, factorySuffix, componentSuffix, paramsSuffix) = (prefix, handle, factory, component, parameters);
        return this;
    }

    /// <summary>The one-byte boolean typedef the ABI declares; <c>_Bool</c> and <c>bool</c> are C's own.</summary>
    public ConventionBuilder Booleans(string byteBool)
    {
        byteBoolType = byteBool;
        return this;
    }

    /// <summary>The prefix of a parameter written back, and the name of the trailing failure lane.</summary>
    public ConventionBuilder OutParams(string prefix, string failureLane)
    {
        (outParamPrefix, errorLaneName) = (prefix, failureLane);
        return this;
    }

    /// <summary>Where a header is addressed from, and the names the raw bindings are generated into.</summary>
    public ConventionBuilder Bindings(string includeDirectory, string commonNamespace, string methodsClass = "NativeMethods")
    {
        (includeDirectoryName, commonBindingsNamespace, bindingsMethodsClass) = (includeDirectory, commonNamespace, methodsClass);
        return this;
    }

    /// <summary>The managed namespace the projections import for the shared types.</summary>
    public ConventionBuilder Managed(string commonNamespace)
    {
        commonManagedNamespace = commonNamespace;
        return this;
    }

    /// <summary>
    /// How a failure is reported: the struct and the kind type, the function that tests a kind, the general kind,
    /// the header that declares all of it, and the class and file that
    /// receive the generated mapping to exceptions.
    /// </summary>
    public ConventionBuilder Failure(string type, string kindType, string isFunction, string generalSingleton,
        string header, IEnumerable<string> includeDirs, string helperClass, string helperNamespace, string kindsOut)
    {
        (errorType, errorKindType, errorIsFunction, errorGeneral) = (type, kindType, isFunction, generalSingleton);
        (errorAbiHeader, errorAbiIncludeDirs) = (header, includeDirs.ToList());
        (errorHelperClass, errorHelperNamespace, errorKindsOut) = (helperClass, helperNamespace, kindsOut);
        return this;
    }

    /// <summary>
    /// Declares a kind of failure: the singleton it is reached by, the name its native type carries, the exception a
    /// managed caller catches (built from a message and a cause), and the error a Zig caller switches on. The Zig name
    /// defaults to the last segment of the native name in PascalCase. With <paramref name="extends"/>, kabic declares
    /// <paramref name="managed"/> as a new exception type deriving from it; without, <paramref name="managed"/> names an
    /// existing type. A kind never declared reads as the general one, which is a plain <see cref="Exception"/> until
    /// it is declared too.
    /// </summary>
    public ConventionBuilder AddError(string singleton, string nativeName, string managed, string? zig = null, string? extends = null)
    {
        errors.Add(new ErrorKindSpec(singleton, nativeName, managed, zig ?? Convention.ZigErrorName(nativeName), extends));
        return this;
    }

    /// <summary>A C owner-wrapper handle type and the managed type a caller holds instead.</summary>
    public ConventionBuilder AddHandleType(string cType, string managed)
    {
        handleTypes[cType] = managed;
        return this;
    }

    /// <summary>A target-language name for a symbol whose derived name is unusable.</summary>
    public ConventionBuilder AddTypeName(string symbol, string name)
    {
        typeNames[symbol] = name;
        return this;
    }

    /// <summary>How component structs are described as field tables.</summary>
    public ConventionBuilder FieldTable(FieldTableConvention table)
    {
        fieldTable = table;
        return this;
    }

    public Convention Build() => new()
    {
        SymbolPrefix = symbolPrefix,
        HandleSuffix = handleSuffix,
        FactorySuffix = factorySuffix,
        ComponentSuffix = componentSuffix,
        ParamsSuffix = paramsSuffix,
        OutParamPrefix = outParamPrefix,
        ErrorLaneName = errorLaneName,
        ByteBoolType = byteBoolType,
        IncludeDirectoryName = includeDirectoryName,
        CommonBindingsNamespace = commonBindingsNamespace,
        BindingsMethodsClass = bindingsMethodsClass,
        CommonManagedNamespace = commonManagedNamespace,
        ErrorType = errorType,
        ErrorKindType = errorKindType,
        ErrorIsFunction = errorIsFunction,
        ErrorGeneralSingleton = errorGeneral,
        ErrorAbiHeader = errorAbiHeader,
        ErrorAbiIncludeDirs = errorAbiIncludeDirs,
        ErrorHelperClass = errorHelperClass,
        ErrorHelperNamespace = errorHelperNamespace,
        ErrorKindsOut = errorKindsOut,
        ErrorKinds = errors.ToList(),
        HandleTypes = new Dictionary<string, string>(handleTypes),
        TypeNameOverrides = new Dictionary<string, string>(typeNames),
        FieldTable = fieldTable,
    };
}
