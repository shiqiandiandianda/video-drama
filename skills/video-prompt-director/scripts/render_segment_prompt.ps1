[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$OutPath
)

# 段级 VideoPromptSpec → 十五节 body 机械渲染器（schema 2.0）
# 纪律：本脚本是 body 的唯一生成途径；只读规格内结构化字段，不产新内容；
# 任一上游 STALE / 非 PASS / 缺字段 → 拒绝渲染。措辞以 _shared/segment-format.md 为准。

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$missing = [System.Collections.Generic.List[string]]::new()

function Has-Property($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Require-Field($Object, [string]$Name, [string]$Context) {
    if (-not (Has-Property $Object $Name)) {
        $script:missing.Add("$Context.$Name")
        return $null
    }
    $value = $Object.$Name
    if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
        $script:missing.Add("$Context.$Name")
        return $null
    }
    return $value
}

function Get-Text($Object, [string]$Name, [string]$Context) {
    $value = Require-Field $Object $Name $Context
    if ($null -eq $value) { return "<缺失:$Context.$Name>" }
    return [string]$value
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "VideoPromptSpec not found: $Path"
    exit 2
}

try {
    $spec = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}
catch {
    Write-Error "Invalid JSON: $($_.Exception.Message)"
    exit 2
}

# —— 前置机械检查：非 PASS / STALE 拒绝渲染 ——
$refuse = [System.Collections.Generic.List[string]]::new()
if ((Has-Property $spec 'schema_version') -and $spec.schema_version -ne '2.0') { $refuse.Add("schema_version must be 2.0 (segment-level).") }
if (Has-Property $spec 'source_artifacts') {
    foreach ($src in @($spec.source_artifacts)) {
        if ((Has-Property $src 'stale') -and $src.stale -eq $true) { $refuse.Add("source_artifacts $($src.full_id) is STALE.") }
        if ((Has-Property $src 'status') -and @('PASS', 'APPROVED') -notcontains $src.status) { $refuse.Add("source_artifacts $($src.full_id) status $($src.status) is not PASS/APPROVED.") }
    }
}
if ($refuse.Count -gt 0) {
    foreach ($r in $refuse) { Write-Host "[REFUSE] $r" -ForegroundColor Red }
    Write-Host "[FAIL] Render refused: upstream not clean." -ForegroundColor Red
    exit 1
}

# —— 必需顶层字段 ——
foreach ($f in @('segment_id', 'covered_shot_ids', 'task', 'segment_context', 'reference_bindings', 'start_state', 'timeline', 'segment_light_color', 'sound_design', 'final_state')) {
    Require-Field $spec $f 'root' | Out-Null
}
$ctx = $spec.segment_context
foreach ($f in @('scene_sub', 'spatial_anchors', 'screen_lock', 'scene_tone', 'light_base', 'visual_style_lock', 'style_pack_positive', 'style_pack_negative')) {
    Require-Field $ctx $f 'segment_context' | Out-Null
}
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { Write-Host "[MISSING] $m" -ForegroundColor Red }
    Write-Host "[FAIL] Render refused: $($missing.Count) required field(s) missing. 缺字段即阻断，禁止编造。" -ForegroundColor Red
    exit 1
}

$duration = [double]$spec.task.target_duration_seconds
$sb = [System.Text.StringBuilder]::new()
function Add-Line([string]$s) { [void]$sb.AppendLine($s) }
function Add-Blank() { [void]$sb.AppendLine('') }

# —— 槽位渲染助手 ——
function Get-SlotLabel($binding) {
    switch ($binding.asset_type) {
        'CHARACTER'  { return "角色" }
        'SCENE'      { return "场景" }
        'PROP'       { return "关键道具" }
        'AUDIO'      { return "角色音频参考" }
        'STORYBOARD' { return "分镜图/站位图" }
        default      { return [string]$binding.asset_type }
    }
}

