[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
function Has-Property($Object, [string]$Name) { return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] }
function Require-Property($Object, [string]$Name, [string]$Context) { if (-not (Has-Property $Object $Name)) { $script:errors.Add("$Context.$Name is required."); return $false }; return $true }
function Is-Array($Value) { return $Value -is [System.Array] }
function Require-Array($Object, [string]$Name, [string]$Context, [bool]$AllowEmpty = $true) { if (-not (Require-Property $Object $Name $Context)) { return $false }; if (-not (Is-Array $Object.$Name)) { $script:errors.Add("$Context.$Name must be an array."); return $false }; if (-not $AllowEmpty -and @($Object.$Name).Count -eq 0) { $script:errors.Add("$Context.$Name must not be empty."); return $false }; return $true }
function Require-NonEmptyString($Object, [string]$Name, [string]$Context) { if (-not (Require-Property $Object $Name $Context)) { return $false }; if ($Object.$Name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Object.$Name)) { $script:errors.Add("$Context.$Name must be a non-empty string."); return $false }; return $true }
function Get-CodePointCount([string]$Text) { $count = 0; for ($i = 0; $i -lt $Text.Length; $i++) { if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])) { $i++ }; $count++ }; return $count }
function Get-SortedArrayKey($Value) { if (-not (Is-Array $Value)) { return $null }; return (@($Value) | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '|' }

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "VideoPromptSpec not found: $Path"; exit 2 }
try { $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

$required = @('schema_version','project_id','flow_authorization_id','scene_id','shot_id','source_beat_ids','artifact_id','artifact_version','full_id','video_prompt_id','status','task','approved_storyboard_set_full_id','approved_image_full_id','source_artifacts','reference_bindings','source_lock','start_state','action_flow','dialogue_audio','camera','lighting_color_material','sound','end_state','continuity_constraints','continuity_checks','body_sections','body','body_char_count','unresolved_fields','change_log')
foreach ($field in $required) { Require-Property $artifact $field 'root' | Out-Null }

if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '1.0') { $errors.Add('root.schema_version must be 1.0.') }
if ((Has-Property $artifact 'flow_authorization_id') -and $artifact.flow_authorization_id -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$') { $errors.Add('root.flow_authorization_id is invalid. Production must be dispatched by S01.') }
if ((Has-Property $artifact 'scene_id') -and $artifact.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add('root.scene_id is invalid.') }
if ((Has-Property $artifact 'shot_id') -and $artifact.shot_id -notmatch '^SHOT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3}$') { $errors.Add('root.shot_id is invalid.') }
if ((Has-Property $artifact 'scene_id') -and (Has-Property $artifact 'shot_id')) { $scenePart = $artifact.scene_id -replace '^SCENE-',''; if ($artifact.shot_id -notmatch ('^SHOT-' + [regex]::Escape($scenePart) + '-[0-9]{3}$')) { $errors.Add('root.shot_id does not belong to root.scene_id.') } }
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'shot_id')) { $expected = $artifact.shot_id -replace '^SHOT-','VP-'; if ($artifact.artifact_id -ne $expected) { $errors.Add("root.artifact_id must be $expected.") } }
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version')) { $expectedFullId = "$($artifact.artifact_id)-$($artifact.artifact_version)"; if ((Has-Property $artifact 'full_id') -and $artifact.full_id -ne $expectedFullId) { $errors.Add('root.full_id is inconsistent.') }; if ((Has-Property $artifact 'video_prompt_id') -and $artifact.video_prompt_id -ne $expectedFullId) { $errors.Add('root.video_prompt_id is inconsistent.') } }
if ((Has-Property $artifact 'status') -and @('DRAFT','CHECKING','REPAIR','PASS','HUMAN_GATE','STALE') -notcontains $artifact.status) { $errors.Add('root.status is invalid.') }
if (Require-Array $artifact 'source_beat_ids' 'root' $false) { foreach ($beatId in @($artifact.source_beat_ids)) { if ([string]$beatId -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') { $errors.Add("Invalid source_beat_ids item $beatId") } } }

foreach ($arrayField in @('source_artifacts','reference_bindings','dialogue_audio','continuity_constraints','unresolved_fields','change_log')) { Require-Array $artifact $arrayField 'root' $true | Out-Null }
$roles = @{}
if (Has-Property $artifact 'source_artifacts') {
    foreach ($source in @($artifact.source_artifacts)) {
        foreach ($field in @('role','artifact_id','artifact_version','full_id','status','stale','scope')) { Require-Property $source $field 'root.source_artifacts[]' | Out-Null }
        if (Has-Property $source 'role') { if ($roles.ContainsKey([string]$source.role)) { $errors.Add("Duplicate source role: $($source.role)") } else { $roles[[string]$source.role] = $source } }
        if ((Has-Property $source 'artifact_id') -and (Has-Property $source 'artifact_version') -and (Has-Property $source 'full_id') -and $source.full_id -ne "$($source.artifact_id)-$($source.artifact_version)") { $errors.Add("Source full_id is inconsistent for role $($source.role).") }
        if ((Has-Property $source 'stale') -and $source.stale -ne $false) { $errors.Add("Source role $($source.role) must not be stale.") }
    }
}
foreach ($requiredRole in @('APPROVED_STORYBOARD_SET','APPROVED_STORYBOARD','STORYBOARD_PROMPT','PLOT_PROGRESSION','STORYBOARD_TABLE','ORIGINAL_DIALOGUE','MODEL_RULES','PREVIOUS_END_STATE')) { if (-not $roles.ContainsKey($requiredRole)) { $errors.Add("Missing source role: $requiredRole") } }
if ((Has-Property $artifact 'approved_storyboard_set_full_id') -and $artifact.approved_storyboard_set_full_id -notmatch '^APPROVED-STORYBOARD-E[0-9]{2,4}-V[0-9]+$') { $errors.Add('approved_storyboard_set_full_id is invalid.') }
if ($roles.ContainsKey('APPROVED_STORYBOARD_SET')) { $source = $roles['APPROVED_STORYBOARD_SET']; if ($source.status -ne 'APPROVED') { $errors.Add('APPROVED_STORYBOARD_SET source must be APPROVED.') }; if ((Has-Property $artifact 'approved_storyboard_set_full_id') -and $artifact.approved_storyboard_set_full_id -ne $source.full_id) { $errors.Add('approved_storyboard_set_full_id must equal APPROVED_STORYBOARD_SET full_id.') } }
if ($roles.ContainsKey('APPROVED_STORYBOARD')) {
    $source = $roles['APPROVED_STORYBOARD']
    if ($source.status -ne 'APPROVED') { $errors.Add('APPROVED_STORYBOARD source must be APPROVED.') }
    if ((Has-Property $artifact 'approved_image_full_id') -and $artifact.approved_image_full_id -ne $source.full_id) { $errors.Add('approved_image_full_id must equal APPROVED_STORYBOARD full_id.') }
    if ($source.scope -ne $artifact.shot_id) { $errors.Add('APPROVED_STORYBOARD scope must equal shot_id.') }
    if (-not (Has-Property $source 'source_prompt_full_id')) { $errors.Add('APPROVED_STORYBOARD source_prompt_full_id is required.') }
    if (-not (Has-Property $source 'approval_record')) { $errors.Add('APPROVED_STORYBOARD approval_record is required.') }
    else { foreach ($field in @('approved_by','approved_at','locked_fields','allowed_changes')) { Require-Property $source.approval_record $field 'APPROVED_STORYBOARD.approval_record' | Out-Null } }
}
if ($roles.ContainsKey('STORYBOARD_PROMPT')) {
    $source = $roles['STORYBOARD_PROMPT']
    if ($source.status -ne 'PASS') { $errors.Add('STORYBOARD_PROMPT source must be PASS.') }
    if ($source.scope -ne $artifact.shot_id) { $errors.Add('STORYBOARD_PROMPT scope must equal shot_id.') }
    if ($roles.ContainsKey('APPROVED_STORYBOARD') -and (Has-Property $roles['APPROVED_STORYBOARD'] 'source_prompt_full_id') -and $roles['APPROVED_STORYBOARD'].source_prompt_full_id -ne $source.full_id) { $errors.Add('APPROVED_STORYBOARD source_prompt_full_id must equal STORYBOARD_PROMPT full_id.') }
}
if ($roles.ContainsKey('PLOT_PROGRESSION') -and $roles['PLOT_PROGRESSION'].status -ne 'PASS') { $errors.Add('PLOT_PROGRESSION source must be PASS.') }
if ($roles.ContainsKey('STORYBOARD_TABLE')) { $source = $roles['STORYBOARD_TABLE']; if ($source.status -ne 'PASS') { $errors.Add('STORYBOARD_TABLE source must be PASS.') }; if (-not (Has-Property $source 'row_full_id')) { $errors.Add('STORYBOARD_TABLE source must include row_full_id.') }; if (-not (Has-Property $source 'storyboard_row_version')) { $errors.Add('STORYBOARD_TABLE source must include storyboard_row_version.') }; if ((Has-Property $source 'row_full_id') -and (Has-Property $source 'storyboard_row_version') -and $source.row_full_id -ne "$($artifact.shot_id)-$($source.storyboard_row_version)") { $errors.Add('STORYBOARD_TABLE row_full_id must equal shot_id + storyboard_row_version.') } }
if ($roles.ContainsKey('MODEL_RULES') -and ((-not (Has-Property $roles['MODEL_RULES'] 'validation_status')) -or $roles['MODEL_RULES'].validation_status -ne 'VERIFIED')) { $errors.Add('MODEL_RULES source must have validation_status VERIFIED.') }
if ($roles.ContainsKey('ORIGINAL_DIALOGUE')) {
    $dialogueSource = $roles['ORIGINAL_DIALOGUE']
    $hasDialoguePolicy = Has-Property $dialogueSource 'dialogue_policy'
    $dialoguePolicy = if ($hasDialoguePolicy) { [string]$dialogueSource.dialogue_policy } else { $null }
    $hasExactLines = (Has-Property $dialogueSource 'exact_lines') -and (Is-Array $dialogueSource.exact_lines)
    if (-not $hasDialoguePolicy -or @('EXACT_SOURCE_TEXT','NO_DIALOGUE') -notcontains $dialoguePolicy) { $errors.Add('ORIGINAL_DIALOGUE.dialogue_policy must be EXACT_SOURCE_TEXT or NO_DIALOGUE.') }
    if (-not $hasExactLines) { $errors.Add('ORIGINAL_DIALOGUE.exact_lines must be an array.') }
    elseif ($dialoguePolicy -eq 'NO_DIALOGUE') {
        if (@($dialogueSource.exact_lines).Count -ne 0 -or @($artifact.dialogue_audio).Count -ne 0) { $errors.Add('NO_DIALOGUE requires empty exact_lines and dialogue_audio arrays.') }
    }
    elseif ($dialoguePolicy -eq 'EXACT_SOURCE_TEXT') {
        if (@($dialogueSource.exact_lines).Count -eq 0) { $errors.Add('EXACT_SOURCE_TEXT requires at least one exact line.') }
        $sourceDialogueKeys = @($dialogueSource.exact_lines | ForEach-Object { "$($_.speaker)|$($_.text)|$($_.source_ref)" } | Sort-Object)
        $artifactDialogueKeys = @($artifact.dialogue_audio | ForEach-Object { "$($_.speaker)|$($_.exact_text)|$($_.source_ref)" } | Sort-Object)
        if (($sourceDialogueKeys -join "`n") -cne ($artifactDialogueKeys -join "`n")) { $errors.Add('dialogue_audio must exactly match ORIGINAL_DIALOGUE.exact_lines.') }
    }
}
foreach ($roleName in @('APPROVED_STORYBOARD','STORYBOARD_PROMPT','PLOT_PROGRESSION','STORYBOARD_TABLE')) {
    if ($roles.ContainsKey($roleName)) {
        $source = $roles[$roleName]
        if (-not (Has-Property $source 'source_beat_ids') -or -not (Is-Array $source.source_beat_ids)) { $errors.Add("$roleName source must include source_beat_ids array.") }
        elseif ((Get-SortedArrayKey $source.source_beat_ids) -ne (Get-SortedArrayKey $artifact.source_beat_ids)) { $errors.Add("$roleName source_beat_ids must match root.source_beat_ids.") }
    }
}

if (Has-Property $artifact 'task') {
    foreach ($field in @('task_mode','generation_task','model','model_rule_profile','product_flow','output_scope','delivery_mode','aspect_ratio','target_duration_seconds')) { Require-Property $artifact.task $field 'root.task' | Out-Null }
    if ((Has-Property $artifact.task 'output_scope') -and $artifact.task.output_scope -ne 'SINGLE_SHOT') { $errors.Add('root.task.output_scope must be SINGLE_SHOT.') }
    if (Has-Property $artifact.task 'model') {
        $expectedDuration = switch ([string]$artifact.task.model) {
            'seedance-2.0' { 15 }
            'seedance-2.5' { 30 }
            default { $errors.Add('root.task.model must be seedance-2.0 or seedance-2.5.'); $null }
        }
        if ($null -ne $expectedDuration -and (Has-Property $artifact.task 'target_duration_seconds') -and [double]$artifact.task.target_duration_seconds -ne $expectedDuration) {
            $errors.Add("root.task.target_duration_seconds must be $expectedDuration for $($artifact.task.model).")
        }
    }
}

if (Has-Property $artifact 'reference_bindings') {
    if (@($artifact.reference_bindings).Count -eq 0) { $errors.Add('root.reference_bindings must contain at least one provided or auto-planned Mixed slot.') }
    $slotNumbers = [System.Collections.Generic.List[int]]::new()
    $slotNames = @{}
    foreach ($binding in @($artifact.reference_bindings)) {
        foreach ($field in @('name','asset_type','mixed_slot','slot_source','availability','reference_role','inherit','ignore')) { Require-Property $binding $field 'root.reference_bindings[]' | Out-Null }
        if ((Has-Property $binding 'inherit') -and -not (Is-Array $binding.inherit)) { $errors.Add('root.reference_bindings[].inherit must be an array.') }
        if ((Has-Property $binding 'ignore') -and -not (Is-Array $binding.ignore)) { $errors.Add('root.reference_bindings[].ignore must be an array.') }
        if ((Has-Property $binding 'slot_source') -and @('INPUT_LEDGER','AUTO_PLANNED') -notcontains [string]$binding.slot_source) { $errors.Add('root.reference_bindings[].slot_source is invalid.') }
        if ((Has-Property $binding 'availability') -and @('PROVIDED','REQUIRED_NOT_PROVIDED') -notcontains [string]$binding.availability) { $errors.Add('root.reference_bindings[].availability is invalid.') }
        if ((Has-Property $binding 'slot_source') -and (Has-Property $binding 'availability')) {
            if ($binding.slot_source -eq 'INPUT_LEDGER' -and $binding.availability -ne 'PROVIDED') { $errors.Add('INPUT_LEDGER bindings must have availability PROVIDED.') }
            if ($binding.slot_source -eq 'AUTO_PLANNED' -and $binding.availability -ne 'REQUIRED_NOT_PROVIDED') { $errors.Add('AUTO_PLANNED bindings must have availability REQUIRED_NOT_PROVIDED.') }
            if ($binding.slot_source -eq 'INPUT_LEDGER') {
                foreach ($assetField in @('asset_id','asset_version')) {
                    if ((-not (Has-Property $binding $assetField)) -or [string]::IsNullOrWhiteSpace([string]$binding.$assetField)) { $errors.Add("INPUT_LEDGER bindings require $assetField.") }
                }
            }
        }
        if ((Has-Property $binding 'mixed_slot') -and (([string]$binding.mixed_slot -notmatch '^[1-9][0-9]*$') -or [int]$binding.mixed_slot -lt 1)) { $errors.Add('root.reference_bindings[].mixed_slot must be a positive integer.') }
        elseif (Has-Property $binding 'mixed_slot') {
            $slot = [int]$binding.mixed_slot
            if ($slotNumbers.Contains($slot)) { $errors.Add("Duplicate mixed_slot: $slot") } else { $slotNumbers.Add($slot) }
        }
        if (Has-Property $binding 'name') {
            $nameKey = [string]$binding.name
            if ($slotNames.ContainsKey($nameKey)) { $errors.Add("Duplicate reference binding name: $nameKey") } else { $slotNames[$nameKey] = $true }
        }
    }
    $sortedSlots = @($slotNumbers | Sort-Object)
    for ($index = 0; $index -lt $sortedSlots.Count; $index++) {
        if ($sortedSlots[$index] -ne ($index + 1)) { $errors.Add('Mixed slots must be contiguous and auto-increment from 1 without gaps.'); break }
    }
    if (-not $roles.ContainsKey('ASSET_LEDGER')) {
        foreach ($binding in @($artifact.reference_bindings)) {
            if ((Has-Property $binding 'slot_source') -and $binding.slot_source -ne 'AUTO_PLANNED') { $errors.Add('Without an ASSET_LEDGER source, every reference binding must be AUTO_PLANNED.') }
        }
    }
}
[object[]]$characterBindingNames = @()
if (Has-Property $artifact 'reference_bindings') { $characterBindingNames = @($artifact.reference_bindings | Where-Object { (Has-Property $_ 'asset_type') -and $_.asset_type -eq 'CHARACTER' } | ForEach-Object { [string]$_.name } | Sort-Object -Unique) }
if (Has-Property $artifact 'action_flow') {
    Require-Array $artifact.action_flow 'timeline' 'root.action_flow' $false | Out-Null
    if (Has-Property $artifact.action_flow 'timeline') {
        $expectedStart = 0.0
        foreach ($segment in @($artifact.action_flow.timeline)) {
            foreach ($field in @('start_seconds','end_seconds','camera_start','primary_event','action_physics','performance','spatial_execution','camera_execution','light_sound_change')) { Require-Property $segment $field 'root.action_flow.timeline[]' | Out-Null }
            if ((Has-Property $segment 'spatial_execution') -and [string]::IsNullOrWhiteSpace([string]$segment.spatial_execution)) { $errors.Add('root.action_flow.timeline[].spatial_execution must explicitly state position changes or POSITIONS_UNCHANGED.') }
            if ([double]$segment.start_seconds -ne $expectedStart) { $errors.Add('Timeline contains a gap or overlap.') }
            if ([double]$segment.end_seconds -le [double]$segment.start_seconds) { $errors.Add('Timeline segment end must be after start.') }
            $expectedStart = [double]$segment.end_seconds
        }
        if ((Has-Property $artifact 'task') -and (Has-Property $artifact.task 'target_duration_seconds') -and $expectedStart -ne [double]$artifact.task.target_duration_seconds) { $errors.Add('Timeline must end at target_duration_seconds.') }
    }
}
if (Has-Property $artifact 'start_state') {
    foreach ($field in @('state_id','source_status','spatial_world','screen_projection','characters','props','camera_carryover','lighting_carryover','sound_carryover')) { Require-Property $artifact.start_state $field 'root.start_state' | Out-Null }
    foreach ($field in @('spatial_world','screen_projection','characters','props')) { if (Has-Property $artifact.start_state $field) { if (-not (Is-Array $artifact.start_state.$field)) { $errors.Add("root.start_state.$field must be an array.") } } }
    if ((Has-Property $artifact.start_state 'characters') -and (Is-Array $artifact.start_state.characters)) {
        $startCharacters = @($artifact.start_state.characters)
        foreach ($name in $characterBindingNames) {
            $matches = @($startCharacters | Where-Object { (Has-Property $_ 'name') -and $_.name -eq $name })
            if ($matches.Count -ne 1) { $errors.Add("root.start_state.characters must contain exactly one position record for visible character $name."); continue }
            $character = $matches[0]
            $context = "root.start_state.characters[$name]"
            foreach ($field in @('name','world_position','screen_position','depth_plane','body_orientation','gaze_target','nearest_anchor','support_and_weight','action_stage','hand_and_contact','performance_state','provenance')) { Require-NonEmptyString $character $field $context | Out-Null }
            if ((Has-Property $character 'screen_position') -and $character.screen_position -notin @('SCREEN_LEFT','SCREEN_CENTER','SCREEN_RIGHT')) { $errors.Add("$context.screen_position must be SCREEN_LEFT, SCREEN_CENTER, or SCREEN_RIGHT.") }
            if ((Has-Property $character 'depth_plane') -and $character.depth_plane -notin @('FOREGROUND','MIDGROUND','BACKGROUND')) { $errors.Add("$context.depth_plane must be FOREGROUND, MIDGROUND, or BACKGROUND.") }
            foreach ($field in @('world_position','screen_position','depth_plane','body_orientation','gaze_target','nearest_anchor')) { if ((Has-Property $character $field) -and [string]$character.$field -eq 'UNKNOWN') { $errors.Add("$context.$field may not be UNKNOWN in a deliverable video prompt.") } }
            if (Require-Array $character 'relative_to' $context $false) {
                foreach ($relation in @($character.relative_to)) {
                    $relationContext = "$context.relative_to[]"
                    foreach ($field in @('target','target_type','horizontal_relation','depth_relation','distance_relation')) { Require-NonEmptyString $relation $field $relationContext | Out-Null }
                    if ((Has-Property $relation 'target_type') -and $relation.target_type -notin @('CHARACTER','ANCHOR')) { $errors.Add("$relationContext.target_type must be CHARACTER or ANCHOR.") }
                    if ((Has-Property $relation 'horizontal_relation') -and $relation.horizontal_relation -notin @('LEFT_OF','RIGHT_OF','ALIGNED_HORIZONTAL','OVERLAPPING')) { $errors.Add("$relationContext.horizontal_relation is invalid.") }
                    if ((Has-Property $relation 'depth_relation') -and $relation.depth_relation -notin @('IN_FRONT_OF','BEHIND','SAME_DEPTH')) { $errors.Add("$relationContext.depth_relation is invalid.") }
                    if ((Has-Property $relation 'distance_relation') -and $relation.distance_relation -notin @('NEAR','MEDIUM','FAR')) { $errors.Add("$relationContext.distance_relation is invalid.") }
                }
                if ($characterBindingNames.Count -gt 1) {
                    foreach ($otherName in @($characterBindingNames | Where-Object { $_ -ne $name })) {
                        if (@($character.relative_to | Where-Object { (Has-Property $_ 'target_type') -and $_.target_type -eq 'CHARACTER' -and (Has-Property $_ 'target') -and $_.target -eq $otherName }).Count -ne 1) { $errors.Add("$context.relative_to must explicitly describe the relation to visible character $otherName.") }
                    }
                }
            }
        }
    }
}
if (Has-Property $artifact 'end_state') {
    foreach ($field in @('state_id','state_kind','characters','next_shot_must_inherit','forbidden_resets')) { Require-Property $artifact.end_state $field 'root.end_state' | Out-Null }
    if ((Has-Property $artifact.end_state 'state_kind') -and $artifact.end_state.state_kind -ne 'PLANNED') { $errors.Add('root.end_state.state_kind must be PLANNED.') }
    foreach ($arrayField in @('next_shot_must_inherit','forbidden_resets')) { if ((Has-Property $artifact.end_state $arrayField) -and -not (Is-Array $artifact.end_state.$arrayField)) { $errors.Add("root.end_state.$arrayField must be an array.") } }
    if ((Has-Property $artifact.end_state 'characters') -and (-not (Is-Array $artifact.end_state.characters) -or @($artifact.end_state.characters).Count -lt $characterBindingNames.Count)) { $errors.Add('root.end_state.characters must retain a position record for every visible character.') }
    elseif ((Has-Property $artifact.end_state 'characters') -and (Is-Array $artifact.end_state.characters)) {
        foreach ($name in $characterBindingNames) {
            $matches = @($artifact.end_state.characters | Where-Object { (Has-Property $_ 'name') -and $_.name -eq $name })
            if ($matches.Count -ne 1) { $errors.Add("root.end_state.characters must contain exactly one planned position record for visible character $name."); continue }
            $character = $matches[0]
            $context = "root.end_state.characters[$name]"
            foreach ($field in @('name','world_position','screen_position','depth_plane','body_orientation','gaze_target','nearest_anchor')) { Require-NonEmptyString $character $field $context | Out-Null }
            if ((Has-Property $character 'screen_position') -and $character.screen_position -notin @('SCREEN_LEFT','SCREEN_CENTER','SCREEN_RIGHT')) { $errors.Add("$context.screen_position is invalid.") }
            if ((Has-Property $character 'depth_plane') -and $character.depth_plane -notin @('FOREGROUND','MIDGROUND','BACKGROUND')) { $errors.Add("$context.depth_plane is invalid.") }
            if (Require-Array $character 'relative_to' $context $false) {
                foreach ($relation in @($character.relative_to)) { foreach ($field in @('target','target_type','horizontal_relation','depth_relation','distance_relation')) { Require-NonEmptyString $relation $field "$context.relative_to[]" | Out-Null } }
                if ($characterBindingNames.Count -gt 1) {
                    foreach ($otherName in @($characterBindingNames | Where-Object { $_ -ne $name })) {
                        if (@($character.relative_to | Where-Object { (Has-Property $_ 'target_type') -and $_.target_type -eq 'CHARACTER' -and (Has-Property $_ 'target') -and $_.target -eq $otherName }).Count -ne 1) { $errors.Add("$context.relative_to must explicitly describe the planned relation to visible character $otherName.") }
                    }
                }
            }
        }
    }
}
if (Has-Property $artifact 'continuity_checks') {
    Require-Property $artifact.continuity_checks 'sequence_index' 'root.continuity_checks' | Out-Null
    if ((Has-Property $artifact.continuity_checks 'sequence_index') -and (([string]$artifact.continuity_checks.sequence_index -notmatch '^[1-9][0-9]*$') -or [int]$artifact.continuity_checks.sequence_index -lt 1)) { $errors.Add('root.continuity_checks.sequence_index must be a positive integer.') }
    foreach ($direction in @('incoming','outgoing')) {
        if (-not (Require-Property $artifact.continuity_checks $direction 'root.continuity_checks')) { continue }
        $check = $artifact.continuity_checks.$direction
        foreach ($field in @('status','neighbor_shot_id','compared_state_ids','checked_fields','mismatches','handoff_signature','boundary_reason')) { Require-Property $check $field "root.continuity_checks.$direction" | Out-Null }
        foreach ($arrayField in @('compared_state_ids','checked_fields','mismatches')) { if ((Has-Property $check $arrayField) -and -not (Is-Array $check.$arrayField)) { $errors.Add("root.continuity_checks.$direction.$arrayField must be an array.") } }
        if ((Has-Property $check 'status') -and @('PASS','BOUNDARY') -notcontains [string]$check.status) { $errors.Add("root.continuity_checks.$direction.status must be PASS or BOUNDARY.") }
        if ((Has-Property $check 'mismatches') -and (Is-Array $check.mismatches) -and @($check.mismatches).Count -gt 0) { $errors.Add("root.continuity_checks.$direction.mismatches must be empty before delivery.") }
        if (Has-Property $check 'status') {
            if ($check.status -eq 'PASS') {
                if (-not (Has-Property $check 'neighbor_shot_id') -or [string]$check.neighbor_shot_id -notmatch '^SHOT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3}$') { $errors.Add("root.continuity_checks.$direction.neighbor_shot_id is required for PASS.") }
                if ((Has-Property $check 'compared_state_ids') -and @($check.compared_state_ids).Count -lt 2) { $errors.Add("root.continuity_checks.$direction.compared_state_ids must contain both adjacent state IDs.") }
                $requiredContinuityFields = @('CHARACTERS','PROPS','SPATIAL_WORLD','CAMERA','LIGHTING','SOUND')
                foreach ($requiredField in $requiredContinuityFields) { if ((-not (Has-Property $check 'checked_fields')) -or @($check.checked_fields) -notcontains $requiredField) { $errors.Add("root.continuity_checks.$direction.checked_fields is missing $requiredField.") } }
                if ((Has-Property $check 'boundary_reason') -and $null -ne $check.boundary_reason) { $errors.Add("root.continuity_checks.$direction.boundary_reason must be null for PASS.") }
            }
            elseif ($check.status -eq 'BOUNDARY') {
                if ((Has-Property $check 'neighbor_shot_id') -and $null -ne $check.neighbor_shot_id) { $errors.Add("root.continuity_checks.$direction.neighbor_shot_id must be null at a boundary.") }
                if ((-not (Has-Property $check 'boundary_reason')) -or [string]::IsNullOrWhiteSpace([string]$check.boundary_reason)) { $errors.Add("root.continuity_checks.$direction.boundary_reason is required at a boundary.") }
            }
        }
        if (Has-Property $check 'handoff_signature') {
            foreach ($signatureField in @('characters','props','spatial_world','camera','lighting','sound')) { Require-Property $check.handoff_signature $signatureField "root.continuity_checks.$direction.handoff_signature" | Out-Null }
        }
    }
}
if (Has-Property $artifact 'body_sections') {
    foreach ($field in @('reference_materials','approved_start_and_spatial_state','continuous_timeline','imaging','sound_continuity_stability')) { if (-not (Require-Property $artifact.body_sections $field 'root.body_sections')) { continue }; if ([string]::IsNullOrWhiteSpace([string]$artifact.body_sections.$field)) { $errors.Add("root.body_sections.$field must not be empty.") } }
    if ((Has-Property $artifact.body_sections 'approved_start_and_spatial_state') -and (Has-Property $artifact 'start_state') -and (Has-Property $artifact.start_state 'characters') -and (Is-Array $artifact.start_state.characters)) {
        $spatialText = [string]$artifact.body_sections.approved_start_and_spatial_state
        foreach ($character in @($artifact.start_state.characters)) {
            if (-not (Has-Property $character 'name') -or $characterBindingNames -notcontains [string]$character.name) { continue }
            foreach ($field in @('name','screen_position','depth_plane','nearest_anchor')) {
                if ((Has-Property $character $field) -and -not $spatialText.Contains([string]$character.$field)) { $errors.Add("root.body_sections.approved_start_and_spatial_state must explicitly mirror $($character.name).$field.") }
            }
            if ((Has-Property $character 'relative_to') -and (Is-Array $character.relative_to)) {
                foreach ($relation in @($character.relative_to)) {
                    foreach ($field in @('target','horizontal_relation','depth_relation','distance_relation')) { if ((Has-Property $relation $field) -and -not $spatialText.Contains([string]$relation.$field)) { $errors.Add("root.body_sections.approved_start_and_spatial_state must explicitly mirror $($character.name) relation $field.") } }
                }
            }
        }
    }
}
if (Has-Property $artifact 'body') {
    $body = ([string]$artifact.body -replace "`r`n","`n") -replace "`r","`n"
    $count = Get-CodePointCount $body
    if ((Has-Property $artifact 'body_char_count') -and [int]$artifact.body_char_count -ne $count) { $errors.Add("root.body_char_count must equal $count.") }
    if ((Has-Property $artifact 'task') -and $artifact.task.model -eq 'seedance-2.5' -and $count -gt 5000) { $errors.Add('Seedance 2.5 body exceeds 5000 characters.') }
    foreach ($pattern in @('@','\{\{\s*Image\b','```','(?i)END\s+FREEZE','下一步我可以')) { if ([regex]::IsMatch($body,$pattern)) { $errors.Add("Body contains forbidden pattern: $pattern") } }
    $bodyMixedSlots = @([regex]::Matches($body,'\{\{Mixed ([1-9][0-9]*)\}\}') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
    $bindingMixedSlots = if (Has-Property $artifact 'reference_bindings') { @($artifact.reference_bindings | ForEach-Object { [int]$_.mixed_slot } | Sort-Object -Unique) } else { @() }
    if ($bodyMixedSlots.Count -eq 0) { $errors.Add('Body must contain at least one {{Mixed x}} slot.') }
    if (($bodyMixedSlots -join '|') -ne ($bindingMixedSlots -join '|')) { $errors.Add('Body Mixed slots must exactly match reference_bindings.mixed_slot values.') }
    if ((Has-Property $artifact 'body_sections') -and (Has-Property $artifact.body_sections 'approved_start_and_spatial_state') -and -not $body.Contains([string]$artifact.body_sections.approved_start_and_spatial_state)) { $errors.Add('Body must include the complete approved_start_and_spatial_state section with explicit character positions.') }
}
if ((Has-Property $artifact 'unresolved_fields') -and @($artifact.unresolved_fields).Count -gt 0 -and $artifact.status -notin @('HUMAN_GATE','REPAIR')) { $errors.Add('Non-empty unresolved_fields require HUMAN_GATE or REPAIR.') }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] VideoPromptSpec validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] VideoPromptSpec structure is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
