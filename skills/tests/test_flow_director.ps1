[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$skillsRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillsRoot 'short-drama-flow-director\scripts\validate_flow_state.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('video-drama-s01-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()

function New-Artifact(
    [string]$Type,
    [string]$Id,
    [string]$Version,
    [string]$Status,
    [AllowNull()][object]$SceneId = $null,
    [AllowNull()][object]$ShotId = $null
) {
    $artifact = [ordered]@{
        project_id='PRJ-001'; artifact_type=$Type; artifact_id=$Id; artifact_version=$Version; full_id=($Id + '-' + $Version)
        flow_authorization_id='FLOW-AUTH-PRJ001-HISTORY-0001'
        status=$Status; current=$true; stale=($Status -eq 'STALE'); scene_id=$SceneId; shot_id=$ShotId
        source_beat_ids=@(); source_full_ids=@(); resource=('outputs/' + $Id.ToLowerInvariant() + '.json')
    }
    if ($Type -eq 'VIDEO_PROMPT') {
        $artifact['segment_id'] = 'SEG-E01-001'
        $artifact['covered_shot_ids'] = @($ShotId)
    }
    return $artifact
}

function New-Bundle(
    [string]$Stage,
    [string]$State,
    [string]$Action,
    [string]$Target,
    [array]$Artifacts = @(),
    [string]$QaMode = $null,
    [AllowNull()][object]$ArtifactFullId = $null,
    [array]$ShotIds = @(),
    [array]$Tickets = @(),
    [string]$TicketId = $null
) {
    $scope = [ordered]@{ episode_ids=@('E01'); scene_ids=@(); shot_ids=$ShotIds; beat_ids=@() }
    $authorizationId = $null
    $authorizations = @()
    $requirements = [ordered]@{
        quality_bar=@('九列齐备')
        project_constraints=[ordered]@{ aspect_ratio='9:16'; model='seedance-2.0'; visual_style_lock='LIVE_ACTION_REALISM' }
        focus=@('邻镜流畅')
    }
    $producerTargets = @{ P1='script-plot-progression'; P2='storyboard-table-director'; P3='storyboard-image-prompt-director'; P4='storyboard-image-generation'; P6='video-prompt-director' }
    if ($Action -in @('CALL_PRODUCER','CALL_QA','ROUTE_REPAIR')) {
        $authorizationId = "FLOW-AUTH-PRJ001-$Stage-0001"
        $authorizationAction = if ($Action -eq 'ROUTE_REPAIR') { 'ROUTE_REPAIR' } else { 'CALL_PRODUCER' }
        $authorizationTarget = if ($Action -eq 'CALL_QA') { $producerTargets[$Stage] } else { $Target }
        $authorizationStatus = if ($Action -eq 'CALL_QA') { 'CONSUMED' } else { 'ISSUED' }
        $authorizationArtifact = if ($Action -eq 'CALL_QA') { $ArtifactFullId } else { $null }
        $authorizationTicket = if ($Action -eq 'ROUTE_REPAIR') { $TicketId } else { $null }
        $authorizations = @([ordered]@{
            authorization_id=$authorizationId; project_id='PRJ-001'; stage=$Stage; action=$authorizationAction; target=$authorizationTarget
            status=$authorizationStatus; scope=$scope; requirements=$requirements; artifact_full_id=$authorizationArtifact; ticket_id=$authorizationTicket; issued_at='2026-08-16T00:00:00+08:00'
        })
        if ($Action -eq 'CALL_QA') {
            foreach ($item in @($Artifacts | Where-Object { $_.full_id -eq $ArtifactFullId })) { $item.flow_authorization_id = $authorizationId }
        }
    }
    return [ordered]@{
        schema_version='1.0'
        project_manifest=[ordered]@{
            project_id='PRJ-001'; manifest_version='V1'; status='ACTIVE'; episode_ids=@('E01'); required_scene_ids=@('SCENE-E01-S01'); visual_style_lock='LIVE_ACTION_REALISM'
            source_materials=@([ordered]@{ source_id='SCRIPT-E01'; source_type='SCRIPT'; version='V1'; status='CURRENT'; locator='file/episode-01.txt' })
            constraints=[ordered]@{}
        }
        stage_state=[ordered]@{
            project_id='PRJ-001'; current_stage=$Stage; state=$State; current_artifact_full_id=$ArtifactFullId
            last_qa_verdict=$null; blocking_reasons=@(); next_action=$Action
        }
        decision_ledger=@()
        artifact_index=$Artifacts
        flow_authorizations=$authorizations
        pending_repair_tickets=$Tickets
        run_log=@()
        dispatch=[ordered]@{
            action=$Action; target=$Target; qa_mode=$QaMode; artifact_full_id=$ArtifactFullId; ticket_id=$TicketId; authorization_id=$authorizationId
            scope=$scope
            requirements=$requirements
            reason='S01 validator regression test'
        }
        delivery=@()
    }
}

function Invoke-Case([string]$Name, $Bundle, [int]$ExpectedExitCode) {
    $path = Join-Path $script:tempRoot ($Name + '.json')
    [IO.File]::WriteAllText($path, ($Bundle | ConvertTo-Json -Depth 40), $script:utf8NoBom)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:validator -Path $path 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Host $line }
    if ($exitCode -ne $ExpectedExitCode) { $script:failures.Add("$Name expected exit $ExpectedExitCode but received $exitCode.") }
    else { Write-Host "[TEST PASS] $Name" -ForegroundColor Green }
}

