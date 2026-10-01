using System.Globalization;

namespace CareAI.Infrastructure.WeeklyReports;

public sealed class RuleBasedWeeklyReportFallbackEngine
{
    public string Generate(AnonymousWeeklyStatistics data)
    {
        string Number(double value) => value.ToString("0.#", CultureInfo.GetCultureInfo("vi-VN"));
        var heart = data.AverageHeartRate is { } hr
            ? $"Nhịp tim trung bình ghi nhận là {Number(hr)} nhịp/phút trong {data.HeartRateDays} ngày có dữ liệu."
            : "Chưa có đủ dữ liệu nhịp tim để tổng kết.";
        var steps = data.AverageDailySteps is { } count
            ? $"Trung bình {Number(count)} bước/ngày trong {data.StepDays} ngày có dữ liệu vận động."
            : "Chưa có dữ liệu bước chân; không thể kết luận rằng cụ không vận động.";
        var oxygen = data.AverageSpo2 is { } spo2 && data.MinimumSpo2 is { } minimum
            ? $"SpO₂ trung bình ghi nhận là {Number(spo2)}%, thấp nhất {Number(minimum)}% trong {data.Spo2Days} ngày có dữ liệu."
            : "Chưa có dữ liệu SpO₂ để tổng kết.";
        var alerts = data.AlertCount > 0
            ? $"Hệ thống ghi nhận {data.AlertCount} nhận định bất thường. Gia đình nên xem chi tiết và hỏi thăm cảm nhận của cụ."
            : "Hệ thống chưa ghi nhận nhận định bất thường trong kỳ; điều này không xác nhận sức khỏe hoàn toàn bình thường.";
        var positive = data.AverageDailySteps > 0
            ? "Có ghi nhận hoạt động đi lại trong tuần."
            : "Gia đình hãy tiếp tục đồng hành và hỏi thăm sinh hoạt của cụ.";
        var oxygenAdvice = data.MinimumSpo2 is < 95
            ? "Có mẫu SpO₂ thấp: hãy hỏi thăm triệu chứng, kiểm tra lại phép đo và trao đổi với nhân viên y tế nếu mức thấp lặp lại. "
            : string.Empty;
        return $"1. Tổng quan sức khỏe tuần\n{heart}\n{steps}\n{oxygen}\n\n"
            + $"2. Điểm tích cực & Cần lưu ý\n{positive}\n{alerts}\n"
            + "Dữ liệu thiếu không được tính là 0 và có thể làm báo cáo chưa đầy đủ.\n\n"
            + "3. Lời khuyên sinh hoạt tuần tới\nGia đình hãy hỏi cụ về giấc ngủ, ăn uống và cảm giác khi vận động; hỗ trợ sinh hoạt phù hợp hướng dẫn của nhân viên y tế. "
            + oxygenAdvice
            + "Không tự đổi thuốc dựa trên báo cáo. Nếu có triệu chứng bất thường, liên hệ nhân viên y tế.\n\n"
            + "Báo cáo hỗ trợ theo dõi, không phải chẩn đoán y khoa.";
    }
}
