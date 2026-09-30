# CareAI — Nhiệm vụ 4.1

Đã triển khai trên source ZIP CareAI-main.zip từ cuộc trò chuyện được tham chiếu. Gói ZIP chứa **chỉ các file mới hoặc đã sửa**, với đường dẫn tính từ thư mục CareAI (nơi có CareAI.slnx). Sao chép đè các file tương ứng vào bản dự án cùng phiên bản; nếu đã sửa các file đó, đối chiếu trước khi ghép.

## Nội dung

- Core/Entities/HealthInsight.cs: entity mới, không phụ thuộc ML.NET.
- Infrastructure/AnomalyDetection: model đầu vào float, vector đầu ra [alert, raw score, p-value], options và detector IID.
- Infrastructure/BackgroundWorkers/AnomalyDetectionWorker.cs: chạy trong tiến trình API lúc 02:00 theo múi giờ cấu hình; tạo scope cho DbContext, truy vấn async và truyền CancellationToken, ghi log, cô lập lỗi theo người dùng.
- CareAiDbContext.cs: mapping HealthInsights và unique index theo người dùng/thiết bị/loại/kết thúc khung giờ.
- DatabaseMigrationHelper.cs: thêm DDL tạo bảng theo cách khởi tạo schema hiện có; không thay bằng EF migrations.
- Program.cs: đăng ký options có validation, detector và hosted worker.
- Infrastructure.csproj: Microsoft.ML và Microsoft.ML.TimeSeries phiên bản 5.0.0.
- AnomalyDetectionTests.cs: 9 test mới.

## Hành vi và giả định dữ liệu

Mặc định múi giờ Asia/Ho_Chi_Minh, không phụ thuộc múi giờ hệ điều hành. Timestamp trong HealthMeasurements được hiểu là UTC, giống cách hệ thống đang lưu dữ liệu. Mỗi người dùng và mỗi thiết bị được phân tích riêng để tránh cộng trùng giữa các đồng hồ.

Mỗi lần chạy dùng 14 khung ngày: tối đa 13 ngày lịch sử và 1 ngày cần đánh giá. Lịch sử phải có ít nhất 7 khung hợp lệ. Chỉ khung kết thúc gần nhất được xét cảnh báo; các ngày lịch sử dùng để làm ấm detector, không tạo lại cảnh báo cũ. Khung thiếu dữ liệu bị bỏ qua, không điền 0; IID dùng các quan sát hợp lệ theo thứ tự thời gian.

- Nhịp tim: trung bình khung 22:00–06:00, cảnh báo khi IID phát hiện tăng và giá trị lớn hơn trung bình lịch sử. Đây là phát hiện tăng ở mức trung bình đêm; không phát hiện mọi đột biến nhịp tim ngắn trong đêm. Repo chưa có nhãn ngủ nên khung ban đêm là đại diện, không khẳng định người dùng đang ngủ.
- Vận động: tổng số bước 06:00–12:00; dùng semantics số bước tăng thêm của DashboardController hiện có. Không dùng trực tiếp bộ đếm tích lũy của thiết bị. Cảnh báo khi tổng bằng 0, lịch sử có tối thiểu 7 buổi sáng có vận động và trung bình ít nhất 100 bước. IID phía âm cũng được chạy và lưu p-value; quy tắc zero-step quyết định cảnh báo này để tránh phụ thuộc hoàn toàn vào mẫu ML nhỏ. PValue không phải xác suất mắc bệnh.
- Mỗi khung phải có ít nhất một số đo hợp lệ trong từng giờ. Điều này chỉ là kiểm tra độ phủ tối thiểu, không chứng minh thiết bị được đeo liên tục. Các thiết bị chỉ gửi khi có vận động sẽ không đủ dữ liệu để cảnh báo zero-step.
- Lúc 02:00 ngày D, đêm và buổi sáng ngày D chưa kết thúc; worker phân tích đêm kết thúc 06:00 và buổi sáng kết thúc 12:00 ngày D-1. Do đó đây là phân tích hằng ngày có độ trễ, không thay thế luồng cảnh báo tức thời.

Ứng dụng cần hoạt động lúc 02:00. Worker không chạy bù khi khởi động, không lưu checkpoint và không phân tích lại ngày bị bỏ lỡ. Khi có lỗi, ghi log và thử lại ở lịch chạy kế tiếp. Unique index ngăn lưu trùng giữa nhiều tiến trình nhưng không tránh việc nhiều máy cùng tính toán. Dữ liệu được tải theo từng người dùng/metric, cần phân trang hoặc tổng hợp SQL nếu khối lượng telemetry mỗi người rất lớn.

## Cấu hình tùy chọn

Không cần sửa appsettings để dùng mặc định. Có thể thêm section sau vào cấu hình API:

```json
"AnomalyDetection": {
  "TimeZoneId": "Asia/Ho_Chi_Minh",
  "Confidence": 95,
  "MinimumBaselineDays": 7,
  "MinimumUsualMorningSteps": 100
}
```

Các ngưỡng là mặc định kỹ thuật cần hiệu chỉnh theo dữ liệu vận hành. Không có thay đổi chuỗi kết nối hoặc credential trong gói này.

## Áp dụng và kiểm tra

Tại thư mục CareAI sau khi chép các file:

```powershell
dotnet restore CareAI.slnx
dotnet test tests/CareAI.UnitTests/CareAI.UnitTests.csproj
dotnet run --project src/CareAI.API/CareAI.API.csproj
```

Khi API khởi động, DatabaseMigrationHelper tạo bảng dbo.HealthInsights nếu chưa có, dùng chuỗi kết nối hiện tại. Tài khoản kết nối cần quyền tạo bảng/index. Nếu bảng đã tồn tại với schema khác, script không tự chuyển đổi schema. Luồng startup hiện có ghi log và tiếp tục chạy khi khởi tạo DB thất bại; cần kiểm tra log DB-INIT thành công trước khi chờ worker.

## Xác minh đã thực hiện

- Build Core, Infrastructure, API và UnitTests thành công trên .NET SDK 9.0.318.
- 45/45 test đạt: 36 test hiện có và 9 test mới.
- Warning CS1998 hiện có ở CareAiMasterFactsTests.cs dòng 348; không có lỗi build.
- Test mới bao gồm spike tăng nhịp tim, không cảnh báo khi giảm, zero-step, vận động bình thường, thiếu dữ liệu/độ phủ/lịch sử, cancellation và chạy worker hai lần chỉ lưu một insight.
- Chưa chạy DDL, kiểm tra unique constraint cạnh tranh hoặc kết nối trên Azure SQL thực tế. Test persistence dùng EF Core InMemory. Chưa chạy chờ lịch 02:00 thực tế.

## Thư viện

Dùng bản ổn định Microsoft.ML.TimeSeries 5.0.0 và Microsoft.ML 5.0.0, tương thích build với net9.0 của source. Không gắn nhãn “LTS” cho ML.NET khi chưa có xác nhận vòng đời hỗ trợ riêng.

- https://www.nuget.org/packages/Microsoft.ML.TimeSeries/5.0.0
- https://learn.microsoft.com/en-us/dotnet/machine-learning/tutorials/sales-anomaly-detection
