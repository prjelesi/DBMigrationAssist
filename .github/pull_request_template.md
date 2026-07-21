## Summary
<!-- What does this PR do? -->

## Type of change
- [ ] New feature (assessment engine, API endpoint, Power Apps screen)
- [ ] Bug fix
- [ ] Factory script update
- [ ] Dataverse schema change
- [ ] Copilot Studio agent update
- [ ] Infrastructure / Docker change

## Testing
- [ ] Ran `Invoke-Assessment.ps1` against sample CSV → output verified
- [ ] Docker container builds and API responds on `/health`
- [ ] Tested affected endpoint(s) with Postman / curl
- [ ] Copilot Studio topic tested in Test pane

## Checklist
- [ ] No secrets or credentials committed (check `.env` not staged)
- [ ] `docker/.env.example` updated if new env vars added
- [ ] `connectors/openapi.json` updated if API changed
- [ ] `dataverse/tables.json` updated if schema changed