try {
    Invoke-Case 'p1-call-producer' (New-Bundle 'P1' 'READY' 'CALL_PRODUCER' 'script-plot-progression') 0

    Invoke-Case 'p2-blocks-without-plot' (New-Bundle 'P2' 'READY' 'CALL_PRODUCER' 'storyboard-table-director') 1

    $plot = New-Artifact 'PLOT' 'PLOT-E01' 'V1' 'PASS'
    Invoke-Case 'p2-call-producer' (New-Bundle 'P2' 'READY' 'CALL_PRODUCER' 'storyboard-table-director' @($plot)) 0

    $missingAuthorization = New-Bundle 'P2' 'READY' 'CALL_PRODUCER' 'storyboard-table-director' @($plot)
    $missingAuthorization.flow_authorizations = @()
    $missingAuthorization.dispatch.authorization_id = $null
    Invoke-Case 'direct-producer-call-without-s01-authorization-is-rejected' $missingAuthorization 1

    $fourDigitBeatPlot = New-Artifact 'PLOT' 'PLOT-E01' 'V1' 'PASS'
    $fourDigitBeatPlot.source_beat_ids = @('BEAT-E01-S01-1000')
    Invoke-Case 'p2-accepts-four-digit-beat' (New-Bundle 'P2' 'READY' 'CALL_PRODUCER' 'storyboard-table-director' @($fourDigitBeatPlot)) 0

    $wrongEpisode = New-Bundle 'P2' 'READY' 'CALL_PRODUCER' 'storyboard-table-director' @($plot)
    $wrongEpisode.project_manifest.episode_ids = @('E01','E02')
    $wrongEpisode.project_manifest.required_scene_ids = @('SCENE-E01-S01','SCENE-E02-S01')
    $wrongEpisode.dispatch.scope.episode_ids = @('E02')
    $wrongEpisode.dispatch.scope.scene_ids = @('SCENE-E02-S01')
    Invoke-Case 'p2-rejects-wrong-episode-plot' $wrongEpisode 1

    $storyboard = New-Artifact 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01' 'V1' 'DRAFT' 'SCENE-E01-S01'
    Invoke-Case 'p2-call-qa' (New-Bundle 'P2' 'WAITING_QA' 'CALL_QA' 'short-drama-unified-qa' @($plot,$storyboard) 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01-V1') 0

    $unconsumedQaAuthorization = New-Bundle 'P2' 'WAITING_QA' 'CALL_QA' 'short-drama-unified-qa' @($plot,$storyboard) 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01-V1'
    $unconsumedQaAuthorization.flow_authorizations[0].status = 'ISSUED'
    $unconsumedQaAuthorization.flow_authorizations[0].artifact_full_id = $null
    Invoke-Case 'qa-rejects-unconsumed-production-authorization' $unconsumedQaAuthorization 1

    $mismatchedQaTarget = New-Bundle 'P2' 'WAITING_QA' 'CALL_QA' 'short-drama-unified-qa' @($plot,$storyboard) 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01-V1'
    $mismatchedQaTarget.stage_state.current_artifact_full_id = 'STORYBOARD-E99-S99-V9'
    Invoke-Case 'call-qa-rejects-state-target-mismatch' $mismatchedQaTarget 1

    $prompt = New-Artifact 'STORYBOARD_PROMPT' 'SP-E01-S01-001' 'V1' 'PASS' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
    Invoke-Case 'p4-uses-canonical-image-generator' (New-Bundle 'P4' 'READY' 'CALL_PRODUCER' 'storyboard-image-generation' @($prompt) $null $null @('SHOT-E01-S01-001')) 0

    $image = New-Artifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-001' 'V1' 'PASS' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
    Invoke-Case 'p5-human-gate' (New-Bundle 'P5' 'WAITING_HUMAN' 'REQUEST_HUMAN_APPROVAL' 'human-director' @($image) $null $null @('SHOT-E01-S01-001')) 0

    $approvedImage = New-Artifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-001' 'V1' 'PASS' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
    $approvedSet = New-Artifact 'APPROVED_STORYBOARD_SET' 'APPROVED-STORYBOARD-E01' 'V1' 'APPROVED'
    $approvedSet.Add('approved_items', @([ordered]@{ shot_id='SHOT-E01-S01-001'; image_full_id='IMG-E01-S01-001-V1'; status='APPROVED'; stale=$false }))
    Invoke-Case 'p6-call-producer' (New-Bundle 'P6' 'READY' 'CALL_PRODUCER' 'video-prompt-director' @($approvedImage,$approvedSet) $null $null @('SHOT-E01-S01-001')) 0

    $staleImage = New-Artifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-001' 'V2' 'STALE' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
    Invoke-Case 'p6-blocks-stale-image' (New-Bundle 'P6' 'READY' 'CALL_PRODUCER' 'video-prompt-director' @($staleImage,$approvedSet) $null $null @('SHOT-E01-S01-001')) 1

    $ticket = [ordered]@{
        ticket_id='RT-STORYBOARD-TABLE-E01-S01-001-001'; qa_mode='STORYBOARD_TABLE'; artifact_id='STORYBOARD-E01-S01'; artifact_version='V1'
        full_id='STORYBOARD-E01-S01-V1'; verdict='REPAIR'; severity='HIGH'; issue_type='CONTINUITY'; issue_ids=@('QI-001')
        evidence='Position mismatch'; repair_instruction='Restore position'; locked_fields=@('dialogue')
        repair_type='LOCAL_REPAIR'; preserve_scope='其余镜头与锁定字段全部保留'; must_fix=@('05 镜人物世界左右恢复（依据 STORYBOARD-E01-S01-V1 前四镜站位）')
        return_to='storyboard-table-director'; max_attempts_remaining=1
        target_shot_ids=@('SHOT-E01-S01-001'); target_fields=@('机位')
    }
    Invoke-Case 'route-repair' (New-Bundle 'P2' 'REPAIRING' 'ROUTE_REPAIR' 'storyboard-table-director' @($plot,$storyboard) $null 'STORYBOARD-E01-S01-V1' @('SHOT-E01-S01-001') @($ticket) $ticket.ticket_id) 0

    $unknownTicket = $ticket | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $unknownTicket.return_to = 'does-not-exist'
    Invoke-Case 'route-repair-rejects-unknown-target' (New-Bundle 'P2' 'REPAIRING' 'ROUTE_REPAIR' 'does-not-exist' @($plot,$storyboard) $null 'STORYBOARD-E01-S01-V1' @('SHOT-E01-S01-001') @($unknownTicket) $unknownTicket.ticket_id) 1

    $video = New-Artifact 'VIDEO_PROMPT' 'VP-E01-S01-001' 'V1' 'PASS' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
    Invoke-Case 'p7-deliver' (New-Bundle 'P7' 'COMPLETE' 'DELIVER' 'delivery' @($video) $null $null @('SHOT-E01-S01-001')) 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "[TEST FAIL] $failure" -ForegroundColor Red }
    exit 1
}

Write-Host '[PASS] S01 flow director regression tests passed.' -ForegroundColor Green
exit 0
