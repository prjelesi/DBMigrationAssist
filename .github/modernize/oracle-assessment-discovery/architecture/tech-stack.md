# Technology Stack

## Runtime and Languages

- .NET 8 and C# for API, worker, shared contracts and assessment agent.
- TypeScript 6, React 19 and Vite 8 for the portal.
- PostgreSQL 16 locally with EF Core 8 and Npgsql 8.

## Feature-Relevant Dependencies

- `Oracle.ManagedDataAccess.Core` 23.7.0 for Oracle connectivity.
- ASP.NET Core controllers, cookie authentication, antiforgery and hosted services.
- EF Core 8.0.11 and Npgsql EF Core 8.0.11 for persistence.
- Azure OpenAI-compatible client through `Azure.AI.OpenAI` 2.2.0-beta.4.
- React Query 5 for server state, Axios 1 for HTTP, React Flow 11 for communication maps.
- xUnit 2.9.2, EF Core SQLite/InMemory and Vitest 4 for tests.

## Current Constraints

- Oracle findings are carried as versioned JSON inside assessment results.
- Database migrations are applied by the API at startup.
- The agent must remain outbound-only and use existing HMAC authentication.
- Portal mutations use cookie authentication and antiforgery.
- Existing graph and portfolio APIs are used by current portal pages and require compatibility during rollout.
- Current Oracle certification is limited; only the PostgreSQL agent has repository E2E coverage.
