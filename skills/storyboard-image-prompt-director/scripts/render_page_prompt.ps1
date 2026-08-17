[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SpecPaths,

    [Parameter(Mandatory = $true)]
    [ValidateSet('COLOR','LINEART_REVIEW','LINEART_CLEAN')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()

function Has-Property($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

# —— 输入：同页 2–10 个已 PASS 的 StoryboardPromptSpec ——
if ($SpecPaths.Count -lt 2 -or $SpecPaths.Count -gt 10) {
    Write-Host "[ERROR] A page requires 2 to 10 panel specs; got $($SpecPaths.Count)." -ForegroundColor Red
    exit 1
}

$specs = @()
foreach ($specPath in $SpecPaths) {
    if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) { $errors.Add("Spec not found: $specPath"); continue }
    try { $specs += (Get-Content -Raw -Encoding UTF8 -LiteralPath $specPath | ConvertFrom-Json) }
    catch { $errors.Add("Invalid JSON: $specPath — $($_.Exception.Message)") }
}
if ($errors.Count -gt 0) { foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }; exit 1 }

# —— 前置机械检查：任一规格非 PASS 即拒绝渲染 ——
foreach ($spec in $specs) {
    $sid = if (Has-Property $spec 'shot_id') { $spec.shot_id } else { '<unknown>' }
    if (-not (Has-Property $spec 'status') -or $spec.status -ne 'PASS') { $errors.Add("$sid status must be PASS before page rendering.") }
    foreach ($field in @('shot_id','positive_prompt','visual_style_lock','style_pack_positive','style_pack_negative','reference_numbering','selected_moment','camera')) {
        if (-not (Has-Property $spec $field)) { $errors.Add("$sid.$field is required for page rendering.") }
    }
    if ((Has-Property $spec 'selected_moment') -and -not (Has-Property $spec.selected_moment 'frozen_state')) { $errors.Add("$sid.selected_moment.frozen_state is required.") }
    if ((Has-Property $spec 'camera') -and -not (Has-Property $spec.camera 'shot_size')) { $errors.Add("$sid.camera.shot_size is required.") }
    if ((Has-Property $spec 'camera') -and -not (Has-Property $spec.camera 'viewpoint')) { $errors.Add("$sid.camera.viewpoint is required.") }
}
if ($errors.Count -gt 0) { foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }; exit 1 }

# —— 同页一致性：同项目、同风格锁、镜号唯一 ——
$projectIds = @($specs | ForEach-Object { if (Has-Property $_ 'project_id') { $_.project_id } } | Sort-Object -Unique)
if ($projectIds.Count -ne 1) { $errors.Add('All panel specs must share one project_id.') }
$locks = @($specs | ForEach-Object { [string]$_.visual_style_lock } | Sort-Object -Unique)
if ($locks.Count -ne 1) { $errors.Add('All panel specs must share one visual_style_lock.') }
$shotIds = @($specs | ForEach-Object { [string]$_.shot_id })
if (@($shotIds | Sort-Object -Unique).Count -ne $shotIds.Count) { $errors.Add('Duplicate shot_id in one page.') }
if ($errors.Count -gt 0) { foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }; exit 1 }

$specs = @($specs | Sort-Object { [string]$_.shot_id })
$styleLock = [string]$specs[0].visual_style_lock
$stylePositive = [string]$specs[0].style_pack_positive
$styleNegative = [string]$specs[0].style_pack_negative
foreach ($spec in $specs) {
    if ([string]$spec.style_pack_positive -ne $stylePositive -or [string]$spec.style_pack_negative -ne $styleNegative) {
        $errors.Add("$($spec.shot_id) style pack text differs from the first spec; packs must be mirrored verbatim.")
    }
}
if ($errors.Count -gt 0) { foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }; exit 1 }

# —— 参考图固定编号合并：同一对象编号必须全页一致 ——
$numbering = @{}
foreach ($spec in $specs) {
    foreach ($entry in @($spec.reference_numbering)) {
        $ref = [string]$entry.ref
        $no = [int]$entry.image_no
        if ($numbering.ContainsKey($ref) -and $numbering[$ref] -ne $no) { $errors.Add("reference_numbering conflict for '$ref': $no vs $($numbering[$ref]).") }
        $numbering[$ref] = $no
    }
}
if ($errors.Count -gt 0) { foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }; exit 1 }
$numberingLines = @($numbering.GetEnumerator() | Sort-Object { $_.Value } | ForEach-Object { "图$($_.Value)是$($_.Key)" })

