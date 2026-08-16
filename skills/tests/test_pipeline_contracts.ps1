[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$skillsRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('video-drama-pipeline-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Json($Value, [string]$Path) { [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 50), $script:utf8NoBom) }
function Invoke-Validator([string]$Name, [string]$ScriptPath, [string[]]$Arguments, [int]$ExpectedExitCode = 0) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Host $line }
    if ($exitCode -ne $ExpectedExitCode) { $script:failures.Add("$Name expected exit $ExpectedExitCode but received $exitCode.") }
    else { Write-Host "[TEST PASS] $Name" -ForegroundColor Green }
}
function New-FlowIndexArtifact([string]$Type, [string]$Id, [string]$Version, [string]$Status, [string]$AuthorizationId, $SceneId = $null, $ShotId = $null) {
    return [ordered]@{
        project_id='PRJ-001'; artifact_type=$Type; artifact_id=$Id; artifact_version=$Version; full_id=($Id + '-' + $Version)
        flow_authorization_id=$AuthorizationId; status=$Status; current=$true; stale=$false; scene_id=$SceneId; shot_id=$ShotId
        source_beat_ids=@(); source_full_ids=@(); resource=('outputs/' + $Id.ToLowerInvariant() + '.json')
    }
}
function New-QaFlowControl([string]$Mode, $Artifact) {
    $stageByMode = @{ PLOT='P1'; STORYBOARD_TABLE='P2'; STORYBOARD_PROMPT='P3'; STORYBOARD_IMAGE='P4'; VIDEO_PROMPT='P6' }
    $typeByMode = @{ PLOT='PLOT'; STORYBOARD_TABLE='STORYBOARD_TABLE'; STORYBOARD_PROMPT='STORYBOARD_PROMPT'; STORYBOARD_IMAGE='STORYBOARD_IMAGE'; VIDEO_PROMPT='VIDEO_PROMPT' }
    $producerByMode = @{ PLOT='script-plot-progression'; STORYBOARD_TABLE='storyboard-table-director'; STORYBOARD_PROMPT='storyboard-image-prompt-director'; STORYBOARD_IMAGE='storyboard-image-generation'; VIDEO_PROMPT='video-prompt-director' }
    $stage = $stageByMode[$Mode]
    $authorizationId = [string]$Artifact.flow_authorization_id
    $sceneId = if ($Artifact.Contains('scene_id')) { $Artifact.scene_id } else { $null }
    $shotId = if ($Artifact.Contains('shot_id')) { $Artifact.shot_id } else { $null }
    [object[]]$sceneScope = @()
    [object[]]$shotScope = @()
    if ($null -ne $sceneId) { $sceneScope = @($sceneId) }
    if ($null -ne $shotId) { $shotScope = @($shotId) }
    $scope = [ordered]@{ episode_ids=@('E01'); scene_ids=$sceneScope; shot_ids=$shotScope; beat_ids=@() }
    $current = New-FlowIndexArtifact $typeByMode[$Mode] $Artifact.artifact_id $Artifact.artifact_version 'DRAFT' $authorizationId $sceneId $shotId
    if ($Artifact.Contains('source_beat_ids')) { $current.source_beat_ids = @($Artifact.source_beat_ids) }
    $index = @($current)
    if ($Mode -eq 'STORYBOARD_TABLE') { $index += New-FlowIndexArtifact 'PLOT' 'PLOT-E01' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' }
    if ($Mode -eq 'STORYBOARD_PROMPT') { $index += New-FlowIndexArtifact 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' }
    if ($Mode -eq 'STORYBOARD_IMAGE') { $index += New-FlowIndexArtifact 'STORYBOARD_PROMPT' 'SP-E01-S01-001' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' 'SHOT-E01-S01-001' }
    if ($Mode -eq 'VIDEO_PROMPT') {
        $image = New-FlowIndexArtifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-001' 'V2' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
        $set = New-FlowIndexArtifact 'APPROVED_STORYBOARD_SET' 'APPROVED-STORYBOARD-E01' 'V1' 'APPROVED' 'FLOW-AUTH-PRJ001-HISTORY-0001'
        $set.Add('approved_items', @([ordered]@{ shot_id='SHOT-E01-S01-001'; image_full_id='IMG-E01-S01-001-V2'; status='APPROVED'; stale=$false }))
        $index += @($image,$set)
    }
    $flowState = [ordered]@{
        schema_version='1.0'
        project_manifest=[ordered]@{ project_id='PRJ-001'; manifest_version='V1'; status='ACTIVE'; episode_ids=@('E01'); required_scene_ids=@('SCENE-E01-S01'); source_materials=@([ordered]@{ source_id='SCRIPT-E01'; source_type='SCRIPT'; version='V1'; status='CURRENT'; locator='file/episode-01.txt' }); constraints=[ordered]@{} }
        stage_state=[ordered]@{ project_id='PRJ-001'; current_stage=$stage; state='WAITING_QA'; current_artifact_full_id=$Artifact.full_id; last_qa_verdict=$null; blocking_reasons=@(); next_action='CALL_QA' }
        decision_ledger=@(); artifact_index=$index
        flow_authorizations=@([ordered]@{ authorization_id=$authorizationId; project_id='PRJ-001'; stage=$stage; action='CALL_PRODUCER'; target=$producerByMode[$Mode]; status='CONSUMED'; scope=$scope; artifact_full_id=$Artifact.full_id; ticket_id=$null; issued_at='2026-08-16T00:00:00+08:00' })
        pending_repair_tickets=@(); run_log=@()
        dispatch=[ordered]@{ action='CALL_QA'; target='short-drama-unified-qa'; qa_mode=$Mode; artifact_full_id=$Artifact.full_id; ticket_id=$null; authorization_id=$authorizationId; scope=$scope; reason='QA regression test' }
        delivery=@()
    }
    return [ordered]@{ production_authorization_id=$authorizationId; flow_state=$flowState }
}
function Test-QaRequest([string]$Name, [string]$Mode, $Artifact, [array]$ApprovedUpstream) {
    $request = [ordered]@{ qa_mode=$Mode; artifact=$Artifact; approved_upstream=$ApprovedUpstream; project_constraints=[ordered]@{}; change_set=$null; previous_version=$null; flow_control=(New-QaFlowControl $Mode $Artifact) }
    $requestPath = Join-Path $script:tempRoot ($Mode.ToLowerInvariant() + '-qa-request.json')
    Write-Json $request $requestPath
    Invoke-Validator $Name (Join-Path $script:skillsRoot '_shared\validate_qa_request.ps1') @('-Path',$requestPath)
}

try {
    $emptyState = [ordered]@{ characters=[ordered]@{}; props=[ordered]@{}; environment=[ordered]@{}; knowledge=[ordered]@{} }
    $plot = [ordered]@{
        schema_version='1.0'; project_id='PRJ-001'; flow_authorization_id='FLOW-AUTH-PRJ001-P1-0001'; artifact_id='PLOT-E01'; artifact_version='V1'; full_id='PLOT-E01-V1'; source_artifact_id='SCRIPT-E01'; source_version='V1'; source_full_id='SCRIPT-E01-V1'
        source_artifacts=@([ordered]@{ source_id='SCRIPT-E01'; source_type='SCRIPT'; version='V1'; scope='E01'; locator_type='LINE'; path='episode-01.txt' }); status='PASS'; scope=[ordered]@{ episode_id='E01'; scene_ids=@('SCENE-E01-S01') }
        coverage_summary=[ordered]@{ total_story_events=1; covered_story_events=1; total_dialogue_lines=0; preserved_dialogue_lines=0 }
        source_coverage=@([ordered]@{ coverage_id='COV-E01-0001'; source_range='SCRIPT-E01-V1:L1'; content_type='EVENT'; source_text='DAUGHTER places the letter in front of FATHER.'; covered_by=@('BEAT-E01-S01-001'); coverage='FULL'; note=$null })
        decision_overrides=@(); conflicts=@(); unknowns=@(); scenes=@([ordered]@{
            scene_id='SCENE-E01-S01'; scene_number=1; source_ranges=@('SCRIPT-E01-V1:L1'); heading=[ordered]@{ time='DAY'; interior_exterior='INT'; location='DINING_ROOM' }; characters_present=@('DAUGHTER','FATHER'); scene_start_state=$emptyState
            beats=@([ordered]@{ beat_id='BEAT-E01-S01-001'; source_ranges=@('SCRIPT-E01-V1:L1'); source_status='CONFIRMED'; start_state=$emptyState; trigger=[ordered]@{ event='DAUGHTER reveals the result'; source_range='SCRIPT-E01-V1:L1' }; actions=@([ordered]@{ order=1; actor='DAUGHTER'; action='places the letter in front of FATHER'; target='FATHER'; source_range='SCRIPT-E01-V1:L1' }); reactions=@(); dialogue=@(); emotion_change=@(); end_state=$emptyState; continuity=[ordered]@{ must_carry_forward=@('LETTER_IN_FRONT_OF_FATHER'); open_actions=@() }; decision_overrides=@(); notes=@() })
            scene_end_state=$emptyState
        }); impact_scope=[ordered]@{ changed_beats=@(); stale_downstream=@() }
    }
    $plotPath = Join-Path $tempRoot 'plot.json'; Write-Json $plot $plotPath
    Invoke-Validator 'S02 canonical no-dialogue PlotProgressionSpec passes' (Join-Path $skillsRoot 'script-plot-progression\scripts\validate_plot_progression.ps1') @('-Path',$plotPath)
    Test-QaRequest 'S02 QA request envelope passes' 'PLOT' $plot @([ordered]@{ full_id='SCRIPT-E01-V1'; status='APPROVED' })

    $storyboard = [ordered]@{
        schema_version = '1.0'; artifact_type = 'StoryboardTable'; project_id = 'PRJ-001'; flow_authorization_id='FLOW-AUTH-PRJ001-P2-0001'
        scene_id = 'SCENE-E01-S01'; source_beat_ids = @('BEAT-E01-S01-001')
        artifact_id = 'STORYBOARD-E01-S01'; artifact_version = 'V1'; full_id = 'STORYBOARD-E01-S01-V1'
        source_artifact_id = 'PLOT-E01'; source_version = 'V1'; source_full_id = 'PLOT-E01-V1'; source_status = 'PASS'; source_stale = $false
        status = 'PASS'; aspect_ratio = '9:16'; visual_style = 'LIVE_ACTION'; realism = 'HIGH'
        shot_map = @([ordered]@{
            project_id = 'PRJ-001'; scene_id = 'SCENE-E01-S01'; shot_no = '01'; shot_id = 'SHOT-E01-S01-001'
            artifact_id = 'SHOT-E01-S01-001'; artifact_version = 'V1'; full_id = 'SHOT-E01-S01-001-V1'; storyboard_row_version = 'V1'
            source_artifact_id = 'PLOT-E01'; source_version = 'V1'; source_full_id = 'PLOT-E01-V1'; source_status = 'PASS'; source_stale = $false; source_beat_ids = @('BEAT-E01-S01-001'); status = 'PASS'
            columns = [ordered]@{ scene = 'DAY_INT_DINING_ROOM'; shot_no = '01'; shot_size = 'MEDIUM'; camera_position = 'EYE_LEVEL_FRONT'; camera_movement = 'FIXED'; visual_description = 'DAUGHTER places the letter in front of FATHER.'; duration_s = 3; performance = 'DAUGHTER keeps a fingertip on the paper while FATHER looks down.'; director_note = 'Keep the legal side of the interaction axis.' }
        })
    }
    $storyboardPath = Join-Path $tempRoot 'storyboard.json'; Write-Json $storyboard $storyboardPath
    Invoke-Validator 'S03 canonical StoryboardTable passes' (Join-Path $skillsRoot 'storyboard-table-director\scripts\validate_storyboard_artifact.ps1') @('-Path',$storyboardPath)
    Test-QaRequest 'S03 QA request envelope passes' 'STORYBOARD_TABLE' $storyboard @($plot)

    $storyboardPrompt = [ordered]@{
        schema_version = '1.0'; project_id = 'PRJ-001'; flow_authorization_id='FLOW-AUTH-PRJ001-P3-0001'; scene_id = 'SCENE-E01-S01'; shot_id = 'SHOT-E01-S01-001'; source_beat_ids = @('BEAT-E01-S01-001')
        artifact_id = 'SP-E01-S01-001'; artifact_version = 'V1'; full_id = 'SP-E01-S01-001-V1'; prompt_id = 'SP-E01-S01-001-V1'
        source_artifact_id = 'STORYBOARD-E01-S01'; source_version = 'V1'; source_full_id = 'STORYBOARD-E01-S01-V1'; source_status = 'PASS'; source_stale = $false; storyboard_row_version = 'V1'; source_row_full_id = 'SHOT-E01-S01-001-V1'; source_row_status = 'PASS'; source_row_stale = $false; status = 'PASS'
        frame_role = 'STORYBOARD_KEYFRAME'; selected_moment = [ordered]@{ phase = 'FIRST_CONTACT'; source_evidence = 'DAUGHTER places the letter in front of FATHER.'; frozen_state = 'DAUGHTER still touches the letter.'; selection_reason = 'The action result and reaction are both visible.' }
        positive_prompt = 'Single vertical live-action storyboard keyframe in a dining room, medium eye-level front view.'
        asset_requirements = [ordered]@{ character_count=2; scene_count=1; prop_count=1 }; asset_bindings = [ordered]@{
            characters = @([ordered]@{ name='DAUGHTER'; asset_id='CHAR-DAUGHTER-01'; asset_version='V1'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') },[ordered]@{ name='FATHER'; asset_id='CHAR-FATHER-01'; asset_version='V1'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') })
            scene = @([ordered]@{ name='DINING_ROOM'; asset_id='SCENE-DINING-01'; asset_version='V1'; reference_role='SPACE_STYLE'; inherit=@('LAYOUT','ANCHORS'); ignore=@('REFERENCE_PEOPLE') })
            props = @([ordered]@{ name='LETTER'; asset_id='PROP-LETTER-01'; asset_version='V1'; reference_role='PROP_APPEARANCE'; inherit=@('SIZE','COLOR'); ignore=@('UNCONFIRMED_TEXT') })
        }; camera = [ordered]@{ shot_size = 'MEDIUM' }; spatial_continuity = [ordered]@{}; prop_states = @([ordered]@{ prop='LETTER'; owner='DAUGHTER'; contact='RIGHT_HAND'; position='TABLE'; orientation='TOWARD_FATHER'; state='INTACT' })
        text_policy = [ordered]@{ mode = 'FORBIDDEN'; exact_source_text = $null }; locked_fields = @('STORY_MOMENT','SHOT_SIZE','VIEWPOINT','POSITIONS','CORE_PROP','ASPECT_RATIO')
        negative_constraints = @('NO_EXTRA_CHARACTERS'); aspect_ratio = '9:16'; unresolved_fields = @(); change_log = @()
    }
    $storyboardPromptPath = Join-Path $tempRoot 'storyboard-prompt.json'; Write-Json $storyboardPrompt $storyboardPromptPath
    Invoke-Validator 'S04 preserves source_beat_ids and passes' (Join-Path $skillsRoot 'storyboard-image-prompt-director\scripts\validate_storyboard_prompt.ps1') @('-Path',$storyboardPromptPath)
    Test-QaRequest 'S04 QA request envelope passes' 'STORYBOARD_PROMPT' $storyboardPrompt @($storyboard,$storyboard.shot_map[0])

    $approved = [ordered]@{
        schema_version = '1.0'; project_id = 'PRJ-001'; artifact_id = 'APPROVED-STORYBOARD-E01'; artifact_version = 'V1'; full_id = 'APPROVED-STORYBOARD-E01-V1'; status = 'APPROVED'
        items = @([ordered]@{ scene_id = 'SCENE-E01-S01'; shot_id = 'SHOT-E01-S01-001'; source_beat_ids = @('BEAT-E01-S01-001'); artifact_id = 'IMG-E01-S01-001'; artifact_version = 'V2'; full_id = 'IMG-E01-S01-001-V2'; source_prompt_full_id = 'SP-E01-S01-001-V1'; status = 'APPROVED'; stale = $false; resource = 'storyboard-001.png'; approved_by = 'Human Director'; approved_at = '2026-08-14T00:00:00+08:00'; locked_fields = @('COMPOSITION','SHOT_SIZE','POSITIONS','CORE_PROP','STORY_MOMENT'); allowed_changes = @('NATURAL_ACTION_DETAIL') })
    }
    $approvedPath = Join-Path $tempRoot 'approved-storyboard.json'; Write-Json $approved $approvedPath
    Invoke-Validator 'ApprovedStoryboardSet bridge passes' (Join-Path $skillsRoot '_shared\validate_approved_storyboard.ps1') @('-Path',$approvedPath,'-ShotId','SHOT-E01-S01-001')

    $sections = [ordered]@{ reference_materials = 'Reference DAUGHTER{{Mixed 1}}, FATHER{{Mixed 2}}, DINING_ROOM{{Mixed 3}}, and LETTER{{Mixed 4}}.'; approved_start_and_spatial_state = 'At 0 seconds, DAUGHTER is SCREEN_LEFT in MIDGROUND beside TABLE_EDGE, LEFT_OF FATHER at SAME_DEPTH and NEAR distance; FATHER is SCREEN_RIGHT in MIDGROUND beside CHAIR, RIGHT_OF DAUGHTER at SAME_DEPTH and NEAR distance. Both face each other across the table.'; continuous_timeline = '0-3 seconds: DAUGHTER places the letter down without changing the established relation. 3-9 seconds: FATHER looks at it while both remain in position. 9-15 seconds: both settle into the resulting pause.'; imaging = 'Medium eye-level fixed camera, 50mm at f/4.'; sound_continuity_stability = 'Keep room tone and paper contact sound. No BGM.' }
    $body = @($sections.reference_materials,$sections.approved_start_and_spatial_state,$sections.continuous_timeline,$sections.imaging,$sections.sound_continuity_stability) -join "`n`n"
    $boundarySignature = [ordered]@{ characters=@(); props=@(); spatial_world=@(); camera='FIXED_MEDIUM'; lighting='UNCHANGED'; sound='ROOM_TONE' }
    $videoPrompt = [ordered]@{
        schema_version = '1.0'; project_id = 'PRJ-001'; flow_authorization_id='FLOW-AUTH-PRJ001-P6-0001'; scene_id = 'SCENE-E01-S01'; shot_id = 'SHOT-E01-S01-001'; source_beat_ids = @('BEAT-E01-S01-001')
        artifact_id = 'VP-E01-S01-001'; artifact_version = 'V1'; full_id = 'VP-E01-S01-001-V1'; video_prompt_id = 'VP-E01-S01-001-V1'; status = 'DRAFT'
        task = [ordered]@{ task_mode = 'CREATE'; generation_task = 'MULTIMODAL_REFERENCE'; model = 'seedance-2.0'; model_rule_profile = 'SD20-V3.4'; product_flow = 'OMNI_REFERENCE'; output_scope = 'SINGLE_SHOT'; delivery_mode = 'PROMPT_ONLY'; aspect_ratio = '9:16'; target_duration_seconds = 15 }
        approved_storyboard_set_full_id = 'APPROVED-STORYBOARD-E01-V1'; approved_image_full_id = 'IMG-E01-S01-001-V2'
        source_artifacts = @(
            [ordered]@{ role='APPROVED_STORYBOARD_SET'; artifact_id='APPROVED-STORYBOARD-E01'; artifact_version='V1'; full_id='APPROVED-STORYBOARD-E01-V1'; status='APPROVED'; stale=$false; scope='E01' },
            [ordered]@{ role='APPROVED_STORYBOARD'; artifact_id='IMG-E01-S01-001'; artifact_version='V2'; full_id='IMG-E01-S01-001-V2'; status='APPROVED'; stale=$false; scope='SHOT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001'); resource='storyboard-001.png'; source_prompt_full_id='SP-E01-S01-001-V1'; approval_record=[ordered]@{ approved_by='Human Director'; approved_at='2026-08-14T00:00:00+08:00'; locked_fields=@('COMPOSITION','SHOT_SIZE','POSITIONS','CORE_PROP','STORY_MOMENT'); allowed_changes=@('NATURAL_ACTION_DETAIL') } },
            [ordered]@{ role='STORYBOARD_PROMPT'; artifact_id='SP-E01-S01-001'; artifact_version='V1'; full_id='SP-E01-S01-001-V1'; status='PASS'; stale=$false; scope='SHOT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001') },
            [ordered]@{ role='PLOT_PROGRESSION'; artifact_id='PLOT-E01'; artifact_version='V1'; full_id='PLOT-E01-V1'; status='PASS'; stale=$false; scope='BEAT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001') },
            [ordered]@{ role='STORYBOARD_TABLE'; artifact_id='STORYBOARD-E01-S01'; artifact_version='V1'; full_id='STORYBOARD-E01-S01-V1'; status='PASS'; stale=$false; scope='SHOT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001'); row_full_id='SHOT-E01-S01-001-V1'; storyboard_row_version='V1' },
            [ordered]@{ role='ORIGINAL_DIALOGUE'; artifact_id='SCRIPT-E01'; artifact_version='V1'; full_id='SCRIPT-E01-V1'; status='APPROVED'; stale=$false; scope='SCRIPT-E01-V1:L1'; dialogue_policy='NO_DIALOGUE'; exact_lines=@() },
            [ordered]@{ role='ASSET_LEDGER'; artifact_id='ASSET-LEDGER-PRJ001'; artifact_version='V1'; full_id='ASSET-LEDGER-PRJ001-V1'; status='APPROVED'; stale=$false; scope='SHOT-E01-S01-001' },
            [ordered]@{ role='MODEL_RULES'; artifact_id='SD20-RULES'; artifact_version='V3.4'; full_id='SD20-RULES-V3.4'; status='PASS'; stale=$false; scope='seedance-2.0'; validation_status='VERIFIED' },
            [ordered]@{ role='PREVIOUS_END_STATE'; artifact_id='PE-E01-S01-000'; artifact_version='V1'; full_id='PE-E01-S01-000-V1'; status='PASS'; stale=$false; scope='SHOT-E01-S01-000' }
        )
        reference_bindings = @(
            [ordered]@{ name='DAUGHTER'; asset_type='CHARACTER'; asset_id='CHAR-DAUGHTER-01'; asset_version='V1'; mixed_slot=1; slot_source='INPUT_LEDGER'; availability='PROVIDED'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') },
            [ordered]@{ name='FATHER'; asset_type='CHARACTER'; asset_id='CHAR-FATHER-01'; asset_version='V1'; mixed_slot=2; slot_source='INPUT_LEDGER'; availability='PROVIDED'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') },
            [ordered]@{ name='DINING_ROOM'; asset_type='SCENE'; asset_id=$null; asset_version=$null; mixed_slot=3; slot_source='AUTO_PLANNED'; availability='REQUIRED_NOT_PROVIDED'; reference_role='SPACE_STYLE'; inherit=@('LAYOUT'); ignore=@('REFERENCE_PEOPLE') },
            [ordered]@{ name='LETTER'; asset_type='PROP'; asset_id=$null; asset_version=$null; mixed_slot=4; slot_source='AUTO_PLANNED'; availability='REQUIRED_NOT_PROVIDED'; reference_role='PROP_APPEARANCE'; inherit=@('SIZE','COLOR'); ignore=@('UNCONFIRMED_TEXT') }
        ); source_lock = [ordered]@{ locked_fields=@('/shot_id'); allowed_changes=@(); change_set_id=$null; repair_ticket_id=$null }
        start_state = [ordered]@{
            state_id='SS-E01-S01-001-V1'; source_status='APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM'
            spatial_world=@('DAUGHTER_AT_LEFT_TABLE_EDGE','FATHER_AT_RIGHT_CHAIR'); screen_projection=@('DAUGHTER_SCREEN_LEFT_MIDGROUND','FATHER_SCREEN_RIGHT_MIDGROUND')
            characters=@(
                [ordered]@{ name='DAUGHTER'; world_position='LEFT_SIDE_OF_DINING_TABLE'; screen_position='SCREEN_LEFT'; depth_plane='MIDGROUND'; body_orientation='FACING_FATHER_ACROSS_TABLE'; gaze_target='FATHER'; nearest_anchor='TABLE_EDGE'; relative_to=@([ordered]@{ target='FATHER'; target_type='CHARACTER'; horizontal_relation='LEFT_OF'; depth_relation='SAME_DEPTH'; distance_relation='NEAR' }); support_and_weight='SEATED_BALANCED'; action_stage='PREPARATION'; hand_and_contact='RIGHT_HAND_ON_LETTER'; performance_state='CONTROLLED_BREATH'; provenance='APPROVED_IMAGE_VISIBLE' },
                [ordered]@{ name='FATHER'; world_position='RIGHT_SIDE_OF_DINING_TABLE'; screen_position='SCREEN_RIGHT'; depth_plane='MIDGROUND'; body_orientation='FACING_DAUGHTER_ACROSS_TABLE'; gaze_target='LETTER'; nearest_anchor='CHAIR'; relative_to=@([ordered]@{ target='DAUGHTER'; target_type='CHARACTER'; horizontal_relation='RIGHT_OF'; depth_relation='SAME_DEPTH'; distance_relation='NEAR' }); support_and_weight='SEATED_BALANCED'; action_stage='REACTION_READY'; hand_and_contact='HANDS_CLEAR_OF_LETTER'; performance_state='QUIET_ATTENTION'; provenance='APPROVED_IMAGE_VISIBLE' }
            )
            props=@(); camera_carryover='FIXED_AND_STABLE'; lighting_carryover='UNCHANGED'; sound_carryover='ROOM_TONE'
        }
        action_flow = [ordered]@{ core_emotion='RESTRAINED_EXPECTATION'; intended_result='LETTER_IN_FRONT_OF_FATHER'; timeline=@(
            [ordered]@{ start_seconds=0; end_seconds=3; camera_start='FIXED_MEDIUM'; primary_event='DAUGHTER_PLACES_LETTER'; action_physics='RIGHT_HAND_MOVES_FORWARD_AND_RELEASES_AFTER_CONTACT'; performance='FATHER_LOOKS_DOWN'; spatial_execution='POSITIONS_UNCHANGED; DAUGHTER REMAINS LEFT_OF FATHER AT SAME_DEPTH'; camera_execution='FIXED'; light_sound_change='PAPER_CONTACT' },
            [ordered]@{ start_seconds=3; end_seconds=9; camera_start='FIXED_MEDIUM'; primary_event='FATHER_READS_RESULT'; action_physics='HEAD_AND_GAZE_SETTLE'; performance='BREATH_PAUSES'; spatial_execution='POSITIONS_UNCHANGED; FATHER REMAINS RIGHT_OF DAUGHTER AT SAME_DEPTH'; camera_execution='FIXED'; light_sound_change='ROOM_TONE' },
            [ordered]@{ start_seconds=9; end_seconds=15; camera_start='FIXED_MEDIUM'; primary_event='BOTH_SETTLE'; action_physics='WEIGHT_AND_HANDS_STABILIZE'; performance='RESTRAINED_REACTION_CONTINUES'; spatial_execution='POSITIONS_UNCHANGED'; camera_execution='FIXED'; light_sound_change='ROOM_TONE_CONTINUES' }
        ) }
        dialogue_audio = @(); camera = [ordered]@{}; lighting_color_material = [ordered]@{}; sound = [ordered]@{}
        end_state = [ordered]@{ state_id='PE-E01-S01-001-V1'; state_kind='PLANNED'; characters=@([ordered]@{ name='DAUGHTER'; world_position='LEFT_SIDE_OF_DINING_TABLE'; screen_position='SCREEN_LEFT'; depth_plane='MIDGROUND'; body_orientation='FACING_FATHER_ACROSS_TABLE'; gaze_target='FATHER'; nearest_anchor='TABLE_EDGE'; relative_to=@([ordered]@{ target='FATHER'; target_type='CHARACTER'; horizontal_relation='LEFT_OF'; depth_relation='SAME_DEPTH'; distance_relation='NEAR' }) },[ordered]@{ name='FATHER'; world_position='RIGHT_SIDE_OF_DINING_TABLE'; screen_position='SCREEN_RIGHT'; depth_plane='MIDGROUND'; body_orientation='FACING_DAUGHTER_ACROSS_TABLE'; gaze_target='LETTER'; nearest_anchor='CHAIR'; relative_to=@([ordered]@{ target='DAUGHTER'; target_type='CHARACTER'; horizontal_relation='RIGHT_OF'; depth_relation='SAME_DEPTH'; distance_relation='NEAR' }) }); next_shot_must_inherit=@('LETTER_IN_FRONT_OF_FATHER','DAUGHTER_LEFT_OF_FATHER'); forbidden_resets=@('PROP_HAND_SWAP','CHARACTER_POSITION_SWAP') }; continuity_constraints = @('LETTER_IN_FRONT_OF_FATHER','DAUGHTER_LEFT_OF_FATHER')
        continuity_checks = [ordered]@{
            sequence_index=1
            incoming=[ordered]@{ status='BOUNDARY'; neighbor_shot_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$boundarySignature; boundary_reason='PROJECT_START' }
            outgoing=[ordered]@{ status='BOUNDARY'; neighbor_shot_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$boundarySignature; boundary_reason='PROJECT_END' }
        }
        body_sections = $sections; body = $body; body_char_count = $body.Length; unresolved_fields = @(); change_log = @()
    }
    $videoPromptPath = Join-Path $tempRoot 'video-prompt.json'; Write-Json $videoPrompt $videoPromptPath
    Invoke-Validator 'S05 consumes the approved bridge and passes' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$videoPromptPath)
    Test-QaRequest 'S05 QA request envelope passes' 'VIDEO_PROMPT' $videoPrompt @($approved,$plot,$storyboard,$storyboard.shot_map[0])

    $brokenStoryboard = $storyboard | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $brokenStoryboard.shot_map[0].status = 'DRAFT'
    $brokenPath = Join-Path $tempRoot 'broken-storyboard.json'; Write-Json $brokenStoryboard $brokenPath
    Invoke-Validator 'Table PASS with row DRAFT is rejected' (Join-Path $skillsRoot 'storyboard-table-director\scripts\validate_storyboard_artifact.ps1') @('-Path',$brokenPath) 1

    $stalePrompt = $storyboardPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $stalePrompt.source_row_stale = $true
    $stalePromptPath = Join-Path $tempRoot 'stale-storyboard-prompt.json'; Write-Json $stalePrompt $stalePromptPath
    Invoke-Validator 'S04 rejects a stale StoryboardRow source' (Join-Path $skillsRoot 'storyboard-image-prompt-director\scripts\validate_storyboard_prompt.ps1') @('-Path',$stalePromptPath) 1

    $mismatchedVideo = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    @($mismatchedVideo.source_artifacts | Where-Object { $_.role -eq 'STORYBOARD_TABLE' })[0].source_beat_ids = @('BEAT-E01-S01-999')
    $mismatchedVideoPath = Join-Path $tempRoot 'mismatched-video-prompt.json'; Write-Json $mismatchedVideo $mismatchedVideoPath
    Invoke-Validator 'S05 rejects source_beat_ids mismatch' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$mismatchedVideoPath) 1

    $autoPlannedAssets = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $autoPlannedAssets.source_artifacts = @($autoPlannedAssets.source_artifacts | Where-Object { $_.role -ne 'ASSET_LEDGER' })
    foreach ($binding in @($autoPlannedAssets.reference_bindings)) {
        $binding.slot_source = 'AUTO_PLANNED'
        $binding.availability = 'REQUIRED_NOT_PROVIDED'
        $binding.asset_id = $null
        $binding.asset_version = $null
    }
    $autoPlannedAssetsPath = Join-Path $tempRoot 'auto-planned-assets.json'; Write-Json $autoPlannedAssets $autoPlannedAssetsPath
    Invoke-Validator 'S05 accepts auto-planned Mixed slots without an asset ledger' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$autoPlannedAssetsPath)

    $wrongDurationVideo = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $wrongDurationVideo.task.target_duration_seconds = 14
    $wrongDurationVideo.action_flow.timeline[-1].end_seconds = 14
    $wrongDurationPath = Join-Path $tempRoot 'wrong-duration-video.json'; Write-Json $wrongDurationVideo $wrongDurationPath
    Invoke-Validator 'Seedance 2.0 rejects any target duration other than 15 seconds' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$wrongDurationPath) 1

    $video25 = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $video25.task.model = 'seedance-2.5'
    $video25.task.model_rule_profile = 'SD25-PROJECT-V1'
    $video25.task.target_duration_seconds = 30
    $video25.action_flow.timeline[-1].end_seconds = 30
    $video25.body_sections.continuous_timeline = '0-3 seconds: DAUGHTER places the letter down. 3-9 seconds: FATHER looks at it. 9-30 seconds: both settle into the resulting pause.'
    $video25.body = @($video25.body_sections.reference_materials,$video25.body_sections.approved_start_and_spatial_state,$video25.body_sections.continuous_timeline,$video25.body_sections.imaging,$video25.body_sections.sound_continuity_stability) -join "`n`n"
    $video25.body_char_count = $video25.body.Length
    $video25Rules = @($video25.source_artifacts | Where-Object { $_.role -eq 'MODEL_RULES' })[0]
    $video25Rules.artifact_id = 'SD25-RULES'; $video25Rules.artifact_version = 'V1'; $video25Rules.full_id = 'SD25-RULES-V1'; $video25Rules.scope = 'seedance-2.5'
    $video25Path = Join-Path $tempRoot 'video-25.json'; Write-Json $video25 $video25Path
    Invoke-Validator 'Seedance 2.5 accepts exactly 30 seconds' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$video25Path)

    $missingMixedSlots = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingMixedSlots.reference_bindings = @()
    $missingMixedSlotsPath = Join-Path $tempRoot 'missing-mixed-slots.json'; Write-Json $missingMixedSlots $missingMixedSlotsPath
    Invoke-Validator 'S05 rejects a prompt without provided or auto-planned Mixed slots' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingMixedSlotsPath) 1

    $missingAssets = $storyboardPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingAssets.asset_bindings.characters = @()
    $missingAssetsPath = Join-Path $tempRoot 'missing-assets.json'; Write-Json $missingAssets $missingAssetsPath
    Invoke-Validator 'S04 rejects asset count bypass' (Join-Path $skillsRoot 'storyboard-image-prompt-director\scripts\validate_storyboard_prompt.ps1') @('-Path',$missingAssetsPath) 1

    $missingDialoguePolicy = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    @($missingDialoguePolicy.source_artifacts | Where-Object { $_.role -eq 'ORIGINAL_DIALOGUE' })[0].PSObject.Properties.Remove('dialogue_policy')
    $missingDialoguePolicyPath = Join-Path $tempRoot 'missing-dialogue-policy.json'; Write-Json $missingDialoguePolicy $missingDialoguePolicyPath
    Invoke-Validator 'S05 rejects empty dialogue without NO_DIALOGUE' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingDialoguePolicyPath) 1

    $wrongRowVersion = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    @($wrongRowVersion.source_artifacts | Where-Object { $_.role -eq 'STORYBOARD_TABLE' })[0].row_full_id = 'SHOT-E01-S01-001-V9'
    $wrongRowVersionPath = Join-Path $tempRoot 'wrong-row-version.json'; Write-Json $wrongRowVersion $wrongRowVersionPath
    Invoke-Validator 'S05 rejects row_full_id and row version mismatch' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$wrongRowVersionPath) 1

    $missingCharacterPositions = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingCharacterPositions.start_state.characters = @()
    $missingCharacterPositionsPath = Join-Path $tempRoot 'missing-character-positions.json'; Write-Json $missingCharacterPositions $missingCharacterPositionsPath
    Invoke-Validator 'S05 rejects missing structured character positions' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingCharacterPositionsPath) 1

    $vagueCharacterPositions = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $vagueCharacterPositions.body_sections.approved_start_and_spatial_state = 'At 0 seconds, the two characters keep their positions as shown in the reference image.'
    $vagueCharacterPositions.body = @($vagueCharacterPositions.body_sections.reference_materials,$vagueCharacterPositions.body_sections.approved_start_and_spatial_state,$vagueCharacterPositions.body_sections.continuous_timeline,$vagueCharacterPositions.body_sections.imaging,$vagueCharacterPositions.body_sections.sound_continuity_stability) -join "`n`n"
    $vagueCharacterPositions.body_char_count = $vagueCharacterPositions.body.Length
    $vagueCharacterPositionsPath = Join-Path $tempRoot 'vague-character-positions.json'; Write-Json $vagueCharacterPositions $vagueCharacterPositionsPath
    Invoke-Validator 'S05 rejects body without explicit character position relations' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$vagueCharacterPositionsPath) 1

    $missingTimelinePosition = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingTimelinePosition.action_flow.timeline[1].PSObject.Properties.Remove('spatial_execution')
    $missingTimelinePositionPath = Join-Path $tempRoot 'missing-timeline-position.json'; Write-Json $missingTimelinePosition $missingTimelinePositionPath
    Invoke-Validator 'S05 rejects timeline without position execution' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingTimelinePositionPath) 1

    $missingArtifactAuthorization = $storyboardPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingArtifactAuthorization.PSObject.Properties.Remove('flow_authorization_id')
    $missingArtifactAuthorizationPath = Join-Path $tempRoot 'missing-artifact-authorization.json'; Write-Json $missingArtifactAuthorization $missingArtifactAuthorizationPath
    Invoke-Validator 'Production artifact without S01 authorization is rejected' (Join-Path $skillsRoot 'storyboard-image-prompt-director\scripts\validate_storyboard_prompt.ps1') @('-Path',$missingArtifactAuthorizationPath) 1

    $forgedFlowControl = New-QaFlowControl 'STORYBOARD_PROMPT' $storyboardPrompt
    $forgedFlowControl.production_authorization_id = 'FLOW-AUTH-PRJ001-P3-9999'
    $forgedQaRequest = [ordered]@{ qa_mode='STORYBOARD_PROMPT'; artifact=$storyboardPrompt; approved_upstream=@($storyboard,$storyboard.shot_map[0]); project_constraints=[ordered]@{}; change_set=$null; previous_version=$null; flow_control=$forgedFlowControl }
    $forgedQaRequestPath = Join-Path $tempRoot 'forged-qa-authorization.json'; Write-Json $forgedQaRequest $forgedQaRequestPath
    Invoke-Validator 'QA rejects forged authorization mismatch' (Join-Path $skillsRoot '_shared\validate_qa_request.ps1') @('-Path',$forgedQaRequestPath) 1

    $badQaRequest = [ordered]@{ qa_mode='STORYBOARD_TABLE'; artifact=$storyboard; approved_upstream=$plot; project_constraints=[ordered]@{}; change_set=$null; previous_version=$null }
    $badQaRequestPath = Join-Path $tempRoot 'bad-qa-request.json'; Write-Json $badQaRequest $badQaRequestPath
    Invoke-Validator 'QA request rejects scalar approved_upstream' (Join-Path $skillsRoot '_shared\validate_qa_request.ps1') @('-Path',$badQaRequestPath) 1
}
finally {
    if ((Test-Path -LiteralPath $tempRoot) -and ([IO.Path]::GetFullPath($tempRoot)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { [IO.Directory]::Delete($tempRoot,$true) }
}

if ($failures.Count -gt 0) { foreach ($failure in $failures) { Write-Host "[TEST FAIL] $failure" -ForegroundColor Red }; exit 1 }
Write-Host '[PASS] All S02-S05 pipeline contract tests passed.' -ForegroundColor Green
exit 0
