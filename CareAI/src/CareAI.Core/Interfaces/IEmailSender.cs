namespace CareAI.Core.Interfaces;

public interface IEmailSender
{
    Task SendEmailAsync(string toEmail, string subject, string body, CancellationToken ct = default);
}
