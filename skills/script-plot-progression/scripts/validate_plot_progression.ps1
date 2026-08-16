[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$errors = New-Object 'System.Collections.Generic.List[string]'
$warnings = New-Object 'System.Collections.Generic.List[string]'
$sceneIds = New-Object 'System.Collections.Generic.HashSet[string]'
$beatIds = New-Object 'System.Collections.Generic.HashSet[string]'
$coverageIds = New-Object 'System.Collections.Generic.HashSet[string]'
$dialogueRecords = New-Object 'System.Collections.Generic.List[object]'

function Add-ValidationError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Add-ValidationWarning {
    param([string]$Message)
    $script:warnings.Add($Message)
}

function Test-HasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.PSObject.Methods.Name -contains "ContainsKey") {
            return $Object.ContainsKey($Name)
        }
        return $Object.Contains($Name)
    }
    return $Object.PSObject.Properties.Name -contains $Name
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if (-not (Test-HasProperty $Object $Name)) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        Write-Output -NoEnumerate $Object[$Name]
        return
    }
    Write-Output -NoEnumerate $Object.$Name
}

function Test-NonEmptyString {
    param($Value)
    return ($Value -is [string]) -and (-not [string]::IsNullOrWhiteSpace($Value))
}

function Test-IsArray {
    param($Value)
    return $Value -is [System.Array]
}

function Require-Property {
    param($Object, [string]$Name, [string]$Context)
    if (-not (Test-HasProperty $Object $Name)) {
        Add-ValidationError "$Context is missing required property '$Name'."
        return $false
    }
    return $true
}

function Require-StringProperty {
    param($Object, [string]$Name, [string]$Context)
    if (-not (Require-Property $Object $Name $Context)) { return $false }
    if (-not (Test-NonEmptyString (Get-PropertyValue $Object $Name))) {
        Add-ValidationError "$Context.$Name must be a non-empty string."
        return $false
    }
    return $true
}

function Require-ArrayProperty {
    param($Object, [string]$Name, [string]$Context)
    if (-not (Require-Property $Object $Name $Context)) { return $false }
    if (-not (Test-IsArray (Get-PropertyValue $Object $Name))) {
        Add-ValidationError "$Context.$Name must be a JSON array."
        return $false
    }
    return $true
}

function Test-StateObject {
    param($State, [string]$Context)
    if ($null -eq $State) {
        Add-ValidationError "$Context must be an object."
        return
    }
    foreach ($field in @("characters", "props", "environment", "knowledge")) {
        if (-not (Require-Property $State $field $Context)) { continue }
        $value = Get-PropertyValue $State $field
        if (($null -eq $value) -or ($value -is [string]) -or ($value -is [System.Array])) {
            Add-ValidationError "$Context.$field must be a JSON object."
        }
    }
}

function Find-ForbiddenFields {
    param($Value, [string]$JsonPath)
    if ($null -eq $Value) { return }

    $forbidden = @(
        "shot_id", "shot_size", "camera", "camera_angle", "camera_movement",
        "focal_length", "aperture", "duration_seconds", "image_prompt", "video_prompt"
    )

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $propertyPath = "$JsonPath/$key"
            if ($forbidden -contains $key) {
                Add-ValidationError "Forbidden downstream field found at $propertyPath."
            }
            Find-ForbiddenFields $Value[$key] $propertyPath
        }
        return
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) {
        $index = 0
        foreach ($item in $Value) {
            Find-ForbiddenFields $item "$JsonPath/$index"
            $index++
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $propertyPath = "$JsonPath/$($property.Name)"
            if ($forbidden -contains $property.Name) {
                Add-ValidationError "Forbidden downstream field found at $propertyPath."
            }
            Find-ForbiddenFields $property.Value $propertyPath
        }
    }
}

