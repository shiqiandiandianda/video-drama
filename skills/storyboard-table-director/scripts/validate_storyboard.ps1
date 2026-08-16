[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [switch]$Json,

    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Severity,
        [string]$Code,
        [string]$Message,
        [int]$Row = 0
    )

    $List.Add([pscustomobject]@{
        severity = $Severity
        code = $Code
        row = $Row
        message = $Message
    })
}

function Split-MarkdownRow {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if ($trimmed.StartsWith('|')) {
        $trimmed = $trimmed.Substring(1)
    }
    if ($trimmed.EndsWith('|')) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }
    return @($trimmed -split '\|' | ForEach-Object { $_.Trim() })
}

function Test-SeparatorRow {
    param([string]$Line)

    $cells = Split-MarkdownRow $Line
    if ($cells.Count -ne 9) {
        return $false
    }
    foreach ($cell in $cells) {
        if ($cell -notmatch '^:?-{3,}:?$') {
            return $false
        }
    }
    return $true
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$lines = @(Get-Content -LiteralPath $resolvedPath -Encoding UTF8)
$expectedHeaders = @('场景', '镜号', '景别', '机位', '运镜', '画面描述', '秒数/s', '人物情绪/细节动作', '导演备注')
$issues = [System.Collections.Generic.List[object]]::new()
$headerIndexes = [System.Collections.Generic.List[int]]::new()
$dataRows = [System.Collections.Generic.List[object]]::new()
$tableOrdinal = 0

for ($index = 0; $index -lt $lines.Count; $index++) {
    $cells = Split-MarkdownRow $lines[$index]
    if ($cells.Count -ne 9) {
        continue
    }

    $matches = $true
    for ($column = 0; $column -lt 9; $column++) {
        if ($cells[$column] -ne $expectedHeaders[$column]) {
            $matches = $false
            break
        }
    }
    if ($matches) {
        $headerIndexes.Add($index)
        $tableOrdinal++

        if (($index + 1) -ge $lines.Count -or -not (Test-SeparatorRow $lines[$index + 1])) {
            Add-Issue $issues 'ERROR' 'INVALID_SEPARATOR' '九列表头后的 Markdown 分隔行无效。' ($index + 2)
            continue
        }

        $rowCount = 0
        $dataIndex = $index + 2
        while ($dataIndex -lt $lines.Count) {
            $line = $lines[$dataIndex]
            if ([string]::IsNullOrWhiteSpace($line) -or -not $line.Trim().StartsWith('|')) {
                break
            }
            $rowCells = Split-MarkdownRow $line
            $dataRows.Add([pscustomobject]@{
                table_index = $tableOrdinal
                source_line = $dataIndex + 1
                cells = $rowCells
            })
            $rowCount++
            $dataIndex++
        }

        if ($rowCount -eq 0) {
            Add-Issue $issues 'ERROR' 'NO_SHOTS' ("第 {0} 张九列表没有任何镜头行。" -f $tableOrdinal) ($index + 3)
        }
        $index = $dataIndex - 1
    }
}

if ($headerIndexes.Count -eq 0) {
    Add-Issue $issues 'ERROR' 'HEADER_NOT_FOUND' '未找到固定九列表头。'
}

$previousScene = $null
$previousShot = 0
$previousTable = 0
$observableTokens = @('视线', '眼神', '眨眼', '眼睑', '呼吸', '吸气', '呼气', '屏息', '喉结', '嘴角', '嘴唇', '下颌', '胸口', '手指', '指尖', '指腹', '拇指', '手腕', '肩线', '重心', '步幅', '衣料', '发丝', '停顿', '摩挲')
$abstractEmotionPattern = '十分震惊|内心复杂|非常担心|非常害怕|很紧张|很害怕|很生气|非常生气|十分悲伤|非常焦虑|^平静[。；;]?$|^压迫[。；;]?$'
$promptPattern = 'Seedance|Prompt|提示词|\{\{Mixed|\{\{Image|负面词|negative prompt|模型参数'

foreach ($row in $dataRows) {
    $cells = @($row.cells)
    $lineNo = [int]$row.source_line
    if ([int]$row.table_index -ne $previousTable) {
        $previousScene = $null
        $previousShot = 0
        $previousTable = [int]$row.table_index
    }
    if ($cells.Count -ne 9) {
        Add-Issue $issues 'ERROR' 'COLUMN_COUNT' ("镜头行应为 9 列，实际为 {0} 列。" -f $cells.Count) $lineNo
        continue
    }

    for ($column = 0; $column -lt 9; $column++) {
        if ([string]::IsNullOrWhiteSpace($cells[$column])) {
            Add-Issue $issues 'ERROR' 'EMPTY_FIELD' ("第 {0} 列 [{1}] 为空。" -f ($column + 1), $expectedHeaders[$column]) $lineNo
        }
    }

    $scene = $cells[0]
    $shotText = $cells[1]
    $shotNumber = 0
    if (-not [int]::TryParse($shotText, [ref]$shotNumber)) {
        Add-Issue $issues 'ERROR' 'SHOT_NUMBER' ("镜号 [{0}] 不是整数。" -f $shotText) $lineNo
    } else {
        if ($scene -ne $previousScene) {
            if ($shotNumber -ne 1) {
                Add-Issue $issues 'WARNING' 'SCENE_START_NUMBER' ("新场景首镜通常应从 01 开始，当前为 {0}。" -f $shotText) $lineNo
            }
        } elseif ($shotNumber -ne ($previousShot + 1)) {
            Add-Issue $issues 'ERROR' 'SHOT_SEQUENCE' ("同场镜号不连续：上一镜 {0}，当前镜 {1}。" -f $previousShot, $shotText) $lineNo
        }
        $previousShot = $shotNumber
        $previousScene = $scene
    }

    if ($scene -notmatch '(日|夜|晨|清晨|黄昏|傍晚)' -or $scene -notmatch '(内|外)' -or $scene -notmatch '[／/]') {
        Add-Issue $issues 'WARNING' 'SCENE_FORMAT' '场景建议使用：时间＋内/外景＋地点，例如：夜外／旧城巷道。' $lineNo
    }

    $duration = 0.0
    if (-not [double]::TryParse($cells[6], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -or $duration -le 0) {
        Add-Issue $issues 'ERROR' 'DURATION' ("秒数/s [{0}] 必须是大于 0 的数值。" -f $cells[6]) $lineNo
    } elseif ($duration -lt 1.0) {
        Add-Issue $issues 'WARNING' 'VERY_SHORT_DURATION' ("{0} 秒通常不足以建立可读动作或反应。" -f $duration) $lineNo
    }

    $movement = $cells[4]
    $movementMatches = [regex]::Matches($movement, '变焦推拉|手持跟拍|升降|环绕|跟拍|手持|固定|变焦|推|拉|摇|移|跟|升|降|甩')
    $movementKinds = @($movementMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($movementKinds.Count -eq 0) {
        Add-Issue $issues 'WARNING' 'UNKNOWN_MOVEMENT' '运镜列未识别为固定、推、拉、摇、移、跟拍、环绕、升降、手持、甩镜或变焦推拉。' $lineNo
    } elseif ($movementKinds.Count -gt 1) {
        Add-Issue $issues 'ERROR' 'MULTIPLE_MOVEMENTS' ("一个镜头出现多个主要运镜：{0}。" -f ($movementKinds -join '、')) $lineNo
    }

    $allText = $cells -join ' '
    if ($allText -match $promptPattern) {
        Add-Issue $issues 'ERROR' 'OUT_OF_SCOPE_PROMPT' '九列表混入了模型参数、素材槽位或 Prompt 内容。' $lineNo
    }

    $performanceText = "{0} {1}" -f $cells[5], $cells[7]
    $observableCount = 0
    foreach ($token in $observableTokens) {
        if ($performanceText.Contains($token)) {
            $observableCount++
        }
    }

    if ($cells[7] -match $abstractEmotionPattern -and $observableCount -lt 2) {
        Add-Issue $issues 'ERROR' 'ABSTRACT_EMOTION' '情绪列只有抽象判断，缺少至少两类可观察表演证据。' $lineNo
    }

    if ($cells[2] -match '近景|特写' -and $duration -ge 2.0 -and $observableCount -lt 2) {
        Add-Issue $issues 'WARNING' 'CLOSEUP_PERFORMANCE' '2 秒以上近景/特写建议至少包含两类生命体征或微表演。' $lineNo
    }
}

$errorCount = @($issues | Where-Object { $_.severity -eq 'ERROR' }).Count
$warningCount = @($issues | Where-Object { $_.severity -eq 'WARNING' }).Count
$result = [pscustomobject]@{
    path = $resolvedPath
    table_found = $headerIndexes.Count -gt 0
    table_count = $headerIndexes.Count
    shot_count = $dataRows.Count
    error_count = $errorCount
    warning_count = $warningCount
    valid = ($errorCount -eq 0 -and (-not $Strict -or $warningCount -eq 0))
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Output ("Storyboard validation: {0}" -f $resolvedPath)
    Write-Output ("Tables: {0}  Shots: {1}  Errors: {2}  Warnings: {3}" -f $result.table_count, $result.shot_count, $errorCount, $warningCount)
    foreach ($issue in $issues) {
        $location = if ($issue.row -gt 0) { "line $($issue.row)" } else { 'document' }
        Write-Output ("[{0}] {1} ({2}): {3}" -f $issue.severity, $issue.code, $location, $issue.message)
    }
}

if ($errorCount -gt 0) {
    exit 1
}
if ($Strict -and $warningCount -gt 0) {
    exit 2
}
exit 0
