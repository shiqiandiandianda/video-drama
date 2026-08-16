[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
$allowedRepairTargets = @(
    'script-plot-progression',
    'storyboard-table-director',
    'storyboard-image-prompt-director',
    'storyboard-image-generation',
    'video-prompt-director'
)

function Has-Property($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Require-Property($Object, [string]$Name, [string]$Context) {
    if (-not (Has-Property $Object $Name)) {
        $script:errors.Add("$Context.$Name is required.")
        return $false
    }
    return $true
}

function Is-Array($Value) {
    return $Value -is [System.Array]
}

function Require-Array($Object, [string]$Name, [string]$Context, [bool]$AllowEmpty = $true) {
    if (-not (Require-Property $Object $Name $Context)) { return $false }
    if (-not (Is-Array $Object.$Name)) {
        $script:errors.Add("$Context.$Name must be an array.")
        return $false
    }
    if (-not $AllowEmpty -and @($Object.$Name).Count -eq 0) {
        $script:errors.Add("$Context.$Name must not be empty.")
        return $false
    }
    return $true
}

function Require-NonEmptyString($Object, [string]$Name, [string]$Context) {
    if (-not (Require-Property $Object $Name $Context)) { return $false }
    if ($Object.$Name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Object.$Name)) {
        $script:errors.Add("$Context.$Name must be a non-empty string.")
        return $false
    }
    return $true
}

function Validate-Issue($Issue, [int]$Index, [string]$Mode, [string]$ExpectedPrefix) {
    $context = "root.issues[$Index]"
    foreach ($field in @('issue_id','severity','rule_id','issue_type','blocking','artifact_path','scope','evidence','owner','repairable','message')) {
        Require-Property $Issue $field $context | Out-Null
    }

    foreach ($field in @('issue_id','rule_id','issue_type','artifact_path','owner','message')) {
        Require-NonEmptyString $Issue $field $context | Out-Null
    }

    if ((Has-Property $Issue 'severity') -and @('CRITICAL','HIGH','MEDIUM','LOW') -notcontains $Issue.severity) {
        $script:errors.Add("$context.severity is invalid.")
    }
    if ((Has-Property $Issue 'rule_id') -and [string]$Issue.rule_id -notmatch "^$ExpectedPrefix-") {
        $script:errors.Add("$context.rule_id does not belong to qa_mode $Mode.")
    }
    foreach ($field in @('blocking','repairable')) {
        if ((Has-Property $Issue $field) -and $Issue.$field -isnot [bool]) {
            $script:errors.Add("$context.$field must be boolean.")
        }
    }
    Require-Array $Issue 'scope' $context $false | Out-Null

    if (Has-Property $Issue 'evidence') {
        $evidence = $Issue.evidence
        if ($null -eq $evidence -or $evidence -is [string] -or $evidence -is [System.Array]) {
            $script:errors.Add("$context.evidence must be an object.")
        }
        else {
            foreach ($field in @('expected','actual','source_refs')) {
                Require-Property $evidence $field "$context.evidence" | Out-Null
            }
            Require-NonEmptyString $evidence 'expected' "$context.evidence" | Out-Null
            Require-NonEmptyString $evidence 'actual' "$context.evidence" | Out-Null
            Require-Array $evidence 'source_refs' "$context.evidence" $false | Out-Null
        }
    }
}

function Validate-Ticket(
    $Ticket,
    [int]$Index,
    $Root,
    [System.Collections.Generic.HashSet[string]]$IssueIds,
    [hashtable]$IssueOwners,
    [System.Collections.Generic.HashSet[string]]$TicketIds,
    [System.Collections.Generic.HashSet[string]]$TicketedIssueIds
) {
    $context = "root.repair_ticket[$Index]"
    foreach ($field in @('ticket_id','qa_mode','artifact_id','artifact_version','full_id','verdict','severity','issue_type','issue_ids','evidence','repair_instruction','locked_fields','return_to','max_attempts_remaining')) {
        Require-Property $Ticket $field $context | Out-Null
    }

    foreach ($field in @('ticket_id','artifact_id','artifact_version','full_id','issue_type','evidence','repair_instruction','return_to')) {
        Require-NonEmptyString $Ticket $field $context | Out-Null
    }

    if ((Has-Property $Ticket 'ticket_id') -and -not $TicketIds.Add([string]$Ticket.ticket_id)) {
        $script:errors.Add("Duplicate ticket_id: $($Ticket.ticket_id)")
    }

    if ((Has-Property $Ticket 'qa_mode') -and $Ticket.qa_mode -ne $Root.qa_mode) {
        $script:errors.Add("$context.qa_mode must match root.qa_mode.")
    }
    if ((Has-Property $Ticket 'artifact_id') -and $Ticket.artifact_id -ne $Root.artifact_id) {
        $script:errors.Add("$context.artifact_id must match root.artifact_id.")
    }
    if ((Has-Property $Ticket 'artifact_version') -and $Ticket.artifact_version -ne $Root.artifact_version) {
        $script:errors.Add("$context.artifact_version must match root.artifact_version.")
    }
    if ((Has-Property $Ticket 'full_id') -and $Ticket.full_id -ne $Root.full_id) {
        $script:errors.Add("$context.full_id must match root.full_id.")
    }
    if ((Has-Property $Ticket 'verdict') -and $Ticket.verdict -ne 'REPAIR') {
        $script:errors.Add("$context.verdict must be REPAIR.")
    }
    if ((Has-Property $Ticket 'return_to') -and $script:allowedRepairTargets -notcontains $Ticket.return_to) {
        $script:errors.Add("$context.return_to must name a canonical production target.")
    }
    if ((Has-Property $Ticket 'severity') -and @('CRITICAL','HIGH','MEDIUM','LOW') -notcontains $Ticket.severity) {
        $script:errors.Add("$context.severity is invalid.")
    }
    if (Require-Array $Ticket 'issue_ids' $context $false) {
        foreach ($issueId in @($Ticket.issue_ids)) {
            if (-not $IssueIds.Contains([string]$issueId)) {
                $script:errors.Add("$context.issue_ids references unknown issue_id $issueId.")
            }
            else {
                $TicketedIssueIds.Add([string]$issueId) | Out-Null
                if ($IssueOwners.ContainsKey([string]$issueId) -and (Has-Property $Ticket 'return_to') -and $IssueOwners[[string]$issueId] -ne $Ticket.return_to) {
                    $script:errors.Add("$context.return_to must equal owner of issue $issueId.")
                }
            }
        }
    }
    Require-Array $Ticket 'locked_fields' $context $false | Out-Null

    if (Has-Property $Ticket 'max_attempts_remaining') {
        $attempts = $Ticket.max_attempts_remaining
        if ($attempts -isnot [int] -and $attempts -isnot [long]) {
            $script:errors.Add("$context.max_attempts_remaining must be an integer.")
        }
        elseif ([int64]$attempts -lt 1) {
            $script:errors.Add("$context.max_attempts_remaining must be at least 1 for REPAIR.")
        }
    }

    switch ([string]$Root.qa_mode) {
        'PLOT' {
            Require-Array $Ticket 'affected_scope' $context $false | Out-Null
            Require-Array $Ticket 'allowed_paths' $context $false | Out-Null
        }
        'STORYBOARD_TABLE' {
            Require-Array $Ticket 'target_shot_ids' $context $false | Out-Null
            Require-Array $Ticket 'target_fields' $context $false | Out-Null
        }
        'STORYBOARD_PROMPT' {
            Require-Array $Ticket 'target_shot_ids' $context $false | Out-Null
            Require-Array $Ticket 'allowed_paths' $context $false | Out-Null
        }
        'STORYBOARD_IMAGE' {
            Require-Array $Ticket 'target_shot_ids' $context $false | Out-Null
            Require-Array $Ticket 'regeneration_constraints' $context $false | Out-Null
        }
        'VIDEO_PROMPT' {
            Require-Array $Ticket 'affected_scope' $context $false | Out-Null
            Require-Array $Ticket 'allowed_changes' $context $false | Out-Null
        }
    }
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "QA response not found: $Path"
    exit 2
}

try {
    $root = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}
catch {
    Write-Error "Invalid JSON: $($_.Exception.Message)"
    exit 2
}

foreach ($field in @('schema_version','qa_mode','artifact_id','artifact_version','full_id','verdict','checked_against','issues','repair_ticket','stale_downstream','checked_at')) {
    Require-Property $root $field 'root' | Out-Null
}

foreach ($field in @('artifact_id','artifact_version','full_id','checked_at')) {
    Require-NonEmptyString $root $field 'root' | Out-Null
}

$modes = @('PLOT','STORYBOARD_TABLE','STORYBOARD_PROMPT','STORYBOARD_IMAGE','VIDEO_PROMPT')
$prefixes = @{
    PLOT = 'PLOT'
    STORYBOARD_TABLE = 'STB'
    STORYBOARD_PROMPT = 'SP'
    STORYBOARD_IMAGE = 'IMG'
    VIDEO_PROMPT = 'VP'
}

if ((Has-Property $root 'schema_version') -and $root.schema_version -ne '1.0') {
    $errors.Add('root.schema_version must be 1.0.')
}
if ((Has-Property $root 'qa_mode') -and $modes -notcontains $root.qa_mode) {
    $errors.Add('root.qa_mode is invalid.')
}
if ((Has-Property $root 'verdict') -and @('PASS','REPAIR','HUMAN_GATE') -notcontains $root.verdict) {
    $errors.Add('root.verdict is invalid.')
}
if ((Has-Property $root 'artifact_id') -and [string]$root.artifact_id -match '-V[0-9]+$') {
    $errors.Add('root.artifact_id must be a stable ID without a version suffix.')
}
if ((Has-Property $root 'artifact_version') -and [string]$root.artifact_version -notmatch '^V[1-9][0-9]*$') {
    $errors.Add('root.artifact_version must match V<n>.')
}
if ((Has-Property $root 'artifact_id') -and (Has-Property $root 'artifact_version') -and (Has-Property $root 'full_id')) {
    $expectedFullId = "$($root.artifact_id)-$($root.artifact_version)"
    if ($root.full_id -ne $expectedFullId) {
        $errors.Add("root.full_id must be $expectedFullId.")
    }
}

if (Require-Array $root 'checked_against' 'root' $false) {
    if ((Has-Property $root 'full_id') -and @($root.checked_against) -notcontains $root.full_id) {
        $errors.Add('root.checked_against must include root.full_id.')
    }
}
Require-Array $root 'issues' 'root' $true | Out-Null
Require-Array $root 'stale_downstream' 'root' $true | Out-Null

if (Has-Property $root 'checked_at') {
    $parsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$root.checked_at, [ref]$parsedTimestamp)) {
        $errors.Add('root.checked_at must be a valid ISO-8601 timestamp.')
    }
}

$issueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$issueOwners = @{}
$blockingIssueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$blockingCount = 0
$nonRepairableCount = 0
$nonBlockingCount = 0
if ((Has-Property $root 'issues') -and (Is-Array $root.issues) -and $modes -contains $root.qa_mode) {
    $issueIndex = 0
    foreach ($issue in @($root.issues)) {
        Validate-Issue $issue $issueIndex ([string]$root.qa_mode) ([string]$prefixes[$root.qa_mode])
        if ((Has-Property $issue 'issue_id') -and -not $issueIds.Add([string]$issue.issue_id)) {
            $errors.Add("Duplicate issue_id: $($issue.issue_id)")
        }
        elseif ((Has-Property $issue 'issue_id') -and (Has-Property $issue 'owner')) {
            $issueOwners[[string]$issue.issue_id] = [string]$issue.owner
        }
        if ((Has-Property $issue 'blocking') -and $issue.blocking -eq $true) {
            $blockingCount++
            if (Has-Property $issue 'issue_id') { $blockingIssueIds.Add([string]$issue.issue_id) | Out-Null }
        }
        elseif (Has-Property $issue 'blocking') { $nonBlockingCount++ }
        if ((Has-Property $issue 'repairable') -and $issue.repairable -eq $false) { $nonRepairableCount++ }
        $issueIndex++
    }
}

