using Microsoft.ML.Data;

namespace CareAI.Infrastructure.AnomalyDetection;

public sealed class TimeSeriesInput
{
    public float Value { get; set; }
}

public sealed class SpikePrediction
{
    // ML.NET: alert, raw score, p-value.
    [VectorType(3)]
    public double[] Prediction { get; set; } = Array.Empty<double>();
}

public sealed class AnomalyDetectionOptions
{
    public string TimeZoneId { get; set; } = "Asia/Ho_Chi_Minh";
    public double Confidence { get; set; } = 95;
    // Require at least one valid measurement in every hour of a window.
    public int MinimumBaselineDays { get; set; } = 7;
    public double MinimumUsualMorningSteps { get; set; } = 100;
}