# ========== 一、参考素材说明 ==========
Add-Line '一、参考素材说明'
Add-Blank
$bindings = @($spec.reference_bindings | Sort-Object { [int]$_.mixed_slot })
foreach ($b in $bindings) {
    $tail = ''
    if ($b.asset_type -eq 'STORYBOARD') { $tail = '（如有）' }
    Add-Line ("$(Get-SlotLabel $b) $($b.name) {{Mixed $($b.mixed_slot)}}$tail")
}
Add-Blank

# ========== 二、参考素材使用规则 ==========
Add-Line '二、参考素材使用规则'
Add-Blank
foreach ($b in $bindings) {
    switch ($b.asset_type) {
        'CHARACTER'  { Add-Line ("$($b.name) {{Mixed $($b.mixed_slot)}} 只参考人物脸部、年龄感、肤色、发型、发色、身材比例、服装和当前伤势状态。") }
        'SCENE'      { Add-Line ("$($b.name) {{Mixed $($b.mixed_slot)}} 只参考场景建筑结构、空间关系、材质、环境、门窗、家具及固定视觉特征。") }
        'PROP'       { Add-Line ("$($b.name) {{Mixed $($b.mixed_slot)}} 只参考其尺寸、材质、颜色、形状、结构和正确使用方式，不得变成其他物体。") }
        'AUDIO'      { Add-Line ("$($b.name) {{Mixed $($b.mixed_slot)}} 只参考音色、年龄感与发声状态。") }
        'STORYBOARD' {
            Add-Line '如使用分镜图/站位图：'
            Add-Line '只参考人物站位、景别、构图、镜头方向和运镜逻辑，不继承草图风格、文字、编号、箭头、边框、标签等非画面内容。'
        }
    }
}
Add-Blank
Add-Line '本段未出现的人物、场景、道具不得自行增加。'
Add-Blank

# ========== 三、统一视觉与摄影基准 ==========
Add-Line '三、统一视觉与摄影基准'
Add-Blank
Add-Line ("$($spec.task.aspect_ratio)竖屏，" + $(Get-Text $ctx 'style_pack_positive' 'segment_context'))
Add-Blank
Add-Line ("整体视觉风格：" + $(Get-Text $ctx.scene_tone 'style' 'segment_context.scene_tone'))
Add-Line ("整体色彩：" + $(Get-Text $ctx.scene_tone 'color_palette' 'segment_context.scene_tone'))
Add-Line ("整体节奏：" + $(Get-Text $ctx.scene_tone 'rhythm' 'segment_context.scene_tone'))
Add-Blank
Add-Line '摄影机运动只在人物动作、视线变化、信息揭示或情绪爆点发生时触发。'
Add-Line '快速运镜结束后必须立即恢复稳定清晰。'
Add-Line '禁止持续无意义晃动、无意义旋转和无动机运镜。'
Add-Line '不生成字幕、片中文字、标题、logo、水印、BGM。'
Add-Blank

# ========== 四、场景空间锚点 ==========
Add-Line '四、场景空间锚点'
Add-Blank
Add-Line ("Scene ID：" + $spec.scene_id + "（" + $(Get-Text $ctx 'scene_sub' 'segment_context') + "）")
Add-Blank
Add-Line '固定场景关系'
foreach ($a in @($ctx.spatial_anchors)) {
    if ($a.kind -eq 'CAMERA_ANCHOR') { continue }
    Add-Line ("$($a.screen_position)：$($a.name)（$($a.description)）")
}
Add-Blank
Add-Line '人物空间关系'
foreach ($c in @($ctx.screen_lock.characters)) {
    $side = switch ($c.screen_side) { 'LEFT' { '画面左侧' } 'RIGHT' { '画面右侧' } default { '画面中央' } }
    Add-Line ("$($c.name) 始终位于：$side")
}
Add-Line ("人物之间的主关系轴：$($ctx.screen_lock.main_axis)")
Add-Blank
Add-Line '除非剧情明确要求，不交换左右位置、不镜像反转、不无理由越轴。'
Add-Blank
Add-Line '场景视角锚点'
foreach ($a in @($ctx.spatial_anchors)) {
    if ($a.kind -ne 'CAMERA_ANCHOR') { continue }
    Add-Line ("摄影机主要位于：$($a.screen_position)")
    Add-Line ("主要朝向：$($a.description)")
}
Add-Blank

