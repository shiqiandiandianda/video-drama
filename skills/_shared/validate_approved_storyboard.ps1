[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$ShotId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
function Has-Property($Object, [string]$Name) { return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] }
function Require-Property($Object, [string]$Name, [string]$Context) { if (-not (Has-Property $Object $Name)) { $script:errors.Add("$Context.$Name is required."); return $false }; return $true }
function Is-Array($Value) { return $Value -is [System.Array] }

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "ApprovedStoryboardSet not found: $Path"; exit 2 }
try { $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

foreach ($field in @('schema_version','project_id','artifact_id','artifact_version','full_id','status','items')) { Require-Property $artifact $field 'root' | Out-Null }
if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '1.0') { $errors.Add('root.schema_version must be 1.0.') }
if ((Has-Property $artifact 'artifact_id') -and $artifact.artifact_id -notmatch '^APPROVED-STORYBOARD-E[0-9]{2,4}$') { $errors.Add('root.artifact_id is invalid.') }
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version') -and (Has-Property $artifact 'full_id') -and $artifact.full_id -ne "$($artifact.artifact_id)-$($artifact.artifact_version)") { $errors.Add('root.full_id is inconsistent.') }
if ((Has-Property $artifact 'status') -and $artifact.status -ne 'APPROVED') { $errors.Add('root.status must be APPROVED.') }
if ((Has-Property $artifact 'items') -and -not (Is-Array $artifact.items)) { $errors.Add('root.items must be an array.') }

$matchingItems = @()
if (Has-Property $artifact 'items') {
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $index = 0
    foreach ($item in @($artifact.items)) {
        $context = "root.items[$index]"
        foreach ($field in @('scene_id','shot_id','source_beat_ids','artifact_id','artifact_version','full_id','source_prompt_full_id','status','stale','resource','approved_by','approved_at','locked_fields','allowed_changes')) { Require-Property $item $field $context | Out-Null }
        if ((Has-Property $item 'shot_id') -and -not $seen.Add([string]$item.shot_id)) { $errors.Add("Duplicate approved shot_id: $($item.shot_id)") }
        if ((Has-Property $item 'scene_id') -and $item.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add("$context.scene_id is invalid.") }
        if ((Has-Property $item 'shot_id') -and $item.shot_id -notmatch '^SHOT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3}$') { $errors.Add("$context.shot_id is invalid.") }
        if ((Has-Property $item 'artifact_id') -and (Has-Property $item 'shot_id')) { $expected = $item.shot_id -replace '^SHOT-','IMG-'; if ($item.artifact_id -ne $expected) { $errors.Add("$context.artifact_id must be $expected.") } }
        if ((Has-Property $item 'artifact_id') -and (Has-Property $item 'artifact_version') -and (Has-Property $item 'full_id') -and $item.full_id -ne "$($item.artifact_id)-$($item.artifact_version)") { $errors.Add("$context.full_id is inconsistent.") }
        if ((Has-Property $item 'source_prompt_full_id') -and $item.source_prompt_full_id -notmatch '^SP-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3}-V[0-9]+$') { $errors.Add("$context.source_prompt_full_id is invalid.") }
        if ((Has-Property $item 'status') -and $item.status -ne 'APPROVED') { $errors.Add("$context.status must be APPROVED.") }
        if ((Has-Property $item 'stale') -and $item.stale -ne $false) { $errors.Add("$context.stale must be false.") }
        foreach ($arrayField in @('source_beat_ids','locked_fields','allowed_changes')) { if (-not (Has-Property $item $arrayField) -or -not (Is-Array $item.$arrayField) -or @($item.$arrayField).Count -eq 0) { $errors.Add("$context.$arrayField must be a non-empty array.") } }
        if (-not [string]::IsNullOrWhiteSpace($ShotId) -and (Has-Property $item 'shot_id') -and $item.shot_id -eq $ShotId) { $matchingItems += $item }
        $index++
    }
}
if (-not [string]::IsNullOrWhiteSpace($ShotId) -and $matchingItems.Count -ne 1) { $errors.Add("Exactly one APPROVED item must match ShotId $ShotId.") }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] ApprovedStoryboardSet validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] ApprovedStoryboardSet is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