function Test-OrderedEntries {
    param($Beat, [string]$Context)
    $orders = New-Object 'System.Collections.Generic.List[int]'

    $groups = @(
        @{ Name = "actions"; Actor = "actor"; Text = "action"; Target = $true },
        @{ Name = "reactions"; Actor = "actor"; Text = "reaction"; Target = $false },
        @{ Name = "dialogue"; Actor = "speaker"; Text = "text"; Target = $false }
    )

    foreach ($group in $groups) {
        $name = $group.Name
        if (-not (Require-ArrayProperty $Beat $name $Context)) { continue }
        if ($Beat -is [System.Collections.IDictionary]) {
            $items = @($Beat[$name])
        }
        else {
            $items = @($Beat.$name)
        }
        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $itemContext = "$Context.$name[$i]"
            foreach ($required in @("order", $group.Actor, $group.Text, "source_range")) {
                Require-Property $item $required $itemContext | Out-Null
            }
            if ($group.Target) {
                Require-Property $item "target" $itemContext | Out-Null
            }
            if ($name -eq "dialogue") {
                Require-Property $item "timing" $itemContext | Out-Null
            }

            if (Test-HasProperty $item "order") {
                $order = Get-PropertyValue $item "order"
                if (($order -isnot [int]) -and ($order -isnot [long])) {
                    Add-ValidationError "$itemContext.order must be an integer."
                }
                elseif ($order -lt 1) {
                    Add-ValidationError "$itemContext.order must be positive."
                }
                else {
                    $orders.Add([int]$order)
                }
            }

            foreach ($requiredText in @($group.Actor, $group.Text, "source_range")) {
                if ((Test-HasProperty $item $requiredText) -and -not (Test-NonEmptyString (Get-PropertyValue $item $requiredText))) {
                    Add-ValidationError "$itemContext.$requiredText must be a non-empty string."
                }
            }

            if ($name -eq "dialogue" -and
                (Test-HasProperty $item "source_range") -and
                (Test-HasProperty $item "text")) {
                $script:dialogueRecords.Add([pscustomobject]@{
                    BeatId = $Beat.beat_id
                    SourceRange = $item.source_range
                    Text = $item.text
                })
            }
        }
    }

    if ($orders.Count -eq 0) {
        Add-ValidationError "$Context must contain at least one action, reaction, or dialogue entry."
        return
    }

    $duplicates = $orders | Group-Object | Where-Object { $_.Count -gt 1 }
    foreach ($duplicate in $duplicates) {
        Add-ValidationError "$Context has duplicate narrative order $($duplicate.Name)."
    }

    $sorted = @($orders | Sort-Object -Unique)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $expected = $i + 1
        if ($sorted[$i] -ne $expected) {
            Add-ValidationError "$Context narrative orders must be contiguous from 1; expected $expected but found $($sorted[$i])."
            break
        }
    }
}

try {
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
}
catch {
    Write-Error "Artifact file not found: $Path"
    exit 2
}

try {
    $raw = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 100
    $artifact = $serializer.DeserializeObject($raw)
}
catch {
    Write-Error "Artifact is not valid UTF-8 JSON: $($_.Exception.Message)"
    exit 2
}

$topLevelRequired = @(
    "schema_version", "project_id", "artifact_id", "artifact_version", "full_id",
    "source_artifact_id", "source_version", "source_full_id", "source_artifacts", "status", "scope",
    "coverage_summary", "source_coverage", "decision_overrides", "conflicts",
    "unknowns", "scenes", "impact_scope"
)
foreach ($field in $topLevelRequired) {
    Require-Property $artifact $field "root" | Out-Null
}

foreach ($field in @("schema_version", "project_id", "artifact_id", "artifact_version", "full_id", "source_artifact_id", "source_version", "source_full_id", "status")) {
    if (Test-HasProperty $artifact $field) {
        if (-not (Test-NonEmptyString (Get-PropertyValue $artifact $field))) {
            Add-ValidationError "root.$field must be a non-empty string."
        }
    }
}