# ========== 五、承接上一段 15 秒 ==========
Add-Line '五、承接上一段15秒'
Add-Line '上一段终帧状态'
Add-Blank
$ss = $spec.start_state
foreach ($c in @($ss.characters)) {
    Add-Line ("$($c.name)：")
    Add-Line ("位置：$($c.screen_position) / $($c.depth_plane)")
    Add-Line ("景深：$($c.focus_state)$(if (-not $c.focus_state) {'实焦'})")
    Add-Line ("姿态与朝向：$($c.body_orientation)")
    Add-Line ("视线：$($c.gaze_target)")
    Add-Line ("双手状态：$($c.hand_and_contact)")
    if (Has-Property $c 'injury_and_wardrobe') { Add-Line ("伤势与服装状态：$($c.injury_and_wardrobe)") }
    Add-Blank
}
foreach ($p in @($ss.props)) {
    Add-Line ("关键道具：$($p.name) 位于 $($p.position)，由 $($p.holder_or_contact) 持有/放置，状态：$($p.state)")
}
Add-Blank
if (Has-Property $ss 'foreground') { Add-Line ("前景：$($ss.foreground)") }
if (Has-Property $ss 'midground') { Add-Line ("中景：$($ss.midground)") }
if (Has-Property $ss 'background') { Add-Line ("背景：$($ss.background)") }
if (Has-Property $ss 'camera_carryover') { Add-Line ("场景视角：$($ss.camera_carryover)") }
if (Has-Property $ss 'action_carryover') { Add-Line ("动作状态：$($ss.action_carryover)") }
Add-Blank
Add-Line '本段0.0秒必须直接继承以上人物位置、动作状态、朝向、道具归属、伤势、场景方向和摄影机空间关系。'
Add-Blank

