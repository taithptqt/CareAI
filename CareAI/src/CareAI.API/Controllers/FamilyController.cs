using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Controllers;

[ApiController]
[Authorize]
public class FamilyController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<FamilyController> _logger;

    public FamilyController(CareAiDbContext db, ILogger<FamilyController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Sinh mã mời 6 ký tự tham gia nhóm chăm sóc gia đình (TTL 24 giờ, mã hóa SHA-256) (UC-03)
    /// RBAC: Chỉ người bảo hộ chính (Primary Caregiver) mới có quyền tạo mã mời.
    /// </summary>
    [HttpPost("api/v1/elders/{elderId}/invitations")]
    [ProducesResponseType(typeof(CreateInvitationResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CreateInvitation(string elderId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var elder = await _db.ElderProfiles.FirstOrDefaultAsync(e => e.Id == elderId && !e.IsDeleted, ct);
        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderId && ec.IsActive, ct);

        if (relation == null)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý người cao tuổi này." });
        }

        if (relation.Role != CaregiverRole.Primary)
        {
            _logger.LogWarning("[FAMILY-INVITE-FORBIDDEN] Secondary Caregiver {CaregiverId} cố tạo mã mời cho Elder {ElderId}", caregiverId, elderId);
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền tạo mã mời gia đình." });
        }

        // Sinh mã mời 6 ký tự ngẫu nhiên chữ in hoa và số (bỏ 0, O, 1, I để tránh nhầm lẫn)
        const string chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
        var codeBuilder = new StringBuilder(6);
        for (int i = 0; i < 6; i++)
        {
            int index = RandomNumberGenerator.GetInt32(0, chars.Length);
            codeBuilder.Append(chars[index]);
        }
        var invitationCode = codeBuilder.ToString();

        // Băm SHA-256 lưu trữ an toàn trong CSDL
        using var sha = SHA256.Create();
        var codeHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(invitationCode))).ToLowerInvariant();

        var expiresAt = DateTime.UtcNow.AddHours(24);

        var invitation = new FamilyInvitation
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = elderId,
            InvitedByCaregiverId = caregiverId,
            InvitationCode = invitationCode,
            InvitationCodeHash = codeHash,
            IsUsed = false,
            ExpiresAt = expiresAt,
            CreatedAt = DateTime.UtcNow
        };

        _db.FamilyInvitations.Add(invitation);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("[FAMILY-INVITE] Primary Caregiver {CaregiverId} đã tạo mã mời {Code} cho Cụ {ElderId} (TTL 24h)",
            caregiverId, invitationCode, elderId);

        return StatusCode(StatusCodes.Status201Created, new CreateInvitationResponse(invitationCode, expiresAt));
    }

    /// <summary>
    /// Chấp nhận mã mời gia đình 6 ký tự để trở thành Secondary Caregiver (UC-03)
    /// </summary>
    [HttpPost("api/v1/invitations/accept")]
    [ProducesResponseType(typeof(AcceptInvitationResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> AcceptInvitation([FromBody] AcceptInvitationRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        if (string.IsNullOrWhiteSpace(request.InvitationCode))
        {
            return BadRequest(new { error = "Mã mời không được để trống." });
        }

        var normalizedCode = request.InvitationCode.Trim().ToUpperInvariant();
        using var sha = SHA256.Create();
        var codeHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(normalizedCode))).ToLowerInvariant();

        var now = DateTime.UtcNow;
        var invite = await _db.FamilyInvitations
            .Include(fi => fi.ElderProfile)
            .FirstOrDefaultAsync(fi => !fi.IsUsed && fi.ExpiresAt >= now &&
                                      (fi.InvitationCodeHash == codeHash || fi.InvitationCode == normalizedCode), ct);

        if (invite == null)
        {
            return BadRequest(new { error = "Mã mời không chính xác, đã qua sử dụng hoặc đã hết hạn (24 giờ)." });
        }

        if (invite.ElderProfile == null || invite.ElderProfile.IsDeleted)
        {
            return BadRequest(new { error = "Hồ sơ người cao tuổi tương ứng không còn khả dụng." });
        }

        // Kiểm tra xem caregiver đã là thành viên trong nhóm chưa
        var existingRelation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.ElderProfileId == invite.ElderProfileId && ec.CaregiverId == caregiverId, ct);

        if (existingRelation != null && existingRelation.IsActive)
        {
            return Conflict(new { error = "Bạn đã là thành viên trong nhóm chăm sóc của người cao tuổi này." });
        }

        if (existingRelation != null)
        {
            // Tái kích hoạt quan hệ cũ
            existingRelation.IsActive = true;
            existingRelation.Role = CaregiverRole.Secondary;
            existingRelation.AssignedAt = now;
        }
        else
        {
            // Thêm quan hệ mới với vai trò Secondary Caregiver
            _db.ElderCaregivers.Add(new ElderCaregiver
            {
                Id = Guid.NewGuid().ToString(),
                ElderProfileId = invite.ElderProfileId,
                CaregiverId = caregiverId,
                Role = CaregiverRole.Secondary,
                IsActive = true,
                AssignedAt = now
            });
        }

        // Đánh dấu mã mời đã dùng
        invite.IsUsed = true;
        invite.AcceptedByCaregiverId = caregiverId;
        invite.AcceptedAt = now;

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[FAMILY-JOIN] Caregiver {CaregiverId} đã tham gia nhóm chăm sóc của Cụ {ElderId} qua mã mời",
            caregiverId, invite.ElderProfileId);

        return Ok(new AcceptInvitationResponse(
            invite.ElderProfileId,
            invite.ElderProfile.FullName,
            CaregiverRole.Secondary.ToString()
        ));
    }

    /// <summary>
    /// Danh sách các thành viên trong nhóm chăm sóc của một Người cao tuổi (UC-03)
    /// </summary>
    [HttpGet("api/v1/elders/{elderId}/members")]
    [ProducesResponseType(typeof(List<FamilyMemberDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetFamilyMembers(string elderId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var isMember = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderId && ec.IsActive, ct);

        if (!isMember)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem nhóm chăm sóc của người cao tuổi này." });
        }

        var members = await _db.ElderCaregivers
            .AsNoTracking()
            .Where(ec => ec.ElderProfileId == elderId && ec.IsActive)
            .Include(ec => ec.Caregiver)
            .OrderBy(ec => ec.Role) // Primary trước, Secondary sau
            .ThenBy(ec => ec.AssignedAt)
            .ToListAsync(ct);

        var result = members
            .Where(m => m.Caregiver != null)
            .Select(m => new FamilyMemberDto(
                m.CaregiverId,
                m.Caregiver!.FullName,
                m.Caregiver.Email,
                m.Caregiver.PhoneNumber,
                m.Role.ToString(),
                m.IsActive,
                m.AssignedAt
            ))
            .ToList();

        return Ok(result);
    }

    /// <summary>
    /// Thu hồi quyền thành viên trong nhóm chăm sóc gia đình (UC-03)
    /// RBAC: Chỉ Primary Caregiver mới có quyền xóa thành viên khác. Không thể tự xóa chính mình.
    /// </summary>
    [HttpDelete("api/v1/elders/{elderId}/members/{targetCaregiverId}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RevokeFamilyMember(string elderId, string targetCaregiverId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var callerRelation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderId && ec.IsActive, ct);

        if (callerRelation == null)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý nhóm gia đình này." });
        }

        var isSelfLeave = caregiverId == targetCaregiverId;

        if (callerRelation.Role != CaregiverRole.Primary)
        {
            if (!isSelfLeave)
            {
                _logger.LogWarning("[FAMILY-REVOKE-FORBIDDEN] Secondary Caregiver {CaregiverId} cố xóa thành viên {TargetId}", caregiverId, targetCaregiverId);
                return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền thu hồi quyền thành viên." });
            }
        }
        else if (isSelfLeave)
        {
            return BadRequest(new { error = "Người bảo hộ chính không thể tự xóa quyền của chính mình khỏi nhóm." });
        }

        var targetRelation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == targetCaregiverId && ec.ElderProfileId == elderId && ec.IsActive, ct);

        if (targetRelation == null)
        {
            return NotFound(new { error = "Không tìm thấy thành viên cần xóa trong nhóm chăm sóc." });
        }

        targetRelation.IsActive = false;
        await _db.SaveChangesAsync(ct);

        if (isSelfLeave)
        {
            _logger.LogInformation("[FAMILY-SELF-LEAVE] Secondary Caregiver {CaregiverId} đã tự rút khỏi nhóm chăm sóc Elder {ElderId}",
                caregiverId, elderId);
            return Ok(new { message = "Bạn đã rời khỏi nhóm chăm sóc người cao tuổi thành công.", targetCaregiverId });
        }

        _logger.LogInformation("[FAMILY-REVOKED] Primary Caregiver {CaregiverId} đã thu hồi quyền thành viên của {TargetId} khỏi Elder {ElderId}",
            caregiverId, targetCaregiverId, elderId);

        return Ok(new { message = "Đã thu hồi quyền thành viên trong nhóm gia đình thành công.", targetCaregiverId });
    }
}