# —— 版式：固定 2 列 5 行，阅读顺序编号 ——
$panelCount = $specs.Count
$emptyCells = 10 - $panelCount

# —— 模式模板（静态文案，唯一出处为本脚本）——
$modeHeader = @{
    COLOR = @(
        "生成一张 2 列 5 行分镜页，彩色完成稿，画幅比例与单镜规格一致。",
        "风格基准：$stylePositive"
    )
    LINEART_REVIEW = @(
        "生成一张 2 列 5 行分镜评审页：黑白灰阶线稿，人物与关键道具贴中文标签，运镜以箭头标注方向。",
        "禁止彩色主体、禁止灰阶写实化、禁止任何对白气泡与说明栏文字。"
    )
    LINEART_CLEAN = @(
        "生成一张 2 列 5 行净线稿分镜页：黑白线稿，无标签、无箭头、无任何文字。"
    )
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($h in $modeHeader[$Mode]) { $lines.Add($h) }
$lines.Add("版式：2 列 5 行，共 10 格，阅读顺序从左到右、从上到下；本页使用 $panelCount 格" + $(if ($emptyCells -gt 0) { "，剩余 $emptyCells 格留空" } else { '' }) + '。')
if ($numberingLines.Count -gt 0 -and $Mode -eq 'COLOR') { $lines.Add('参考图：' + ($numberingLines -join '，') + '。') }
$lines.Add('')

for ($i = 0; $i -lt $panelCount; $i++) {
    $spec = $specs[$i]
    $panelNo = $i + 1
    $movement = 'FIXED'
    if ((Has-Property $spec 'camera') -and (Has-Property $spec.camera 'camera_movement')) { $movement = [string]$spec.camera.camera_movement }
    $arrow = switch ($movement) {
        'FIXED' { '固定镜头，无运镜箭头' }
        'PUSH_IN' { '运镜箭头：推近' }
        'PULL_OUT' { '运镜箭头：拉远' }
        'PAN_LEFT' { '运镜箭头：左摇' }
        'PAN_RIGHT' { '运镜箭头：右摇' }
        'TILT_UP' { '运镜箭头：上摇' }
        'TILT_DOWN' { '运镜箭头：下摇' }
        'TRACK_LEFT' { '运镜箭头：左移' }
        'TRACK_RIGHT' { '运镜箭头：右移' }
        default { "运镜箭头：$movement" }
    }
    $projection = ''
    if ((Has-Property $spec 'spatial_continuity') -and (Has-Property $spec.spatial_continuity 'screen_projection')) {
        $projection = '；' + (@($spec.spatial_continuity.screen_projection) -join '；')
    }
    $propText = ''
    if (Has-Property $spec 'prop_states') {
        $propText = '；道具：' + (@($spec.prop_states | ForEach-Object { "$($_.prop)$($_.position)$($_.state)" }) -join '；')
    }
    $panelLine = "第${panelNo}格（$($spec.shot_id)）：$($spec.camera.shot_size)，$($spec.camera.viewpoint)。$($spec.selected_moment.frozen_state)$projection$propText"
    if ($Mode -eq 'LINEART_REVIEW') { $panelLine += "。$arrow" }
    $lines.Add($panelLine)
}
$lines.Add('')

# —— 负面约束：模式静态项 + 风格负词包 ——
$negatives = [System.Collections.Generic.List[string]]::new()
$negatives.Add('禁止多格合并、缺格、格号错乱；禁止镜号文字污染画面。')
if ($Mode -eq 'LINEART_REVIEW') { $negatives.Add('禁止彩色、禁止写实渲染、禁止漏标标签、禁止箭头缺失或全部同向。') }
if ($Mode -eq 'LINEART_CLEAN') { $negatives.Add('禁止标签、箭头与任何文字。') }
if ($Mode -eq 'COLOR') { $negatives.Add($styleNegative) }
$lines.Add('负面约束：' + ($negatives -join '；'))

$promptText = ($lines -join "`n") + "`n"

if ($OutPath) {
    [IO.File]::WriteAllText($OutPath, $promptText, (New-Object Text.UTF8Encoding($false)))
    Write-Host "[PASS] Page prompt ($Mode, $panelCount panels) written: $OutPath" -ForegroundColor Green
}
else {
    Write-Output $promptText
}
exit 0