# ========== 六/七/八/九、镜头时间轴（含对白与镜尾状态） ==========
function Render-ShotBlock($shot, [bool]$withHeaders) {
    if ($withHeaders) { Add-Line '六、镜头时间轴' ; Add-Blank }
    $seq = '{0:D2}' -f [int]$shot.shot_seq
    Add-Line ("【镜头$seq｜$($shot.start_s)—$($shot.end_s)秒】")
    Add-Line '摄影参数'
    Add-Blank
    Add-Line ("$($shot.camera.focal_length_mm)mm，f/$($shot.camera.aperture_f)，$($shot.camera.shot_size)，$($shot.camera.viewpoint)。")
    Add-Blank
    Add-Line '画面空间'
    Add-Blank
    foreach ($c in @($shot.spatial_frame.characters)) {
        Add-Line ("$($c.name)：位于画面 $($c.screen_position) $($c.depth_plane)，$($c.focus_state)，身体朝向 $($c.body_orientation)。")
    }
    foreach ($p in @($shot.spatial_frame.props)) {
        Add-Line ("关键道具：$($p.name) 位于 $($p.screen_area)，由 $($p.held_by) 持有/放置。")
    }
    if (Has-Property $shot.spatial_frame 'foreground') { Add-Line ("前景：$($shot.spatial_frame.foreground)") }
    if (Has-Property $shot.spatial_frame 'midground') { Add-Line ("中景：$($shot.spatial_frame.midground)") }
    if (Has-Property $shot.spatial_frame 'background') { Add-Line ("背景：$($shot.spatial_frame.background)") }
    Add-Blank
    Add-Line '场景视角锚点'
    Add-Line ("摄影机位于 $($shot.spatial_frame.camera_anchor)。")
    Add-Line ("保持：$($ctx.screen_lock.main_axis) 关系不变。")
    Add-Line '不得改变场景方向。'
    Add-Blank
    Add-Line '人物动作与表演'
    Add-Blank
    Add-Line ([string]$shot.action_performance.beats_description)
    Add-Blank
    Add-Line ("表演状态：" + [string]$shot.action_performance.performance)
    Add-Blank
    Add-Line '动作必须体现真实物理重量、惯性、接触反馈和因果关系。'
    Add-Line '一个镜头原则上只完成一个主要动作目标。'
    Add-Blank
    Add-Line '摄影机运动与焦点'
    Add-Blank
    Add-Line ("摄影机：$($shot.camera.confirmed_movement)")
    Add-Line ("运镜触发点：$($shot.camera.movement_trigger)")
    Add-Line ("焦点落点：$($shot.camera.movement_landing)")
    Add-Line ("焦点目标：$($shot.camera.focus_target)")
    Add-Blank
    Add-Line '快速运镜阶段允许短促方向性运动模糊，到达落点后立即恢复清晰。'
    Add-Blank

    # —— 七、时间轴内对白（写在本镜块内） ——
    if ($withHeaders) { Add-Line '七、时间轴内对白' ; Add-Blank }
    foreach ($d in @($shot.dialogue_blocks)) {
        if ($d.block_type -eq 'NO_DIALOGUE') {
            Add-Line '无对白，人物闭嘴，无随机口型。'
            Add-Blank
            continue
        }
        Add-Line ("【$($d.start_s)—$($d.end_s)秒】")
        Add-Blank
        Add-Line ("[$($d.speaker)音色：$($d.voice)]")
        Add-Blank
        if ($d.block_type -eq 'INNER_OS') {
            Add-Line '内心OS，不需要口型匹配，人物嘴部保持自然闭合，只保留对应面部微表情：'
        }
        else {
            Add-Line '口型精确匹配台词：'
        }
        Add-Blank
        Add-Line ("“$($d.exact_text)”")
        Add-Blank
        if (@($d.pause_before_keywords).Count -gt 0) {
            Add-Line ("关键词“$($d.pause_before_keywords -join '”“')”前停顿 $($d.pause_seconds) 秒，同时配合 $($d.primary_gesture)。")
        }
        if (@($d.stress_keywords).Count -gt 0) {
            Add-Line ("关键词“$($d.stress_keywords -join '”“')”处加重，同时配合 $($d.primary_gesture)。")
        }
        Add-Line ("台词结束后保持 $($d.after_hold_s) 秒闭嘴表演，人物继续眼神与动作状态，不得立即切断表演。")
        if ($d.block_type -eq 'INNER_OS') { Add-Line 'OS不生成字幕，不显示内心文字。' }
        Add-Blank
    }

    # —— 八、镜尾状态 ——
    if ($withHeaders) { Add-Line '八、镜尾状态' ; Add-Blank }
    $es = $shot.shot_end_state
    Add-Line '终帧：'
    foreach ($k in $es.characters.PSObject.Properties) { Add-Line ("$($k.Name)：$($k.Value)") }
    foreach ($k in $es.props.PSObject.Properties) { Add-Line ("道具 $($k.Name)：$($k.Value)") }
    Add-Line ("摄影机：$($es.camera.position)，焦点：$($es.camera.focus)")
    Add-Line ("动作停在：$($es.action_stop)")
    Add-Blank
    Add-Line '下一镜必须直接继承该状态。'
    Add-Line '不得在切镜后自动重置人物姿势、位置、道具或伤势。'
    Add-Blank
}

