# CAREAI AGENT INSTRUCTIONS & INVARIANTS

Every agent operating in this repository must strictly adhere to the commitments defined in:
`d:\IT\PRACTICE\CAM_KET_NGUYEN_TAC_TRIEN_KHAI_CAREAI.md`

### SUPREME PRINCIPLE:
0. STRICT 100% COMMAND COMPLIANCE:
   - ONLY execute what the USER explicitly requests. Never run ahead or take unapproved initiatives.
   - 100% precision: verify every technical statement and code artifact against the approved project documents.
   - Stop and wait for the user's next command upon completing each request.

### Invariant Rules:
1. Sovereign Modular Monolith (.NET 9 LTS) - strictly NO microservices, Kafka, Redis, or Docker/K8s overengineering.
2. Stick 100% to the 16 approved Use Cases (UC-01 to UC-16).
3. Zero-preview packages: strictly stable LTS dependencies (EF Core 9.0.2).
4. Lowercase SHA-256 token hashing (`.ToLowerInvariant()`).
5. HTTP header `X-DeviceId` without hyphen between Device and Id.
6. Deduplication on `ProcessedTelemetryLedgers` only.
7. Filtered Unique Index `UIX_Incidents_SingleActiveElder` on `(ElderProfileId)` where `Status IN ('Open', 'Acknowledged')`.
8. Fast-Lane SOS saves all accompanying samples (Fact 35).
9. Android Native uses Device Protected Storage context & Direct Boot (`LOCKED_BOOT_COMPLETED`).
10. All code must compile cleanly (`dotnet build` exit code 0) and pass all tests (`dotnet test` 36/36 passed).
11. Mandatory Progress Tracking: Always read `d:\IT\PRACTICE\TIEN_TRINH_DU_AN_CAREAI.md` before starting work and continuously auto-update progress and changelog after every session.
12. Mandatory Lessons Learned & Troubleshooting Playbook: Always consult `d:\IT\PRACTICE\SO_TAY_KINH_NGHIEM_DEV_VA_FIX_LOI_CAREAI.md` when encountering errors or before technical operations, and continuously append newly discovered insights and bugfixes after every run.
