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
    $entry = [ordered]@{
        project_id='PRJ-001'; artifact_type=$Type; artifact_id=$Id; artifact_version=$Version; full_id=($Id + '-' + $Version)
        flow_authorization_id=$AuthorizationId; status=$Status; current=$true; stale=$false; scene_id=$SceneId; shot_id=$ShotId
        source_beat_ids=@(); source_full_ids=@(); resource=('outputs/' + $Id.ToLowerInvariant() + '.json')
    }
    if ($Type -eq 'VIDEO_PROMPT') {
        $entry['segment_id'] = 'SEG-E01-001'
        $entry['covered_shot_ids'] = @('SHOT-E01-S01-001','SHOT-E01-S01-002')
    }
    return $entry
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
    if ($Artifact.Contains('covered_shot_ids')) { $shotScope = @($Artifact.covered_shot_ids) }
    $scope = [ordered]@{ episode_ids=@('E01'); scene_ids=$sceneScope; shot_ids=$shotScope; beat_ids=@() }
    $requirements = [ordered]@{
        quality_bar=@('九列齐备')
        project_constraints=[ordered]@{ aspect_ratio='9:16'; model='seedance-2.0'; visual_style_lock='LIVE_ACTION_REALISM' }
        focus=@('邻镜流畅')
    }
    $current = New-FlowIndexArtifact $typeByMode[$Mode] $Artifact.artifact_id $Artifact.artifact_version 'DRAFT' $authorizationId $sceneId $shotId
    if ($Artifact.Contains('source_beat_ids')) { $current.source_beat_ids = @($Artifact.source_beat_ids) }
    $index = @($current)
    if ($Mode -eq 'STORYBOARD_TABLE') { $index += New-FlowIndexArtifact 'PLOT' 'PLOT-E01' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' }
    if ($Mode -eq 'STORYBOARD_PROMPT') { $index += New-FlowIndexArtifact 'STORYBOARD_TABLE' 'STORYBOARD-E01-S01' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' }
    if ($Mode -eq 'STORYBOARD_IMAGE') { $index += New-FlowIndexArtifact 'STORYBOARD_PROMPT' 'SP-E01-S01-001' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' 'SHOT-E01-S01-001' }
    if ($Mode -eq 'VIDEO_PROMPT') {
        $image = New-FlowIndexArtifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-001' 'V2' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' 'SHOT-E01-S01-001'
        $image2 = New-FlowIndexArtifact 'STORYBOARD_IMAGE' 'IMG-E01-S01-002' 'V1' 'PASS' 'FLOW-AUTH-PRJ001-HISTORY-0001' 'SCENE-E01-S01' 'SHOT-E01-S01-002'
        $set = New-FlowIndexArtifact 'APPROVED_STORYBOARD_SET' 'APPROVED-STORYBOARD-E01' 'V1' 'APPROVED' 'FLOW-AUTH-PRJ001-HISTORY-0001'
        $set.Add('approved_items', @(
            [ordered]@{ shot_id='SHOT-E01-S01-001'; image_full_id='IMG-E01-S01-001-V2'; status='APPROVED'; stale=$false },
            [ordered]@{ shot_id='SHOT-E01-S01-002'; image_full_id='IMG-E01-S01-002-V1'; status='APPROVED'; stale=$false }
        ))
        $index += @($image,$image2,$set)
    }
    $flowState = [ordered]@{
        schema_version='1.0'
        project_manifest=[ordered]@{ project_id='PRJ-001'; manifest_version='V1'; status='ACTIVE'; episode_ids=@('E01'); required_scene_ids=@('SCENE-E01-S01'); visual_style_lock='LIVE_ACTION_REALISM'; source_materials=@([ordered]@{ source_id='SCRIPT-E01'; source_type='SCRIPT'; version='V1'; status='CURRENT'; locator='file/episode-01.txt' }); constraints=[ordered]@{} }
        stage_state=[ordered]@{ project_id='PRJ-001'; current_stage=$stage; state='WAITING_QA'; current_artifact_full_id=$Artifact.full_id; last_qa_verdict=$null; blocking_reasons=@(); next_action='CALL_QA' }
        decision_ledger=@(); artifact_index=$index
        flow_authorizations=@([ordered]@{ authorization_id=$authorizationId; project_id='PRJ-001'; stage=$stage; action='CALL_PRODUCER'; target=$producerByMode[$Mode]; status='CONSUMED'; scope=$scope; requirements=$requirements; artifact_full_id=$Artifact.full_id; ticket_id=$null; issued_at='2026-08-16T00:00:00+08:00' })
        pending_repair_tickets=@(); run_log=@()
        dispatch=[ordered]@{ action='CALL_QA'; target='short-drama-unified-qa'; qa_mode=$Mode; artifact_full_id=$Artifact.full_id; ticket_id=$null; authorization_id=$authorizationId; scope=$scope; requirements=$requirements; reason='QA regression test' }
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
            scene_id='SCENE-E01-S01'; scene_number=1; source_ranges=@('SCRIPT-E01-V1:L1'); heading=[ordered]@{ time='DAY'; interior_exterior='INT'; location='DINING_ROOM' }
            scene_main='住宅'; scene_sub='住宅-餐厅'
            spatial_anchors=@([ordered]@{ kind='FIXTURE'; name='餐桌'; screen_position='画面中央'; description='长方形木桌' },[ordered]@{ kind='CAMERA_ANCHOR'; name='主机位'; screen_position='餐厅门侧'; description='朝餐桌方向拍摄' })
            scene_tone=[ordered]@{ style='现实都市家庭'; color_palette='暖黄主调'; rhythm='克制递进' }
            light_base=[ordered]@{ key_direction='右侧窗外'; color_temperature='暖黄' }
            characters_present=@('DAUGHTER','FATHER'); scene_start_state=$emptyState
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
            scene_sub = '住宅-餐厅'
            spatial_anchors = @([ordered]@{ kind='FIXTURE'; name='餐桌'; screen_position='画面中央'; description='长方形木桌' },[ordered]@{ kind='CAMERA_ANCHOR'; name='主机位'; screen_position='餐厅门侧'; description='朝餐桌方向拍摄' })
            screen_lock = [ordered]@{ characters=@([ordered]@{ name='DAUGHTER'; screen_side='LEFT'; vertical='EYE_LEVEL' },[ordered]@{ name='FATHER'; screen_side='RIGHT'; vertical='EYE_LEVEL' }); main_axis='左→右'; two_shot_same_direction=$true }
            end_state = [ordered]@{ characters=[ordered]@{ DAUGHTER='站在餐桌旁等待'; FATHER='低头看通知书' }; props=[ordered]@{ LETTER='平放在父亲面前' }; camera=[ordered]@{ position='门侧平视'; focus='父亲眼睛' }; action_stop='父亲低头看信瞬间' }
            dialogue_delivery = @()
            segment_hint = [ordered]@{ segment_id='SEG-E01-001'; note='与 SHOT-E01-S01-002 合段' }
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
        visual_style_lock = 'LIVE_ACTION_REALISM'
        style_pack_positive = '真人实拍短剧风格，真实演员、真实皮肤纹理、真实服装与真实场景材质。'
        style_pack_negative = '禁止 3D 渲染感、CG 感、动画感、卡通感。'
        reference_numbering = @([ordered]@{ image_no=1; ref='DAUGHTER' },[ordered]@{ image_no=2; ref='FATHER' },[ordered]@{ image_no=3; ref='DINING_ROOM' },[ordered]@{ image_no=4; ref='LETTER' })
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

    $body = @(
        '一、参考素材说明'
        'DAUGHTER{{Mixed 1}}，FATHER{{Mixed 2}}，DINING_ROOM{{Mixed 3}}，LETTER{{Mixed 4}}。'
        '二、参考素材使用规则'
        '只参考身份与外观，不继承参考图姿势与背景。'
        '三、统一视觉与摄影基准'
        '真人实拍短剧风格，9:16 画幅，seedance-2.0。'
        '四、场景空间锚点'
        '餐桌位于画面中央，主机位在餐厅门侧朝餐桌方向。'
        '五、承接上一段15秒'
        '项目开始，无上一段。'
        '六、镜头时间轴'
        '【镜头1｜0—7.5秒】全景，DAUGHTER 将通知书放到 FATHER 面前。'
        '【镜头2｜7.5—15秒】中近景，FATHER 低头看信，两人沉默。'
        '七、时间轴内对白'
        '本段无对白。'
        '八、镜尾状态'
        '镜头1：通知书平放在父亲面前；镜头2：两人维持停顿。'
        '九、后续镜头重复结构'
        '后续镜头按同一结构重复。'
        '十、全段光线与色彩'
        '右侧窗外暖黄主光。'
        '十一、全段摄影规格'
        '镜头1：35mm f/4.0；镜头2：50mm f/2.8。'
        '十二、声音设计'
        '室内底噪与纸张接触声，无 BGM。'
        '十三、全段连续性约束'
        '通知书在父亲面前，DAUGHTER 在左 FATHER 在右。'
        '十四、负面约束'
        '禁止字幕、水印、额外人物。'
        '十五、本段15秒最终承接状态'
        '通知书平放父亲面前，两人停顿落定。'
    ) -join "`n"
    $boundarySignature = [ordered]@{ characters=@(); props=@(); spatial_world=@(); camera='FIXED_MEDIUM'; lighting='UNCHANGED'; sound='ROOM_TONE' }
    $videoPrompt = [ordered]@{
        schema_version = '2.0'; project_id = 'PRJ-001'; flow_authorization_id='FLOW-AUTH-PRJ001-P6-0001'; requirements_ref='FLOW-AUTH-PRJ001-P6-0001'
        scene_id = 'SCENE-E01-S01'; segment_id = 'SEG-E01-001'; shot_id = 'SHOT-E01-S01-001'
        covered_shot_ids = @('SHOT-E01-S01-001','SHOT-E01-S01-002'); source_beat_ids = @('BEAT-E01-S01-001')
        artifact_id = 'VP-E01-001'; artifact_version = 'V1'; full_id = 'VP-E01-001-V1'; video_prompt_id = 'VP-E01-001-V1'; status = 'DRAFT'
        task = [ordered]@{ task_mode = 'CREATE'; generation_task = 'MULTIMODAL_REFERENCE'; model = 'seedance-2.0'; model_rule_profile = 'SD20-V3.4'; product_flow = 'OMNI_REFERENCE'; output_scope = 'SEGMENT'; delivery_mode = 'PROMPT_ONLY'; aspect_ratio = '9:16'; target_duration_seconds = 15 }
        approved_storyboard_set_full_id = 'APPROVED-STORYBOARD-E01-V1'; approved_image_full_id = 'IMG-E01-S01-001-V2'
        segment_context = [ordered]@{
            scene_sub = '住宅-餐厅'
            spatial_anchors = @([ordered]@{ kind='FIXTURE'; name='餐桌'; screen_position='画面中央'; description='长方形木桌' },[ordered]@{ kind='CAMERA_ANCHOR'; name='主机位'; screen_position='餐厅门侧'; description='朝餐桌方向拍摄' })
            screen_lock = [ordered]@{ characters=@([ordered]@{ name='DAUGHTER'; screen_side='LEFT'; vertical='EYE_LEVEL' },[ordered]@{ name='FATHER'; screen_side='RIGHT'; vertical='EYE_LEVEL' }); main_axis='左→右' }
            scene_tone = [ordered]@{ style='现实都市家庭'; color_palette='暖黄主调'; rhythm='克制递进' }
            light_base = [ordered]@{ key_direction='右侧窗外'; color_temperature='暖黄' }
            visual_style_lock = 'LIVE_ACTION_REALISM'
            style_pack_positive = '真人实拍短剧风格，真实演员、真实皮肤纹理、真实服装与真实场景材质。'
            style_pack_negative = '禁止 3D 渲染感、CG 感、动画感、卡通感。'
        }
        source_artifacts = @(
            [ordered]@{ role='APPROVED_STORYBOARD_SET'; artifact_id='APPROVED-STORYBOARD-E01'; artifact_version='V1'; full_id='APPROVED-STORYBOARD-E01-V1'; status='APPROVED'; stale=$false; scope='E01' },
            [ordered]@{ role='APPROVED_STORYBOARD'; artifact_id='IMG-E01-S01-001'; artifact_version='V2'; full_id='IMG-E01-S01-001-V2'; status='APPROVED'; stale=$false; scope='SHOT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001'); resource='storyboard-001.png'; source_prompt_full_id='SP-E01-S01-001-V1'; approval_record=[ordered]@{ approved_by='Human Director'; approved_at='2026-08-14T00:00:00+08:00'; locked_fields=@('COMPOSITION','SHOT_SIZE','POSITIONS','CORE_PROP','STORY_MOMENT'); allowed_changes=@('NATURAL_ACTION_DETAIL') } },
            [ordered]@{ role='STORYBOARD_PROMPT'; artifact_id='SP-E01-S01-001'; artifact_version='V1'; full_id='SP-E01-S01-001-V1'; status='PASS'; stale=$false; scope='SHOT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001') },
            [ordered]@{ role='PLOT_PROGRESSION'; artifact_id='PLOT-E01'; artifact_version='V1'; full_id='PLOT-E01-V1'; status='PASS'; stale=$false; scope='BEAT-E01-S01-001'; source_beat_ids=@('BEAT-E01-S01-001') },
            [ordered]@{ role='STORYBOARD_TABLE'; artifact_id='STORYBOARD-E01-S01'; artifact_version='V1'; full_id='STORYBOARD-E01-S01-V1'; status='PASS'; stale=$false; scope='SEG-E01-001'; covered_row_full_ids=@('SHOT-E01-S01-001-V1','SHOT-E01-S01-002-V1') },
            [ordered]@{ role='ORIGINAL_DIALOGUE'; artifact_id='SCRIPT-E01'; artifact_version='V1'; full_id='SCRIPT-E01-V1'; status='APPROVED'; stale=$false; scope='SCRIPT-E01-V1:L1'; dialogue_policy='NO_DIALOGUE'; exact_lines=@() },
            [ordered]@{ role='ASSET_LEDGER'; artifact_id='ASSET-LEDGER-PRJ001'; artifact_version='V1'; full_id='ASSET-LEDGER-PRJ001-V1'; status='APPROVED'; stale=$false; scope='PRJ-001' },
            [ordered]@{ role='MODEL_RULES'; artifact_id='SD20-RULES'; artifact_version='V3.4'; full_id='SD20-RULES-V3.4'; status='PASS'; stale=$false; scope='seedance-2.0'; validation_status='VERIFIED' },
            [ordered]@{ role='PREVIOUS_END_STATE'; artifact_id='VP-E01-000'; artifact_version='V1'; full_id='VP-E01-000-V1'; status='PASS'; stale=$false; scope='SEG-E01-000' }
        )
        reference_bindings = @(
            [ordered]@{ name='DAUGHTER'; asset_type='CHARACTER'; asset_id='CHAR-DAUGHTER-01'; asset_version='V1'; mixed_slot=1; slot_source='INPUT_LEDGER'; availability='PROVIDED'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') },
            [ordered]@{ name='FATHER'; asset_type='CHARACTER'; asset_id='CHAR-FATHER-01'; asset_version='V1'; mixed_slot=2; slot_source='INPUT_LEDGER'; availability='PROVIDED'; reference_role='IDENTITY_APPEARANCE'; inherit=@('FACE','COSTUME'); ignore=@('BACKGROUND') },
            [ordered]@{ name='DINING_ROOM'; asset_type='SCENE'; asset_id=$null; asset_version=$null; mixed_slot=3; slot_source='AUTO_PLANNED'; availability='REQUIRED_NOT_PROVIDED'; reference_role='SPACE_STYLE'; inherit=@('LAYOUT'); ignore=@('REFERENCE_PEOPLE') },
            [ordered]@{ name='LETTER'; asset_type='PROP'; asset_id=$null; asset_version=$null; mixed_slot=4; slot_source='AUTO_PLANNED'; availability='REQUIRED_NOT_PROVIDED'; reference_role='PROP_APPEARANCE'; inherit=@('SIZE','COLOR'); ignore=@('UNCONFIRMED_TEXT') }
        ); source_lock = [ordered]@{ locked_fields=@('/segment_id','/covered_shot_ids'); allowed_changes=@(); change_set_id=$null; repair_ticket_id=$null }
        start_state = [ordered]@{
            state_id='SS-E01-001-V1'; source_status='APPROVED_STORYBOARD_PLUS_LOCKED_UPSTREAM'
            characters=@(
                [ordered]@{ name='DAUGHTER'; screen_position='SCREEN_LEFT'; depth_plane='MIDGROUND' },
                [ordered]@{ name='FATHER'; screen_position='SCREEN_RIGHT'; depth_plane='MIDGROUND' }
            )
            props=@()
        }
        timeline = @(
            [ordered]@{
                shot_seq=1; shot_id='SHOT-E01-S01-001'; row_full_id='SHOT-E01-S01-001-V1'; start_s=0; end_s=7.5
                camera=[ordered]@{ shot_size='全景'; viewpoint='正面平视'; confirmed_movement='FIXED'; movement_trigger='NONE'; movement_landing='无'; focal_length_mm=35; aperture_f=4.0; focus_target='父女双人' }
                spatial_frame=[ordered]@{ characters=@([ordered]@{ name='DAUGHTER'; screen_position='SCREEN_LEFT' },[ordered]@{ name='FATHER'; screen_position='SCREEN_RIGHT' }); props=@() }
                action_performance=[ordered]@{ beats_description='DAUGHTER 将通知书放到 FATHER 面前'; performance='眼神克制，呼吸放缓' }
                dialogue_blocks=@([ordered]@{ block_type='NO_DIALOGUE' })
                shot_end_state=[ordered]@{ characters=[ordered]@{ DAUGHTER='站在餐桌旁等待'; FATHER='低头看通知书' }; props=[ordered]@{ LETTER='平放在父亲面前' }; camera=[ordered]@{ position='门侧平视' }; action_stop='通知书落桌瞬间' }
            },
            [ordered]@{
                shot_seq=2; shot_id='SHOT-E01-S01-002'; row_full_id='SHOT-E01-S01-002-V1'; start_s=7.5; end_s=15
                camera=[ordered]@{ shot_size='中近景'; viewpoint='正面平视'; confirmed_movement='FIXED'; movement_trigger='NONE'; movement_landing='无'; focal_length_mm=50; aperture_f=2.8; focus_target='父亲眼睛' }
                spatial_frame=[ordered]@{ characters=@([ordered]@{ name='FATHER'; screen_position='SCREEN_RIGHT' }); props=@([ordered]@{ name='LETTER'; screen_area='画面中央' }) }
                action_performance=[ordered]@{ beats_description='FATHER 低头看信，两人沉默'; performance='呼吸停顿后恢复' }
                dialogue_blocks=@([ordered]@{ block_type='NO_DIALOGUE' })
                shot_end_state=[ordered]@{ characters=[ordered]@{ DAUGHTER='等待'; FATHER='看完抬头' }; props=[ordered]@{ LETTER='平放在父亲面前' }; camera=[ordered]@{ position='门侧平视' }; action_stop='停顿落定' }
            }
        )
        segment_light_color = [ordered]@{ key_direction='右侧窗外'; color_temperature='暖黄'; face_lit_side='右侧'; face_shadow_side='左侧'; rim_light='窗外轮廓'; background_brightness='暗于人物'; prop_highlight='通知书纸面高光' }
        sound_design = [ordered]@{ ambient=@('室内底噪'); action_sfx=@([ordered]@{ shot_seq=1; sfx='纸张接触桌面' }); music_policy='NO_BGM'; dialogue_priority='对白清晰优先'; spatial_rule='声音方向与画面一致' }
        final_state = [ordered]@{
            state_id='PE-E01-001-V1'; state_kind='PLANNED'
            characters=@([ordered]@{ name='DAUGHTER'; screen_position='SCREEN_LEFT' },[ordered]@{ name='FATHER'; screen_position='SCREEN_RIGHT' })
            props=@([ordered]@{ name='LETTER'; position='父亲面前桌面'; held_by=$null })
            foreground='桌面通知书'; midground='父女双人'; background='餐厅空间'
            camera_anchor='门侧机位朝餐桌'
            camera=[ordered]@{ focal_length_mm=50; viewpoint='平视'; movement_state='STOPPED'; final_focus='父亲眼睛' }
            action_stop='停顿落定'
            next_segment_must_inherit=@('LETTER_IN_FRONT_OF_FATHER'); forbidden_resets=@('PROP_HAND_SWAP','CHARACTER_POSITION_SWAP')
        }
        continuity_constraints = @('LETTER_IN_FRONT_OF_FATHER','DAUGHTER_LEFT_OF_FATHER')
        continuity_checks = [ordered]@{
            window=2
            incoming=[ordered]@{ status='BOUNDARY'; neighbor_segment_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$boundarySignature; boundary_reason='PROJECT_START' }
            outgoing=[ordered]@{ status='BOUNDARY'; neighbor_segment_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$boundarySignature; boundary_reason='PROJECT_END' }
            window_checks=@()
        }
        body = $body; body_char_count = $body.Length; body_rendered_by = 'render_segment_prompt.ps1'; unresolved_fields = @(); change_log = @()
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
    @($mismatchedVideo.source_artifacts | Where-Object { $_.role -eq 'STORYBOARD_TABLE' })[0].PSObject.Properties.Remove('covered_row_full_ids')
    $mismatchedVideoPath = Join-Path $tempRoot 'mismatched-video-prompt.json'; Write-Json $mismatchedVideo $mismatchedVideoPath
    Invoke-Validator 'S05 rejects STORYBOARD_TABLE source without covered rows' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$mismatchedVideoPath) 1

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
    $wrongDurationVideo.timeline[-1].end_s = 14
    $wrongDurationPath = Join-Path $tempRoot 'wrong-duration-video.json'; Write-Json $wrongDurationVideo $wrongDurationPath
    Invoke-Validator 'Seedance 2.0 rejects any target duration other than 15 seconds' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$wrongDurationPath) 1

    $video25 = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $video25.task.model = 'seedance-2.5'
    $video25.task.model_rule_profile = 'SD25-PROJECT-V1'
    $video25.task.target_duration_seconds = 30
    $video25.timeline[-1].end_s = 30
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

    $wrongOptics = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $wrongOptics.timeline[0].camera.focal_length_mm = 85
    $wrongOpticsPath = Join-Path $tempRoot 'wrong-optics.json'; Write-Json $wrongOptics $wrongOpticsPath
    Invoke-Validator 'S05 rejects optics out of range for shot size' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$wrongOpticsPath) 1

    $missingCharacterPositions = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingCharacterPositions.start_state.PSObject.Properties.Remove('characters')
    $missingCharacterPositionsPath = Join-Path $tempRoot 'missing-character-positions.json'; Write-Json $missingCharacterPositions $missingCharacterPositionsPath
    Invoke-Validator 'S05 rejects missing structured character positions' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingCharacterPositionsPath) 1

    $vagueBody = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $vagueBody.body = $vagueBody.body -replace [regex]::Escape('十五、本段15秒最终承接状态'), '十五、'
    $vagueBody.body_char_count = $vagueBody.body.Length
    $vagueBodyPath = Join-Path $tempRoot 'vague-body.json'; Write-Json $vagueBody $vagueBodyPath
    Invoke-Validator 'S05 rejects body missing a section header' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$vagueBodyPath) 1

    $missingTimelinePosition = $videoPrompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $missingTimelinePosition.timeline[1].PSObject.Properties.Remove('spatial_frame')
    $missingTimelinePositionPath = Join-Path $tempRoot 'missing-timeline-position.json'; Write-Json $missingTimelinePosition $missingTimelinePositionPath
    Invoke-Validator 'S05 rejects timeline without spatial frame' (Join-Path $skillsRoot 'video-prompt-director\scripts\validate_video_prompt.ps1') @('-Path',$missingTimelinePositionPath) 1

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
