[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot 'validate_qa_response.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("s06-qa-tests-" + [guid]::NewGuid().ToString('N'))
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Case($Object, [string]$Name) {
    $path = Join-Path $tempRoot "$Name.json"
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Run-Case([string]$Name, $Object, [int]$ExpectedExitCode) {
    $path = Write-Case $Object $Name
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $validator -Path $path | Out-Host
    $actual = $LASTEXITCODE
    if ($actual -ne $ExpectedExitCode) {
        $script:failures.Add("$Name expected exit $ExpectedExitCode but got $actual")
    }
}

function New-Issue([bool]$Repairable = $true) {
    return [ordered]@{
        issue_id = 'QI-STORYBOARD-TABLE-001'
        severity = 'HIGH'
        rule_id = 'STB-AXIS-001'
        issue_type = 'AXIS_OR_POSITION_CONTINUITY'
        blocking = $true
        artifact_path = '/shot_map/4/columns/camera_position'
        scope = @('SHOT-E01-S01-005')
        evidence = [ordered]@{
            expected = 'Character A remains world-left of Character B'
            actual = 'Shot 005 reverses the established positions'
            source_refs = @('STORYBOARD-E01-S01-V1/SHOT-E01-S01-001..004')
        }
        owner = 'storyboard-table-director'
        repairable = $Repairable
        message = 'Shot 005 reverses positions without motivation'
    }
}

$base = [ordered]@{
    schema_version = '1.0'
    qa_mode = 'STORYBOARD_TABLE'
    artifact_id = 'STORYBOARD-E01-S01'
    artifact_version = 'V1'
    full_id = 'STORYBOARD-E01-S01-V1'
    verdict = 'PASS'
    checked_against = @('STORYBOARD-E01-S01-V1','PLOT-E01-V1')
    issues = @()
    repair_ticket = $null
    stale_downstream = @()
    checked_at = '2026-08-16T12:00:00+08:00'
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    Run-Case 'valid-pass' $base 0

    $repair = $base | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $repair.verdict = 'REPAIR'
    $repair.issues = @(New-Issue)
    $repair.repair_ticket = [ordered]@{
        ticket_id = 'RT-STORYBOARD-TABLE-E01-S01-005-001'
        qa_mode = 'STORYBOARD_TABLE'
        artifact_id = 'STORYBOARD-E01-S01'
        artifact_version = 'V1'
        full_id = 'STORYBOARD-E01-S01-V1'
        verdict = 'REPAIR'
        severity = 'HIGH'
        issue_type = 'AXIS_OR_POSITION_CONTINUITY'
        issue_ids = @('QI-STORYBOARD-TABLE-001')
        evidence = 'Shot 005 conflicts with the authoritative positions in shots 001-004'
        repair_instruction = 'Restore only the established positions and legal axis side in shot 005'
        target_shot_ids = @('SHOT-E01-S01-005')
        target_fields = @('camera_position','visual_description','director_notes')
        locked_fields = @('scene','shot_number','shot_size','duration','dialogue','other_shots')
        return_to = 'storyboard-table-director'
        max_attempts_remaining = 1
    }
    Run-Case 'valid-repair' $repair 0

    $plotRepair = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $plotRepair.qa_mode = 'PLOT'
    $plotRepair.artifact_id = 'PLOT-E01'
    $plotRepair.full_id = 'PLOT-E01-V1'
    $plotRepair.checked_against = @('PLOT-E01-V1','SCRIPT-E01-V1')
    $plotRepair.issues[0].rule_id = 'PLOT-DIALOGUE-001'
    $plotRepair.issues[0].issue_id = 'QI-PLOT-001'
    $plotRepair.issues[0].owner = 'script-plot-progression'
    $plotRepair.repair_ticket.qa_mode = 'PLOT'
    $plotRepair.repair_ticket.artifact_id = 'PLOT-E01'
    $plotRepair.repair_ticket.full_id = 'PLOT-E01-V1'
    $plotRepair.repair_ticket.issue_ids = @('QI-PLOT-001')
    $plotRepair.repair_ticket.return_to = 'script-plot-progression'
    $plotRepair.repair_ticket | Add-Member -NotePropertyName affected_scope -NotePropertyValue @('BEAT-E01-S01-001')
    $plotRepair.repair_ticket | Add-Member -NotePropertyName allowed_paths -NotePropertyValue @('/scenes/0/beats/0/dialogue')
    Run-Case 'valid-plot-repair' $plotRepair 0

    $promptRepair = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $promptRepair.qa_mode = 'STORYBOARD_PROMPT'
    $promptRepair.artifact_id = 'SP-E01-S01-005'
    $promptRepair.full_id = 'SP-E01-S01-005-V1'
    $promptRepair.checked_against = @('SP-E01-S01-005-V1','STORYBOARD-E01-S01-V1')
    $promptRepair.issues[0].rule_id = 'SP-SPATIAL-001'
    $promptRepair.issues[0].issue_id = 'QI-STORYBOARD-PROMPT-001'
    $promptRepair.issues[0].owner = 'storyboard-image-prompt-director'
    $promptRepair.repair_ticket.qa_mode = 'STORYBOARD_PROMPT'
    $promptRepair.repair_ticket.artifact_id = 'SP-E01-S01-005'
    $promptRepair.repair_ticket.full_id = 'SP-E01-S01-005-V1'
    $promptRepair.repair_ticket.issue_ids = @('QI-STORYBOARD-PROMPT-001')
    $promptRepair.repair_ticket.return_to = 'storyboard-image-prompt-director'
    $promptRepair.repair_ticket | Add-Member -NotePropertyName allowed_paths -NotePropertyValue @('/spatial_continuity')
    Run-Case 'valid-storyboard-prompt-repair' $promptRepair 0

    $imageRepair = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $imageRepair.qa_mode = 'STORYBOARD_IMAGE'
    $imageRepair.artifact_id = 'IMG-E01-S01-005'
    $imageRepair.full_id = 'IMG-E01-S01-005-V1'
    $imageRepair.checked_against = @('IMG-E01-S01-005-V1','SP-E01-S01-005-V1')
    $imageRepair.issues[0].rule_id = 'IMG-SPATIAL-001'
    $imageRepair.issues[0].issue_id = 'QI-STORYBOARD-IMAGE-001'
    $imageRepair.issues[0].owner = 'storyboard-image-generation'
    $imageRepair.repair_ticket.qa_mode = 'STORYBOARD_IMAGE'
    $imageRepair.repair_ticket.artifact_id = 'IMG-E01-S01-005'
    $imageRepair.repair_ticket.full_id = 'IMG-E01-S01-005-V1'
    $imageRepair.repair_ticket.issue_ids = @('QI-STORYBOARD-IMAGE-001')
    $imageRepair.repair_ticket.return_to = 'storyboard-image-generation'
    $imageRepair.repair_ticket | Add-Member -NotePropertyName regeneration_constraints -NotePropertyValue @('Keep Character A world-left of Character B')
    Run-Case 'valid-storyboard-image-repair' $imageRepair 0

    $videoRepair = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $videoRepair.qa_mode = 'VIDEO_PROMPT'
    $videoRepair.artifact_id = 'VP-E01-S01-005'
    $videoRepair.full_id = 'VP-E01-S01-005-V1'
    $videoRepair.checked_against = @('VP-E01-S01-005-V1','IMG-E01-S01-005-V1')
    $videoRepair.issues[0].rule_id = 'VP-START-001'
    $videoRepair.issues[0].issue_id = 'QI-VIDEO-PROMPT-001'
    $videoRepair.issues[0].owner = 'video-prompt-director'
    $videoRepair.repair_ticket.qa_mode = 'VIDEO_PROMPT'
    $videoRepair.repair_ticket.artifact_id = 'VP-E01-S01-005'
    $videoRepair.repair_ticket.full_id = 'VP-E01-S01-005-V1'
    $videoRepair.repair_ticket.issue_ids = @('QI-VIDEO-PROMPT-001')
    $videoRepair.repair_ticket.return_to = 'video-prompt-director'
    $videoRepair.repair_ticket | Add-Member -NotePropertyName affected_scope -NotePropertyValue @('SHOT-E01-S01-005')
    $videoRepair.repair_ticket | Add-Member -NotePropertyName allowed_changes -NotePropertyValue @('/start_state/characters')
    Run-Case 'valid-video-prompt-repair' $videoRepair 0

    $badPass = $base | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $badPass.issues = @(New-Issue)
    Run-Case 'invalid-pass-with-issue' $badPass 1

    $badTicket = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $badTicket.repair_ticket.qa_mode = 'PLOT'
    Run-Case 'invalid-ticket-mode' $badTicket 1

    $unknownRoute = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $unknownRoute.repair_ticket.return_to = 'does-not-exist'
    Run-Case 'invalid-unknown-return-target' $unknownRoute 1

    $ownerMismatch = $repair | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $ownerMismatch.issues[0].owner = 'script-plot-progression'
    Run-Case 'invalid-owner-return-target-mismatch' $ownerMismatch 1

    $human = $base | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $human.verdict = 'HUMAN_GATE'
    $human.issues = @(New-Issue -Repairable $false)
    Run-Case 'valid-human-gate' $human 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
    exit 1
}

Write-Host '[PASS] All QA response validator tests passed.' -ForegroundColor Green
exit 0
