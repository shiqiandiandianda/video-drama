[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()

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
    $value = $Object.$Name
    if (-not (Is-Array $value)) {
        $script:errors.Add("$Context.$Name must be an array.")
        return $false
    }
    if (-not $AllowEmpty -and @($value).Count -eq 0) {
        $script:errors.Add("$Context.$Name must not be empty.")
        return $false
    }
    return $true
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "Storyboard artifact not found: $Path"
    exit 2
}

try {
    $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}
catch {
    Write-Error "Invalid JSON: $($_.Exception.Message)"
    exit 2
}

$required = @('schema_version','artifact_type','project_id','flow_authorization_id','scene_id','source_beat_ids','artifact_id','artifact_version','full_id','source_artifact_id','source_version','source_full_id','source_status','source_stale','status','shot_map')
foreach ($field in $required) { Require-Property $artifact $field 'root' | Out-Null }

if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '1.0') { $errors.Add('root.schema_version must be 1.0.') }
if ((Has-Property $artifact 'flow_authorization_id') -and $artifact.flow_authorization_id -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$') { $errors.Add('root.flow_authorization_id is invalid. Production must be dispatched by S01.') }
if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -ne 'StoryboardTable') { $errors.Add('root.artifact_type must be StoryboardTable.') }
if ((Has-Property $artifact 'scene_id') -and $artifact.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add('root.scene_id must match SCENE-E##-S##.') }
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'scene_id')) {
    $expectedArtifactId = 'STORYBOARD-' + ($artifact.scene_id -replace '^SCENE-','')
    if ($artifact.artifact_id -ne $expectedArtifactId) { $errors.Add("root.artifact_id must be $expectedArtifactId.") }
}
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version') -and (Has-Property $artifact 'full_id')) {
    if ($artifact.full_id -ne "$($artifact.artifact_id)-$($artifact.artifact_version)") { $errors.Add('root.full_id does not match artifact_id and artifact_version.') }
}
if ((Has-Property $artifact 'source_artifact_id') -and $artifact.source_artifact_id -notmatch '^PLOT-E[0-9]{2,4}$') { $errors.Add('root.source_artifact_id must match PLOT-E##.') }
if ((Has-Property $artifact 'source_artifact_id') -and (Has-Property $artifact 'source_version') -and (Has-Property $artifact 'source_full_id')) {
    if ($artifact.source_full_id -ne "$($artifact.source_artifact_id)-$($artifact.source_version)") { $errors.Add('root.source_full_id does not match source_artifact_id and source_version.') }
}
if ((Has-Property $artifact 'source_status') -and $artifact.source_status -ne 'PASS') { $errors.Add('root.source_status must be PASS.') }
if ((Has-Property $artifact 'source_stale') -and $artifact.source_stale -ne $false) { $errors.Add('root.source_stale must be false.') }

$allowedStatuses = @('DRAFT','CHECKING','REPAIR','PASS','HUMAN_GATE','APPROVED','STALE')
if ((Has-Property $artifact 'status') -and $allowedStatuses -notcontains $artifact.status) { $errors.Add('root.status is invalid.') }
Require-Array $artifact 'source_beat_ids' 'root' $false | Out-Null
Require-Array $artifact 'shot_map' 'root' $false | Out-Null

$tableBeatIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
if (Has-Property $artifact 'source_beat_ids') {
    foreach ($beatId in @($artifact.source_beat_ids)) {
        if ([string]$beatId -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') { $errors.Add("Invalid table source_beat_ids item $beatId") }
        if (-not $tableBeatIds.Add([string]$beatId)) { $errors.Add("Duplicate table source_beat_ids item $beatId") }
    }
}

$mappedBeatIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$shotIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$expectedShotNo = 1
$columnNames = @('scene','shot_no','shot_size','camera_position','camera_movement','visual_description','duration_s','performance','director_note')
if (Has-Property $artifact 'shot_map') {
    foreach ($row in @($artifact.shot_map)) {
        $context = "root.shot_map[$($expectedShotNo - 1)]"
        foreach ($field in @('project_id','scene_id','shot_no','shot_id','artifact_id','artifact_version','full_id','storyboard_row_version','source_artifact_id','source_version','source_full_id','source_status','source_stale','source_beat_ids','status','columns')) {
            Require-Property $row $field $context | Out-Null
        }
        if ((Has-Property $row 'project_id') -and $row.project_id -ne $artifact.project_id) { $errors.Add("$context.project_id must match root.project_id.") }
        if ((Has-Property $row 'scene_id') -and $row.scene_id -ne $artifact.scene_id) { $errors.Add("$context.scene_id must match root.scene_id.") }
        if (Has-Property $row 'shot_no') {
            $parsedShotNo = 0
            if (-not [int]::TryParse([string]$row.shot_no, [ref]$parsedShotNo) -or $parsedShotNo -ne $expectedShotNo) { $errors.Add("$context.shot_no must be the next sequential shot number.") }
        }
        if ((Has-Property $row 'shot_id') -and (Has-Property $artifact 'scene_id')) {
            $scenePart = $artifact.scene_id -replace '^SCENE-',''
            $expectedShotId = 'SHOT-' + $scenePart + '-' + $expectedShotNo.ToString('000')
            if ($row.shot_id -ne $expectedShotId) { $errors.Add("$context.shot_id must be $expectedShotId.") }
            if (-not $shotIds.Add([string]$row.shot_id)) { $errors.Add("Duplicate shot_id: $($row.shot_id)") }
        }
        if ((Has-Property $row 'artifact_id') -and (Has-Property $row 'shot_id') -and $row.artifact_id -ne $row.shot_id) { $errors.Add("$context.artifact_id must equal shot_id.") }
        if ((Has-Property $row 'artifact_version') -and (Has-Property $row 'storyboard_row_version') -and $row.artifact_version -ne $row.storyboard_row_version) { $errors.Add("$context.artifact_version must equal storyboard_row_version.") }
        if ((Has-Property $row 'artifact_id') -and (Has-Property $row 'artifact_version') -and (Has-Property $row 'full_id') -and $row.full_id -ne "$($row.artifact_id)-$($row.artifact_version)") { $errors.Add("$context.full_id is inconsistent.") }
        if ((Has-Property $row 'source_artifact_id') -and $row.source_artifact_id -ne $artifact.source_artifact_id) { $errors.Add("$context.source_artifact_id must match root source.") }
        if ((Has-Property $row 'source_version') -and $row.source_version -ne $artifact.source_version) { $errors.Add("$context.source_version must match root source.") }
        if ((Has-Property $row 'source_full_id') -and $row.source_full_id -ne $artifact.source_full_id) { $errors.Add("$context.source_full_id must match root source.") }
        if ((Has-Property $row 'source_status') -and $row.source_status -ne 'PASS') { $errors.Add("$context.source_status must be PASS.") }
        if ((Has-Property $row 'source_stale') -and $row.source_stale -ne $false) { $errors.Add("$context.source_stale must be false.") }
        if (Require-Array $row 'source_beat_ids' $context $false) {
            foreach ($beatId in @($row.source_beat_ids)) {
                if (-not $tableBeatIds.Contains([string]$beatId)) { $errors.Add("$context references beat outside root.source_beat_ids: $beatId") }
                $mappedBeatIds.Add([string]$beatId) | Out-Null
            }
        }
        if ((Has-Property $artifact 'status') -and $artifact.status -eq 'PASS' -and (Has-Property $row 'status') -and $row.status -ne 'PASS') { $errors.Add("$context.status must be PASS when table status is PASS.") }
        if ((Has-Property $row 'status') -and $allowedStatuses -notcontains $row.status) { $errors.Add("$context.status is invalid.") }
        if (Has-Property $row 'columns') {
            foreach ($columnName in $columnNames) { Require-Property $row.columns $columnName "$context.columns" | Out-Null }
            if ((Has-Property $row.columns 'shot_no') -and [string]$row.columns.shot_no -ne [string]$row.shot_no) { $errors.Add("$context.columns.shot_no must match row shot_no.") }
            if (Has-Property $row.columns 'duration_s') {
                $duration = 0.0
                if (-not [double]::TryParse([string]$row.columns.duration_s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -or $duration -le 0) { $errors.Add("$context.columns.duration_s must be greater than zero.") }
            }
        }
        $expectedShotNo++
    }
}

foreach ($beatId in $tableBeatIds) {
    if (-not $mappedBeatIds.Contains($beatId)) { $errors.Add("Unmapped table beat: $beatId") }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    Write-Host "[FAIL] StoryboardTable validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] StoryboardTable structure is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