if (Has-Property $root 'verdict') {
    switch ([string]$root.verdict) {
        'PASS' {
            if ((Has-Property $root 'issues') -and @($root.issues).Count -ne 0) {
                $errors.Add('PASS requires an empty issues array.')
            }
            if ((Has-Property $root 'repair_ticket') -and $null -ne $root.repair_ticket) {
                $errors.Add('PASS requires repair_ticket to be null.')
            }
        }
        'REPAIR' {
            if ($blockingCount -lt 1) {
                $errors.Add('REPAIR requires at least one blocking issue.')
            }
            if ($nonBlockingCount -gt 0) {
                $errors.Add('REPAIR issues must all be blocking under the current hard-check protocol.')
            }
            if ($nonRepairableCount -gt 0) {
                $errors.Add('REPAIR cannot contain a non-repairable issue; use HUMAN_GATE.')
            }
            if (-not (Has-Property $root 'repair_ticket') -or $null -eq $root.repair_ticket) {
                $errors.Add('REPAIR requires at least one repair ticket.')
            }
            else {
                [object[]]$tickets = @($root.repair_ticket)
                if ($tickets.Count -eq 0) {
                    $errors.Add('REPAIR requires at least one repair ticket.')
                }
                else {
                    $ticketIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    $ticketedIssueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    for ($ticketIndex = 0; $ticketIndex -lt $tickets.Count; $ticketIndex++) {
                        Validate-Ticket $tickets[$ticketIndex] $ticketIndex $root $issueIds $issueOwners $ticketIds $ticketedIssueIds
                    }
                    foreach ($blockingIssueId in $blockingIssueIds) {
                        if (-not $ticketedIssueIds.Contains($blockingIssueId)) {
                            $errors.Add("Blocking issue $blockingIssueId is not covered by any repair ticket.")
                        }
                    }
                }
            }
        }
        'HUMAN_GATE' {
            if ($blockingCount -lt 1) {
                $errors.Add('HUMAN_GATE requires at least one blocking issue.')
            }
            if ($nonRepairableCount -lt 1) {
                $errors.Add('HUMAN_GATE requires at least one non-repairable issue.')
            }
            if ($nonBlockingCount -gt 0) {
                $errors.Add('HUMAN_GATE issues must all be blocking under the current hard-check protocol.')
            }
            if ((Has-Property $root 'repair_ticket') -and $null -ne $root.repair_ticket) {
                $errors.Add('HUMAN_GATE requires repair_ticket to be null.')
            }
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) {
        Write-Host "[ERROR] $validationError" -ForegroundColor Red
    }
    Write-Host "[FAIL] QA response validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] QA response is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