if ((Test-HasProperty $artifact "schema_version") -and $artifact.schema_version -ne "1.0") {
    Add-ValidationError "root.schema_version must be '1.0'."
}
if ((Test-HasProperty $artifact "artifact_id") -and $artifact.artifact_id -notmatch '^PLOT-[A-Z0-9][A-Z0-9-]*$') {
    Add-ValidationError "root.artifact_id must match PLOT-<scope>."
}
if ((Test-HasProperty $artifact "artifact_version") -and $artifact.artifact_version -notmatch '^V[1-9][0-9]*$') {
    Add-ValidationError "root.artifact_version must match V<number>."
}
if ((Test-HasProperty $artifact "artifact_id") -and (Test-HasProperty $artifact "artifact_version") -and (Test-HasProperty $artifact "full_id")) {
    $expectedFullId = "$($artifact.artifact_id)-$($artifact.artifact_version)"
    if ($artifact.full_id -ne $expectedFullId) {
        Add-ValidationError "root.full_id must equal '$expectedFullId'."
    }
}
if ((Test-HasProperty $artifact "source_artifact_id") -and (Test-HasProperty $artifact "source_version") -and (Test-HasProperty $artifact "source_full_id")) {
    $expectedSourceFullId = "$($artifact.source_artifact_id)-$($artifact.source_version)"
    if ($artifact.source_full_id -ne $expectedSourceFullId) {
        Add-ValidationError "root.source_full_id must equal '$expectedSourceFullId'."
    }
}

$allowedStatuses = @("DRAFT", "CHECKING", "REPAIR", "PASS", "HUMAN_GATE", "STALE")
if ((Test-HasProperty $artifact "status") -and $allowedStatuses -notcontains $artifact.status) {
    Add-ValidationError "root.status is not an allowed plot artifact status."
}

if (Require-ArrayProperty $artifact "source_artifacts" "root") {
    $sourceIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $primarySourceMatches = 0
    $allowedSourceTypes = @("SCRIPT", "CONFIRMED_DECISION", "CHARACTER_RELATION", "SCENE_FACT", "ASSET_CONSTRAINT", "TRANSCRIPT")
    foreach ($source in @($artifact.source_artifacts)) {
        $context = "root.source_artifacts"
        foreach ($field in @("source_id", "source_type", "version", "scope", "locator_type")) {
            Require-StringProperty $source $field $context | Out-Null
        }
        if (Test-HasProperty $source "source_id") {
            if (-not $sourceIds.Add([string]$source.source_id)) {
                Add-ValidationError "Duplicate source_id '$($source.source_id)'."
            }
            if ((Test-HasProperty $artifact "source_artifact_id") -and $source.source_id -eq $artifact.source_artifact_id) {
                $primarySourceMatches++
                if ((Test-HasProperty $source "source_type") -and $source.source_type -ne "SCRIPT") {
                    Add-ValidationError "The primary source_artifact_id must reference a SCRIPT source."
                }
                if ((Test-HasProperty $source "version") -and (Test-HasProperty $artifact "source_version") -and $source.version -ne $artifact.source_version) {
                    Add-ValidationError "root.source_version must match the primary source entry version."
                }
            }
        }
        if ((Test-HasProperty $source "source_type") -and $allowedSourceTypes -notcontains $source.source_type) {
            Add-ValidationError "Unsupported source_type '$($source.source_type)'."
        }
    }
    if ((Test-HasProperty $artifact "source_artifact_id") -and -not $sourceIds.Contains([string]$artifact.source_artifact_id)) {
        Add-ValidationError "root.source_artifact_id must reference an item in source_artifacts."
    }
    elseif ($primarySourceMatches -ne 1) {
        Add-ValidationError "root.source_artifact_id must reference exactly one primary source entry."
    }
}

