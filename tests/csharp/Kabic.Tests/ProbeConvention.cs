namespace Kabic.Tests;

internal static class ProbeConvention
{
    public static readonly Convention Value = new()
    {
        SymbolPrefix = "ke_",
        HandleSuffix = "_handle",
        FactorySuffix = "_create",
        ComponentSuffix = "_component",
        ParamsSuffix = "_params",
        ErrorOutParamType = "ke_error**",
        BooleanReturnTypes = ["_Bool", "bool", "ke_bool"],
        ByteBoolType = "ke_bool",
        ErrorType = "ke_error",
        ErrorKindType = "ke_error_type",
        ErrorIsFunction = "ke_error_is",
        ErrorGeneralSingleton = "KE_ERROR_GENERAL",
        ErrorKinds =
        [
            new("NotFound", "KE_ERROR_NOT_FOUND"),
            new("Io", "KE_ERROR_IO"),
            new("OutOfMemory", "KE_ERROR_OUT_OF_MEMORY"),
            new("InvalidArgument", "KE_ERROR_INVALID_ARGUMENT"),
            new("NotInitialized", "KE_ERROR_NOT_INITIALIZED"),
            new("NotSupported", "KE_ERROR_NOT_SUPPORTED"),
            new("AlreadyExists", "KE_ERROR_ALREADY_EXISTS"),
        ],
        ZigErrorAbi = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "zig_error_abi.zig")),
        ErrorHelperClass = "KernelError",
        CommonManagedNamespace = "KernelEngine.Common",
        CommonBindingsNamespace = "KernelEngine.Common.Native",
        VectorTypes = new Dictionary<string, ValueTypeMapping>
        {
            ["ke_vec2"] = new("Vector2", ["x", "y"]),
            ["ke_vec3"] = new("Vector3", ["x", "y", "z"]),
            ["ke_vec4"] = new("Vector4", ["x", "y", "z", "w"]),
            ["ke_quat"] = new("Quaternion", ["x", "y", "z", "w"]),
        },
        MatrixTypes = new Dictionary<string, string> { ["ke_mat4"] = "Matrix4x4" },
        HandleTypes = new Dictionary<string, string>
        {
            ["ke_mesh_handle"] = "KernelEngine.Render.MeshHandle",
            ["ke_material_handle"] = "KernelEngine.Render.MaterialHandle",
            ["ke_texture_handle"] = "KernelEngine.Render.TextureHandle",
            ["ke_ui_font_handle"] = "KernelEngine.Render.FontHandle",
        },
        TypeNameOverrides = new Dictionary<string, string>
        {
            ["ke_ecs"] = "EcsRegistry",
            ["ke_asset_resolver"] = "NativeAssetResolver",
            ["ke_input_actions"] = "NativeInputActions",
            ["ke_physics_2d"] = "Physics2D",
            ["ke_body_type_2d"] = "BodyType2D",
            ["ke_phase"] = "RuntimePhase",
            ["ke_access"] = "RuntimeAccess",
        },
    };
}
