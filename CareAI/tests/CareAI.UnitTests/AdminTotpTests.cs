using CareAI.Infrastructure.Admin;

namespace CareAI.UnitTests;
public sealed class AdminTotpTests
{
    private const string RfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    [Theory]
    [InlineData(59L, "287082")]
    [InlineData(1111111109L, "081804")]
    [InlineData(1111111111L, "050471")]
    [InlineData(1234567890L, "005924")]
    [InlineData(2000000000L, "279037")]
    [InlineData(20000000000L, "353130")]
    public void MatchesSixDigitSuffixOfRfc6238Sha1Vectors(long seconds, string expected) =>
        Assert.Equal(expected, AdminTotp.Code(RfcSecret, seconds / 30));

    [Fact]
    public void AcceptsCurrentCodeAndRejectsReplayOrMalformedCode()
    {
        var time = DateTimeOffset.FromUnixTimeSeconds(1234567890);
        var counter = time.ToUnixTimeSeconds() / 30;
        var code = AdminTotp.Code(RfcSecret, counter);
        Assert.Equal(counter, AdminTotp.Verify(RfcSecret, code, time, -1));
        Assert.Null(AdminTotp.Verify(RfcSecret, code, time, counter));
        Assert.Null(AdminTotp.Verify(RfcSecret, "abcdef", time, -1));
        Assert.Null(AdminTotp.Verify(RfcSecret, null, time, -1));
    }
}