$shots = @($spec.timeline)
if ($shots.Count -gt 0) { Render-ShotBlock $shots[0] $true }
if ($shots.Count -gt 1) {
    Add-Line '九、后续镜头重复结构'
    Add-Blank
    for ($i = 1; $i -lt $shots.Count; $i++) { Render-ShotBlock $shots[$i] $false }
}
Add-Line ("直到 $($duration) 秒结束。")
Add-Blank

# ========== 十、全段光线与色彩 ==========
Add-Line '十、全段光线与色彩'
Add-Blank
$lc = $spec.segment_light_color
Add-Line ("主光方向：$($lc.key_direction)")
Add-Line ("主光色温：$($lc.color_temperature)")
Add-Line ("人物亮面：$($lc.face_lit_side)")
Add-Line ("人物暗面：$($lc.face_shadow_side)")
Add-Line ("轮廓光：$($lc.rim_light)")
Add-Line ("背景亮度：$($lc.background_brightness)")
Add-Line ("关键道具高光：$($lc.prop_highlight)")
Add-Blank
Add-Line '必须保留人物眼神光、面部立体感和场景纵深。'
Add-Line '禁止全场大平光、暗部死黑、高光过曝、廉价蓝紫滤镜或无来源魔法光。'
Add-Blank

# ========== 十一、全段摄影规格 ==========
Add-Line '十一、全段摄影规格'
Add-Blank
Add-Line '24fps，180°快门。'
foreach ($shot in $shots) {
    $seq = '{0:D2}' -f [int]$shot.shot_seq
    Add-Line ("镜头$seq（$($shot.camera.shot_size)）：$($shot.camera.focal_length_mm)mm，f/$($shot.camera.aperture_f)")
}
Add-Blank
Add-Line '高速运动只在明确动作触发点发生。'
Add-Line '人物眼睛、嘴部、手指、关键道具和动作落点必须清晰。'
Add-Blank

# ========== 十二、声音设计 ==========
Add-Line '十二、声音设计'
Add-Blank
Add-Line '不生成背景音乐BGM。'
Add-Line '固定环境声'
foreach ($a in @($spec.sound_design.ambient)) { Add-Line ("【$a】") }
Add-Line '动作声音'
foreach ($s in @($spec.sound_design.action_sfx)) {
    $seq = '{0:D2}' -f [int]$s.shot_seq
    Add-Line ("镜头$seq：【$($s.sfx)】")
}
Add-Blank
Add-Line ([string]$spec.sound_design.dialogue_priority)
Add-Line ([string]$spec.sound_design.spatial_rule)
Add-Blank

# ========== 十三、全段连续性约束 ==========
Add-Line '十三、全段连续性约束'
Add-Blank
Add-Line '人物脸部、年龄、肤色、发型、服装、伤势和身体比例全段稳定。'
Add-Line ("人物左右关系和主空间轴保持一致（$($ctx.screen_lock.main_axis)），除非剧情明确要求，不交换位置、不镜像反转、不无理由越轴。")
$fixtureNames = @($ctx.spatial_anchors | Where-Object { $_.kind -eq 'FIXTURE' } | ForEach-Object { $_.name })
Add-Line ("场景固定锚点（$($fixtureNames -join '、')）空间关系稳定。")
Add-Line '道具形状、材质、尺寸、归属和状态连续。'
Add-Line '上一镜产生的结果必须延续到下一镜：门锁损伤持续存在；撕下的裙摆不会自动恢复；已经拿到手中的道具不能突然消失；已经出现的伤口不能恢复。'
Add-Line '人物动作严格遵循：动作起点 → 动作过程 → 动作结果。'
Add-Line '不允许人物瞬移、站位跳变、道具瞬移、角色突然恢复体力或无原因改变姿势。'
Add-Line '未在剧本和素材中出现的人物、道具、建筑和剧情结果不得自行增加。'
Add-Blank

