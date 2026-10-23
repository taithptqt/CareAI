using System.Net;
using System.Net.Mail;
using CareAI.Core.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Services;

public class SmtpEmailSender : IEmailSender
{
    private readonly IConfiguration _config;
    private readonly IHostEnvironment _env;
    private readonly ILogger<SmtpEmailSender> _logger;

    public SmtpEmailSender(IConfiguration config, IHostEnvironment env, ILogger<SmtpEmailSender> logger)
    {
        _config = config;
        _env = env;
        _logger = logger;
    }

    public async Task SendEmailAsync(string toEmail, string subject, string body, CancellationToken ct = default)
    {
        var host = _config["Smtp:Host"];
        var portStr = _config["Smtp:Port"];
        var username = _config["Smtp:Username"];
        var password = _config["Smtp:Password"];
        var fromAddress = _config["Smtp:From"] ?? "noreply@careai.vn";

        if (!string.IsNullOrWhiteSpace(host) && int.TryParse(portStr, out var port))
        {
            try
            {
                using var client = new SmtpClient(host, port)
                {
                    EnableSsl = !bool.TryParse(_config["Smtp:EnableSsl"], out var ssl) || ssl,
                    DeliveryMethod = SmtpDeliveryMethod.Network
                };

                if (!string.IsNullOrWhiteSpace(username) && !string.IsNullOrWhiteSpace(password))
                {
                    client.Credentials = new NetworkCredential(username, password);
                }

                using var mailMessage = new MailMessage(fromAddress, toEmail, subject, body)
                {
                    IsBodyHtml = true
                };

                await client.SendMailAsync(mailMessage, ct);
                _logger.LogInformation("[EMAIL-SENT] Đã gửi email thành công đến {Email}: {Subject}", toEmail, subject);
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[EMAIL-ERROR] Gửi email qua SMTP thất bại đến {Email}", toEmail);
                if (!_env.IsDevelopment()) throw;
            }
        }

        // Nếu chưa cấu hình máy chủ SMTP, ghi log thông tin phục vụ môi trường nội bộ/kiểm thử
        _logger.LogInformation("[EMAIL-DISPATCH] Thông điệp gửi đến {Email}: {Subject}\nNội dung: {Body}", toEmail, subject, body);
    }
}
