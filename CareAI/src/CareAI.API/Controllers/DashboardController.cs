using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/dashboard")]
[Authorize]
public class DashboardController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<DashboardController> _logger;

    public DashboardController(CareAiDbContext db, ILogger<DashboardController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Bảng điều khiển giám sát sức khỏe tổng hợp của Người cao tuổi (UC-15 / UC-16)
    /// </summary>
    [HttpGet("elder/{elderProfileId}")]
    [ProducesResponseType(typeof(ElderDashboardResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderDashboard(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        // BOLA Check
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var elder = await _db.ElderProfiles
            .Include(e => e.Devices)
            .FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);

        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        var now = DateTime.UtcNow;
        var age = now.Year - elder.DateOfBirth.Year;
        if (elder.DateOfBirth.Date > now.AddYears(-age)) age--;

        // Trạng thái thiết bị (luôn sắp xếp theo LastHeartbeat giảm dần để ưu tiên thiết bị hoạt động mới nhất)
        var activeDevices = elder.Devices
            .Where(d => d.IsActive)
            .OrderByDescending(d => d.LastHeartbeat)
            .ToList();
        var isOnline = activeDevices.Any(d =>
            d.LastHeartbeat >= now.Subtract(DeviceStaleEngine.StaleAfterFor(d.DeviceType)));
        var deviceStatus = isOnline ? "ONLINE" : "OFFLINE";
        var lastSyncedAt = activeDevices.Count > 0 ? (DateTime?)activeDevices.Max(d => d.LastHeartbeat) : null;

        // Xác định tên định danh cụ thể của đồng hồ đeo tay (luôn ưu tiên thiết bị phát tín hiệu mới nhất)
        var watchDevice = activeDevices.FirstOrDefault(d =>
            string.Equals(d.DeviceType, "Smartwatch", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(d.DeviceType, "AppleWatch", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(d.DeviceType, "GalaxyWatch", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(d.DeviceType, "WearOS", StringComparison.OrdinalIgnoreCase));

        string? watchModel = null;
        string watchStatus = "NOT_PAIRED";
        string? watchDisconnectReason = null;
        bool? isWatchWorn = null;
        bool? isWatchCharging = null;
        int? watchBatteryLevel = null;

        if (watchDevice != null)
        {
            if (!string.IsNullOrWhiteSpace(watchDevice.DeviceModel))
            {
                watchModel = watchDevice.DeviceModel;
            }
            else if (watchDevice.Id.StartsWith("DEV_DEMO_", StringComparison.OrdinalIgnoreCase))
            {
                watchModel = "Galaxy Watch (Mô phỏng)";
            }
            else if (string.Equals(watchDevice.DeviceType, "AppleWatch", StringComparison.OrdinalIgnoreCase))
            {
                watchModel = "Apple Watch";
            }
            else
            {
                watchModel = "Galaxy Watch";
            }

            var isWatchOnline = watchDevice.LastHeartbeat >= now.Subtract(DeviceStaleEngine.StaleAfterFor(watchDevice.DeviceType));
            watchStatus = isWatchOnline ? "ONLINE" : "DISCONNECTED";
            watchDisconnectReason = isWatchOnline ? null : (watchDevice.DisconnectReason ?? "SIGNAL_LOST");

            isWatchWorn = watchDevice.IsWatchWorn;
            isWatchCharging = watchDevice.IsWatchCharging;
            watchBatteryLevel = watchDevice.WatchBatteryLevel;

            if (watchDevice.Id.StartsWith("DEV_DEMO_", StringComparison.OrdinalIgnoreCase))
            {
                isWatchWorn ??= true;
                isWatchCharging ??= false;
                watchBatteryLevel ??= 85;
            }
        }

        // Chỉ số sinh hiệu mới nhất
        var latestHr = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "HEART_RATE")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        var latestSpo2 = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "SPO2")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        // Demo metrics remain separate from real vitals, charts and clinical alerts.
        var demoSince = now.AddHours(-1);
        var demoHr = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "DEMO_HEART_RATE" && m.RecordedAt >= demoSince)
            .OrderByDescending(m => m.RecordedAt)
            .FirstOrDefaultAsync(ct);
        var demoSpo2 = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "DEMO_SPO2" && m.RecordedAt >= demoSince)
            .OrderByDescending(m => m.RecordedAt)
            .FirstOrDefaultAsync(ct);

        var latestBp = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && (m.MetricType == "BLOOD_PRESSURE" || m.MetricType == "BP_SYSTOLIC"))
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        // Số bước chân hôm nay
        var todayStart = DateTime.UtcNow.Date;
        var todaySteps = (int)await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "STEPS" && m.Timestamp >= todayStart)
            .SumAsync(m => m.Value, ct);

        // Sự cố đang mở
        var activeIncident = await _db.Incidents
            .Include(i => i.TimelineEvents)
            .FirstOrDefaultAsync(i => i.ElderProfileId == elderProfileId && 
                                     (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        // Badge màu sắc tổng thể
        string badgeColor = "GREEN";
        if (activeIncident != null)
        {
            badgeColor = activeIncident.Severity == IncidentSeverity.Critical ? "RED" : "YELLOW";
        }
        else if (latestHr != null && (latestHr.Value > 100 || latestHr.Value < 50))
        {
            badgeColor = "YELLOW";
        }

        // Tọa độ GPS gần nhất (từ viễn trắc GPS hoặc sự cố cấp cứu)
        var latestLat = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "GPS_LAT")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);
        var latestLng = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "GPS_LNG")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        string? lastKnownGpsLocation = null;
        if (latestLat != null && latestLng != null)
        {
            // Bắt buộc dùng FormattableString.Invariant để đảm bảo tọa độ GPS luôn dùng dấu chấm '.' ngăn cách thập phân,
            // tránh bị đổi thành dấu phẩy ',' trên các môi trường chạy macOS/Linux có CultureInfo địa phương.
            lastKnownGpsLocation = FormattableString.Invariant($"{latestLat.Value:F6}, {latestLng.Value:F6}");
        }
        else
        {
            var lastTimelineGps = await _db.IncidentTimelineEvents
                .Where(t => t.Incident.ElderProfileId == elderProfileId && t.Description.Contains("Tọa độ GPS:") && !t.Description.Contains("N/A"))
                .OrderByDescending(t => t.RecordedAt)
                .Select(t => t.Description)
                .FirstOrDefaultAsync(ct);

            if (lastTimelineGps != null)
            {
                var marker = "Tọa độ GPS:";
                var idx = lastTimelineGps.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    var extracted = lastTimelineGps.Substring(idx + marker.Length).Trim();
                    if (!string.IsNullOrWhiteSpace(extracted))
                    {
                        lastKnownGpsLocation = extracted;
                    }
                }
            }
        }

        var response = new ElderDashboardResponse(
            elder.Id,
            elder.FullName,
            age,
            badgeColor,
            deviceStatus,
            latestHr != null ? new VitalSignDto(latestHr.MetricType, latestHr.Value, latestHr.Unit, DateTime.SpecifyKind(latestHr.Timestamp, DateTimeKind.Utc), latestHr.Value > 100 || latestHr.Value < 50 ? "YELLOW" : "GREEN") : null,
            latestBp != null ? new VitalSignDto(latestBp.MetricType, latestBp.Value, latestBp.Unit, DateTime.SpecifyKind(latestBp.Timestamp, DateTimeKind.Utc), "GREEN") : null,
            latestSpo2 != null ? new VitalSignDto(latestSpo2.MetricType, latestSpo2.Value, latestSpo2.Unit, DateTime.SpecifyKind(latestSpo2.Timestamp, DateTimeKind.Utc), latestSpo2.Value < 95 ? "YELLOW" : "GREEN") : null,
            todaySteps,
            StepGoal: 6000,
            LastKnownGpsLocation: lastKnownGpsLocation,
            lastSyncedAt,
            activeIncident != null ? IncidentDtoMapper.ToResponse(activeIncident, elder.FullName) : null,
            DemoHeartRate: demoHr != null ? new VitalSignDto(demoHr.MetricType, demoHr.Value, demoHr.Unit, DateTime.SpecifyKind(demoHr.Timestamp, DateTimeKind.Utc), "YELLOW") : null,
            DemoSpO2: demoSpo2 != null ? new VitalSignDto(demoSpo2.MetricType, demoSpo2.Value, demoSpo2.Unit, DateTime.SpecifyKind(demoSpo2.Timestamp, DateTimeKind.Utc), "YELLOW") : null,
            WatchModel: watchModel,
            WatchStatus: watchStatus,
            WatchDisconnectReason: watchDisconnectReason,
            IsWatchWorn: isWatchWorn,
            IsWatchCharging: isWatchCharging,
            WatchBatteryLevel: watchBatteryLevel
        );

        return Ok(response);
    }

    /// <summary>
    /// Tra cứu chuỗi dữ liệu biến thiên nhịp tim 24 giờ phục vụ vẽ biểu đồ (Nhiệm vụ 1.4)
    /// </summary>
    [HttpGet("elder/{elderProfileId}/vitals/heart-rate-24h")]
    [ProducesResponseType(typeof(HeartRate24hResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderHeartRate24h(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var since = DateTime.UtcNow.AddHours(-24);
        var samples = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "HEART_RATE" && m.Timestamp >= since)
            .OrderBy(m => m.Timestamp)
            .Select(m => new HeartRatePointDto(m.Timestamp, m.Value))
            .ToListAsync(ct);

        if (samples.Count == 0)
        {
            return Ok(new HeartRate24hResponse([], 0, 0, 0, 0));
        }

        var min = samples.Min(s => s.Value);
        var max = samples.Max(s => s.Value);
        var avg = Math.Round(samples.Average(s => s.Value), 1);
        var latest = samples.Last().Value;

        return Ok(new HeartRate24hResponse(samples, min, max, avg, latest));
    }

    /// <summary>
    /// Tra cứu lịch sử đo huyết áp phục vụ vẽ biểu đồ đường kép Tâm thu / Tâm trương (Nhiệm vụ 1.4 mở rộng)
    /// </summary>
    [HttpGet("elder/{elderProfileId}/vitals/blood-pressure-history")]
    [ProducesResponseType(typeof(BloodPressureHistoryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderBloodPressureHistory(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var since = DateTime.UtcNow.AddDays(-14);
        var sysList = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && (m.MetricType == "BLOOD_PRESSURE_SYS" || m.MetricType == "BLOOD_PRESSURE") && m.Timestamp >= since)
            .OrderBy(m => m.Timestamp)
            .ToListAsync(ct);

        var diaList = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "BLOOD_PRESSURE_DIA" && m.Timestamp >= since)
            .OrderBy(m => m.Timestamp)
            .ToListAsync(ct);

        var points = new List<BloodPressurePointDto>();

        foreach (var sys in sysList)
        {
            var matchedDia = diaList.FirstOrDefault(d => Math.Abs((d.Timestamp - sys.Timestamp).TotalMinutes) <= 5);
            var diaValue = matchedDia?.Value ?? 80.0;
            points.Add(new BloodPressurePointDto(sys.Timestamp, sys.Value, diaValue));
        }

        if (points.Count == 0)
        {
            return Ok(new BloodPressureHistoryResponse([], 0, 0, "Chưa có dữ liệu", "GRAY"));
        }

        var latest = points.Last();
        string classification = "Bình thường";
        string statusColor = "GREEN";

        if (latest.Systolic >= 160 || latest.Diastolic >= 100)
        {
            classification = "Cơn tăng huyết áp (Nguy hiểm)";
            statusColor = "RED";
        }
        else if (latest.Systolic >= 140 || latest.Diastolic >= 90)
        {
            classification = "Tăng huyết áp độ 1";
            statusColor = "YELLOW";
        }
        else if (latest.Systolic >= 120 || latest.Diastolic >= 80)
        {
            classification = "Tiền tăng huyết áp";
            statusColor = "YELLOW";
        }

        return Ok(new BloodPressureHistoryResponse(points, latest.Systolic, latest.Diastolic, classification, statusColor));
    }

    /// <summary>
    /// Tra cứu chuỗi dữ liệu SpO2 24 giờ phục vụ vẽ biểu đồ và đếm số cơn tụt oxy (Nhiệm vụ 1.4 mở rộng)
    /// </summary>
    [HttpGet("elder/{elderProfileId}/vitals/spo2-24h")]
    [ProducesResponseType(typeof(Spo224hResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderSpo224h(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var since = DateTime.UtcNow.AddHours(-24);
        var samples = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "SPO2" && m.Timestamp >= since)
            .OrderBy(m => m.Timestamp)
            .Select(m => new Spo2PointDto(m.Timestamp, m.Value))
            .ToListAsync(ct);

        if (samples.Count == 0)
        {
            return Ok(new Spo224hResponse([], 0, 0, 0, 0, 0, "UNKNOWN"));
        }

        var min = samples.Min(s => s.Value);
        var max = samples.Max(s => s.Value);
        var avg = Math.Round(samples.Average(s => s.Value), 1);
        var latest = samples.Last().Value;
        var dipsCount = samples.Count(s => s.Value < 95.0);
        var statusColor = latest < 90.0 ? "RED" : (latest < 95.0 ? "YELLOW" : "GREEN");

        return Ok(new Spo224hResponse(samples, min, max, avg, latest, dipsCount, statusColor));
    }

    /// <summary>
    /// Tra cứu phân bố vận động bước chân theo 24 giờ trong ngày phục vụ vẽ biểu đồ cột nhịp sinh học (Nhiệm vụ 1.4 mở rộng)
    /// </summary>
    [HttpGet("elder/{elderProfileId}/vitals/hourly-steps-24h")]
    [ProducesResponseType(typeof(HourlySteps24hResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderHourlySteps24h(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var startOfDay = DateTime.UtcNow.Date;
        var stepSamples = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "STEPS" && m.Timestamp >= startOfDay)
            .OrderBy(m => m.Timestamp)
            .ToListAsync(ct);

        var hourlyMap = new Dictionary<int, int>();
        for (int h = 0; h < 24; h++) hourlyMap[h] = 0;

        foreach (var sample in stepSamples)
        {
            var h = sample.Timestamp.Hour;
            hourlyMap[h] += (int)sample.Value;
        }

        var totalSteps = hourlyMap.Values.Sum();
        var list = hourlyMap.OrderBy(kv => kv.Key).Select(kv => new HourlyStepsDto(kv.Key, kv.Value)).ToList();
        var peak = list.OrderByDescending(x => x.Steps).First();

        return Ok(new HourlySteps24hResponse(list, totalSteps, peak.Hour, peak.Steps));
    }

    /// <summary>
    /// Tra cứu tóm tắt thời lượng và chất lượng giấc ngủ đêm qua (Gói B - Circadian Sleep Duration)
    /// </summary>
    [HttpGet("elder/{elderProfileId}/vitals/sleep-summary")]
    [ProducesResponseType(typeof(SleepSummaryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderSleepSummary(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var elder = await _db.ElderProfiles.AsNoTracking().FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);
        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        // Lấy thời điểm bắt đầu đêm qua (từ 20:00 tối hôm trước đến 10:00 sáng hôm nay)
        var today = DateTime.UtcNow.Date;
        var nightStart = today.AddDays(-1).AddHours(20);
        var nightEnd = today.AddHours(10);

        // Kiểm tra xem có bản ghi SLEEP hoặc các giai đoạn SLEEP_* từ cảm biến không
        var sleepSamples = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType.StartsWith("SLEEP") && m.Timestamp >= nightStart && m.Timestamp <= nightEnd)
            .OrderBy(m => m.Timestamp)
            .ToListAsync(ct);

        int totalSleepMinutes = 0;
        DateTime? sleepStart = null;
        DateTime? sleepEnd = null;
        int deepMinutes = 0;
        int lightMinutes = 0;
        int wakeCount = 0;
        int? remMinutes = null;
        int? awakeMinutes = null;
        double? minSleepingHr = null;
        double? avgSleepingHr = null;
        double? minNightSpo2 = null;
        int? nightSpo2Dips = null;
        string? breathingDisturbances = null;
        string sleepQuality;
        string statusColor;

        var totalSleepSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP");
        var deepSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_DEEP");
        var coreSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_CORE");
        var remSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_REM");
        var awakeSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_AWAKE");
        var wakeCountSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_WAKE_COUNT");
        var hrMinSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_HR_MIN");
        var hrAvgSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_HR_AVG");
        var spo2MinSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_SPO2_MIN");
        var spo2DipsSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_SPO2_DIPS");
        var apneaSample = sleepSamples.FirstOrDefault(m => m.MetricType == "SLEEP_APNEA_RISK");

        if (totalSleepSample != null || deepSample != null || coreSample != null)
        {
            if (totalSleepSample != null)
            {
                totalSleepMinutes = (int)totalSleepSample.Value;
                sleepStart = totalSleepSample.Timestamp;
                sleepEnd = totalSleepSample.RecordedAt;
            }

            if (deepSample != null)
            {
                deepMinutes = (int)deepSample.Value;
            }
            if (coreSample != null)
            {
                lightMinutes = (int)coreSample.Value;
            }
            if (remSample != null)
            {
                remMinutes = (int)remSample.Value;
            }
            if (awakeSample != null)
            {
                awakeMinutes = (int)awakeSample.Value;
            }
            if (wakeCountSample != null)
            {
                wakeCount = (int)wakeCountSample.Value;
            }

            // Nếu đồng hồ chỉ đẩy tổng thời gian ngủ (không có stages chi tiết từ phần cứng)
            if (deepSample == null && totalSleepMinutes > 0)
            {
                deepMinutes = (int)(totalSleepMinutes * 0.28);
                lightMinutes = totalSleepMinutes - deepMinutes;
                wakeCount = 1;
            }
            else if (totalSleepMinutes == 0 && (deepMinutes > 0 || lightMinutes > 0))
            {
                totalSleepMinutes = deepMinutes + lightMinutes + (remMinutes ?? 0);
            }

            if (hrMinSample != null) minSleepingHr = hrMinSample.Value;
            if (hrAvgSample != null) avgSleepingHr = hrAvgSample.Value;
            if (spo2MinSample != null) minNightSpo2 = spo2MinSample.Value;
            if (spo2DipsSample != null) nightSpo2Dips = (int)spo2DipsSample.Value;
            if (apneaSample != null) breathingDisturbances = apneaSample.Value >= 1.0 ? "ELEVATED" : "NORMAL";

            // Đánh giá chất lượng giấc ngủ lâm sàng (Clinical Sleep Quality Evaluation)
            if (breathingDisturbances == "ELEVATED" || (minNightSpo2.HasValue && minNightSpo2.Value < 85.0))
            {
                sleepQuality = "Nguy cơ ngưng thở / Thiếu oxy ban đêm";
                statusColor = "RED";
            }
            else if (totalSleepMinutes < 300)
            {
                sleepQuality = "Thiếu ngủ (Nguy cơ suy nhược)";
                statusColor = "RED";
            }
            else if (wakeCount >= 4 || (awakeMinutes.HasValue && awakeMinutes.Value >= 60))
            {
                sleepQuality = "Ngủ chập chờn (Thức giấc nhiều lần)";
                statusColor = "YELLOW";
            }
            else if (deepMinutes < 30 && totalSleepMinutes >= 360)
            {
                sleepQuality = "Ngủ nông (Thiếu ngủ sâu phục hồi)";
                statusColor = "YELLOW";
            }
            else if (totalSleepMinutes < 360)
            {
                sleepQuality = "Ngủ ít (Cần theo dõi)";
                statusColor = "YELLOW";
            }
            else if (totalSleepMinutes > 540)
            {
                sleepQuality = "Ngủ nhiều bất thường";
                statusColor = "YELLOW";
            }
            else
            {
                sleepQuality = "Tốt (Đạt chuẩn y tế)";
                statusColor = "GREEN";
            }
        }
        else
        {
            totalSleepMinutes = 0;
            sleepStart = null;
            sleepEnd = null;
            deepMinutes = 0;
            lightMinutes = 0;
            wakeCount = 0;
            sleepQuality = "Chưa có dữ liệu";
            statusColor = "GRAY";
        }

        var response = new SleepSummaryResponse(
            elderProfileId,
            today,
            totalSleepMinutes,
            sleepStart,
            sleepEnd,
            deepMinutes,
            lightMinutes,
            wakeCount,
            sleepQuality,
            statusColor,
            remMinutes,
            awakeMinutes,
            minSleepingHr,
            avgSleepingHr,
            minNightSpo2,
            nightSpo2Dips,
            breathingDisturbances
        );

        return Ok(response);
    }
}
