using System.Threading.Channels;
using CareAI.Core.DTOs;

namespace CareAI.Infrastructure.Channels;

/// <summary>
/// Giao diện hàng đợi bộ nhớ phi khóa (Non-Blocking Memory Channel) cho các mẻ viễn trắc sinh hiệu
/// Phục vụ Nhiệm vụ 1.2 theo Bản Kế hoạch Triển khai CareAI v111.0
/// </summary>
public interface ITelemetryBatchQueue
{
    ValueTask<bool> EnqueueAsync(TelemetryBatchMessage message, CancellationToken ct = default);
    ChannelReader<TelemetryBatchMessage> Reader { get; }
    int Count { get; }
    int Capacity { get; }
}

/// <summary>
/// Hiện thực hóa hàng đợi phi khóa sử dụng System.Threading.Channels.Channel với BoundedChannelOptions
/// Đảm bảo tốc độ đẩy vào RAM < 1ms và bảo vệ ngưỡng tài nguyên hệ thống
/// </summary>
public class TelemetryBatchQueue : ITelemetryBatchQueue
{
    private readonly Channel<TelemetryBatchMessage> _channel;
    public int Capacity { get; }

    public TelemetryBatchQueue(int capacity = 10_000)
    {
        Capacity = capacity;
        var options = new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleWriter = false,
            SingleReader = true
        };
        _channel = Channel.CreateBounded<TelemetryBatchMessage>(options);
    }

    public ValueTask<bool> EnqueueAsync(TelemetryBatchMessage message, CancellationToken ct = default)
    {
        // Đường truyền nhanh siêu tốc không phân bổ bộ nhớ (Zero-Allocation Fast Path)
        if (_channel.Writer.TryWrite(message))
        {
            return ValueTask.FromResult(true);
        }

        return EnqueueSlowAsync(message, ct);
    }

    private async ValueTask<bool> EnqueueSlowAsync(TelemetryBatchMessage message, CancellationToken ct)
    {
        await _channel.Writer.WriteAsync(message, ct);
        return true;
    }

    public ChannelReader<TelemetryBatchMessage> Reader => _channel.Reader;

    public int Count => _channel.Reader.Count;
}
