namespace KernelEngine.Framework.Animation;

using Point = (float Time, float Value);

/// <summary>A piecewise curve over (time, value) points, sampled with <see cref="Evaluate"/>.</summary>
public class AnimationCurve(List<Point> points, EasingFunction? easingFunction = null)
{
    private readonly List<Point> _points = [.. points.OrderBy(p => p.Time)];
    private readonly EasingFunction _easingFunction = easingFunction ?? Easing.Linear;

    public float Evaluate(float t)
    {
        for (int i = 0; i < _points.Count - 1; i++)
        {
            var start = _points[i];
            var end = _points[i + 1];

            if (t >= start.Time && t <= end.Time)
            {
                float segmentT = (t - start.Time) / (end.Time - start.Time);
                return start.Value + (end.Value - start.Value) * _easingFunction(segmentT);
            }
        }

        return t <= _points.First().Time ? _points.First().Value : _points.Last().Value;
    }
}
