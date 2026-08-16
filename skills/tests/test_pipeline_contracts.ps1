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
function Test-QaRequest([string]$Name, [string]$Mode, $Artifact, [array]$ApprovedUpstream) {
    $request = [ordered]@{ qa_mode=$Mode; artifact=$Artifact; approved_upstream=$ApprovedUpstream; project_constraints=[ordered]@{}; change_set=$null; previous_version=$null }
    $requestPath = Join-Path $script:tempRoot ($Mode.ToLowerInvariant() + '-qa-request.json')
    Write-Json $request $requestPath
    Invoke-Validator $Name (Join-Path $script:skillsRoot '_shared\validate_qa_request.ps1') @('-Path',$requestPath)
}

try {
    $emptyState = [ordered]@{ characters=[ordered]@{}; props=[ordered]@{}; environment=[ordered]@{}; knowledge=[ordered]@{} }
    $plot = [ordered]@{
        schema_version='1.0'; project_id='PRJ-001'; artifact_id='PLOT-E01'; artifact_version='V1'; full_id='PLOT-E01-V1'; source_artifact_id='SCRIPT-E01'; source_version='V1'; source_full_id='SCRIPT-E01-V1'
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
        schema_version = '1.0'; artifact_type = 'StoryboardTable'; project_id = 'PRJ-001'
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
        schema_version = '1.0'; project_id = 'PRJ-001'; scene_id = 'SCENE-E01-S01'; shot_id = 'SHOT-E01-S01-001'; source_beat_ids = @('BEAT-E01-S01-001')
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

    $sections = [ordered]@{ reference_materials = 'Use the approved storyboard and verified asset slots.'; approved_start_and_spatial_state = 'At 0 seconds, DAUGHTER is screen left and FATHER is screen right.'; continuous_timeline = '0-3 seconds: DAUGHTER places the letter down and FATHER looks at it.'; imaging = 'Medium eye-level fixed camera, 50mm at f/4.'; sound_continuity_stability = 'Keep room tone and paper contact sound. No BGM.' }
    $body = @($sections.reference_materials,$sections.approved_start_and_spatial_state,$sections.continuous_timeline,$sections.imaging,$sections.sound_continuity_stability) -join "`n`n"
    $videoPrompt = [ordered]@{
        schema_version = '1.0'; project_id = 'PRJ-001'; scene_id = 'SCENE-E01-S01'; shot_id = 'SHOT-E01-S01-001'; source_beat_ids = @('BEAT-E01-S01-001')
        artifact_id = 'VP-E01-S01-001'; artifact_version = 'V1'; full_id = 'VP-E01-S01-001-V1'; video_prompt_id = 'VP-E01-S01-001-V1'; status = 'DRAFT'
        task = [ordered]@{ task_mode = 'CREATE'; generation_task = 'MULTIMODAL_REFERENCE'; model = 'seedance-2.0'; model_rule_profile = 'SD20-V3.4'; product_flow = 'OMNI_REFERENCE'; output_scope = 'SINGLE_SHOT'; delivery_mode = 'PROMPT_ONLY'; aspect_ratio = '9:16'; target_duration_seconds = 3 }
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
        reference_bindings = @(); source_lock = [ordered]@{ locked_fields=@('/shot_id'); allowed_changes=@(); change_set_id=$null; repair_ticket_id=$null }; start_state = [ordered]@{}
        action_flow = [ordered]@{ core_emotion='RESTRAINED_EXPECTATION'; intended_result='LETTER_IN_FRONT_OF_FATHER'; timeline=@([ordered]@{ start_seconds=0; end_seconds=3; camera_start='FIXED_MEDIUM'; primary_event='DAUGHTER_PLACES_LETTER'; action_physics='RIGHT_HAND_MOVES_FORWARD_AND_RELEASES_AFTER_CONTACT'; performance='FATHER_LOOKS_DOWN'; camera_execution='FIXED'; light_sound_change='PAPER_CONTACT' }) }
        dialogue_audio = @(); camera = [ordered]@{}; lighting_color_material = [ordered]@{}; sound = [ordered]@{}; end_state = [ordered]@{ state_id='PE-E01-S01-001-V1'; state_kind='PLANNED' }; continuity_constraints = @('LETTER_IN_FRONT_OF_FATHER')
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