if (Require-ArrayProperty $artifact "scenes" "root") {
    $scenes = @($artifact.scenes)
    if ($scenes.Count -eq 0) {
        Add-ValidationError "root.scenes must contain at least one scene."
    }

    for ($sceneIndex = 0; $sceneIndex -lt $scenes.Count; $sceneIndex++) {
        $scene = $scenes[$sceneIndex]
        $sceneContext = "root.scenes[$sceneIndex]"
        foreach ($field in @("scene_id", "scene_number", "source_ranges", "heading", "characters_present", "scene_start_state", "beats", "scene_end_state")) {
            Require-Property $scene $field $sceneContext | Out-Null
        }

        if (Require-StringProperty $scene "scene_id" $sceneContext) {
            if ($scene.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') {
                Add-ValidationError "$sceneContext.scene_id must match SCENE-E##-S##."
            }
            if (-not $sceneIds.Add([string]$scene.scene_id)) {
                Add-ValidationError "Duplicate scene_id '$($scene.scene_id)'."
            }
        }

        $expectedBeatPrefix = $null
        if ((Test-HasProperty $scene "scene_id") -and $scene.scene_id -match '^SCENE-(E[0-9]{2,4})-(S[0-9]{2,4})$') {
            $expectedBeatPrefix = "BEAT-$($Matches[1])-$($Matches[2])-"
        }

        if (Test-HasProperty $scene "scene_number") {
            if ((($scene.scene_number -isnot [int]) -and ($scene.scene_number -isnot [long])) -or $scene.scene_number -lt 1) {
                Add-ValidationError "$sceneContext.scene_number must be a positive integer."
            }
        }

        foreach ($arrayField in @("source_ranges", "characters_present", "beats")) {
            Require-ArrayProperty $scene $arrayField $sceneContext | Out-Null
        }
        if ((Test-HasProperty $scene "source_ranges") -and (Test-IsArray $scene.source_ranges) -and @($scene.source_ranges).Count -eq 0) {
            Add-ValidationError "$sceneContext.source_ranges must not be empty."
        }
        elseif ((Test-HasProperty $scene "source_ranges") -and (Test-IsArray $scene.source_ranges)) {
            foreach ($range in @($scene.source_ranges)) {
                if (-not (Test-NonEmptyString $range)) {
                    Add-ValidationError "$sceneContext.source_ranges must contain only non-empty strings."
                }
            }
        }
        if ((Test-HasProperty $scene "characters_present") -and (Test-IsArray $scene.characters_present)) {
            foreach ($character in @($scene.characters_present)) {
                if (-not (Test-NonEmptyString $character)) {
                    Add-ValidationError "$sceneContext.characters_present must contain only non-empty strings."
                }
            }
        }

        if (Test-HasProperty $scene "heading") {
            foreach ($headingField in @("time", "interior_exterior", "location")) {
                Require-StringProperty $scene.heading $headingField "$sceneContext.heading" | Out-Null
            }
        }
        if (Test-HasProperty $scene "scene_start_state") {
            Test-StateObject $scene.scene_start_state "$sceneContext.scene_start_state"
        }
        if (Test-HasProperty $scene "scene_end_state") {
            Test-StateObject $scene.scene_end_state "$sceneContext.scene_end_state"
        }

        if ((Test-HasProperty $scene "beats") -and (Test-IsArray $scene.beats)) {
            $beats = @($scene.beats)
            if ($beats.Count -eq 0) {
                Add-ValidationError "$sceneContext.beats must not be empty."
            }
            for ($beatIndex = 0; $beatIndex -lt $beats.Count; $beatIndex++) {
                $beat = $beats[$beatIndex]
                $beatContext = "$sceneContext.beats[$beatIndex]"
                foreach ($field in @("beat_id", "source_ranges", "source_status", "start_state", "trigger", "actions", "reactions", "dialogue", "emotion_change", "end_state", "continuity", "decision_overrides", "notes")) {
                    Require-Property $beat $field $beatContext | Out-Null
                }

                if (Require-StringProperty $beat "beat_id" $beatContext) {
                    if ($beat.beat_id -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') {
                        Add-ValidationError "$beatContext.beat_id must match BEAT-E##-S##-###."
                    }
                    if (-not $beatIds.Add([string]$beat.beat_id)) {
                        Add-ValidationError "Duplicate beat_id '$($beat.beat_id)'."
                    }
                    if ($null -ne $expectedBeatPrefix -and -not $beat.beat_id.StartsWith($expectedBeatPrefix, [System.StringComparison]::Ordinal)) {
                        Add-ValidationError "$beatContext.beat_id must belong to scene '$($scene.scene_id)'."
                    }
                    $expectedSuffix = ('{0:D3}' -f ($beatIndex + 1))
                    if (-not $beat.beat_id.EndsWith("-$expectedSuffix")) {
                        Add-ValidationError "$beatContext.beat_id must use contiguous scene order ending in $expectedSuffix."
                    }
                }

                if (Require-ArrayProperty $beat "source_ranges" $beatContext) {
                    if (@($beat.source_ranges).Count -eq 0) {
                        Add-ValidationError "$beatContext.source_ranges must not be empty."
                    }
                    foreach ($range in @($beat.source_ranges)) {
                        if (-not (Test-NonEmptyString $range)) {
                            Add-ValidationError "$beatContext.source_ranges must contain only non-empty strings."
                        }
                    }
                }
                if (Require-StringProperty $beat "source_status" $beatContext) {
                    if (@("CONFIRMED", "DERIVED") -notcontains $beat.source_status) {
                        Add-ValidationError "$beatContext.source_status must be CONFIRMED or DERIVED."
                    }
                }
                if (Test-HasProperty $beat "start_state") {
                    Test-StateObject $beat.start_state "$beatContext.start_state"
                }
                if (Test-HasProperty $beat "end_state") {
                    Test-StateObject $beat.end_state "$beatContext.end_state"
                }
                if (Test-HasProperty $beat "trigger") {
                    Require-StringProperty $beat.trigger "event" "$beatContext.trigger" | Out-Null
                    Require-StringProperty $beat.trigger "source_range" "$beatContext.trigger" | Out-Null
                }

                Test-OrderedEntries $beat $beatContext

                if (Require-ArrayProperty $beat "emotion_change" $beatContext) {
                    $emotions = @($beat.emotion_change)
                    for ($emotionIndex = 0; $emotionIndex -lt $emotions.Count; $emotionIndex++) {
                        $emotion = $emotions[$emotionIndex]
                        $emotionContext = "$beatContext.emotion_change[$emotionIndex]"
                        foreach ($field in @("character", "from", "to", "evidence")) {
                            Require-Property $emotion $field $emotionContext | Out-Null
                        }
                        foreach ($field in @("character", "from", "to")) {
                            if ((Test-HasProperty $emotion $field) -and -not (Test-NonEmptyString (Get-PropertyValue $emotion $field))) {
                                Add-ValidationError "$emotionContext.$field must be a non-empty string."
                            }
                        }
                        if ((Require-ArrayProperty $emotion "evidence" $emotionContext) -and @($emotion.evidence).Count -eq 0) {
                            Add-ValidationError "$emotionContext.evidence must not be empty."
                        }
                    }
                }

                if (Test-HasProperty $beat "continuity") {
                    Require-ArrayProperty $beat.continuity "must_carry_forward" "$beatContext.continuity" | Out-Null
                    Require-ArrayProperty $beat.continuity "open_actions" "$beatContext.continuity" | Out-Null
                }
                Require-ArrayProperty $beat "decision_overrides" $beatContext | Out-Null
                Require-ArrayProperty $beat "notes" $beatContext | Out-Null
            }
        }
    }
}

