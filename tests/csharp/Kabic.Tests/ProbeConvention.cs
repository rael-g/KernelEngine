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
