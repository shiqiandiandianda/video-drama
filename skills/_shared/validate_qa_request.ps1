[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
function Has-Property($Object, [string]$Name) { return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] }
function Get-ScopeKey($Scope) {
    if ($null -eq $Scope) { return $null }
    $parts = foreach ($name in @('episode_ids','scene_ids','shot_ids','beat_ids')) {
        if (-not (Has-Property $Scope $name) -or $Scope.$name -isnot [System.Array]) { return $null }
        $name + '=' + (@($Scope.$name | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ',')
    }
    return $parts -join ';'
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "QA request not found: $Path"; exit 2 }
try { $request = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

foreach ($field in @('qa_mode','artifact','approved_upstream','project_constraints','change_set','previous_version','flow_control')) { if (-not (Has-Property $request $field)) { $errors.Add("root.$field is required.") } }
if ((Has-Property $request 'qa_mode') -and @('PLOT','STORYBOARD_TABLE','STORYBOARD_PROMPT','STORYBOARD_IMAGE','VIDEO_PROMPT') -notcontains $request.qa_mode) { $errors.Add('root.qa_mode is invalid.') }
if ((Has-Property $request 'artifact') -and $null -eq $request.artifact) { $errors.Add('root.artifact must contain the complete current artifact.') }
if ((Has-Property $request 'approved_upstream') -and -not ($request.approved_upstream -is [System.Array])) { $errors.Add('root.approved_upstream must be an array.') }
if ((Has-Property $request 'project_constraints') -and $null -eq $request.project_constraints) { $errors.Add('root.project_constraints must be an object; use an empty object when no constraints apply.') }

if (Has-Property $request 'flow_control') {
    $flowControl = $request.flow_control
    if ($null -eq $flowControl -or $flowControl -is [System.Array] -or $flowControl -is [string]) { $errors.Add('root.flow_control must be an object.') }
    else {
        foreach ($field in @('production_authorization_id','flow_state')) { if (-not (Has-Property $flowControl $field)) { $errors.Add("root.flow_control.$field is required.") } }
        if ((Has-Property $flowControl 'production_authorization_id') -and ([string]::IsNullOrWhiteSpace([string]$flowControl.production_authorization_id) -or $flowControl.production_authorization_id -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$')) { $errors.Add('root.flow_control.production_authorization_id is invalid.') }
        if ((Has-Property $flowControl 'flow_state') -and $null -ne $flowControl.flow_state) {
            $flowPath = Join-Path ([IO.Path]::GetTempPath()) ('video-drama-flow-qa-' + [guid]::NewGuid().ToString('N') + '.json')
            $flowValidationPassed = $true
            try {
                [IO.File]::WriteAllText($flowPath, ($flowControl.flow_state | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
                $flowValidator = Join-Path $PSScriptRoot '..\short-drama-flow-director\scripts\validate_flow_state.ps1'
                $flowOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $flowValidator -Path $flowPath 2>&1
                if ($LASTEXITCODE -ne 0) { $flowValidationPassed = $false; $errors.Add('root.flow_control.flow_state failed S01 validation: ' + (@($flowOutput) -join ' | ')) }
            }
            finally { if ([IO.File]::Exists($flowPath)) { [IO.File]::Delete($flowPath) } }

            $flowState = $flowControl.flow_state
            $modeStage = @{ PLOT='P1'; STORYBOARD_TABLE='P2'; STORYBOARD_PROMPT='P3'; STORYBOARD_IMAGE='P4'; VIDEO_PROMPT='P6' }
            $modeProducer = @{ PLOT='script-plot-progression'; STORYBOARD_TABLE='storyboard-table-director'; STORYBOARD_PROMPT='storyboard-image-prompt-director'; STORYBOARD_IMAGE='storyboard-image-generation'; VIDEO_PROMPT='video-prompt-director' }
            $modeType = @{ PLOT='PLOT'; STORYBOARD_TABLE='STORYBOARD_TABLE'; STORYBOARD_PROMPT='STORYBOARD_PROMPT'; STORYBOARD_IMAGE='STORYBOARD_IMAGE'; VIDEO_PROMPT='VIDEO_PROMPT' }
            if ($flowValidationPassed -and (Has-Property $request 'qa_mode') -and $modeStage.ContainsKey([string]$request.qa_mode) -and (Has-Property $request 'artifact') -and $null -ne $request.artifact) {
                $artifact = $request.artifact
                foreach ($field in @('project_id','full_id','flow_authorization_id')) { if (-not (Has-Property $artifact $field) -or [string]::IsNullOrWhiteSpace([string]$artifact.$field)) { $errors.Add("root.artifact.$field is required for flow verification.") } }
                if ((Has-Property $artifact 'flow_authorization_id') -and (Has-Property $flowControl 'production_authorization_id') -and $artifact.flow_authorization_id -ne $flowControl.production_authorization_id) { $errors.Add('root.artifact.flow_authorization_id must equal flow_control.production_authorization_id.') }
                if ([string]$request.qa_mode -eq 'VIDEO_PROMPT') {
                    if (-not (Has-Property $artifact 'segment_id') -or [string]$artifact.segment_id -notmatch '^SEG-E[0-9]{2,}-[0-9]{3}$') { $errors.Add('root.artifact.segment_id is required and must match SEG-E##-### for VIDEO_PROMPT.') }
                    if (-not (Has-Property $artifact 'covered_shot_ids') -or $artifact.covered_shot_ids -isnot [System.Array]) { $errors.Add('root.artifact.covered_shot_ids must be an array for VIDEO_PROMPT.') }
                    else {
                        $covered = @($artifact.covered_shot_ids)
                        if ($covered.Count -lt 2 -or $covered.Count -gt 6) { $errors.Add('root.artifact.covered_shot_ids must cover 2 to 6 shots.') }
                        foreach ($sid in $covered) { if ([string]$sid -notmatch '^SHOT-E[0-9]{2,}-S[0-9]{2,}-[0-9]{3}$') { $errors.Add("root.artifact.covered_shot_ids contains non-canonical ID: $sid.") } }
                        if ((Has-Property $flowState 'dispatch') -and (Has-Property $flowState.dispatch 'scope') -and $null -ne $flowState.dispatch.scope -and (Has-Property $flowState.dispatch.scope 'shot_ids')) {
                            $scopeShots = @($flowState.dispatch.scope.shot_ids | ForEach-Object { [string]$_ })
                            if ($scopeShots.Count -gt 0) { foreach ($sid in $covered) { if ($scopeShots -notcontains [string]$sid) { $errors.Add("covered shot $sid is outside the CALL_QA dispatch scope.") } } }
                        }
                    }
                }
                if (Has-Property $flowState 'dispatch') {
                    $dispatch = $flowState.dispatch
                    if ((-not (Has-Property $dispatch 'action')) -or $dispatch.action -ne 'CALL_QA') { $errors.Add('S06 only accepts an S01 CALL_QA dispatch.') }
                    if ((-not (Has-Property $dispatch 'target')) -or $dispatch.target -ne 'short-drama-unified-qa') { $errors.Add('S01 CALL_QA dispatch must target short-drama-unified-qa.') }
                    if ((Has-Property $dispatch 'qa_mode') -and $dispatch.qa_mode -ne $request.qa_mode) { $errors.Add('S01 dispatch.qa_mode must equal qa_request.qa_mode.') }
                    if ((Has-Property $artifact 'full_id') -and (Has-Property $dispatch 'artifact_full_id') -and $dispatch.artifact_full_id -ne $artifact.full_id) { $errors.Add('S01 dispatch.artifact_full_id must equal artifact.full_id.') }
                    if ((Has-Property $flowControl 'production_authorization_id') -and (Has-Property $dispatch 'authorization_id') -and $dispatch.authorization_id -ne $flowControl.production_authorization_id) { $errors.Add('S01 dispatch.authorization_id must equal flow_control.production_authorization_id.') }
                }
                if (Has-Property $flowState 'stage_state') {
                    if ((Has-Property $flowState.stage_state 'current_stage') -and $flowState.stage_state.current_stage -ne $modeStage[[string]$request.qa_mode]) { $errors.Add('S01 stage_state.current_stage does not match qa_mode.') }
                }
                if ((Has-Property $flowState 'flow_authorizations') -and $flowState.flow_authorizations -is [System.Array] -and (Has-Property $flowControl 'production_authorization_id')) {
                    $authMatches = @($flowState.flow_authorizations | Where-Object { $_.authorization_id -eq $flowControl.production_authorization_id })
                    if ($authMatches.Count -ne 1) { $errors.Add('production_authorization_id must resolve to exactly one S01 authorization.') }
                    else {
                        $auth = $authMatches[0]
                        if ($auth.status -ne 'CONSUMED' -or $auth.stage -ne $modeStage[[string]$request.qa_mode] -or $auth.target -ne $modeProducer[[string]$request.qa_mode] -or $auth.artifact_full_id -ne $artifact.full_id -or $auth.project_id -ne $artifact.project_id) { $errors.Add('Production authorization must be CONSUMED and match stage, producer, project, and artifact.') }
                        if ((Has-Property $flowState 'dispatch') -and (Get-ScopeKey $auth.scope) -ne (Get-ScopeKey $flowState.dispatch.scope)) { $errors.Add('Production authorization scope must equal the current S01 QA dispatch scope.') }
                    }
                }
                if ((Has-Property $flowState 'artifact_index') -and $flowState.artifact_index -is [System.Array] -and (Has-Property $artifact 'full_id')) {
                    $indexMatches = @($flowState.artifact_index | Where-Object { $_.full_id -eq $artifact.full_id -and $_.artifact_type -eq $modeType[[string]$request.qa_mode] -and $_.flow_authorization_id -eq $flowControl.production_authorization_id -and $_.current -eq $true -and $_.stale -eq $false })
                    if ($indexMatches.Count -ne 1) { $errors.Add('Artifact must resolve to one current, non-stale S01 ArtifactIndex entry with the same authorization.') }
                }
            }
        }
        elseif (Has-Property $flowControl 'flow_state') { $errors.Add('root.flow_control.flow_state must be the complete S01 state bundle.') }
    }
}

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] QA request validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] QA request is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