if ((Test-HasProperty $artifact "scope") -and (Test-HasProperty $artifact.scope "scene_ids")) {
    if (-not (Test-IsArray $artifact.scope.scene_ids)) {
        Add-ValidationError "root.scope.scene_ids must be a JSON array."
    }
    else {
        $declared = @($artifact.scope.scene_ids | Sort-Object -Unique)
        $actual = @($sceneIds | Sort-Object)
        if (($declared -join '|') -ne ($actual -join '|')) {
            Add-ValidationError "root.scope.scene_ids must exactly match the scene IDs in root.scenes."
        }
    }
}
if (Test-HasProperty $artifact "scope") {
    Require-StringProperty $artifact.scope "episode_id" "root.scope" | Out-Null
    if ((Test-HasProperty $artifact.scope "episode_id") -and (Test-NonEmptyString $artifact.scope.episode_id)) {
        foreach ($sceneId in $sceneIds) {
            if (-not $sceneId.StartsWith("SCENE-$($artifact.scope.episode_id)-", [System.StringComparison]::Ordinal)) {
                Add-ValidationError "Scene '$sceneId' does not belong to root.scope.episode_id '$($artifact.scope.episode_id)'."
            }
        }
    }
}

$eventTotal = 0
$eventFull = 0
$dialogueTotal = 0
$dialogueFull = 0
if (Require-ArrayProperty $artifact "source_coverage" "root") {
    $coverageItems = @($artifact.source_coverage)
    for ($coverageIndex = 0; $coverageIndex -lt $coverageItems.Count; $coverageIndex++) {
        $coverage = $coverageItems[$coverageIndex]
        $coverageContext = "root.source_coverage[$coverageIndex]"
        foreach ($field in @("coverage_id", "source_range", "content_type", "source_text", "covered_by", "coverage", "note")) {
            Require-Property $coverage $field $coverageContext | Out-Null
        }
        foreach ($field in @("coverage_id", "source_range", "content_type", "source_text", "coverage")) {
            if ((Test-HasProperty $coverage $field) -and -not (Test-NonEmptyString (Get-PropertyValue $coverage $field))) {
                Add-ValidationError "$coverageContext.$field must be a non-empty string."
            }
        }
        if (Test-HasProperty $coverage "coverage_id") {
            if (-not $coverageIds.Add([string]$coverage.coverage_id)) {
                Add-ValidationError "Duplicate coverage_id '$($coverage.coverage_id)'."
            }
        }
        if (Require-ArrayProperty $coverage "covered_by" $coverageContext) {
            if (@($coverage.covered_by).Count -eq 0) {
                $allowEmptyCoverage = (Test-HasProperty $artifact "status") -and
                    $artifact.status -eq "HUMAN_GATE" -and
                    (Test-HasProperty $coverage "coverage") -and
                    $coverage.coverage -ne "FULL"
                if (-not $allowEmptyCoverage) {
                    Add-ValidationError "$coverageContext.covered_by may be empty only for non-FULL coverage in a HUMAN_GATE artifact."
                }
            }
            foreach ($coveredBeat in @($coverage.covered_by)) {
                if (-not $beatIds.Contains([string]$coveredBeat)) {
                    Add-ValidationError "$coverageContext.covered_by references unknown beat '$coveredBeat'."
                }
            }
        }
        if ((Test-HasProperty $coverage "content_type") -and @("EVENT", "DIALOGUE") -notcontains $coverage.content_type) {
            Add-ValidationError "$coverageContext.content_type must be EVENT or DIALOGUE."
        }
        if ((Test-HasProperty $coverage "coverage") -and @("FULL", "PARTIAL", "OMITTED") -notcontains $coverage.coverage) {
            Add-ValidationError "$coverageContext.coverage is invalid."
        }
        if ((Test-HasProperty $coverage "coverage") -and $coverage.coverage -ne "FULL") {
            if ((Test-HasProperty $artifact "status") -and $artifact.status -eq "HUMAN_GATE") {
                Add-ValidationWarning "$coverageContext is not fully covered because the artifact is gated."
            }
            else {
                Add-ValidationError "$coverageContext must be FULL before QA submission."
            }
        }

        if ((Test-HasProperty $coverage "content_type") -and (Test-HasProperty $coverage "coverage")) {
            if ($coverage.content_type -eq "EVENT") {
                $eventTotal++
                if ($coverage.coverage -eq "FULL") { $eventFull++ }
            }
            elseif ($coverage.content_type -eq "DIALOGUE") {
                $dialogueTotal++
                if ($coverage.coverage -eq "FULL") { $dialogueFull++ }

                if ((Test-HasProperty $coverage "source_range") -and
                    (Test-HasProperty $coverage "source_text") -and
                    (Test-HasProperty $coverage "covered_by")) {
                    $matches = @($dialogueRecords | Where-Object {
                        $_.SourceRange -eq $coverage.source_range -and
                        $_.Text -ceq $coverage.source_text -and
                        @($coverage.covered_by) -contains $_.BeatId
                    })
                    if ($matches.Count -eq 0) {
                        Add-ValidationError "$coverageContext does not exactly match a dialogue entry by source range, text, and beat ID."
                    }
                }
            }
        }
    }
}

