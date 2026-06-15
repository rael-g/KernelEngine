using KernelEngine.Audio.MiniAudio;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 15_audio_test — kernel ke_audio → miniaudio plugin → IAudio C# wrapper.
// Two short sine WAVs are generated to %TEMP% at startup (no committed binary
// assets). Click the window to focus, then:
//   • Space  → play the 440 Hz beep
//   • L      → toggle a 220 Hz looping bass
//   • Escape → quit
//
// Edge detection is done in OnUpdate by tracking the previous frame's key
// state, since the new Framework doesn't yet ship an OnInput event hook.

var beepPath = WriteSineWav(440, durationMs: 150);
var bassPath = WriteSineWav(220, durationMs: 500);

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddMiniAudio()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(640, 200, "KernelEngine — 15 Audio Test (click window, then Space)"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.08f, 0.10f, 1.0f)))
        .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        Console.WriteLine("[KernelEngine] Example: 15_audio_test");
        Console.WriteLine("[KernelEngine] Features: miniaudio, sine_synth, edge_keys");

        var audio = sp.GetRequiredService<IAudio>();
        var beep  = audio.LoadSound(beepPath);
        var bass  = audio.LoadSound(bassPath);
        Console.WriteLine($"[Audio] beep={beep.Value} bass={bass.Value}");

        tree.AddNode(new AudioController(audio, beep, bass), "AudioController");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[15_audio_test] Loop running. Close the window to exit.");

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[15_audio_test] Exited cleanly.");

// ── Synthesizes a short 16-bit mono PCM sine WAV with a 10 ms env fade ───────

static string WriteSineWav(int frequency, int durationMs)
{
    const int sampleRate = 44100;
    int numSamples = sampleRate * durationMs / 1000;
    int dataSize   = numSamples * 2;

    var path = Path.Combine(Path.GetTempPath(), $"ke_audio_{frequency}hz_{durationMs}ms.wav");
    using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
    using var w  = new BinaryWriter(fs);
    w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
    w.Write(36 + dataSize);
    w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
    w.Write(16);
    w.Write((short)1);          // PCM
    w.Write((short)1);          // mono
    w.Write(sampleRate);
    w.Write(sampleRate * 2);    // byte rate
    w.Write((short)2);          // block align
    w.Write((short)16);         // bits per sample
    w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
    w.Write(dataSize);

    double envSamples = sampleRate * 0.010;
    for (int i = 0; i < numSamples; i++)
    {
        double t   = (double)i / sampleRate;
        double env = Math.Min(1.0, Math.Min(i / envSamples, (numSamples - i) / envSamples));
        short  s   = (short)(env * 8000 * Math.Sin(2 * Math.PI * frequency * t));
        w.Write(s);
    }
    return path;
}

// ── AudioController node — polls keys + edge-detects key-down ────────────────

sealed class AudioController : Node
{
    private const int KeySpace  = 32;
    private const int KeyL      = 76;
    private const int KeyEscape = 256;

    private readonly IAudio      _audio;
    private readonly SoundHandle _beep;
    private readonly SoundHandle _bass;

    private bool _bassLooping;
    private bool _prevSpace;
    private bool _prevL;
    private bool _prevEsc;

    public AudioController(IAudio audio, SoundHandle beep, SoundHandle bass)
    {
        _audio = audio;
        _beep  = beep;
        _bass  = bass;
    }

    protected override void OnBind(NodeWorld nodeWorld) { /* nothing to materialize — this node only carries behavior */ }

    protected override void OnUpdate(in View view)
    {
        bool space = view.IsKeyDown(KeySpace);
        bool l     = view.IsKeyDown(KeyL);
        bool esc   = view.IsKeyDown(KeyEscape);

        if (space && !_prevSpace)
        {
            _audio.Play(_beep, volume: 0.6f);
            Console.WriteLine("BEEP");
        }
        if (l && !_prevL)
        {
            _bassLooping = !_bassLooping;
            if (_bassLooping)
            {
                _audio.Play(_bass, volume: 0.4f, loop: true);
                Console.WriteLine("BASS on");
            }
            else
            {
                _audio.Stop(_bass);
                Console.WriteLine("BASS off");
            }
        }
        if (esc && !_prevEsc) Environment.Exit(0);

        _prevSpace = space;
        _prevL     = l;
        _prevEsc   = esc;
    }
}
