// ke.globals.slang — engine globals available in all shaders.
// Populated per-frame by the engine before each draw/dispatch.

float     ke_time;
float     ke_dt;
float4x4  ke_view;
float4x4  ke_proj;
float3    ke_cameraPos;
float2    ke_viewportSize;
