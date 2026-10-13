[CmdletBinding()]
param(
  [Parameter(Position=0,Mandatory=$true)]
  [ValidateSet(
    "get-work-item",
    "get-epic-features",
    "get-feature-tree",
    "get-feature-index",
    "get-execution-context",
    "get-epic-tree",
    "update-state",
    "start-work-item",
    "complete-work-item",
    "add-comment"
  )]
  [string]$Operation,
  [int]$Id,
  [int]$PbiId,
  [int]$TaskId,
  [string]$State,
  [string]$Text
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$ApiVersion="7.0"

function Env([string]$Name) {
  $v=[Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($v)) {
    throw "Required environment variable '$Name' is not set."
  }
  $v
}

$Pat=Env "AZURE_DEVOPS_PAT"
$BaseUrl=(Env "AZURE_DEVOPS_URL").TrimEnd("/")
$Project=Env "AZURE_DEVOPS_PROJECT"
$token=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$Headers=@{
  Authorization="Basic $token"
  Accept="application/json"
}

function Invoke-Ado(
  [string]$Method,
  [string]$Uri,
  $Body=$null,
  [string]$ContentType="application/json"
) {
  try {
    $req=@{
      Method=$Method
      Uri=$Uri
      Headers=$Headers
    }

    if ($null -ne $Body) {
      # JSON Patch is already serialized by UpdateState.
      if ($Body -is [string] -and $ContentType -eq "application/json-patch+json") {
        $req.Body=$Body
      } else {
        $req.Body=$Body | ConvertTo-Json -Depth 30 -Compress
      }
      # ContentType must be set as a header for Invoke-RestMethod splatting.
      $req.ContentType=$ContentType
    }

    Invoke-RestMethod @req
  } catch {
    $status=$null
    try {
      $status=[int]$_.Exception.Response.StatusCode
    } catch {}

    if ($status) {
      throw "Azure DevOps request failed (HTTP $status): $Method $Uri"
    }

    throw "Azure DevOps request failed: $Method $Uri - $($_.Exception.Message)"
  }
}

function Field($Fields,[string]$Name) {
  $p=$Fields.PSObject.Properties[$Name]
  if ($null -eq $p) {
    return $null
  }
  $p.Value
}

function RelatedId([string]$Url) {
  if ($Url -match "/workItems/(\d+)(?:\?.*)?$") {
    return [int]$Matches[1]
  }
  $null
}

function NormalizeRelation($r) {
  $name=$null

  if ($r.attributes) {
    $p=$r.attributes.PSObject.Properties["name"]
    if ($p) {
      $name=$p.Value
    }
  }

  [pscustomobject]@{
    rel=$r.rel
    name=$name
    workItemId=(RelatedId $r.url)
    url=$r.url
  }
}

function Raw([int]$WorkItemId) {
  $proj=[Uri]::EscapeDataString($Project)
  Invoke-Ado "GET" "$BaseUrl/$proj/_apis/wit/workitems/$WorkItemId`?`$expand=relations&api-version=$ApiVersion"
}

function Normalize($i) {
  $rels=@()

  if ($i.relations) {
    $rels=@(
      $i.relations | ForEach-Object {
        NormalizeRelation $_
      }
    )
  }

  [pscustomobject]@{
    id=$i.id
    rev=$i.rev
    type=(Field $i.fields "System.WorkItemType")
    title=(Field $i.fields "System.Title")
    state=(Field $i.fields "System.State")
    reason=(Field $i.fields "System.Reason")
    assignedTo=(Field $i.fields "System.AssignedTo")
    areaPath=(Field $i.fields "System.AreaPath")
    iterationPath=(Field $i.fields "System.IterationPath")
    description=(Field $i.fields "System.Description")
    acceptanceCriteria=(Field $i.fields "Microsoft.VSTS.Common.AcceptanceCriteria")
    priority=(Field $i.fields "Microsoft.VSTS.Common.Priority")
    backlogPriority=(Field $i.fields "Microsoft.VSTS.Common.BacklogPriority")
    stackRank=(Field $i.fields "Microsoft.VSTS.Common.StackRank")
    relations=$rels
    url=$i.url
  }
}

function WorkItem([int]$WorkItemId) {
  Normalize (Raw $WorkItemId)
}

function ChildIds($w) {
  @(
    $w.relations |
      Where-Object {
        $_.rel -eq "System.LinkTypes.Hierarchy-Forward" -and
        $null -ne $_.workItemId
      } |
      ForEach-Object {
        [int]$_.workItemId
      }
  )
}

function Rank($i) {
  if ($null -ne $i.backlogPriority) {
    return [double]$i.backlogPriority
  }

  if ($null -ne $i.stackRank) {
    return [double]$i.stackRank
  }

  if ($null -ne $i.priority) {
    return [double]$i.priority
  }

  [double]::MaxValue
}

function Tree(
  [int]$WorkItemId,
  [System.Collections.Generic.HashSet[int]]$Visited
) {
  if (-not $Visited.Add($WorkItemId)) {
    throw "Hierarchy cycle detected at work item #$WorkItemId."
  }

  $w=WorkItem $WorkItemId
  $children=@()

  foreach($cid in (ChildIds $w)) {
    $children+=Tree $cid $Visited
  }

  $children=@(
    $children |
      Sort-Object `
        @{Expression={Rank $_.workItem};Ascending=$true},
        @{Expression={$_.workItem.id};Ascending=$true}
  )

  [pscustomobject]@{
    workItem=$w
    children=$children
  }
}

function EpicTree([int]$EpicId) {
  $visited=[System.Collections.Generic.HashSet[int]]::new()
  $t=Tree $EpicId $visited

  if ($t.workItem.type -ne "Epic") {
    throw "Work item #$EpicId is '$($t.workItem.type)', not an Epic."
  }

  $t
}

function CompactRoot($w) {
  [pscustomobject]@{
    id=$w.id
    type=$w.type
    title=$w.title
    state=$w.state
  }
}

function DependencyInfo($w) {
  $dependsOn=@()
  $successors=@()
  $ambiguous=@()

  foreach($r in @($w.relations)) {
    if ($null -eq $r.workItemId) {
      continue
    }

    $name=""
    if ($null -ne $r.name) {
      $name=[string]$r.name
    }

    $rel=""
    if ($null -ne $r.rel) {
      $rel=[string]$r.rel
    }

    $nameLower=$name.ToLowerInvariant()

    # Azure DevOps dependency topology:
    # Dependency-Reverse / "Predecessor" => current item depends on related item.
    # Dependency-Forward / "Successor"   => related item depends on current item.
    if ($nameLower -eq "predecessor" -or $rel -eq "System.LinkTypes.Dependency-Reverse") {
      $dependsOn += [int]$r.workItemId
      continue
    }

    if ($nameLower -eq "successor" -or $rel -eq "System.LinkTypes.Dependency-Forward") {
      $successors += [int]$r.workItemId
      continue
    }

    if ($rel -like "*Dependency*" -or $nameLower -match "predecessor|successor|depend") {
      $ambiguous += [pscustomobject]@{
        rel=$r.rel
        name=$r.name
        workItemId=[int]$r.workItemId
      }
    }
  }

  [pscustomobject]@{
    dependsOn=@($dependsOn | Sort-Object -Unique)
    successors=@($successors | Sort-Object -Unique)
    ambiguous=@($ambiguous)
  }
}

function CompactFeature($w) {
  $d=DependencyInfo $w

  [pscustomobject]@{
    id=$w.id
    type=$w.type
    title=$w.title
    state=$w.state
    priority=$w.priority
    backlogPriority=$w.backlogPriority
    stackRank=$w.stackRank
    dependsOn=$d.dependsOn
    successors=$d.successors
    ambiguousDependencyRelations=$d.ambiguous
  }
}

function EpicFeatures([int]$EpicId) {
  $epic=WorkItem $EpicId

  if ($epic.type -ne "Epic") {
    throw "Work item #$EpicId is '$($epic.type)', not an Epic."
  }

  $features=@()

  foreach($cid in (ChildIds $epic)) {
    $child=WorkItem $cid

    if ($child.type -eq "Feature") {
      $features+=CompactFeature $child
    }
  }

  $features=@(
    $features |
      Sort-Object `
        @{Expression={
          if ($null -ne $_.backlogPriority) { [double]$_.backlogPriority }
          elseif ($null -ne $_.stackRank) { [double]$_.stackRank }
          elseif ($null -ne $_.priority) { [double]$_.priority }
          else { [double]::MaxValue }
        };Ascending=$true},
        @{Expression={$_.id};Ascending=$true}
  )

  [pscustomobject]@{
    contractVersion="epic-planning-index-v1"
    epic=(CompactRoot $epic)
    features=$features
  }
}

function FeatureTree([int]$FeatureId) {
  $visited=[System.Collections.Generic.HashSet[int]]::new()
  $t=Tree $FeatureId $visited

  if ($t.workItem.type -ne "Feature") {
    throw "Work item #$FeatureId is '$($t.workItem.type)', not a Feature."
  }

  $t
}


function CompactExecutionItem($w) {
  [pscustomobject]@{
    id=$w.id
    type=$w.type
    title=$w.title
    state=$w.state
  }
}

function FeatureIndex([int]$FeatureId) {
  $tree=FeatureTree $FeatureId
  $pbis=@()

  foreach($pbiNode in @($tree.children)) {
    $pbi=$pbiNode.workItem
    if ($pbi.type -ne "Product Backlog Item") {
      continue
    }

    $tasks=@()
    foreach($taskNode in @($pbiNode.children)) {
      $task=$taskNode.workItem
      if ($task.type -eq "Task") {
        $tasks += CompactExecutionItem $task
      }
    }

    $pbis += [pscustomobject]@{
      id=$pbi.id
      type=$pbi.type
      title=$pbi.title
      state=$pbi.state
      tasks=@($tasks)
    }
  }

  [pscustomobject]@{
    contractVersion="feature-execution-index-v1"
    feature=(CompactExecutionItem $tree.workItem)
    pbis=@($pbis)
  }
}

function ExecutionContractItem($w) {
  [pscustomobject]@{
    id=$w.id
    type=$w.type
    title=$w.title
    state=$w.state
    description=$w.description
    acceptanceCriteria=$w.acceptanceCriteria
  }
}

function ExecutionContext([int]$FeatureId,[int]$SelectedPbiId,[int]$SelectedTaskId) {
  if ($SelectedPbiId -le 0) { throw "-PbiId must be a positive work-item ID." }
  if ($SelectedTaskId -le 0) { throw "-TaskId must be a positive work-item ID." }

  $tree=FeatureTree $FeatureId
  $pbiNode=$null
  foreach($candidate in @($tree.children)) {
    if ($candidate.workItem.id -eq $SelectedPbiId -and $candidate.workItem.type -eq "Product Backlog Item") {
      $pbiNode=$candidate
      break
    }
  }
  if ($null -eq $pbiNode) {
    throw "PBI #$SelectedPbiId is not a direct Product Backlog Item child of Feature #$FeatureId."
  }

  $taskNode=$null
  foreach($candidate in @($pbiNode.children)) {
    if ($candidate.workItem.id -eq $SelectedTaskId -and $candidate.workItem.type -eq "Task") {
      $taskNode=$candidate
      break
    }
  }
  if ($null -eq $taskNode) {
    throw "Task #$SelectedTaskId is not a direct Task child of PBI #$SelectedPbiId under Feature #$FeatureId."
  }

  $siblingTasks=@()
  foreach($candidate in @($pbiNode.children)) {
    if ($candidate.workItem.type -eq "Task") {
      $siblingTasks += CompactExecutionItem $candidate.workItem
    }
  }

  $otherPbis=@()
  foreach($candidate in @($tree.children)) {
    if ($candidate.workItem.type -eq "Product Backlog Item" -and $candidate.workItem.id -ne $SelectedPbiId) {
      $otherPbis += CompactExecutionItem $candidate.workItem
    }
  }

  [pscustomobject]@{
    contractVersion="task-execution-context-v1"
    feature=(ExecutionContractItem $tree.workItem)
    activePbi=(ExecutionContractItem $pbiNode.workItem)
    activeTask=(ExecutionContractItem $taskNode.workItem)
    siblingTasks=@($siblingTasks)
    otherPbis=@($otherPbis)
  }
}

function UpdateState([int]$WorkItemId,[string]$NewState) {
  if ([string]::IsNullOrWhiteSpace($NewState)) {
    throw "-State is required."
  }

  $proj=[Uri]::EscapeDataString($Project)

  # Build JSON Patch as a serialized array and send it verbatim.
  # Literal { and } in JSON must be escaped as {{ and }} for the -f operator.
  $patchJson=ConvertTo-Json -InputObject @(@{op='add';path='/fields/System.State';value=$NewState}) -Compress

  Normalize (
    Invoke-Ado `
      "PATCH" `
      "$BaseUrl/$proj/_apis/wit/workitems/$WorkItemId`?api-version=$ApiVersion" `
      $patchJson `
      "application/json-patch+json"
  )
}

# Resolve workflow states by Azure DevOps state category instead of assuming English names.
function WorkflowStates([string]$WorkItemType) {
  $proj=[Uri]::EscapeDataString($Project)
  $type=[Uri]::EscapeDataString($WorkItemType)
  $response=Invoke-Ado "GET" "$BaseUrl/$proj/_apis/wit/workitemtypes/$type/states?api-version=$ApiVersion"
  if ($null -eq $response.value) {
    throw "Azure DevOps did not return workflow states for '$WorkItemType'. No change made."
  }
  @($response.value)
}

function StateCategory($StateDefinition) {
  $category=$null
  foreach($key in @("category","stateCategory")) {
    $prop=$StateDefinition.PSObject.Properties[$key]
    if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
      $category=[string]$prop.Value
      break
    }
  }
  if ($null -eq $category) {
    throw "Workflow state '$($StateDefinition.name)' has no state category; cannot safely infer lifecycle."
  }
  $category.ToLowerInvariant()
}

