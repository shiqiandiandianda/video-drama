[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error([string]$Message) { $script:errors.Add($Message) }
function Has-Property($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}
function Require-Property($Object, [string]$Name, [string]$ObjectPath) {
    if (-not (Has-Property $Object $Name)) {
        Add-Error "$ObjectPath.$Name is required."
        return $false
    }
    return $true
}
function Require-String($Object, [string]$Name, [string]$ObjectPath) {
    if (-not (Require-Property $Object $Name $ObjectPath)) { return $false }
    $value = $Object.$Name
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        Add-Error "$ObjectPath.$Name must be a non-empty string."
        return $false
    }
    return $true
}
function Require-Array($Object, [string]$Name, [string]$ObjectPath) {
    if (-not (Require-Property $Object $Name $ObjectPath)) { return $false }
    if ($Object.$Name -isnot [System.Array]) {
        Add-Error "$ObjectPath.$Name must be an array, including when it has zero or one item."
        return $false
    }
    return $true
}
function Is-CurrentUsable($Artifact) {
    return $Artifact.current -eq $true -and $Artifact.stale -eq $false -and $Artifact.status -ne 'STALE'
}
function Get-UsableArtifacts([string]$ArtifactType, [string]$RequiredStatus) {
    return @($script:artifacts | Where-Object {
        $_.artifact_type -eq $ArtifactType -and $_.status -eq $RequiredStatus -and (Is-CurrentUsable $_)
    })
}
function Scope-Values($Scope, [string]$Name) {
    if ($null -eq $Scope -or -not (Has-Property $Scope $Name)) { return @() }
    return @($Scope.$Name)
}
function Get-ScopeKey($Scope) {
    if ($null -eq $Scope) { return $null }
    $parts = foreach ($name in @('episode_ids','scene_ids','shot_ids','beat_ids')) {
        $values = @(Scope-Values $Scope $name | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $name + '=' + ($values -join ',')
    }
    return $parts -join ';'
}
function Get-ArtifactEpisodeId($Artifact) {
    $candidates = @()
    foreach ($name in @('artifact_id','scene_id','shot_id')) {
        if (Has-Property $Artifact $name) { $candidates += $Artifact.$name }
    }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and [string]$candidate -match '(?:^|-)E([0-9]{2,4})(?:-|$)') {
            return 'E' + $Matches[1]
        }
    }
    return $null
}
function Test-DirectTrackP6Gate($Scope) {
    $tables = @(Get-UsableArtifacts 'STORYBOARD_TABLE' 'PASS')
    if ($tables.Count -eq 0) { return $false }
    $sceneIds = @(Scope-Values $Scope 'scene_ids')
    $shotIds = @(Scope-Values $Scope 'shot_ids')
    $derived = @($shotIds | ForEach-Object { if ([string]$_ -match '^SHOT-(E[0-9]{2,}-S[0-9]{2,})-[0-9]{3}$') { "SCENE-$($Matches[1])" } })
    $sceneIds = @($sceneIds + $derived | Sort-Object -Unique)
    if ($sceneIds.Count -eq 0) { return $true }
    foreach ($sceneId in $sceneIds) {
        if (@($tables | Where-Object { (Has-Property $_ 'scene_id') -and $_.scene_id -eq $sceneId }).Count -eq 0) { return $false }
    }
    return $true
}
function Has-GateForStage([string]$Stage, $Scope) {
    switch ($Stage) {
        'P1' {
            $scripts = @($script:sources | Where-Object { $_.source_type -eq 'SCRIPT' -and $_.status -eq 'CURRENT' })
            if ($scripts.Count -eq 0 -or $script:hasConflict) { return $false }
            $episodeIds = @(Scope-Values $Scope 'episode_ids')
            if ($episodeIds.Count -eq 0) { $episodeIds = @($script:manifestEpisodeIds) }
            $handoffs = @($script:artifacts | Where-Object { $_.artifact_type -eq 'EPISODE_HANDOFF' -and $_.status -in @('PASS','APPROVED') -and (Is-CurrentUsable $_) })
            foreach ($episodeId in $episodeIds) {
                $idx = [Array]::IndexOf($script:manifestEpisodeIds, $episodeId)
                if ($idx -gt 0) {
                    $prevId = $script:manifestEpisodeIds[$idx - 1]
                    if (@($handoffs | Where-Object { $_.artifact_id -eq "HANDOFF-$prevId" }).Count -eq 0) { return $false }
                }
                elseif ($idx -lt 0 -and $handoffs.Count -eq 0) { return $false }
            }
            return $true
        }
        'P2' {
            $plots = @(Get-UsableArtifacts 'PLOT' 'PASS')
            $episodeIds = @(Scope-Values $Scope 'episode_ids')
            if ($episodeIds.Count -eq 0) { return $plots.Count -gt 0 }
            foreach ($episodeId in $episodeIds) {
                if (@($plots | Where-Object { (Get-ArtifactEpisodeId $_) -eq $episodeId }).Count -eq 0) { return $false }
            }
            return $true
        }
        'P3' {
            $tables = @(Get-UsableArtifacts 'STORYBOARD_TABLE' 'PASS')
            $sceneIds = @(Scope-Values $Scope 'scene_ids')
            if ($sceneIds.Count -eq 0) { return $tables.Count -gt 0 }
            foreach ($sceneId in $sceneIds) {
                if (@($tables | Where-Object { (Has-Property $_ 'scene_id') -and $_.scene_id -eq $sceneId }).Count -eq 0) { return $false }
            }
            return $true
        }
        'P4' {
            $prompts = @(Get-UsableArtifacts 'STORYBOARD_PROMPT' 'PASS')
            $shotIds = @(Scope-Values $Scope 'shot_ids')
            if ($shotIds.Count -eq 0) { return $prompts.Count -gt 0 }
            foreach ($shotId in $shotIds) {
                if (@($prompts | Where-Object { (Has-Property $_ 'shot_id') -and $_.shot_id -eq $shotId }).Count -eq 0) { return $false }
            }
            return $true
        }
        'P5' {
            $images = @(Get-UsableArtifacts 'STORYBOARD_IMAGE' 'PASS')
            $shotIds = @(Scope-Values $Scope 'shot_ids')
            if ($shotIds.Count -eq 0) { return $images.Count -gt 0 }
            foreach ($shotId in $shotIds) {
                if (@($images | Where-Object { (Has-Property $_ 'shot_id') -and $_.shot_id -eq $shotId }).Count -eq 0) { return $false }
            }
            return $true
        }
        'P6' {
            if ($script:imageTrack -eq 'DISABLED') { return (Test-DirectTrackP6Gate $Scope) }
            if ($script:imageTrack -eq 'OPTIONAL' -and (Test-DirectTrackP6Gate $Scope)) { return $true }
            $sets = @(Get-UsableArtifacts 'APPROVED_STORYBOARD_SET' 'APPROVED')
            if ($sets.Count -eq 0) { return $false }
            $images = @(Get-UsableArtifacts 'STORYBOARD_IMAGE' 'PASS')
            $approvedItems = @($sets | ForEach-Object { @($_.approved_items) })
            $shotIds = @(Scope-Values $Scope 'shot_ids')
            if ($shotIds.Count -eq 0) {
                $shotIds = @($approvedItems | Where-Object { $_.status -eq 'APPROVED' -and $_.stale -eq $false } | ForEach-Object { $_.shot_id } | Select-Object -Unique)
            }
            if ($shotIds.Count -eq 0) { return $false }
            foreach ($shotId in $shotIds) {
                $items = @($approvedItems | Where-Object { $_.shot_id -eq $shotId -and $_.status -eq 'APPROVED' -and $_.stale -eq $false })
                if ($items.Count -ne 1) { return $false }
                $imageFullId = $items[0].image_full_id
                if (@($images | Where-Object { (Has-Property $_ 'shot_id') -and $_.shot_id -eq $shotId -and $_.full_id -eq $imageFullId }).Count -ne 1) { return $false }
            }
            return $true
        }
        'P7' {
            $prompts = @(Get-UsableArtifacts 'VIDEO_PROMPT' 'PASS')
            $shotIds = @(Scope-Values $Scope 'shot_ids')
            if ($shotIds.Count -eq 0) { return $prompts.Count -gt 0 }
            foreach ($shotId in $shotIds) {
                $hits = @($prompts | Where-Object {
                    ((Has-Property $_ 'shot_id') -and $_.shot_id -eq $shotId) -or
                    ((Has-Property $_ 'covered_shot_ids') -and @($_.covered_shot_ids) -contains $shotId)
                })
                if ($hits.Count -eq 0) { return $false }
            }
            return $true
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "[ERROR] File not found: $Path" -ForegroundColor Red
    exit 1
}

try { $bundle = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch {
    Write-Host "[ERROR] Invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not (Require-String $bundle 'schema_version' '$')) { }
elseif ($bundle.schema_version -ne '1.0') { Add-Error '$.schema_version must be "1.0".' }

foreach ($property in @('project_manifest','stage_state','dispatch')) {
    if (-not (Require-Property $bundle $property '$')) { continue }
    if ($null -eq $bundle.$property -or $bundle.$property -is [System.Array] -or $bundle.$property -is [string]) {
        Add-Error "$.${property} must be an object."
    }
}
foreach ($property in @('decision_ledger','artifact_index','flow_authorizations','pending_repair_tickets','run_log','delivery')) {
    Require-Array $bundle $property '$' | Out-Null
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    exit 1
}

$manifest = $bundle.project_manifest
$stage = $bundle.stage_state
$dispatch = $bundle.dispatch
$script:sources = @($manifest.source_materials)
$script:artifacts = @($bundle.artifact_index)
$script:authorizations = @($bundle.flow_authorizations)
$script:hasConflict = $false
$script:manifestEpisodeIds = @($manifest.episode_ids)
$script:imageTrack = 'OPTIONAL'
if ((Has-Property $manifest 'constraints') -and (Has-Property $manifest.constraints 'storyboard_image_track') -and $null -ne $manifest.constraints.storyboard_image_track) { $script:imageTrack = [string]$manifest.constraints.storyboard_image_track }

Require-String $manifest 'project_id' '$.project_manifest' | Out-Null
Require-String $manifest 'manifest_version' '$.project_manifest' | Out-Null
Require-String $manifest 'status' '$.project_manifest' | Out-Null
foreach ($name in @('episode_ids','required_scene_ids','source_materials')) { Require-Array $manifest $name '$.project_manifest' | Out-Null }
Require-Property $manifest 'constraints' '$.project_manifest' | Out-Null
if ((Has-Property $manifest 'manifest_version') -and $manifest.manifest_version -notmatch '^V[1-9][0-9]*$') { Add-Error '$.project_manifest.manifest_version must match V<n>.' }
if ((Has-Property $manifest 'status') -and $manifest.status -notin @('ACTIVE','ON_HOLD','COMPLETE')) { Add-Error '$.project_manifest.status is invalid.' }
if ((Has-Property $manifest 'visual_style_lock') -and $manifest.visual_style_lock -notin @('LIVE_ACTION_REALISM','GUOMAN_3D_CG')) { Add-Error '$.project_manifest.visual_style_lock must be LIVE_ACTION_REALISM or GUOMAN_3D_CG.' }
if (-not (Has-Property $manifest 'visual_style_lock')) { Add-Error '$.project_manifest.visual_style_lock is required (HUMAN_GATE 补锁，不得默认猜测).' }
if ((Has-Property $manifest 'constraints') -and (Has-Property $manifest.constraints 'storyboard_image_track') -and $manifest.constraints.storyboard_image_track -notin @('REQUIRED','OPTIONAL','DISABLED')) { Add-Error '$.project_manifest.constraints.storyboard_image_track is invalid.' }

$sourceCurrentCounts = @{}
for ($i = 0; $i -lt $script:sources.Count; $i++) {
    $source = $script:sources[$i]
    $sourcePath = "$.project_manifest.source_materials[$i]"
    foreach ($name in @('source_id','source_type','version','status','locator')) { Require-String $source $name $sourcePath | Out-Null }
    if ((Has-Property $source 'source_type') -and $source.source_type -notin @('SCRIPT','DIRECTOR_DECISION','ASSET','CONSTRAINT','OTHER')) { Add-Error "$sourcePath.source_type is invalid." }
    if ((Has-Property $source 'version') -and $source.version -notmatch '^V[1-9][0-9]*$') { Add-Error "$sourcePath.version must match V<n>." }
    if ((Has-Property $source 'status') -and $source.status -notin @('CURRENT','SUPERSEDED')) { Add-Error "$sourcePath.status is invalid." }
    if ((Has-Property $source 'source_id') -and (Has-Property $source 'status') -and $source.status -eq 'CURRENT') {
        if (-not $sourceCurrentCounts.ContainsKey($source.source_id)) { $sourceCurrentCounts[$source.source_id] = 0 }
        $sourceCurrentCounts[$source.source_id]++
    }
}
foreach ($key in $sourceCurrentCounts.Keys) {
    if ($sourceCurrentCounts[$key] -gt 1) { Add-Error "source_id $key has more than one CURRENT version." }
}

Require-String $stage 'project_id' '$.stage_state' | Out-Null
Require-String $stage 'current_stage' '$.stage_state' | Out-Null
Require-String $stage 'state' '$.stage_state' | Out-Null
Require-String $stage 'next_action' '$.stage_state' | Out-Null
Require-Property $stage 'current_artifact_full_id' '$.stage_state' | Out-Null
Require-Property $stage 'last_qa_verdict' '$.stage_state' | Out-Null
Require-Array $stage 'blocking_reasons' '$.stage_state' | Out-Null
if ((Has-Property $stage 'current_stage') -and $stage.current_stage -notin @('P1','P2','P3','P4','P5','P6','P7')) { Add-Error '$.stage_state.current_stage is invalid.' }
if ((Has-Property $stage 'state') -and $stage.state -notin @('READY','WAITING_PRODUCER','WAITING_QA','REPAIRING','WAITING_HUMAN','BLOCKED','COMPLETE')) { Add-Error '$.stage_state.state is invalid.' }
if ((Has-Property $stage 'last_qa_verdict') -and $null -ne $stage.last_qa_verdict -and $stage.last_qa_verdict -notin @('PASS','REPAIR','HUMAN_GATE')) { Add-Error '$.stage_state.last_qa_verdict is invalid.' }
if ((Has-Property $stage 'state') -and $stage.state -eq 'BLOCKED' -and @($stage.blocking_reasons).Count -eq 0) { Add-Error 'BLOCKED state requires blocking_reasons.' }
if ((Has-Property $stage 'state') -and $stage.state -eq 'COMPLETE' -and $stage.current_stage -ne 'P7') { Add-Error 'Only P7 may be COMPLETE.' }
if ($script:imageTrack -eq 'DISABLED' -and (Has-Property $stage 'current_stage') -and $stage.current_stage -in @('P3','P4','P5')) { Add-Error 'DIRECT_TRACK (storyboard_image_track=DISABLED) may not enter P3/P4/P5.' }

if ((Has-Property $manifest 'project_id') -and (Has-Property $stage 'project_id') -and $manifest.project_id -ne $stage.project_id) { Add-Error 'project_manifest.project_id and stage_state.project_id must match.' }

$decisionIds = @{}
$decisions = @($bundle.decision_ledger)
for ($i = 0; $i -lt $decisions.Count; $i++) {
    $decision = $decisions[$i]
    $decisionPath = "$.decision_ledger[$i]"
    foreach ($name in @('decision_id','status','source_id','scope','summary')) { Require-String $decision $name $decisionPath | Out-Null }
    if ((Has-Property $decision 'status') -and $decision.status -notin @('CONFIRMED','PROVISIONAL','REJECTED','CONFLICT')) { Add-Error "$decisionPath.status is invalid." }
    if ((Has-Property $decision 'status') -and $decision.status -eq 'CONFLICT') { $script:hasConflict = $true }
    if (Has-Property $decision 'decision_id') {
        if ($decisionIds.ContainsKey($decision.decision_id)) { Add-Error "Duplicate decision_id: $($decision.decision_id)." }
        else { $decisionIds[$decision.decision_id] = $true }
    }
}

$artifactTypes = @('PLOT','STORYBOARD_TABLE','STORYBOARD_PROMPT','STORYBOARD_IMAGE','APPROVED_STORYBOARD_SET','VIDEO_PROMPT','EPISODE_HANDOFF','DELIVERY_PACKAGE')
$artifactStatuses = @('DRAFT','CHECKING','REPAIR','PASS','HUMAN_GATE','APPROVED','STALE')
$currentIds = @{}
for ($i = 0; $i -lt $script:artifacts.Count; $i++) {
    $artifact = $script:artifacts[$i]
    $artifactPath = "$.artifact_index[$i]"
    foreach ($name in @('project_id','artifact_type','artifact_id','artifact_version','full_id','status','resource')) { Require-String $artifact $name $artifactPath | Out-Null }
    if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -in @('PLOT','STORYBOARD_TABLE','STORYBOARD_PROMPT','STORYBOARD_IMAGE','VIDEO_PROMPT')) {
        Require-String $artifact 'flow_authorization_id' $artifactPath | Out-Null
    }
    foreach ($name in @('current','stale')) {
        if (Require-Property $artifact $name $artifactPath) {
            if ($artifact.$name -isnot [bool]) { Add-Error "$artifactPath.$name must be boolean." }
        }
    }
    foreach ($name in @('source_beat_ids','source_full_ids')) { Require-Array $artifact $name $artifactPath | Out-Null }
    if ((Has-Property $artifact 'project_id') -and (Has-Property $manifest 'project_id') -and $artifact.project_id -ne $manifest.project_id) { Add-Error "$artifactPath.project_id must match the manifest." }
    if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -notin $artifactTypes) { Add-Error "$artifactPath.artifact_type is invalid." }
    if ((Has-Property $artifact 'artifact_version') -and $artifact.artifact_version -notmatch '^V[1-9][0-9]*$') { Add-Error "$artifactPath.artifact_version must match V<n>." }
    if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version') -and (Has-Property $artifact 'full_id') -and $artifact.full_id -ne ($artifact.artifact_id + '-' + $artifact.artifact_version)) { Add-Error "$artifactPath.full_id must equal artifact_id + '-' + artifact_version." }
    if ((Has-Property $artifact 'status') -and $artifact.status -notin $artifactStatuses) { Add-Error "$artifactPath.status is invalid." }
    if ((Has-Property $artifact 'status') -and (Has-Property $artifact 'stale') -and (($artifact.status -eq 'STALE') -ne ($artifact.stale -eq $true))) { Add-Error "$artifactPath.status STALE and stale=true must be set together." }
    if ((Has-Property $artifact 'scene_id') -and $null -ne $artifact.scene_id -and $artifact.scene_id -notmatch '^SCENE-E[0-9]{2,}-S[0-9]{2,}$') { Add-Error "$artifactPath.scene_id is not canonical." }
    if ((Has-Property $artifact 'shot_id') -and $null -ne $artifact.shot_id -and $artifact.shot_id -notmatch '^SHOT-E[0-9]{2,}-S[0-9]{2,}-[0-9]{3}$') { Add-Error "$artifactPath.shot_id is not canonical." }
    if ((Has-Property $artifact 'segment_id') -and $null -ne $artifact.segment_id -and $artifact.segment_id -notmatch '^SEG-E[0-9]{2,}-[0-9]{3}$') { Add-Error "$artifactPath.segment_id is not canonical." }
    if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -eq 'VIDEO_PROMPT') {
        if (Require-Array $artifact 'covered_shot_ids' $artifactPath) {
            foreach ($coveredId in @($artifact.covered_shot_ids)) {
                if ([string]$coveredId -notmatch '^SHOT-E[0-9]{2,}-S[0-9]{2,}-[0-9]{3}$') { Add-Error "$artifactPath.covered_shot_ids contains non-canonical ID: $coveredId." }
            }
        }
    }
    if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -eq 'EPISODE_HANDOFF' -and (Has-Property $artifact 'artifact_id') -and $artifact.artifact_id -notmatch '^HANDOFF-E[0-9]{2,}$') { Add-Error "$artifactPath.artifact_id must match HANDOFF-E## for EPISODE_HANDOFF." }
    foreach ($beatId in @($artifact.source_beat_ids)) {
        if ($beatId -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') { Add-Error "$artifactPath.source_beat_ids contains non-canonical ID: $beatId." }
    }
    if ((Has-Property $artifact 'current') -and $artifact.current -eq $true -and (Has-Property $artifact 'artifact_id')) {
        if ($currentIds.ContainsKey($artifact.artifact_id)) { Add-Error "artifact_id $($artifact.artifact_id) has more than one current version." }
        else { $currentIds[$artifact.artifact_id] = $true }
    }
    if ((Has-Property $artifact 'artifact_type') -and $artifact.artifact_type -eq 'APPROVED_STORYBOARD_SET') {
        if (Require-Array $artifact 'approved_items' $artifactPath) {
            $approvedItems = @($artifact.approved_items)
            for ($j = 0; $j -lt $approvedItems.Count; $j++) {
                $item = $approvedItems[$j]
                $itemPath = "$artifactPath.approved_items[$j]"
                foreach ($name in @('shot_id','image_full_id','status')) { Require-String $item $name $itemPath | Out-Null }
                if (Require-Property $item 'stale' $itemPath) {
                    if ($item.stale -isnot [bool]) { Add-Error "$itemPath.stale must be boolean." }
                }
                if ((Has-Property $item 'shot_id') -and $item.shot_id -notmatch '^SHOT-E[0-9]{2,}-S[0-9]{2,}-[0-9]{3}$') { Add-Error "$itemPath.shot_id is not canonical." }
                if ((Has-Property $item 'status') -and $item.status -ne 'APPROVED') { Add-Error "$itemPath.status must be APPROVED." }
                if ((Has-Property $item 'stale') -and $item.stale -eq $true) { Add-Error "$itemPath may not be stale in a current APPROVED set." }
            }
        }
    }
}

$authorizationIds = @{}
for ($i = 0; $i -lt $script:authorizations.Count; $i++) {
    $authorization = $script:authorizations[$i]
    $authorizationPath = "$.flow_authorizations[$i]"
    foreach ($name in @('authorization_id','project_id','stage','action','target','status','issued_at')) { Require-String $authorization $name $authorizationPath | Out-Null }
    foreach ($name in @('scope','artifact_full_id','ticket_id')) { Require-Property $authorization $name $authorizationPath | Out-Null }
    if ((Has-Property $authorization 'authorization_id') -and $authorization.authorization_id -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$') { Add-Error "$authorizationPath.authorization_id is invalid." }
    if ((Has-Property $authorization 'authorization_id')) {
        if ($authorizationIds.ContainsKey($authorization.authorization_id)) { Add-Error "Duplicate authorization_id: $($authorization.authorization_id)." }
        else { $authorizationIds[$authorization.authorization_id] = $true }
    }
    if ((Has-Property $authorization 'project_id') -and $authorization.project_id -ne $manifest.project_id) { Add-Error "$authorizationPath.project_id must match project_manifest.project_id." }
    if ((Has-Property $authorization 'stage') -and $authorization.stage -notin @('P1','P2','P3','P4','P6')) { Add-Error "$authorizationPath.stage is invalid." }
    if ((Has-Property $authorization 'action') -and $authorization.action -notin @('CALL_PRODUCER','ROUTE_REPAIR')) { Add-Error "$authorizationPath.action is invalid." }
    if ((Has-Property $authorization 'status') -and $authorization.status -notin @('ISSUED','CONSUMED','REVOKED')) { Add-Error "$authorizationPath.status is invalid." }
    if ((Has-Property $authorization 'scope') -and $null -ne $authorization.scope) {
        foreach ($name in @('episode_ids','scene_ids','shot_ids','beat_ids')) { Require-Array $authorization.scope $name "$authorizationPath.scope" | Out-Null }
    }
    if (Require-Property $authorization 'requirements' $authorizationPath) {
        if ($null -ne $authorization.requirements) {
            $req = $authorization.requirements
            if ($req -is [System.Array] -or $req -is [string]) { Add-Error "$authorizationPath.requirements must be an object." }
            else {
                if ((Has-Property $req 'quality_bar') -and $req.quality_bar -isnot [System.Array]) { Add-Error "$authorizationPath.requirements.quality_bar must be an array." }
                if ((Has-Property $req 'focus') -and $req.focus -isnot [System.Array]) { Add-Error "$authorizationPath.requirements.focus must be an array." }
                if ((Has-Property $req 'project_constraints') -and ($req.project_constraints -is [System.Array] -or $req.project_constraints -is [string])) { Add-Error "$authorizationPath.requirements.project_constraints must be an object." }
            }
        }
        elseif ((Has-Property $authorization 'status') -and $authorization.status -in @('ISSUED','CONSUMED')) { Add-Error "$authorizationPath.requirements is required for ISSUED/CONSUMED authorizations." }
    }
    if ((Has-Property $authorization 'status') -and $authorization.status -eq 'ISSUED' -and (Has-Property $authorization 'artifact_full_id') -and $null -ne $authorization.artifact_full_id) { Add-Error "$authorizationPath.artifact_full_id must be null while status is ISSUED." }
    if ((Has-Property $authorization 'status') -and $authorization.status -eq 'CONSUMED' -and ((-not (Has-Property $authorization 'artifact_full_id')) -or [string]::IsNullOrWhiteSpace([string]$authorization.artifact_full_id))) { Add-Error "$authorizationPath.artifact_full_id is required while status is CONSUMED." }
}

if (Has-Property $stage 'current_artifact_full_id') {
    $currentFullId = $stage.current_artifact_full_id
    if ($null -ne $currentFullId) {
        if ($currentFullId -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$currentFullId)) {
            Add-Error '$.stage_state.current_artifact_full_id must be null or a non-empty string.'
        }
        else {
            $currentMatches = @($script:artifacts | Where-Object { $_.full_id -eq $currentFullId -and $_.current -eq $true })
            if ($currentMatches.Count -ne 1) { Add-Error 'stage_state.current_artifact_full_id must resolve to one current ArtifactIndex entry.' }
        }
    }
    elseif ((Has-Property $stage 'state') -and $stage.state -in @('WAITING_QA','REPAIRING')) {
        Add-Error "Stage state $($stage.state) requires current_artifact_full_id."
    }
}

Require-String $dispatch 'action' '$.dispatch' | Out-Null
Require-Property $dispatch 'target' '$.dispatch' | Out-Null
Require-Property $dispatch 'qa_mode' '$.dispatch' | Out-Null
Require-Property $dispatch 'artifact_full_id' '$.dispatch' | Out-Null
Require-Property $dispatch 'ticket_id' '$.dispatch' | Out-Null
Require-Property $dispatch 'authorization_id' '$.dispatch' | Out-Null
Require-Property $dispatch 'scope' '$.dispatch' | Out-Null
Require-Property $dispatch 'reason' '$.dispatch' | Out-Null
if (Require-Property $dispatch 'requirements' '$.dispatch') {
    if ($null -ne $dispatch.requirements) {
        $dispatchReq = $dispatch.requirements
        if ($dispatchReq -is [System.Array] -or $dispatchReq -is [string]) { Add-Error '$.dispatch.requirements must be an object.' }
        else {
            if ((Has-Property $dispatchReq 'quality_bar') -and $dispatchReq.quality_bar -isnot [System.Array]) { Add-Error '$.dispatch.requirements.quality_bar must be an array.' }
            if ((Has-Property $dispatchReq 'focus') -and $dispatchReq.focus -isnot [System.Array]) { Add-Error '$.dispatch.requirements.focus must be an array.' }
            if ((Has-Property $dispatchReq 'project_constraints') -and ($dispatchReq.project_constraints -is [System.Array] -or $dispatchReq.project_constraints -is [string])) { Add-Error '$.dispatch.requirements.project_constraints must be an object.' }
        }
    }
}
$actions = @('CALL_PRODUCER','CALL_QA','ROUTE_REPAIR','REQUEST_HUMAN_APPROVAL','MARK_STALE','DELIVER','BLOCK','NONE')
if ((Has-Property $dispatch 'action') -and $dispatch.action -notin $actions) { Add-Error '$.dispatch.action is invalid.' }
if ((Has-Property $stage 'next_action') -and (Has-Property $dispatch 'action') -and $stage.next_action -ne $dispatch.action) { Add-Error 'stage_state.next_action must equal dispatch.action.' }
if ($null -ne $dispatch.scope) {
    foreach ($name in @('episode_ids','scene_ids','shot_ids','beat_ids')) { Require-Array $dispatch.scope $name '$.dispatch.scope' | Out-Null }
}

$allowedByState = @{
    READY=@('CALL_PRODUCER','MARK_STALE','BLOCK'); WAITING_PRODUCER=@('NONE','BLOCK'); WAITING_QA=@('CALL_QA','NONE','BLOCK')
    REPAIRING=@('ROUTE_REPAIR','CALL_QA','NONE','BLOCK'); WAITING_HUMAN=@('REQUEST_HUMAN_APPROVAL','BLOCK','NONE')
    BLOCKED=@('BLOCK','NONE'); COMPLETE=@('DELIVER','NONE')
}
if ((Has-Property $stage 'state') -and (Has-Property $dispatch 'action') -and $allowedByState.ContainsKey($stage.state) -and $dispatch.action -notin $allowedByState[$stage.state]) {
    Add-Error "dispatch action $($dispatch.action) is invalid for stage state $($stage.state)."
}

$producerTargets = @{ P1='script-plot-progression'; P2='storyboard-table-director'; P3='storyboard-image-prompt-director'; P4='storyboard-image-generation'; P6='video-prompt-director' }
$repairTargets = @('script-plot-progression','storyboard-table-director','storyboard-image-prompt-director','storyboard-image-generation','video-prompt-director')
$qaModes = @{ P1='PLOT'; P2='STORYBOARD_TABLE'; P3='STORYBOARD_PROMPT'; P4='STORYBOARD_IMAGE'; P6='VIDEO_PROMPT' }
$qaTypes = @{ P1='PLOT'; P2='STORYBOARD_TABLE'; P3='STORYBOARD_PROMPT'; P4='STORYBOARD_IMAGE'; P6='VIDEO_PROMPT' }

if ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'CALL_PRODUCER') {
    if (-not $producerTargets.ContainsKey($stage.current_stage)) { Add-Error "No producer may be called at $($stage.current_stage)." }
    elseif ($dispatch.target -ne $producerTargets[$stage.current_stage]) { Add-Error "CALL_PRODUCER target must be $($producerTargets[$stage.current_stage]) at $($stage.current_stage)." }
    if (-not (Has-GateForStage $stage.current_stage $dispatch.scope)) { Add-Error "The authoritative upstream gate for $($stage.current_stage) is not satisfied." }
    if (-not (Has-Property $dispatch 'requirements') -or $null -eq $dispatch.requirements) { Add-Error 'CALL_PRODUCER requires dispatch.requirements.' }
    if ([string]::IsNullOrWhiteSpace([string]$dispatch.authorization_id)) { Add-Error 'CALL_PRODUCER requires authorization_id.' }
    else {
        $matches = @($script:authorizations | Where-Object { $_.authorization_id -eq $dispatch.authorization_id })
        if ($matches.Count -ne 1) { Add-Error 'CALL_PRODUCER authorization_id must resolve to one authorization.' }
        else {
            $auth = $matches[0]
            if ($auth.project_id -ne $manifest.project_id -or $auth.stage -ne $stage.current_stage -or $auth.action -ne 'CALL_PRODUCER' -or $auth.target -ne $dispatch.target -or $auth.status -ne 'ISSUED' -or (Get-ScopeKey $auth.scope) -ne (Get-ScopeKey $dispatch.scope)) { Add-Error 'CALL_PRODUCER authorization must be ISSUED and exactly match project, stage, action, target, and scope.' }
            if ((Has-Property $dispatch 'requirements') -and (Has-Property $auth 'requirements') -and $null -ne $dispatch.requirements -and $null -ne $auth.requirements -and (ConvertTo-Json $auth.requirements -Depth 10 -Compress) -ne (ConvertTo-Json $dispatch.requirements -Depth 10 -Compress)) { Add-Error 'CALL_PRODUCER dispatch.requirements must equal the issued authorization requirements.' }
        }
    }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'CALL_QA') {
    if (-not $qaModes.ContainsKey($stage.current_stage)) { Add-Error "QA may not be called at $($stage.current_stage)." }
    else {
        if ($dispatch.target -ne 'short-drama-unified-qa') { Add-Error 'CALL_QA target must be short-drama-unified-qa.' }
        if ($dispatch.qa_mode -ne $qaModes[$stage.current_stage]) { Add-Error "qa_mode must be $($qaModes[$stage.current_stage]) at $($stage.current_stage)." }
        if ([string]::IsNullOrWhiteSpace([string]$dispatch.artifact_full_id)) { Add-Error 'CALL_QA requires artifact_full_id.' }
        else {
            if ($stage.current_artifact_full_id -ne $dispatch.artifact_full_id) { Add-Error 'CALL_QA artifact_full_id must equal stage_state.current_artifact_full_id.' }
            $matches = @($script:artifacts | Where-Object { $_.full_id -eq $dispatch.artifact_full_id -and $_.artifact_type -eq $qaTypes[$stage.current_stage] -and $_.status -in @('DRAFT','CHECKING') -and (Is-CurrentUsable $_) })
            if ($matches.Count -ne 1) { Add-Error 'CALL_QA artifact must be the unique current, non-stale DRAFT/CHECKING artifact of the stage type.' }
        }
        if (-not (Has-GateForStage $stage.current_stage $dispatch.scope)) { Add-Error "The QA upstream gate for $($stage.current_stage) is not satisfied." }
        if (-not (Has-Property $dispatch 'requirements') -or $null -eq $dispatch.requirements) { Add-Error 'CALL_QA requires dispatch.requirements (S06 ruling basis).' }
        if ([string]::IsNullOrWhiteSpace([string]$dispatch.authorization_id)) { Add-Error 'CALL_QA requires the consumed production authorization_id.' }
        else {
            $authorizations = @($script:authorizations | Where-Object { $_.authorization_id -eq $dispatch.authorization_id })
            if ($authorizations.Count -ne 1) { Add-Error 'CALL_QA authorization_id must resolve to one authorization.' }
            else {
                $auth = $authorizations[0]
                if ($auth.project_id -ne $manifest.project_id -or $auth.stage -ne $stage.current_stage -or $auth.target -ne $producerTargets[$stage.current_stage] -or $auth.status -ne 'CONSUMED' -or $auth.artifact_full_id -ne $dispatch.artifact_full_id -or (Get-ScopeKey $auth.scope) -ne (Get-ScopeKey $dispatch.scope)) { Add-Error 'CALL_QA must reference the matching CONSUMED production authorization.' }
                $indexed = @($script:artifacts | Where-Object { $_.full_id -eq $dispatch.artifact_full_id -and (Has-Property $_ 'flow_authorization_id') -and $_.flow_authorization_id -eq $dispatch.authorization_id })
                if ($indexed.Count -ne 1) { Add-Error 'CALL_QA artifact must carry the same flow_authorization_id.' }
            }
        }
    }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'REQUEST_HUMAN_APPROVAL') {
    if ($stage.current_stage -ne 'P5' -or $dispatch.target -ne 'human-director') { Add-Error 'REQUEST_HUMAN_APPROVAL is only valid at P5 and must target human-director.' }
    if (-not (Has-GateForStage 'P5' $dispatch.scope)) { Add-Error 'P5 requires current non-stale STORYBOARD_IMAGE: PASS for the requested shots.' }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'ROUTE_REPAIR') {
    if ([string]::IsNullOrWhiteSpace([string]$dispatch.ticket_id)) { Add-Error 'ROUTE_REPAIR requires ticket_id.' }
    else {
        $tickets = @($bundle.pending_repair_tickets | Where-Object { $_.ticket_id -eq $dispatch.ticket_id })
        if ($tickets.Count -ne 1) { Add-Error 'ROUTE_REPAIR ticket_id must match one pending ticket.' }
        else {
            $ticket = $tickets[0]
            if ($ticket.verdict -ne 'REPAIR') { Add-Error 'The routed ticket verdict must be REPAIR.' }
            if ($ticket.return_to -notin $repairTargets) { Add-Error 'RepairTicket.return_to is not a canonical production target.' }
            if ($ticket.return_to -ne $dispatch.target) { Add-Error 'ROUTE_REPAIR target must equal RepairTicket.return_to.' }
            if ($ticket.full_id -ne $stage.current_artifact_full_id) { Add-Error 'RepairTicket.full_id must equal stage_state.current_artifact_full_id.' }
            if ([int]$ticket.max_attempts_remaining -lt 1) { Add-Error 'RepairTicket.max_attempts_remaining must be at least 1.' }
            if (@($ticket.locked_fields).Count -eq 0) { Add-Error 'RepairTicket.locked_fields must be non-empty.' }
            if (-not (Has-Property $ticket 'repair_type') -or $ticket.repair_type -notin @('FULL_REDO','LOCAL_REPAIR','REINFORCE_CONSTRAINT')) { Add-Error 'RepairTicket.repair_type must be FULL_REDO, LOCAL_REPAIR, or REINFORCE_CONSTRAINT.' }
            if (-not (Has-Property $ticket 'must_fix') -or @($ticket.must_fix).Count -eq 0) { Add-Error 'RepairTicket.must_fix must be a non-empty array.' }
            if (Has-Property $ticket 'target_segment_ids') {
                foreach ($segId in @($ticket.target_segment_ids)) {
                    if ([string]$segId -notmatch '^SEG-E[0-9]{2,}-[0-9]{3}$') { Add-Error "RepairTicket.target_segment_ids contains non-canonical ID: $segId." }
                }
            }
            if (-not (Has-Property $dispatch 'requirements') -or $null -eq $dispatch.requirements) { Add-Error 'ROUTE_REPAIR requires dispatch.requirements.' }
            if ([string]::IsNullOrWhiteSpace([string]$dispatch.authorization_id)) { Add-Error 'ROUTE_REPAIR requires authorization_id.' }
            else {
                $matches = @($script:authorizations | Where-Object { $_.authorization_id -eq $dispatch.authorization_id })
                if ($matches.Count -ne 1) { Add-Error 'ROUTE_REPAIR authorization_id must resolve to one authorization.' }
                else {
                    $auth = $matches[0]
                    if ($auth.project_id -ne $manifest.project_id -or $auth.stage -ne $stage.current_stage -or $auth.action -ne 'ROUTE_REPAIR' -or $auth.target -ne $dispatch.target -or $auth.status -ne 'ISSUED' -or $auth.ticket_id -ne $dispatch.ticket_id -or (Get-ScopeKey $auth.scope) -ne (Get-ScopeKey $dispatch.scope)) { Add-Error 'ROUTE_REPAIR authorization must be ISSUED and exactly match project, stage, target, ticket, and scope.' }
                }
            }
        }
    }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'MARK_STALE') {
    $affected = @(Scope-Values $dispatch.scope 'scene_ids').Count + @(Scope-Values $dispatch.scope 'shot_ids').Count + @(Scope-Values $dispatch.scope 'beat_ids').Count
    if ($affected -eq 0) { Add-Error 'MARK_STALE requires a non-empty scene, shot, or beat scope.' }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'BLOCK') {
    if (@($stage.blocking_reasons).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$dispatch.reason)) { Add-Error 'BLOCK requires blocking_reasons and a reason.' }
}
elseif ((Has-Property $dispatch 'action') -and $dispatch.action -eq 'DELIVER') {
    if ($stage.current_stage -ne 'P7' -or -not (Has-GateForStage 'P7' $dispatch.scope)) { Add-Error 'DELIVER requires P7 and current non-stale VIDEO_PROMPT: PASS artifacts.' }
}

if ($script:hasConflict -and $dispatch.action -notin @('BLOCK','REQUEST_HUMAN_APPROVAL')) { Add-Error 'An unresolved DecisionLedger CONFLICT requires BLOCK or a human request.' }

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    exit 1
}

Write-Host "[PASS] S01 flow state is structurally valid and dispatch $($dispatch.action) satisfies the mechanical stage gate." -ForegroundColor Green
exit 0
