namespace Kabic;

/// <summary>
/// Builds the <see cref="Convention"/> of an ABI by declaring what it names, one call per fact.
/// Every list is open: an ABI adds as many result codes, vector types or handle types as it has.
/// </summary>
public sealed class ConventionBuilder
{
    string symbolPrefix = "", handleSuffix = "", factorySuffix = "", componentSuffix = "", paramsSuffix = "";
    string outParamPrefix = "out_";
    string includeDirectoryName = "", commonBindingsNamespace = "", bindingsMethodsClass = "NativeMethods";
    string commonManagedNamespace = "";
    string resultAbiHeader = "";
    IReadOnlyList<string> resultAbiIncludeDirs = [];
    string resultType = "", resultOk = "", resultManagedType = "", resultHelperClass = "", resultCodesOut = "";
    readonly List<ResultCodeSpec> resultCodes = [];
    FieldTableConvention? fieldTable;
    readonly Dictionary<string, string> handleTypes = [], typeNames = [];
    readonly List<IShapePack> packs = [];

    /// <summary>
    /// The spellings that mark what a symbol is: its prefix and the suffix of a handle, a factory,
    /// a component and a parameter bag.
    /// </summary>
    public ConventionBuilder Symbols(string prefix, string handle, string factory, string component, string parameters)
    {
        (symbolPrefix, handleSuffix, factorySuffix, componentSuffix, paramsSuffix) = (prefix, handle, factory, component, parameters);
        return this;
    }

    /// <summary>The prefix of a parameter written back.</summary>
    public ConventionBuilder OutParams(string prefix)
    {
        outParamPrefix = prefix;
        return this;
    }

    /// <summary>
    /// Where a header is addressed from, and the names the raw bindings are generated into.
    /// </summary>
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
    /// How a fallible call returns its outcome as a code: the C type of the code, the constant that
    /// means success, the managed type the bindings declare for it, and the class that turns a code
    /// into an exception, the last two fully qualified.
    /// </summary>
    public ConventionBuilder Result(string cType, string ok, string managedType, string helperClass, string codesOut = "")
    {
        (resultType, resultOk, resultManagedType, resultHelperClass, resultCodesOut) = (cType, ok, managedType, helperClass, codesOut);
        return this;
    }

    /// <summary>
    /// The header that declares the result type and its codes, relative to the repository root,
    /// and the include directories it is read with.
    /// </summary>
    public ConventionBuilder ResultAbi(string header, IEnumerable<string> includeDirs)
    {
        (resultAbiHeader, resultAbiIncludeDirs) = (header, includeDirs.ToList());
        return this;
    }

    /// <summary>
    /// Declares the exception a code reads as on the managed side. With <paramref name="extends"/>,
    /// kabic declares <paramref name="managed"/> as a new exception type deriving from it. A code
    /// never declared reads as the general exception.
    /// </summary>
    public ConventionBuilder AddResultCode(string code, string managed, string? extends = null)
    {
        resultCodes.Add(new ResultCodeSpec(code, managed, extends));
        return this;
    }

    /// <summary>Adds a pack of types the ABI has beyond C's own.</summary>
    public ConventionBuilder Use(IShapePack pack)
    {
        packs.Add(pack);
        return this;
    }

    /// <summary>
    /// A C owner-wrapper handle type and the managed type a caller holds instead.
    /// </summary>
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

    /// <summary>
    /// Builds the <see cref="Convention"/> from the facts declared so far, without checking them.
    /// </summary>
    /// <returns>
    /// A convention holding a copy of the handle types, the type-name overrides, the result codes
    /// and the packs.
    /// </returns>
    public Convention Build() => new()
    {
        SymbolPrefix = symbolPrefix,
        HandleSuffix = handleSuffix,
        FactorySuffix = factorySuffix,
        ComponentSuffix = componentSuffix,
        ParamsSuffix = paramsSuffix,
        OutParamPrefix = outParamPrefix,
        IncludeDirectoryName = includeDirectoryName,
        CommonBindingsNamespace = commonBindingsNamespace,
        BindingsMethodsClass = bindingsMethodsClass,
        CommonManagedNamespace = commonManagedNamespace,
        ResultAbiHeader = resultAbiHeader,
        ResultAbiIncludeDirs = resultAbiIncludeDirs,
        ResultType = resultType,
        ResultOk = resultOk,
        ResultManagedType = resultManagedType,
        ResultHelperClass = resultHelperClass,
        ResultCodesOut = resultCodesOut,
        ResultCodes = resultCodes.ToList(),
        HandleTypes = new Dictionary<string, string>(handleTypes),
        TypeNameOverrides = new Dictionary<string, string>(typeNames),
        FieldTable = fieldTable,
        Packs = packs.ToList(),
    };
}