function ResolveState($States,[string]$Category,[string]$CurrentState) {
  $matches=@($States | Where-Object { (StateCategory $_) -eq $Category.ToLowerInvariant() })
  if ($matches.Count -eq 0) {
    throw "No '$Category' state configured for this work item type. No change made."
  }
  if ($matches.Count -eq 1) { return [string]$matches[0].name }
  $current=@($matches | Where-Object { $_.name -eq $CurrentState })
  if ($current.Count -eq 1) { return [string]$current[0].name }
  throw "Multiple '$Category' states configured: $($matches.name -join ', '). Use update-state with an explicit state."
}

function AssertSupportedType($WorkItem) {
  if (@("Epic","Feature","Product Backlog Item","Task") -cnotcontains [string]$WorkItem.type) {
    throw "Unsupported work item type '$($WorkItem.type)' for lifecycle operation; use update-state explicitly."
  }
}

function StartWorkItem([int]$WorkItemId) {
  $item=WorkItem $WorkItemId
  AssertSupportedType $item
  $states=WorkflowStates $item.type
  $current=@($states | Where-Object { $_.name -eq $item.state })
  if ($current.Count -ne 1) { throw "Unknown current state '$($item.state)'. No change made." }
  $category=StateCategory $current[0]
  if ($category -eq "inprogress") {
    return [pscustomobject]@{id=$item.id;type=$item.type;state=$item.state;changed=$false;reason="already-in-progress"}
  }
  if ($category -ne "proposed") {
    throw "Cannot start #$WorkItemId from '$($item.state)' ($category). No change made."
  }

  $deps=DependencyInfo $item
  if (@($deps.ambiguous).Count -gt 0) {
    throw "Ambiguous dependency relations for #$WorkItemId; resolve them before starting."
  }
  foreach($predecessorId in @($deps.dependsOn)) {
    $predecessor=WorkItem ([int]$predecessorId)
    $preStates=WorkflowStates $predecessor.type
    $preCurrent=@($preStates | Where-Object { $_.name -eq $predecessor.state })
    if ($preCurrent.Count -ne 1 -or (StateCategory $preCurrent[0]) -ne "completed") {
      throw "Predecessor #$predecessorId is not completed. Cannot start #$WorkItemId."
    }
  }

  $target=ResolveState $states "inprogress" $item.state
  $updated=UpdateState $WorkItemId $target
  [pscustomobject]@{id=$updated.id;type=$updated.type;state=$updated.state;changed=$true}
}

