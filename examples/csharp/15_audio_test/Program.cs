using KernelEngine.Audio;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

using KernelEngine.Framework.Native;

using InputAction = KernelEngine.Framework.InputAction;

var beepPath = WriteSineWav(440, durationMs: 150);
var bassPath = WriteSineWav(220, durationMs: 500);

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddSingleton(_ =>
    {
        var actions = new InputActions();
        var test = actions.AddMap("AudioTest", 0);
        actions.BindKey(actions.AddAction(test, "Beep", NativeActionType.Button), Key.Space);
        actions.BindKey(actions.AddAction(test, "Bass", NativeActionType.Button), Key.L);
        actions.BindKey(actions.AddAction(test, "Quit", NativeActionType.Button), Key.Escape);
        return actions;
    })
    .AddMiniaudioAudio()
    .AddAudioScene()
    .AddAudioComponentsNodeTypes()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig(Title: "KernelEngine — 15 Audio Test (click window, then Space)", Width: 640, Height: 200))
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new System.Numerics.Vector4(0.05f, 0.08f, 0.10f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        Console.WriteLine("[KernelEngine] Example: 15_audio_test");
        Console.WriteLine("[KernelEngine] Features: miniaudio, sine_synth, edge_keys");

        var audio = sp.GetRequiredService<IAudio>();
        var beep = audio.LoadSound(beepPath);
        var bass = audio.LoadSound(bassPath);
        Console.WriteLine($"[Audio] beep={beep} bass={bass}");

        tree.AddNode(new AudioController(audio, beep, bass), "AudioController");
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[15_audio_test] Loop running. Close the window to exit.");

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();


Console.WriteLine("[15_audio_test] Exited cleanly.");

static string WriteSineWav(int frequency, int durationMs)
{
    const int sampleRate = 44100;
    int numSamples = sampleRate * durationMs / 1000;
    int dataSize = numSamples * 2;

    var path = Path.Combine(Path.GetTempPath(), $"ke_audio_{frequency}hz_{durationMs}ms.wav");
    using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
    using var w = new BinaryWriter(fs);
    w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
    w.Write(36 + dataSize);
    w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
    w.Write(16);
    w.Write((short)1);
    w.Write((short)1);
    w.Write(sampleRate);
    w.Write(sampleRate * 2);
    w.Write((short)2);
    w.Write((short)16);
    w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
    w.Write(dataSize);

    double envSamples = sampleRate * 0.010;
    for (int i = 0; i < numSamples; i++)
    {
        double t = (double)i / sampleRate;
        double env = Math.Min(1.0, Math.Min(i / envSamples, (numSamples - i) / envSamples));
        short s = (short)(env * 8000 * Math.Sin(2 * Math.PI * frequency * t));
        w.Write(s);
    }
    return path;
}

sealed class AudioController : Node
{

    private readonly IAudio _audio;
    private readonly uint _beep;
    private readonly uint _bass;

    private uint _bassVoice;

    public AudioController(IAudio audio, uint beep, uint bass)
    {
        _audio = audio;
        _beep = beep;
        _bass = bass;
    }

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        if (new InputAction(this, "Beep").JustPressed)
        {
            _audio.VoiceStart(_beep, volume: 0.6f, pitch: 1f, loop: false);
            Console.WriteLine("BEEP");
        }
        if (new InputAction(this, "Bass").JustPressed)
        {
            if (_bassVoice == 0)
            {
                _bassVoice = _audio.VoiceStart(_bass, volume: 0.4f, pitch: 1f, loop: true);
                Console.WriteLine("BASS on");
            }
            else
            {
                _audio.VoiceStop(_bassVoice);
                _bassVoice = 0;
                Console.WriteLine("BASS off");
            }
        }
        if (new InputAction(this, "Quit").JustPressed) Environment.Exit(0);
    }
}
