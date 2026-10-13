# Usage examples

Set the required environment variables (do not commit your PAT). Run from the repository root.

```powershell
$env:AZURE_DEVOPS_URL = "https://dev.azure.com/my-org"
$env:AZURE_DEVOPS_PROJECT = "MyProject"
$env:AZURE_DEVOPS_PAT = "<your secret PAT>"
$script = "./skills/azure-devops/scripts/ado-workitems.ps1"

pwsh $script get-work-item -Id 123
pwsh $script get-epic-features -Id 100
pwsh $script get-feature-index -Id 101
pwsh $script get-execution-context -Id 101 -PbiId 102 -TaskId 103
pwsh $script get-feature-tree -Id 101
pwsh $script get-epic-tree -Id 100
```

Write operations modify Azure DevOps. Use only when authorized:

```powershell
pwsh $script update-state -Id 103 -State "In Progress"
pwsh $script add-comment -Id 103 -Text "Implementation started"
```

State names depend on the Azure DevOps process. Parent-child relations are distinct from dependency relations.

## Prompts for agents

- "Use the Azure DevOps skill to show Epic 100 and its Features with dependencies, without loading all PBI descriptions."
- "Use the Azure DevOps skill to show the compact PBI/Task index for Feature 101."
- "Use the Azure DevOps skill to retrieve the execution context for Feature 101, PBI 102, Task 103."

## Start and complete work items (v1.1)

```powershell
pwsh $script start-work-item -Id 103
pwsh $script complete-work-item -Id 103
```

Starting validates predecessors; completing validates direct children. Both respect the process's state categories and do not cascade. Confirm the user authorizes each write.