function CompleteWorkItem([int]$WorkItemId) {
  $item=WorkItem $WorkItemId
  AssertSupportedType $item
  $states=WorkflowStates $item.type
  $current=@($states | Where-Object { $_.name -eq $item.state })
  if ($current.Count -ne 1) { throw "Unknown current state '$($item.state)'. No change made." }
  $category=StateCategory $current[0]
  if ($category -eq "completed") {
    return [pscustomobject]@{id=$item.id;type=$item.type;state=$item.state;changed=$false;reason="already-completed"}
  }
  if ($category -ne "inprogress") {
    throw "Cannot complete #$WorkItemId from '$($item.state)' ($category). Start it first."
  }

  foreach($childId in (ChildIds $item)) {
    $child=WorkItem ([int]$childId)
    $childStates=WorkflowStates $child.type
    $childCurrent=@($childStates | Where-Object { $_.name -eq $child.state })
    if ($childCurrent.Count -ne 1 -or (StateCategory $childCurrent[0]) -ne "completed") {
      throw "Child #$childId ($($child.type)) is not completed. Cannot complete #$WorkItemId."
    }
  }

  $target=ResolveState $states "completed" $item.state
  $updated=UpdateState $WorkItemId $target
  [pscustomobject]@{id=$updated.id;type=$updated.type;state=$updated.state;changed=$true}
}

