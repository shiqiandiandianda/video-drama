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
function Get-CodePointCount([string]$Text) { $count = 0; for ($i = 0; $i -lt $Text.Length; $i++) { if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])) { $i++ }; $count++ }; return $count }
function Get-SortedArrayKey($Value) { if (-not (Is-Array $Value)) { return $null }; return (@($Value) | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '|' }

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "VideoPromptSpec not found: $Path"; exit 2 }
try { $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

$required = @('schema_version','project_id','scene_id','shot_id','source_beat_ids','artifact_id','artifact_version','full_id','video_prompt_id','status','task','approved_storyboard_set_full_id','approved_image_full_id','source_artifacts','reference_bindings','source_lock','start_state','action_flow','dialogue_audio','camera','lighting_color_material','sound','end_state','continuity_constraints','body_sections','body','body_char_count','unresolved_fields','change_log')
foreach ($field in $required) { Require-Property $artifact $field 'root' | Out-Null }

if ((Has-Property $artifact 'schema_version') -and $artifact.schema_version -ne '1.0') { $errors.Add('root.schema_version must be 1.0.') }
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
foreach ($requiredRole in @('APPROVED_STORYBOARD_SET','APPROVED_STORYBOARD','STORYBOARD_PROMPT','PLOT_PROGRESSION','STORYBOARD_TABLE','ORIGINAL_DIALOGUE','ASSET_LEDGER','MODEL_RULES','PREVIOUS_END_STATE')) { if (-not $roles.ContainsKey($requiredRole)) { $errors.Add("Missing source role: $requiredRole") } }
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

if (Has-Property $artifact 'task') { foreach ($field in @('task_mode','generation_task','model','model_rule_profile','product_flow','output_scope','delivery_mode','aspect_ratio','target_duration_seconds')) { Require-Property $artifact.task $field 'root.task' | Out-Null }; if ((Has-Property $artifact.task 'output_scope') -and $artifact.task.output_scope -ne 'SINGLE_SHOT') { $errors.Add('root.task.output_scope must be SINGLE_SHOT.') } }
if (Has-Property $artifact 'action_flow') {
    Require-Array $artifact.action_flow 'timeline' 'root.action_flow' $false | Out-Null
    if (Has-Property $artifact.action_flow 'timeline') {
        $expectedStart = 0.0
        foreach ($segment in @($artifact.action_flow.timeline)) {
            foreach ($field in @('start_seconds','end_seconds','camera_start','primary_event','action_physics','performance','camera_execution','light_sound_change')) { Require-Property $segment $field 'root.action_flow.timeline[]' | Out-Null }
            if ([double]$segment.start_seconds -ne $expectedStart) { $errors.Add('Timeline contains a gap or overlap.') }
            if ([double]$segment.end_seconds -le [double]$segment.start_seconds) { $errors.Add('Timeline segment end must be after start.') }
            $expectedStart = [double]$segment.end_seconds
        }
        if ((Has-Property $artifact 'task') -and (Has-Property $artifact.task 'target_duration_seconds') -and $expectedStart -ne [double]$artifact.task.target_duration_seconds) { $errors.Add('Timeline must end at target_duration_seconds.') }
    }
}
if ((Has-Property $artifact 'end_state') -and ((-not (Has-Property $artifact.end_state 'state_kind')) -or $artifact.end_state.state_kind -ne 'PLANNED')) { $errors.Add('root.end_state.state_kind must be PLANNED.') }
if (Has-Property $artifact 'body_sections') { foreach ($field in @('reference_materials','approved_start_and_spatial_state','continuous_timeline','imaging','sound_continuity_stability')) { if (-not (Require-Property $artifact.body_sections $field 'root.body_sections')) { continue }; if ([string]::IsNullOrWhiteSpace([string]$artifact.body_sections.$field)) { $errors.Add("root.body_sections.$field must not be empty.") } } }
if (Has-Property $artifact 'body') {
    $body = ([string]$artifact.body -replace "`r`n","`n") -replace "`r","`n"
    $count = Get-CodePointCount $body
    if ((Has-Property $artifact 'body_char_count') -and [int]$artifact.body_char_count -ne $count) { $errors.Add("root.body_char_count must equal $count.") }
    if ((Has-Property $artifact 'task') -and $artifact.task.model -eq 'seedance-2.5' -and $count -gt 5000) { $errors.Add('Seedance 2.5 body exceeds 5000 characters.') }
    foreach ($pattern in @('@','\{\{\s*Image\b','```','(?i)END\s+FREEZE','下一步我可以')) { if ([regex]::IsMatch($body,$pattern)) { $errors.Add("Body contains forbidden pattern: $pattern") } }
}
if ((Has-Property $artifact 'unresolved_fields') -and @($artifact.unresolved_fields).Count -gt 0 -and $artifact.status -notin @('HUMAN_GATE','REPAIR')) { $errors.Add('Non-empty unresolved_fields require HUMAN_GATE or REPAIR.') }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] VideoPromptSpec validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] VideoPromptSpec structure is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
