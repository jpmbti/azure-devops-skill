# Troubleshooting

## Missing environment variables
Set `AZURE_DEVOPS_URL`, `AZURE_DEVOPS_PROJECT`, and `AZURE_DEVOPS_PAT` in the shell that starts your agent or PowerShell script.

## PowerShell not found
Install PowerShell 7 and confirm `pwsh -v` works.

## HTTP 401 or 403
Check PAT expiration, required scopes, organization/project access, and the configured URL.

## HTTP 404
Check work item IDs, project name and Azure DevOps Server/Services URL.

## Invalid state
Use a state supported by the work item type and process (e.g. Agile/Scrum/custom process).

## Hierarchy mismatch
`get-execution-context` validates the specified Feature → PBI → Task chain. Verify the IDs and parent relations.

## Large outputs
Prefer `get-epic-features` → `get-feature-index` → `get-execution-context` instead of `get-epic-tree`.