foreach ($record in $dialogueRecords) {
    $matches = @($artifact.source_coverage | Where-Object {
        $_.content_type -eq "DIALOGUE" -and
        $_.source_range -eq $record.SourceRange -and
        $_.source_text -ceq $record.Text -and
        @($_.covered_by) -contains $record.BeatId
    })
    if ($matches.Count -eq 0) {
        Add-ValidationError "Dialogue in beat '$($record.BeatId)' at '$($record.SourceRange)' lacks an exact source_coverage item."
    }
}

if (Test-HasProperty $artifact "coverage_summary") {
    $summary = $artifact.coverage_summary
    $expectedCounts = @{
        total_story_events = $eventTotal
        covered_story_events = $eventFull
        total_dialogue_lines = $dialogueTotal
        preserved_dialogue_lines = $dialogueFull
    }
    foreach ($field in $expectedCounts.Keys) {
        if (Require-Property $summary $field "root.coverage_summary") {
            if ((Get-PropertyValue $summary $field) -ne $expectedCounts[$field]) {
                Add-ValidationError "root.coverage_summary.$field must equal $($expectedCounts[$field])."
            }
        }
    }
}

foreach ($arrayField in @("decision_overrides", "conflicts", "unknowns")) {
    Require-ArrayProperty $artifact $arrayField "root" | Out-Null
}

