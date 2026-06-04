using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using KernelEngine.Asset.Assimp;
using KernelEngine.TaskScheduler.Enki;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger()
    .AddConsoleSink()
    .AddGlfwWindow(1280, 720, "KernelEngine — 13 Full Tree Demo")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddEnkiTaskScheduler()
    .AddAssimpAssetLoader();

using var app = new Application();

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 13_full_scene");
    Console.WriteLine("[KernelEngine] Features: all_stabilized_systems, shadows, hdr, bloom, ssao, many_lights, assimp");

    // Camera. No Camera.LookAt helper yet (framework gap — Kanban OBS.5); the camera looks
    // down its local -Z, so orient it manually toward the Tree center for a 3/4 framing.
    var cam = app.Tree.AddNode(
        new Camera { Fov = 60f, Near = 0.1f, Far = 1000f },
        "MainCamera");
    var eye = new Vector3(8f, 8f, 15f);
    var lookRot = Quaternion.CreateFromRotationMatrix(
        Matrix4x4.CreateWorld(eye, Vector3.Normalize(new Vector3(0f, 2f, 0f) - eye), Vector3.UnitY));
    cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };

    // Static directional light. Direction is the vector FROM the lit surface TOWARD the light
    // source; a directional light ignores Position, so this must be set for shading + shadows.
    var sun = app.Tree.AddNode(
        new DirectionalLight {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = new Vector3(1f, 0.95f, 0.8f),
            Intensity = 4.0f
        },
        "Sun");

    // Ground plane
    var floorMat = await resources.CreateMaterialAsync(new Vector4(0.2f, 0.2f, 0.2f, 1f), metallic: 0.0f, roughness: 0.9f);
    var floor = app.Tree.AddNode(new MeshRenderer { MaterialHandle = floorMat }, "Floor");
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

        var modelRoot = app.Tree.AddNode("CenterBox");
        for (int i = 0; i < modelData.Meshes.Count; i++)
        {
            var meshData = modelData.Meshes[i];
            var gpuMesh = await resources.CreateMeshAsync(
                meshData.Vertices.ToArray(),
                meshData.Indices.ToArray());
            var material = meshData.MaterialIndex >= 0 ? gpuMaterials[meshData.MaterialIndex] : default;
            app.Tree.AddNode(
                new MeshRenderer { MeshHandle = gpuMesh, MaterialHandle = material },
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
        app.Tree.AddNode(
            new OrbitingLight {
                Color = i % 2 == 0 ? Vector3.UnitX : Vector3.UnitZ,
                Intensity = 40f,
                Radius = 18f,
                OrbitRadius = 5f,
                Speed = 0.5f + i * 0.1f,
                Phase = i * (MathF.PI / 4f)
            },
            $"OrbitLight_{i}");
    }
};

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.05f, 0.05f, 0.08f, 1f);
    tree.SetAmbientLight(0.02f, 0.02f, 0.02f);
    
    // Enable all post-FX
    tree.SetTonemapping(true, 1.0f, 2.2f);
    tree.SetBloom(true, 0.9f, 1.0f);
    tree.SetSsao(true, 0.5f, 0.025f, 1.5f);
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

sealed class OrbitingLight : PointLight
{
    public float OrbitRadius { get; init; } = 5f;
    public float Speed { get; init; } = 1.0f;
    public float Phase { get; init; } = 0.0f;
    private float _time;

    protected override void Update(float dt)
    {
        _time += dt * Speed;
        float x = MathF.Cos(_time + Phase) * OrbitRadius;
        float z = MathF.Sin(_time + Phase) * OrbitRadius;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 3f, z) };
    }
}
