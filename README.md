# Azure DevOps Work Items Skill

Agent-independent Azure DevOps work-item integration with compact Epic → Feature → Product Backlog Item (PBI) → Task views, dependency metadata, work-item details, state updates and comments.

**This is a data-access skill, not an orchestrator.** It does not depend on Qwen Orchestrator, OpenCode, Codex, Claude Code or any other agent. Any agent that can run PowerShell and consume JSON may use it. A Qwen Code extension manifest is included solely as a convenient distribution adapter.

## Requirements

- PowerShell 7+ (`pwsh --version`). macOS: `brew install powershell` if Homebrew is installed.
- Access to Azure DevOps Services or an Azure DevOps Server compatible with the configured REST API versions.
- Azure DevOps PAT with minimum necessary Work Items read access; write access is required for state updates and comments.
- Three environment variables: `AZURE_DEVOPS_URL`, `AZURE_DEVOPS_PROJECT`, `AZURE_DEVOPS_PAT`.

## Install in Qwen Code

```bash
qwen extensions install https://github.com/jpmbti/azure-devops-skill
qwen extensions list
```

Restart an active Qwen Code CLI session after installing from the terminal. In Qwen Code, use `/skills` and look for `azure-devops-skill:azure-devops`. The installation URL works **after the GitHub repository is created and these files are published**.

To update or remove:

```bash
qwen extensions update azure-devops-skill
qwen extensions uninstall azure-devops-skill
```

## Use without Qwen Code

```bash
git clone https://github.com/jpmbti/azure-devops-skill.git
cd azure-devops-skill
pwsh -File skills/azure-devops/scripts/ado-workitems.ps1 get-work-item -Id 123
```

You can use the same `SKILL.md` and PowerShell script in another agent's skills directory, or invoke the script directly. No extension installation is necessary outside Qwen Code.

## Configure environment (macOS/Linux)

```bash
export AZURE_DEVOPS_URL='https://dev.azure.com/YOUR_ORG'
export AZURE_DEVOPS_PROJECT='YOUR_PROJECT'
read -rsp 'Azure DevOps PAT: ' AZURE_DEVOPS_PAT; echo
export AZURE_DEVOPS_PAT
```

`export` applies only to the current shell and its child processes. GUI-launched apps and unrelated terminals may not inherit these variables. Use your platform's secure secrets manager or approved process environment configuration for long-term use; never commit PATs or place them in `SKILL.md`.

## First use

Find the installed script, or use the repository checkout:

```bash
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 get-work-item -Id 123
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 get-epic-features -Id 100
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 get-feature-index -Id 200
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 get-execution-context -Id 200 -PbiId 300 -TaskId 400
```

Replace the IDs with actual work item IDs. For an installed extension, the agent should resolve `scripts/ado-workitems.ps1` relative to the installed skill's `SKILL.md` rather than copying the example checkout path.

## Example prompts for an agent

- “Use the Azure DevOps skill to show Epic #100 and its direct Features, including states, priorities and predecessor dependencies.”
- “Show the compact PBI/Task index of Feature #200. Do not load description bodies yet.”
- “Load the complete execution context for Feature #200, PBI #300, Task #400, preserving the three descriptions and acceptance criteria.”
- “Inspect Task #400 and its related work items. Do not modify anything.”
- “With my authorization, update Task #400 to In Progress and add a short status comment.”

## Operations

| Command | Purpose |
| --- | --- |
| `get-work-item` | Single item with fields and relations |
| `get-epic-features` | Compact Epic/Feature planning index |
| `get-feature-index` | Compact Feature/PBI/Task index |
| `get-execution-context` | Validated Feature/PBI/Task context |
| `get-feature-tree` | Full Feature tree, potentially large |
| `get-epic-tree` | Full Epic tree, potentially large |
| `start-work-item` | Start a work item after predecessor and state checks |
| `complete-work-item` | Complete a work item after direct-child checks |
| `update-state` | Modify work-item state |
| `add-comment` | Add work-item comment |

## Important limitations

- The script is designed around Scrum work-item type names (`Epic`, `Feature`, `Product Backlog Item`, `Task`). Agile/CMMI/custom processes may require type mapping.
- The full-tree operations recursively fetch items and can generate many API calls. Prefer compact indexes for agent contexts. The Feature index and execution-context operations currently build a tree internally, so compact **output** does not guarantee few API calls.
- `get-execution-context` returns active descriptions but does not include all raw relation objects; retrieve `get-work-item` when full relation details are required.
- The script uses a PAT and PowerShell; it does not require the Microsoft Azure DevOps MCP. The MCP can be integrated separately in a future version.
- Valid workflow states vary by process. `start-work-item` and `complete-work-item` use workflow state categories and hierarchy/dependency guards; they do not verify code reviews, builds, PRs or approvals.

See [examples](docs/EXAMPLES.md), [security](docs/SECURITY.md), [troubleshooting](docs/TROUBLESHOOTING.md) and [changes](CHANGELOG.md).
## Lifecycle operations (v1.1)

```bash
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 start-work-item -Id 123
pwsh -File ./skills/azure-devops/scripts/ado-workitems.ps1 complete-work-item -Id 123
```

These operations apply to Epic, Feature, Product Backlog Item, and Task. Starting requires a proposed state and completed predecessors. Completion requires an in-progress state and completed direct children. They never cascade state changes. If the process defines multiple states in a target category, use `update-state -State "..."` explicitly.