if ((Test-HasProperty $artifact "decision_overrides") -and (Test-IsArray $artifact.decision_overrides)) {
    foreach ($decision in @($artifact.decision_overrides)) {
        foreach ($field in @("decision_id", "overrides_source", "original_value", "confirmed_value", "affected_beats", "status")) {
            Require-Property $decision $field "root.decision_overrides" | Out-Null
        }
        if ((Test-HasProperty $decision "status") -and $decision.status -ne "CONFIRMED") {
            Add-ValidationError "All applied decision_overrides must have status CONFIRMED."
        }
        Require-ArrayProperty $decision "affected_beats" "root.decision_overrides" | Out-Null
    }
}

$hasUnresolvedConflict = $false
if ((Test-HasProperty $artifact "conflicts") -and (Test-IsArray $artifact.conflicts)) {
    foreach ($conflict in @($artifact.conflicts)) {
        foreach ($field in @("conflict_id", "source_refs", "summary", "affected_scope", "status", "question")) {
            Require-Property $conflict $field "root.conflicts" | Out-Null
        }
        Require-ArrayProperty $conflict "source_refs" "root.conflicts" | Out-Null
        Require-ArrayProperty $conflict "affected_scope" "root.conflicts" | Out-Null
        if ((Test-HasProperty $conflict "status") -and $conflict.status -eq "UNRESOLVED") {
            $hasUnresolvedConflict = $true
        }
    }
}
$hasBlockingUnknown = $false
if ((Test-HasProperty $artifact "unknowns") -and (Test-IsArray $artifact.unknowns)) {
    foreach ($unknown in @($artifact.unknowns)) {
        foreach ($field in @("unknown_id", "description", "affected_scope", "blocking", "source_refs")) {
            Require-Property $unknown $field "root.unknowns" | Out-Null
        }
        Require-ArrayProperty $unknown "affected_scope" "root.unknowns" | Out-Null
        Require-ArrayProperty $unknown "source_refs" "root.unknowns" | Out-Null
        if ((Test-HasProperty $unknown "blocking") -and $unknown.blocking -eq $true) {
            $hasBlockingUnknown = $true
        }
    }
}
if (($hasUnresolvedConflict -or $hasBlockingUnknown) -and $artifact.status -ne "HUMAN_GATE") {
    Add-ValidationError "Unresolved conflicts or blocking unknowns require root.status HUMAN_GATE."
}
if ($artifact.status -eq "HUMAN_GATE" -and -not ($hasUnresolvedConflict -or $hasBlockingUnknown)) {
    Add-ValidationWarning "Artifact is HUMAN_GATE but no unresolved conflict or blocking unknown was found."
}

if (Test-HasProperty $artifact "impact_scope") {
    Require-ArrayProperty $artifact.impact_scope "changed_beats" "root.impact_scope" | Out-Null
    Require-ArrayProperty $artifact.impact_scope "stale_downstream" "root.impact_scope" | Out-Null
}

Find-ForbiddenFields $artifact ""

foreach ($warning in $warnings) {
    Write-Host "[WARN] $warning" -ForegroundColor Yellow
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) {
        Write-Host "[ERROR] $validationError" -ForegroundColor Red
    }
    Write-Host "[FAIL] PlotProgressionSpec validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] PlotProgressionSpec structure is valid: $resolvedPath" -ForegroundColor Green
exit 0
