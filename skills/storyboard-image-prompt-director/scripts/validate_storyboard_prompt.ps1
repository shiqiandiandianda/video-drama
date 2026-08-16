[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()

function Has-Property($Object, [string]$Name) { return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] }
function Require-Property($Object, [string]$Name, [string]$Context) {
    if (-not (Has-Property $Object $Name)) { $script:errors.Add("$Context.$Name is required."); return $false }
    return $true
}
function Is-Array($Value) { return $Value -is [System.Array] }
function Require-Array($Object, [string]$Name, [string]$Context, [bool]$AllowEmpty = $true) {
    if (-not (Require-Property $Object $Name $Context)) { return $false }
    if (-not (Is-Array $Object.$Name)) { $script:errors.Add("$Context.$Name must be an array."); return $false }
    if (-not $AllowEmpty -and @($Object.$Name).Count -eq 0) { $script:errors.Add("$Context.$Name must not be empty."); return $false }
    return $true
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "StoryboardPromptSpec not found: $Path"; exit 2 }
try { $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

$required = @('schema_version','project_id','scene_id','shot_id','source_beat_ids','artifact_id','artifact_version','full_id','prompt_id','source_artifact_id','source_version','source_full_id','source_status','source_stale','storyboard_row_version','source_row_full_id','source_row_status','source_row_stale','status','frame_role','selected_moment','positive_prompt','asset_requirements','asset_bindings','camera','spatial_continuity','prop_states','text_policy','locked_fields','negative_constraints','aspect_ratio','unresolved_fields','change_log')
foreach ($field in $required) { Require-Property $artifact $field 'root' | Out-Null }

if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '1.0') { $errors.Add('root.schema_version must be 1.0.') }
if ((Has-Property $artifact 'scene_id') -and $artifact.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add('root.scene_id is invalid.') }
if ((Has-Property $artifact 'shot_id') -and $artifact.shot_id -notmatch '^SHOT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3}$') { $errors.Add('root.shot_id is invalid.') }
if ((Has-Property $artifact 'scene_id') -and (Has-Property $artifact 'shot_id')) {
    $scenePart = $artifact.scene_id -replace '^SCENE-',''
    if ($artifact.shot_id -notmatch ('^SHOT-' + [regex]::Escape($scenePart) + '-[0-9]{3}$')) { $errors.Add('root.shot_id does not belong to root.scene_id.') }
}
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'shot_id')) {
    $expected = $artifact.shot_id -replace '^SHOT-','SP-'
    if ($artifact.artifact_id -ne $expected) { $errors.Add("root.artifact_id must be $expected.") }
}
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version')) {
    $expectedFullId = "$($artifact.artifact_id)-$($artifact.artifact_version)"
    if ((Has-Property $artifact 'full_id') -and $artifact.full_id -ne $expectedFullId) { $errors.Add('root.full_id is inconsistent.') }
    if ((Has-Property $artifact 'prompt_id') -and $artifact.prompt_id -ne $expectedFullId) { $errors.Add('root.prompt_id is inconsistent.') }
}
if ((Has-Property $artifact 'source_artifact_id') -and $artifact.source_artifact_id -notmatch '^STORYBOARD-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add('root.source_artifact_id is invalid.') }
if ((Has-Property $artifact 'source_artifact_id') -and (Has-Property $artifact 'source_version') -and (Has-Property $artifact 'source_full_id') -and $artifact.source_full_id -ne "$($artifact.source_artifact_id)-$($artifact.source_version)") { $errors.Add('root.source_full_id is inconsistent.') }
if ((Has-Property $artifact 'shot_id') -and (Has-Property $artifact 'storyboard_row_version') -and (Has-Property $artifact 'source_row_full_id') -and $artifact.source_row_full_id -ne "$($artifact.shot_id)-$($artifact.storyboard_row_version)") { $errors.Add('root.source_row_full_id is inconsistent.') }
if ((Has-Property $artifact 'source_status') -and $artifact.source_status -ne 'PASS') { $errors.Add('root.source_status must be PASS.') }
if ((Has-Property $artifact 'source_row_status') -and $artifact.source_row_status -ne 'PASS') { $errors.Add('root.source_row_status must be PASS.') }
if ((Has-Property $artifact 'source_stale') -and $artifact.source_stale -ne $false) { $errors.Add('root.source_stale must be false.') }
if ((Has-Property $artifact 'source_row_stale') -and $artifact.source_row_stale -ne $false) { $errors.Add('root.source_row_stale must be false.') }
if ((Has-Property $artifact 'status') -and @('DRAFT','CHECKING','REPAIR','PASS','HUMAN_GATE','STALE') -notcontains $artifact.status) { $errors.Add('root.status is invalid.') }
if (Require-Array $artifact 'source_beat_ids' 'root' $false) {
    foreach ($beatId in @($artifact.source_beat_ids)) { if ([string]$beatId -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') { $errors.Add("Invalid source_beat_ids item $beatId") } }
}
foreach ($arrayField in @('prop_states','locked_fields','negative_constraints','unresolved_fields','change_log')) { Require-Array $artifact $arrayField 'root' $true | Out-Null }
foreach ($field in @('phase','source_evidence','frozen_state','selection_reason')) { if (Has-Property $artifact 'selected_moment') { Require-Property $artifact.selected_moment $field 'root.selected_moment' | Out-Null } }
if ((Has-Property $artifact 'positive_prompt') -and [string]::IsNullOrWhiteSpace([string]$artifact.positive_prompt)) { $errors.Add('root.positive_prompt must not be empty.') }
if (Has-Property $artifact 'asset_bindings') {
    foreach ($field in @('characters','scene','props')) { Require-Array $artifact.asset_bindings $field 'root.asset_bindings' $true | Out-Null }
    if (Has-Property $artifact 'asset_requirements') {
        $requirementMap = [ordered]@{ character_count='characters'; scene_count='scene'; prop_count='props' }
        foreach ($entry in $requirementMap.GetEnumerator()) {
            if (Require-Property $artifact.asset_requirements $entry.Key 'root.asset_requirements') {
                $expectedCount = 0
                if (-not [int]::TryParse([string]$artifact.asset_requirements.($entry.Key), [ref]$expectedCount) -or $expectedCount -lt 0) { $errors.Add("root.asset_requirements.$($entry.Key) must be a non-negative integer.") }
                elseif ((Has-Property $artifact.asset_bindings $entry.Value) -and @($artifact.asset_bindings.($entry.Value)).Count -ne $expectedCount) { $errors.Add("root.asset_bindings.$($entry.Value) count must equal asset_requirements.$($entry.Key).") }
            }
        }
    }
    foreach ($groupName in @('characters','scene','props')) {
        if (Has-Property $artifact.asset_bindings $groupName) {
            foreach ($binding in @($artifact.asset_bindings.$groupName)) {
                foreach ($field in @('name','asset_id','asset_version','reference_role','inherit','ignore')) { Require-Property $binding $field "root.asset_bindings.$groupName[]" | Out-Null }
                if ((Has-Property $binding 'asset_id') -and [string]::IsNullOrWhiteSpace([string]$binding.asset_id)) { $errors.Add("root.asset_bindings.$groupName[].asset_id must not be empty.") }
                foreach ($arrayField in @('inherit','ignore')) { if ((Has-Property $binding $arrayField) -and -not (Is-Array $binding.$arrayField)) { $errors.Add("root.asset_bindings.$groupName[].$arrayField must be an array.") } }
            }
        }
    }
}
if ((Has-Property $artifact 'unresolved_fields') -and @($artifact.unresolved_fields).Count -gt 0 -and (Has-Property $artifact 'status') -and $artifact.status -notin @('HUMAN_GATE','REPAIR')) { $errors.Add('Non-empty unresolved_fields require HUMAN_GATE or REPAIR.') }

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    Write-Host "[FAIL] StoryboardPromptSpec validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] StoryboardPromptSpec structure is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
