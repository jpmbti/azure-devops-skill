---
name: azure-devops
description: Agent-independent Azure DevOps work item access. Retrieve Epics, Features, PBIs, Tasks, relations, dependencies, compact execution contexts, update states and add comments.
---

# Azure DevOps Skill

This skill is independent of any agent, IDE, or orchestrator. It exposes an Azure DevOps PowerShell command-line interface.

## Prerequisites

- PowerShell 7 (command `pwsh`)
- Network access to the Azure DevOps Server/Services instance
- `AZURE_DEVOPS_URL`, `AZURE_DEVOPS_PROJECT`, `AZURE_DEVOPS_PAT` environment variables

Never display or log PATs. Run the script located at `scripts/ado-workitems.ps1` **relative to this SKILL.md file**.

## Operations

| Operation | Arguments | Purpose |
| --- | --- | --- |
| `get-work-item` | `-Id <id>` | Work item fields and relations |
| `get-epic-features` | `-Id <epicId>` | Compact Epic and direct Features with dependencies |
| `get-feature-index` | `-Id <featureId>` | Compact Feature, PBI and Task index |
| `get-execution-context` | `-Id <featureId> -PbiId <pbiId> -TaskId <taskId>` | Bounded Feature/PBI/Task contract, validated hierarchy |
| `get-feature-tree` | `-Id <featureId>` | Complete selected Feature subtree |
| `get-epic-tree` | `-Id <epicId>` | Complete Epic hierarchy; use sparingly |
| `update-state` | `-Id <id> -State "<state>"` | Change state to a valid process-specific state |
| `add-comment` | `-Id <id> -Text "<comment>"` | Add a comment |

### Example

```powershell
pwsh ./scripts/ado-workitems.ps1 get-epic-features -Id 100
pwsh ./scripts/ado-workitems.ps1 get-feature-index -Id 101
pwsh ./scripts/ado-workitems.ps1 get-execution-context -Id 101 -PbiId 102 -TaskId 103
```

## Context-efficient retrieval

For large Epics, use `get-epic-features` to find the Feature, then `get-feature-index` to select a PBI/Task, then `get-execution-context` to load just the active chain. Avoid `get-epic-tree` unless a complete diagnostic dump is explicitly required. Do not replace missing descriptions with invented summaries. Treat Azure DevOps as the source of truth.

Parent/Child relations define hierarchy. Predecessor/Successor relations define dependencies; do not confuse them. Any agent or orchestrator using this skill decides its own work-selection, approval, branching, testing and execution lifecycle.

## Safety

Read operations are non-mutating. `update-state` and `add-comment` change Azure DevOps; perform them only when the user or invoking workflow authorizes the change. Never claim an update succeeded until the command returns success.

For detailed setup, examples and troubleshooting, see the repository README and docs.