function AddComment([int]$WorkItemId,[string]$CommentText) {
  if ([string]::IsNullOrWhiteSpace($CommentText)) {
    throw "-Text is required."
  }

  $proj=[Uri]::EscapeDataString($Project)

  Invoke-Ado `
    "POST" `
    "$BaseUrl/$proj/_apis/wit/workItems/$WorkItemId/comments?api-version=6.0-preview.3" `
    @{text=$CommentText}
}

if ($Id -le 0) {
  throw "-Id must be a positive work-item ID."
}

switch($Operation) {
  "get-work-item" {
    WorkItem $Id | ConvertTo-Json -Depth 30
  }

  "get-epic-features" {
    EpicFeatures $Id | ConvertTo-Json -Depth 30
  }

  "get-feature-tree" {
    FeatureTree $Id | ConvertTo-Json -Depth 50
  }

  "get-feature-index" {
    FeatureIndex $Id | ConvertTo-Json -Depth 30
  }

  "get-execution-context" {
    ExecutionContext $Id $PbiId $TaskId | ConvertTo-Json -Depth 30
  }

  "get-epic-tree" {
    EpicTree $Id | ConvertTo-Json -Depth 50
  }

  "update-state" {
    UpdateState $Id $State | ConvertTo-Json -Depth 30
  }

  "start-work-item" {
    StartWorkItem $Id | ConvertTo-Json -Depth 30
  }

  "complete-work-item" {
    CompleteWorkItem $Id | ConvertTo-Json -Depth 30
  }

  "add-comment" {
    AddComment $Id $Text | ConvertTo-Json -Depth 30
  }
}