[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# 段级 VideoPromptSpec 结构校验（schema 2.0）
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

# 图纸 §5 景别 → 焦段/光圈映射表
function Get-OpticsRange([string]$shotSize) {
    if ($shotSize -match '大全景|远景' ) { return @{ fmin = 24; fmax = 35; amin = 4.0; amax = 5.6 } }
    if ($shotSize -match '中全景|中景|全景') { return @{ fmin = 35; fmax = 50; amin = 2.8; amax = 4.0 } }
    if ($shotSize -match '中近景|近景') { return @{ fmin = 50; fmax = 70; amin = 2.0; amax = 2.8 } }
    if ($shotSize -match '极特写|特写') { return @{ fmin = 70; fmax = 85; amin = 2.0; amax = 2.8 } }
    return $null
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "VideoPromptSpec not found: $Path"; exit 2 }
try { $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

$required = @('schema_version','project_id','flow_authorization_id','requirements_ref','scene_id','segment_id','shot_id','covered_shot_ids','source_beat_ids','artifact_id','artifact_version','full_id','video_prompt_id','status','task','segment_context','source_artifacts','reference_bindings','source_lock','start_state','timeline','segment_light_color','sound_design','final_state','continuity_constraints','continuity_checks','body','body_char_count','unresolved_fields','change_log')
foreach ($field in $required) { Require-Property $artifact $field 'root' | Out-Null }

if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '2.0') { $errors.Add('root.schema_version must be 2.0 (segment-level).') }
if ((Has-Property $artifact 'flow_authorization_id') -and $artifact.flow_authorization_id -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$') { $errors.Add('root.flow_authorization_id is invalid. Production must be dispatched by S01.') }
if ((Has-Property $artifact 'requirements_ref') -and $artifact.requirements_ref -notmatch '^FLOW-AUTH-[A-Z0-9][A-Z0-9-]*-[0-9]{4}$') { $errors.Add('root.requirements_ref must reference the issuing FlowAuthorization.') }
if ((Has-Property $artifact 'scene_id') -and $artifact.scene_id -notmatch '^SCENE-E[0-9]{2,4}-S[0-9]{2,4}$') { $errors.Add('root.scene_id is invalid.') }
if ((Has-Property $artifact 'segment_id') -and $artifact.segment_id -notmatch '^SEG-E[0-9]{2,4}-[0-9]{3}$') { $errors.Add('root.segment_id must match SEG-E##-###.') }
if ((Has-Property $artifact 'segment_id') -and (Has-Property $artifact 'artifact_id')) {
    $expectedArtifactId = $artifact.segment_id -replace '^SEG-', 'VP-'
    if ($artifact.artifact_id -ne $expectedArtifactId) { $errors.Add("root.artifact_id must be $expectedArtifactId.") }
}
if ((Has-Property $artifact 'artifact_id') -and (Has-Property $artifact 'artifact_version')) {
    $expectedFullId = "$($artifact.artifact_id)-$($artifact.artifact_version)"
    if ((Has-Property $artifact 'full_id') -and $artifact.full_id -ne $expectedFullId) { $errors.Add('root.full_id is inconsistent.') }
    if ((Has-Property $artifact 'video_prompt_id') -and $artifact.video_prompt_id -ne $expectedFullId) { $errors.Add('root.video_prompt_id is inconsistent.') }
}
if ((Has-Property $artifact 'status') -and @('DRAFT','CHECKING','REPAIR','PASS','HUMAN_GATE','STALE') -notcontains $artifact.status) { $errors.Add('root.status is invalid.') }

# covered_shot_ids：2–6、同场、镜号连续、首镜等于 shot_id
if (Require-Array $artifact 'covered_shot_ids' 'root' $false) {
    $covered = @($artifact.covered_shot_ids)
    if ($covered.Count -lt 2 -or $covered.Count -gt 6) { $errors.Add('root.covered_shot_ids must contain 2 to 6 shots.') }
    $scenePart = $null
    if (Has-Property $artifact 'scene_id') { $scenePart = $artifact.scene_id -replace '^SCENE-','' }
    $shotNumbers = [System.Collections.Generic.List[int]]::new()
    foreach ($sid in $covered) {
        if ([string]$sid -notmatch '^SHOT-E[0-9]{2,4}-S[0-9]{2,4}-([0-9]{3})$') { $errors.Add("Invalid covered_shot_ids item $sid"); continue }
        $shotNumber = [int]$Matches[1]
        if ($scenePart -and [string]$sid -notmatch ('^SHOT-' + [regex]::Escape($scenePart) + '-[0-9]{3}$')) { $errors.Add("covered shot $sid does not belong to root.scene_id.") }
        $shotNumbers.Add($shotNumber)
    }
    $sorted = @($shotNumbers | Sort-Object)
    for ($i = 1; $i -lt $sorted.Count; $i++) { if ($sorted[$i] -ne $sorted[$i - 1] + 1) { $errors.Add('root.covered_shot_ids must be contiguous shot numbers.'); break } }
    if ((Has-Property $artifact 'shot_id') -and $covered.Count -gt 0 -and $artifact.shot_id -ne [string]$covered[0]) { $errors.Add('root.shot_id must equal the first covered shot.') }
}
if (Require-Array $artifact 'source_beat_ids' 'root' $false) { foreach ($beatId in @($artifact.source_beat_ids)) { if ([string]$beatId -notmatch '^BEAT-E[0-9]{2,4}-S[0-9]{2,4}-[0-9]{3,4}$') { $errors.Add("Invalid source_beat_ids item $beatId") } } }

# task
if (Has-Property $artifact 'task') {
    foreach ($field in @('task_mode','generation_task','model','model_rule_profile','product_flow','output_scope','delivery_mode','aspect_ratio','target_duration_seconds')) { Require-Property $artifact.task $field 'root.task' | Out-Null }
    if ((Has-Property $artifact.task 'output_scope') -and $artifact.task.output_scope -ne 'SEGMENT') { $errors.Add('root.task.output_scope must be SEGMENT.') }
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

# segment_context
if (Has-Property $artifact 'segment_context') {
    foreach ($field in @('scene_sub','spatial_anchors','screen_lock','scene_tone','light_base','visual_style_lock','style_pack_positive','style_pack_negative')) { Require-Property $artifact.segment_context $field 'root.segment_context' | Out-Null }
    if ((Has-Property $artifact.segment_context 'visual_style_lock') -and @('GUOMAN_3D_CG','LIVE_ACTION_REALISM') -notcontains $artifact.segment_context.visual_style_lock) { $errors.Add('root.segment_context.visual_style_lock is invalid.') }
    if ((Has-Property $artifact.segment_context 'spatial_anchors') -and (Is-Array $artifact.segment_context.spatial_anchors) -and @($artifact.segment_context.spatial_anchors).Count -lt 2) { $errors.Add('root.segment_context.spatial_anchors must contain at least 2 anchors.') }
}

# 双轨判定与来源角色
$isVisualTrack = (Has-Property $artifact 'approved_storyboard_set_full_id') -and -not [string]::IsNullOrWhiteSpace([string]$artifact.approved_storyboard_set_full_id)
$roles = @{}
foreach ($arrayField in @('source_artifacts','reference_bindings','continuity_constraints','unresolved_fields','change_log')) { Require-Array $artifact $arrayField 'root' $true | Out-Null }
if (Has-Property $artifact 'source_artifacts') {
    foreach ($source in @($artifact.source_artifacts)) {
        foreach ($field in @('role','artifact_id','artifact_version','full_id','status','stale','scope')) { Require-Property $source $field 'root.source_artifacts[]' | Out-Null }
        if (Has-Property $source 'role') { if ($roles.ContainsKey([string]$source.role)) { $errors.Add("Duplicate source role: $($source.role)") } else { $roles[[string]$source.role] = $source } }
        if ((Has-Property $source 'artifact_id') -and (Has-Property $source 'artifact_version') -and (Has-Property $source 'full_id') -and $source.full_id -ne "$($source.artifact_id)-$($source.artifact_version)") { $errors.Add("Source full_id is inconsistent for role $($source.role).") }
        if ((Has-Property $source 'stale') -and $source.stale -ne $false) { $errors.Add("Source role $($source.role) must not be stale.") }
    }
}
foreach ($requiredRole in @('STORYBOARD_TABLE','PLOT_PROGRESSION','ORIGINAL_DIALOGUE','MODEL_RULES')) { if (-not $roles.ContainsKey($requiredRole)) { $errors.Add("Missing source role: $requiredRole") } }
if ($isVisualTrack) {
    foreach ($requiredRole in @('APPROVED_STORYBOARD_SET','APPROVED_STORYBOARD','STORYBOARD_PROMPT')) { if (-not $roles.ContainsKey($requiredRole)) { $errors.Add("VISUAL_TRACK missing source role: $requiredRole") } }
    if ((Has-Property $artifact 'approved_storyboard_set_full_id') -and $artifact.approved_storyboard_set_full_id -notmatch '^APPROVED-STORYBOARD-E[0-9]{2,4}-V[0-9]+$') { $errors.Add('approved_storyboard_set_full_id is invalid.') }
    if ($roles.ContainsKey('APPROVED_STORYBOARD_SET')) { $source = $roles['APPROVED_STORYBOARD_SET']; if ($source.status -ne 'APPROVED') { $errors.Add('APPROVED_STORYBOARD_SET source must be APPROVED.') }; if ($artifact.approved_storyboard_set_full_id -ne $source.full_id) { $errors.Add('approved_storyboard_set_full_id must equal APPROVED_STORYBOARD_SET full_id.') } }
    if ($roles.ContainsKey('APPROVED_STORYBOARD')) {
        $source = $roles['APPROVED_STORYBOARD']
        if ($source.status -ne 'APPROVED') { $errors.Add('APPROVED_STORYBOARD source must be APPROVED.') }
        if ((Has-Property $artifact 'approved_image_full_id') -and $artifact.approved_image_full_id -ne $source.full_id) { $errors.Add('approved_image_full_id must equal APPROVED_STORYBOARD full_id.') }
        if (-not (Has-Property $source 'approval_record')) { $errors.Add('APPROVED_STORYBOARD approval_record is required.') }
    }
    if ($roles.ContainsKey('STORYBOARD_PROMPT') -and $roles['STORYBOARD_PROMPT'].status -ne 'PASS') { $errors.Add('STORYBOARD_PROMPT source must be PASS.') }
}
else {
    foreach ($forbiddenRole in @('APPROVED_STORYBOARD_SET','APPROVED_STORYBOARD','STORYBOARD_PROMPT')) { if ($roles.ContainsKey($forbiddenRole)) { $errors.Add("DIRECT_TRACK must not carry source role: $forbiddenRole") } }
}
if ($roles.ContainsKey('PLOT_PROGRESSION') -and $roles['PLOT_PROGRESSION'].status -ne 'PASS') { $errors.Add('PLOT_PROGRESSION source must be PASS.') }
if ($roles.ContainsKey('STORYBOARD_TABLE')) { $source = $roles['STORYBOARD_TABLE']; if ($source.status -ne 'PASS') { $errors.Add('STORYBOARD_TABLE source must be PASS.') }; if (-not (Has-Property $source 'covered_row_full_ids')) { $errors.Add('STORYBOARD_TABLE source must include covered_row_full_ids.') } }
if ($roles.ContainsKey('MODEL_RULES') -and ((-not (Has-Property $roles['MODEL_RULES'] 'validation_status')) -or $roles['MODEL_RULES'].validation_status -ne 'VERIFIED')) { $errors.Add('MODEL_RULES source must have validation_status VERIFIED.') }
if ($roles.ContainsKey('PREVIOUS_END_STATE') -and (Has-Property $artifact 'start_state') -and (Has-Property $artifact.start_state 'source_status')) {
    $prevId = [string]$roles['PREVIOUS_END_STATE'].artifact_id
    if ($prevId -match '^HANDOFF-' -and $artifact.start_state.source_status -ne 'EPISODE_HANDOFF') { $errors.Add('Cross-episode first segment must set start_state.source_status EPISODE_HANDOFF.') }
}

# ORIGINAL_DIALOGUE 与段内对白块
if ($roles.ContainsKey('ORIGINAL_DIALOGUE')) {
    $dialogueSource = $roles['ORIGINAL_DIALOGUE']
    $dialoguePolicy = if (Has-Property $dialogueSource 'dialogue_policy') { [string]$dialogueSource.dialogue_policy } else { $null }
    if (@('EXACT_SOURCE_TEXT','NO_DIALOGUE') -notcontains $dialoguePolicy) { $errors.Add('ORIGINAL_DIALOGUE.dialogue_policy must be EXACT_SOURCE_TEXT or NO_DIALOGUE.') }
    $allBlocks = @()
    if (Has-Property $artifact 'timeline') { foreach ($shot in @($artifact.timeline)) { if (Has-Property $shot 'dialogue_blocks') { $allBlocks += @($shot.dialogue_blocks) } } }
    $spokenBlocks = @($allBlocks | Where-Object { $_.block_type -ne 'NO_DIALOGUE' })
    if ($dialoguePolicy -eq 'NO_DIALOGUE' -and $spokenBlocks.Count -gt 0) { $errors.Add('NO_DIALOGUE requires all dialogue_blocks to be NO_DIALOGUE.') }
    if ($dialoguePolicy -eq 'EXACT_SOURCE_TEXT') {
        $sourceKeys = @($dialogueSource.exact_lines | ForEach-Object { "$($_.speaker)|$($_.text)|$($_.source_ref)" } | Sort-Object)
        $blockKeys = @($spokenBlocks | ForEach-Object { "$($_.speaker)|$($_.exact_text)|$($_.source_ref)" } | Sort-Object)
        if (($sourceKeys -join "`n") -cne ($blockKeys -join "`n")) { $errors.Add('timeline dialogue_blocks must exactly match ORIGINAL_DIALOGUE.exact_lines.') }
    }
}

# reference_bindings 槽位机制
if (Has-Property $artifact 'reference_bindings') {
    if (@($artifact.reference_bindings).Count -eq 0) { $errors.Add('root.reference_bindings must contain at least one Mixed slot.') }
    $slotNumbers = [System.Collections.Generic.List[int]]::new()
    foreach ($binding in @($artifact.reference_bindings)) {
        foreach ($field in @('name','asset_type','mixed_slot','slot_source','availability','reference_role','inherit','ignore')) { Require-Property $binding $field 'root.reference_bindings[]' | Out-Null }
        if ((Has-Property $binding 'slot_source') -and @('INPUT_LEDGER','AUTO_PLANNED') -notcontains [string]$binding.slot_source) { $errors.Add('root.reference_bindings[].slot_source is invalid.') }
        if ((Has-Property $binding 'availability') -and @('PROVIDED','REQUIRED_NOT_PROVIDED') -notcontains [string]$binding.availability) { $errors.Add('root.reference_bindings[].availability is invalid.') }
        if ((Has-Property $binding 'mixed_slot') -and (([string]$binding.mixed_slot -notmatch '^[1-9][0-9]*$') -or [int]$binding.mixed_slot -lt 1)) { $errors.Add('root.reference_bindings[].mixed_slot must be a positive integer.') }
        elseif (Has-Property $binding 'mixed_slot') { $slot = [int]$binding.mixed_slot; if ($slotNumbers.Contains($slot)) { $errors.Add("Duplicate mixed_slot: $slot") } else { $slotNumbers.Add($slot) } }
        if ((Has-Property $binding 'asset_type') -and $binding.asset_type -eq 'STORYBOARD' -and -not $isVisualTrack) { $errors.Add('STORYBOARD binding is only allowed in VISUAL_TRACK.') }
    }
    $sortedSlots = @($slotNumbers | Sort-Object)
    for ($index = 0; $index -lt $sortedSlots.Count; $index++) { if ($sortedSlots[$index] -ne ($index + 1)) { $errors.Add('Mixed slots must be contiguous and auto-increment from 1 without gaps.'); break } }
    if (-not $roles.ContainsKey('ASSET_LEDGER')) {
        foreach ($binding in @($artifact.reference_bindings)) { if ((Has-Property $binding 'slot_source') -and $binding.slot_source -ne 'AUTO_PLANNED') { $errors.Add('Without an ASSET_LEDGER source, every reference binding must be AUTO_PLANNED.') } }
    }
}

# start_state
if (Has-Property $artifact 'start_state') {
    foreach ($field in @('state_id','source_status','characters','props')) { Require-Property $artifact.start_state $field 'root.start_state' | Out-Null }
    if ((Has-Property $artifact.start_state 'source_status') -and @('APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM','LOCKED_UPSTREAM_PLUS_PREVIOUS_END_STATE','EPISODE_HANDOFF') -notcontains $artifact.start_state.source_status) { $errors.Add('root.start_state.source_status is invalid.') }
    if (-not $isVisualTrack -and (Has-Property $artifact.start_state 'source_status') -and $artifact.start_state.source_status -eq 'APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM') { $errors.Add('DIRECT_TRACK must not use APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM.') }
}

# timeline：首镜 0.0 起、连续、末镜=段时长、单镜 ≥1.5、焦段光圈合表、对白在镜内
if (Has-Property $artifact 'timeline') {
    $shots = @($artifact.timeline)
    if ($shots.Count -lt 2 -or $shots.Count -gt 6) { $errors.Add('root.timeline must contain 2 to 6 shot blocks.') }
    $expectedStart = 0.0
    $duration = if ((Has-Property $artifact 'task') -and (Has-Property $artifact.task 'target_duration_seconds')) { [double]$artifact.task.target_duration_seconds } else { 0 }
    $expectedSeq = 1
    foreach ($shot in $shots) {
        $shotContext = "root.timeline[$($expectedSeq - 1)]"
        foreach ($field in @('shot_seq','shot_id','row_full_id','start_s','end_s','camera','spatial_frame','action_performance','dialogue_blocks','shot_end_state')) { Require-Property $shot $field $shotContext | Out-Null }
        if ((Has-Property $shot 'shot_seq') -and [int]$shot.shot_seq -ne $expectedSeq) { $errors.Add("$shotContext.shot_seq must be $expectedSeq.") }
        if ((Has-Property $shot 'start_s') -and [double]$shot.start_s -ne $expectedStart) { $errors.Add("$shotContext timeline contains a gap or overlap.") }
        if ((Has-Property $shot 'start_s') -and (Has-Property $shot 'end_s')) {
            $shotLen = [double]$shot.end_s - [double]$shot.start_s
            if ($shotLen -le 0) { $errors.Add("$shotContext end_s must be after start_s.") }
            elseif ($shotLen -lt 1.5) { $errors.Add("$shotContext shot duration must be at least 1.5 seconds.") }
            $expectedStart = [double]$shot.end_s
        }
        if (Has-Property $shot 'camera') {
            foreach ($field in @('shot_size','viewpoint','confirmed_movement','movement_trigger','movement_landing','focal_length_mm','aperture_f','focus_target')) { Require-Property $shot.camera $field "$shotContext.camera" | Out-Null }
            if ((Has-Property $shot.camera 'confirmed_movement') -and $shot.camera.confirmed_movement -ne 'FIXED' -and (([string]::IsNullOrWhiteSpace([string]$shot.camera.movement_trigger)) -or [string]$shot.camera.movement_trigger -eq 'NONE')) { $errors.Add("$shotContext.camera non-fixed movement requires a movement_trigger.") }
            if ((Has-Property $shot.camera 'shot_size') -and (Has-Property $shot.camera 'focal_length_mm') -and (Has-Property $shot.camera 'aperture_f')) {
                $range = Get-OpticsRange ([string]$shot.camera.shot_size)
                if ($null -ne $range) {
                    if ([double]$shot.camera.focal_length_mm -lt $range.fmin -or [double]$shot.camera.focal_length_mm -gt $range.fmax) { $errors.Add("$shotContext.camera.focal_length_mm out of range for $($shot.camera.shot_size) ($($range.fmin)-$($range.fmax)mm).") }
                    if ([double]$shot.camera.aperture_f -lt $range.amin -or [double]$shot.camera.aperture_f -gt $range.amax) { $errors.Add("$shotContext.camera.aperture_f out of range for $($shot.camera.shot_size) (f/$($range.amin)-f/$($range.amax)).") }
                }
            }
        }
        if ((Has-Property $shot 'dialogue_blocks') -and (Has-Property $shot 'start_s') -and (Has-Property $shot 'end_s')) {
            foreach ($block in @($shot.dialogue_blocks)) {
                if (-not (Has-Property $block 'block_type')) { $errors.Add("$shotContext.dialogue_blocks[].block_type is required."); continue }
                if (@('LIP_SYNC','INNER_OS','NO_DIALOGUE') -notcontains $block.block_type) { $errors.Add("$shotContext.dialogue_blocks[].block_type is invalid.") }
                if ($block.block_type -eq 'NO_DIALOGUE') { continue }
                foreach ($field in @('speaker','start_s','end_s','exact_text','source_ref','voice','pause_before_keywords','pause_seconds','stress_keywords','primary_gesture','after_hold_s')) { Require-Property $block $field "$shotContext.dialogue_blocks[]" | Out-Null }
                if ((Has-Property $block 'start_s') -and (Has-Property $block 'end_s')) {
                    if ([double]$block.start_s -lt [double]$shot.start_s -or [double]$block.end_s -gt [double]$shot.end_s) { $errors.Add("$shotContext dialogue block must stay inside its shot timeline.") }
                }
            }
        }
        $expectedSeq++
    }
    if ($duration -gt 0 -and $expectedStart -ne $duration) { $errors.Add('root.timeline must end exactly at target_duration_seconds.') }
}

# final_state
if (Has-Property $artifact 'final_state') {
    foreach ($field in @('state_id','state_kind','characters','props','foreground','midground','background','camera_anchor','camera','action_stop','next_segment_must_inherit','forbidden_resets')) { Require-Property $artifact.final_state $field 'root.final_state' | Out-Null }
    if ((Has-Property $artifact.final_state 'state_kind') -and $artifact.final_state.state_kind -ne 'PLANNED') { $errors.Add('root.final_state.state_kind must be PLANNED.') }
    if (Has-Property $artifact.final_state 'camera') { foreach ($field in @('focal_length_mm','viewpoint','movement_state','final_focus')) { Require-Property $artifact.final_state.camera $field 'root.final_state.camera' | Out-Null } }
}

# continuity_checks：window=2 + incoming/outgoing + window_checks
if (Has-Property $artifact 'continuity_checks') {
    if ((Has-Property $artifact.continuity_checks 'window') -and [int]$artifact.continuity_checks.window -ne 2) { $errors.Add('root.continuity_checks.window must be 2.') }
    if (-not (Has-Property $artifact.continuity_checks 'window')) { $errors.Add('root.continuity_checks.window is required.') }
    foreach ($direction in @('incoming','outgoing')) {
        if (-not (Require-Property $artifact.continuity_checks $direction 'root.continuity_checks')) { continue }
        $check = $artifact.continuity_checks.$direction
        foreach ($field in @('status','neighbor_segment_id','compared_state_ids','checked_fields','mismatches','handoff_signature','boundary_reason')) { Require-Property $check $field "root.continuity_checks.$direction" | Out-Null }
        if ((Has-Property $check 'status') -and @('PASS','BOUNDARY') -notcontains [string]$check.status) { $errors.Add("root.continuity_checks.$direction.status must be PASS or BOUNDARY.") }
        if ((Has-Property $check 'mismatches') -and (Is-Array $check.mismatches) -and @($check.mismatches).Count -gt 0) { $errors.Add("root.continuity_checks.$direction.mismatches must be empty before delivery.") }
        if (Has-Property $check 'status') {
            if ($check.status -eq 'PASS') {
                if (-not (Has-Property $check 'neighbor_segment_id') -or [string]$check.neighbor_segment_id -notmatch '^SEG-E[0-9]{2,4}-[0-9]{3}$') { $errors.Add("root.continuity_checks.$direction.neighbor_segment_id is required for PASS.") }
                if ((Has-Property $check 'compared_state_ids') -and @($check.compared_state_ids).Count -lt 2) { $errors.Add("root.continuity_checks.$direction.compared_state_ids must contain both adjacent state IDs.") }
            }
            elseif ($check.status -eq 'BOUNDARY') {
                if ((Has-Property $check 'neighbor_segment_id') -and $null -ne $check.neighbor_segment_id) { $errors.Add("root.continuity_checks.$direction.neighbor_segment_id must be null at a boundary.") }
                if ((-not (Has-Property $check 'boundary_reason')) -or [string]::IsNullOrWhiteSpace([string]$check.boundary_reason)) { $errors.Add("root.continuity_checks.$direction.boundary_reason is required at a boundary.") }
            }
        }
    }
    if (Require-Array $artifact.continuity_checks 'window_checks' 'root.continuity_checks' $true) {
        foreach ($wc in @($artifact.continuity_checks.window_checks)) {
            foreach ($field in @('neighbor_segment_id','distance','checked_fields','mismatches')) { Require-Property $wc $field 'root.continuity_checks.window_checks[]' | Out-Null }
            if ((Has-Property $wc 'distance') -and [int]$wc.distance -ne 2) { $errors.Add('root.continuity_checks.window_checks[].distance must be 2.') }
            if ((Has-Property $wc 'mismatches') -and (Is-Array $wc.mismatches) -and @($wc.mismatches).Count -gt 0) { $errors.Add('root.continuity_checks.window_checks[].mismatches must be empty before delivery.') }
        }
    }
}

# body：渲染来源、字数、槽位、禁词、十五节标题
if (Has-Property $artifact 'body') {
    if ((Has-Property $artifact 'body_rendered_by') -and $artifact.body_rendered_by -ne 'render_segment_prompt.ps1') { $errors.Add('root.body must be rendered by render_segment_prompt.ps1.') }
    if (-not (Has-Property $artifact 'body_rendered_by')) { $errors.Add('root.body_rendered_by is required; hand-written body is forbidden.') }
    $body = ([string]$artifact.body -replace "`r`n","`n") -replace "`r","`n"
    $count = Get-CodePointCount $body
    if ((Has-Property $artifact 'body_char_count') -and [int]$artifact.body_char_count -ne $count) { $errors.Add("root.body_char_count must equal $count.") }
    if ((Has-Property $artifact 'task') -and $artifact.task.model -eq 'seedance-2.5' -and $count -gt 5000) { $errors.Add('Seedance 2.5 body exceeds 5000 characters.') }
    foreach ($pattern in @('@','\{\{\s*Image\b','```','(?i)END\s+FREEZE','下一步我可以')) { if ([regex]::IsMatch($body,$pattern)) { $errors.Add("Body contains forbidden pattern: $pattern") } }
    $bodyMixedSlots = @([regex]::Matches($body,'\{\{Mixed ([1-9][0-9]*)\}\}') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
    $bindingMixedSlots = if (Has-Property $artifact 'reference_bindings') { @($artifact.reference_bindings | ForEach-Object { [int]$_.mixed_slot } | Sort-Object -Unique) } else { @() }
    if ($bodyMixedSlots.Count -eq 0) { $errors.Add('Body must contain at least one {{Mixed x}} slot.') }
    if (($bodyMixedSlots -join '|') -ne ($bindingMixedSlots -join '|')) { $errors.Add('Body Mixed slots must exactly match reference_bindings.mixed_slot values.') }
    $sectionHeaders = @('一、参考素材说明','二、参考素材使用规则','三、统一视觉与摄影基准','四、场景空间锚点','五、承接上一段15秒','六、镜头时间轴','七、时间轴内对白','八、镜尾状态','九、后续镜头重复结构','十、全段光线与色彩','十一、全段摄影规格','十二、声音设计','十三、全段连续性约束','十四、负面约束','十五、本段15秒最终承接状态')
    $lastIndex = -1
    foreach ($header in $sectionHeaders) {
        $idx = $body.IndexOf($header)
        if ($idx -lt 0) { $errors.Add("Body is missing section header: $header") }
        elseif ($idx -le $lastIndex) { $errors.Add("Body section header out of order: $header") }
        else { $lastIndex = $idx }
    }
}
if ((Has-Property $artifact 'unresolved_fields') -and @($artifact.unresolved_fields).Count -gt 0 -and $artifact.status -notin @('HUMAN_GATE','REPAIR')) { $errors.Add('Non-empty unresolved_fields require HUMAN_GATE or REPAIR.') }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] VideoPromptSpec validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] VideoPromptSpec (segment 2.0) structure is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
