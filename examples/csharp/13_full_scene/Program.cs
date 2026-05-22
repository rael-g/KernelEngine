using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Asset.Assimp;
using KernelEngine.TaskScheduler.Enki;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 13 Full Scene Demo")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddEnkiTaskScheduler()
    .AddAssimpAssetLoader();

using var app = new Application();

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 13_full_scene");
    Console.WriteLine("[KernelEngine] Features: all_stabilized_systems, shadows, hdr, bloom, ssao, many_lights, assimp");

    // Camera. No CameraNode.LookAt helper yet (framework gap — Kanban OBS.5); the camera looks
    // down its local -Z, so orient it manually toward the scene center for a 3/4 framing.
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "MainCamera");
    var eye = new Vector3(8f, 8f, 15f);
    var lookRot = Quaternion.CreateFromRotationMatrix(
        Matrix4x4.CreateWorld(eye, Vector3.Normalize(new Vector3(0f, 2f, 0f) - eye), Vector3.UnitY));
    cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };
    app.ActiveWorld.ActiveCamera = cam.Entity;

    // Static directional light. Direction is the vector FROM the lit surface TOWARD the light
    // source; a directional light ignores Position, so this must be set for shading + shadows.
    var sun = app.Scene.AddNode(
        new LightNode {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = new Vector3(1f, 0.95f, 0.8f),
            Intensity = 4.0f
        },
        "Sun");

    // Ground plane
    var floorMat = await resources.CreateMaterialAsync(new Vector4(0.2f, 0.2f, 0.2f, 1f), metallic: 0.0f, roughness: 0.9f);
    var floor = app.Scene.AddNode(new MeshNode { MaterialHandle = floorMat }, "Floor");
    // Default mesh (handle 0) is a quad in the XY plane (normal +Z). Rotate -90° about X to lay it
    // flat as a ground plane (normal +Y); local Y becomes world depth, so scale X and Y for size.
    floor.LocalTransform = floor.LocalTransform with
    {
        Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitX, -MathF.PI / 2f),
        Scale = new Vector3(50f, 50f, 1f)
    };

    // Load model: same raw 3-step pattern as example 12 (no engine helper — see Kanban [B5.6]).
    var loader = app.Services.GetRequiredService<IAssetLoader>();
    try {
        string modelPath = Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/Box.gltf");
        using var modelData = await loader.LoadModelAsync(modelPath);

        var gpuTextures = new TextureHandle[modelData.Textures.Count];
        for (int i = 0; i < modelData.Textures.Count; i++)
        {
            var tex = modelData.Textures[i];
            gpuTextures[i] = await resources.CreateTextureAsync(tex.Width, tex.Height, tex.Pixels.ToArray());
        }

        var gpuMaterials = new MaterialHandle[modelData.Materials.Count];
        for (int i = 0; i < modelData.Materials.Count; i++)
        {
            var mat = modelData.Materials[i];
            var albedo = mat.AlbedoTextureIndex >= 0 ? gpuTextures[mat.AlbedoTextureIndex] : default;
            var normal = mat.NormalMapTextureIndex >= 0 ? gpuTextures[mat.NormalMapTextureIndex] : default;
            gpuMaterials[i] = await resources.CreateMaterialAsync(
                mat.BaseColor, textureHandle: albedo,
                metallic: mat.Metallic, roughness: mat.Roughness,
                normalMapHandle: normal);
        }

        var modelRoot = app.Scene.AddNode("CenterBox");
        for (int i = 0; i < modelData.Meshes.Count; i++)
        {
            var meshData = modelData.Meshes[i];
            var gpuMesh = await resources.CreateMeshAsync(
                meshData.Vertices.ToArray(),
                meshData.Indices.ToArray());
            var material = meshData.MaterialIndex >= 0 ? gpuMaterials[meshData.MaterialIndex] : default;
            app.Scene.AddNode(
                new MeshNode { MeshHandle = gpuMesh, MaterialHandle = material },
                meshData.Name, parent: modelRoot);
        }
        modelRoot.LocalTransform = modelRoot.LocalTransform with {
            Position = new Vector3(0f, 2f, 0f),
            Scale = new Vector3(2.0f)
        };
    } catch { /* ignore */ }

    // Dynamic point lights
    for (int i = 0; i < 8; i++)
    {
        app.Scene.AddNode(
            new OrbitingLight {
                Color = i % 2 == 0 ? Vector3.UnitX : Vector3.UnitZ,
                Radius = 5f,
                Speed = 0.5f + i * 0.1f,
                Phase = i * (MathF.PI / 4f)
            },
            $"OrbitLight_{i}");
    }
};

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.05f, 0.05f, 0.08f, 1f);
    scene.SetAmbientLight(0.02f, 0.02f, 0.02f);
    
    // Enable all post-FX
    scene.SetTonemapping(true, 1.0f, 2.2f);
    scene.SetBloom(true, 0.9f, 1.0f);
    scene.SetSsao(true, 0.5f, 0.025f, 1.5f);
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

sealed class OrbitingLight : Node
{
    public Vector3 Color { get; init; } = Vector3.One;
    public float Radius { get; init; } = 5f;
    public float Speed { get; init; } = 1.0f;
    public float Phase { get; init; } = 0.0f;
    private float _time;

    protected override void OnStart()
    {
        var comp = AddComponent<PointLightComponent>(PointLightNode.ComponentId);
        comp[0] = new PointLightComponent { R = Color.X, G = Color.Y, B = Color.Z, Intensity = 40f, Radius = 18f };
    }

    protected override void OnUpdate(float dt)
    {
        _time += dt * Speed;
        float x = MathF.Cos(_time + Phase) * Radius;
        float z = MathF.Sin(_time + Phase) * Radius;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 3f, z) };
    }
}
