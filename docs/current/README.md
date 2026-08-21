# Current System Documentation

**Status:** Authoritative current-state documentation  
**Baseline:** `main` at `9740e207603d5c2302e46207df228dd9af7b94ff`  
**Reviewed:** 2026-08-20

This documentation describes the system that is implemented in this repository. It separates verified capabilities from known limitations and future work.

## Documentation set

| Document | Purpose |
|---|---|
| [System Overview](SYSTEM_OVERVIEW.md) | Product scope, implemented workflows, portal routes and feature status. |
| [Architecture and Security](ARCHITECTURE_AND_SECURITY.md) | Runtime components, persistence, trust boundaries, authentication and authorization. |
| [API Reference](API_REFERENCE.md) | Implemented HTTP endpoint groups, access model and important behavior. |
| [Operations and Deployment](OPERATIONS_AND_DEPLOYMENT.md) | Local setup, build, storage, health checks and Azure deployment model. |
| [Known Limitations](KNOWN_LIMITATIONS.md) | Unsupported, partial and unverified capabilities that must not be presented as complete. |

## Source of truth

When documentation and code disagree, use the implementation and tests as the source of truth. The primary implementation anchors are:

- `src/backend/AssessmentToolkit.Api/Program.cs` and `Controllers/`
- `src/backend/AssessmentToolkit.Data/AssessmentDbContext.cs` and `Migrations/`
- `src/backend/AssessmentToolkit.Worker/`
- `src/agent/AssessmentToolkit.Agent/`
- `src/frontend/src/App.tsx`, `pages/` and `lib/api.ts`
- `docker-compose.yml`, `build.ps1`, `infra/` and `tests/`