# ========== 十四、负面约束 ==========
Add-Line '十四、负面约束'
Add-Blank
Add-Line '禁止：字幕、标题、logo、水印、片中文字、对白气泡、随机BGM。'
Add-Line '禁止人物换脸、年龄漂移、肤色变化、发型漂移、服装变化、重复人物、随机群演增减。'
Add-Line '禁止左右镜像、站位乱跳、无意义越轴、视线反转、动作方向反转。'
Add-Line '禁止手指异常、多余肢体、身体穿模、人物与道具融合、道具穿过身体。'
Add-Line '禁止场景结构变化、门窗互换、家具漂移、摄影机穿墙或进入不存在的空间。'
Add-Line '禁止无意义持续晃动、持续旋转、焦点漂移、快速运镜结束后人物仍然模糊。'
Add-Line '禁止擅自增加原剧本不存在的关键动作、道具、角色、场景、伤势或剧情结果。'
Add-Blank
Add-Line ([string]$ctx.style_pack_negative)
Add-Blank

# ========== 十五、本段最终承接状态 ==========
Add-Line '十五、本段15秒最终承接状态'
Add-Blank
Add-Line '这是下一段15秒必须直接读取的状态。'
Add-Blank
$fs = $spec.final_state
foreach ($c in @($fs.characters)) {
    Add-Line ("$($c.name)")
    Add-Line ("画面位置：$($c.screen_position) / $($c.depth_plane)")
    Add-Line ("景深：$($c.focus_state)")
    Add-Line ("姿态：$($c.posture)")
    Add-Line ("身体朝向：$($c.body_orientation)")
    Add-Line ("视线：$($c.gaze_target)")
    Add-Line ("手部：$($c.hands)")
    Add-Line ("伤势：$($c.injury)")
    Add-Line ("情绪：$($c.emotion)")
    Add-Blank
}
foreach ($p in @($fs.props)) {
    Add-Line ("道具 $($p.name)：$($p.position)，持有：$($p.held_by)")
}
Add-Blank
Add-Line ("前景：$($fs.foreground)")
Add-Line ("中景：$($fs.midground)")
Add-Line ("背景：$($fs.background)")
Add-Line ("场景视角锚点：$($fs.camera_anchor)")
Add-Blank
Add-Line ("摄影机：$($fs.camera.focal_length_mm)mm，$($fs.camera.viewpoint)，运动状态：$($fs.camera.movement_state)，最终焦点：$($fs.camera.final_focus)")
Add-Blank
Add-Line ("最后动作停在：$($fs.action_stop)")
Add-Blank
Add-Line '下一段第一帧必须直接从这一状态继续，不重新起动作。'

$body = $sb.ToString() -replace "`r`n", "`n" -replace "`r", "`n"
$body = $body.TrimEnd()
$surrogatePairs = [regex]::Matches($body, '[ᄀ-࿿][Ⰰ-]').Count
# 上一行字符类仅为占位；以下用显式代理区转义重新计数（code point = UTF-16 长度 - 代理对数）
$surrogatePairs = [regex]::Matches($body, '[\uD800-\uDBFF][\uDC00-\uDFFF]').Count
$charCount = $body.Length - $surrogatePairs

$spec | Add-Member -NotePropertyName body -NotePropertyValue $body -Force
$spec | Add-Member -NotePropertyName body_char_count -NotePropertyValue $charCount -Force
$spec | Add-Member -NotePropertyName body_rendered_by -NotePropertyValue 'render_segment_prompt.ps1' -Force
$spec | Add-Member -NotePropertyName body_rendered_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force

$target = $Path
if ($OutPath) { $target = $OutPath }
$json = $spec | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($target, $json, [System.Text.UTF8Encoding]::new($false))

if ($charCount -gt 5000) {
    Write-Host "[WARN] body_char_count=$charCount exceeds 5000; confirm model limit for $($spec.task.model)." -ForegroundColor Yellow
}
Write-Host "[PASS] Rendered 15-section body ($charCount chars) -> $target" -ForegroundColor Green
exit 0
