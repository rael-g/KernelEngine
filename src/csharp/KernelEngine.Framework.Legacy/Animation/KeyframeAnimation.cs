namespace KernelEngine.Framework.Legacy.Animation;

using KeyFrame = (float Time, float Value, EasingFunction? EasingFunction);

/// <summary>Animates through an ordered list of keyframes, easing between each pair.</summary>
public class KeyframeAnimation : AnimationBase
{
    private readonly List<KeyFrame> _keyframes;

    public KeyframeAnimation(List<KeyFrame> keyframes)
        : base(keyframes.First().Value, keyframes.Last().Value)
    {
        if (keyframes.Count < 2)
            throw new ArgumentException("At least two keyframes are required.");

        _keyframes = [.. keyframes.OrderBy(k => k.Time)];
    }

    public override void Update(float deltaTime)
    {
        if (IsCompleted) return;

        ElapsedTime += deltaTime;
        for (int i = 0; i < _keyframes.Count - 1; i++)
        {
            var start = _keyframes[i];
            var end = _keyframes[i + 1];

            if (ElapsedTime >= start.Time && ElapsedTime <= end.Time)
            {
                Weight = (ElapsedTime - start.Time) / (end.Time - start.Time);
                Current = Interpolate(start.Value, end.Value, Weight, start.EasingFunction);
                return;
            }
        }

        IsCompleted = true;
        Current = To;
    }
}
