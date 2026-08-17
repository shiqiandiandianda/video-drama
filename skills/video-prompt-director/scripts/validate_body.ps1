param(
    [Parameter(Mandatory = $true)]
    [string]$BodyPath,

    [int]$MaxChars = 0,

    [ValidateSet(0,15,30)]
    [int]$ExpectedDurationSeconds = 0
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BodyPath -PathType Leaf)) {
    Write-Error "Body file not found: $BodyPath"
    exit 2
}

$body = Get-Content -LiteralPath $BodyPath -Raw -Encoding UTF8
$body = $body -replace "`r`n", "`n"
$body = $body -replace "`r", "`n"

if ([string]::IsNullOrWhiteSpace($body)) {
    Write-Error 'Body is empty.'
    exit 1
}

function Get-UnicodeCodePointCount {
    param([string]$Text)

    $count = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $current = $Text[$index]
        if (
            [char]::IsHighSurrogate($current) -and
            ($index + 1) -lt $Text.Length -and
            [char]::IsLowSurrogate($Text[$index + 1])
        ) {
            $index++
        }
        $count++
    }
    return $count
}

$issues = [System.Collections.Generic.List[string]]::new()
$charCount = Get-UnicodeCodePointCount -Text $body

if ($MaxChars -gt 0 -and $charCount -gt $MaxChars) {
    $issues.Add("BODY_CHAR_LIMIT_EXCEEDED: $charCount > $MaxChars")
}

$forbiddenPatterns = [ordered]@{
    'AT_REFERENCE_FORBIDDEN' = '@'
    'IMAGE_SLOT_FORBIDDEN' = '\{\{\s*Image\b'
    'MARKDOWN_FENCE_FORBIDDEN' = '```'
    'END_FREEZE_FORBIDDEN' = '(?i)END\s+FREEZE'
    'OS_LABEL_FORBIDDEN' = '(?m)^\s*OS\s*[:：]'
    'NEXT_STEP_TALK_FORBIDDEN' = '\u4E0B\u4E00\u6B65\u6211\u53EF\u4EE5'
    'MARKETING_LABEL_FORBIDDEN' = '\u4F4E\u5D29\u574F\u4F18\u5316\u7248|\u5DE5\u4E1A\u6267\u884C\u7248'
}

foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    if ([regex]::IsMatch($body, $entry.Value)) {
        $issues.Add($entry.Key)
    }
}

$mixedTokens = [regex]::Matches($body, '\{\{\s*Mixed[^}]*\}\}')
foreach ($token in $mixedTokens) {
    if ($token.Value -notmatch '^\{\{Mixed [1-9][0-9]*\}\}$') {
        $issues.Add("INVALID_MIXED_TOKEN: $($token.Value)")
    }
}

if ($mixedTokens.Count -eq 0) {
    $issues.Add('MIXED_SLOT_REQUIRED')
}
else {
    $mixedSlotNumbers = @($mixedTokens | ForEach-Object {
        if ($_.Value -match '^\{\{Mixed ([1-9][0-9]*)\}\}$') { [int]$Matches[1] }
    } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
    for ($slotIndex = 0; $slotIndex -lt $mixedSlotNumbers.Count; $slotIndex++) {
        if ($mixedSlotNumbers[$slotIndex] -ne ($slotIndex + 1)) {
            $issues.Add('MIXED_SLOTS_MUST_AUTO_INCREMENT_FROM_1')
            break
        }
    }
}

$timelinePattern = '【镜头([0-9]+)｜([0-9]+(?:\.[0-9]+)?)—([0-9]+(?:\.[0-9]+)?)秒】'
$timelineMatches = [regex]::Matches($body, $timelinePattern)
$zeroTimelineCount = @($timelineMatches | Where-Object { [double]::Parse($_.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) -eq 0 }).Count
if ($zeroTimelineCount -gt 1) {
    $issues.Add("MULTIPLE_ZERO_TIMELINES: $zeroTimelineCount")
}
if ($timelineMatches.Count -eq 0) {
    $issues.Add('TIMELINE_REQUIRED')
}
else {
    $expectedStart = 0.0
    foreach ($timelineMatch in $timelineMatches) {
        $segmentStart = [double]::Parse($timelineMatch.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
        $segmentEnd = [double]::Parse($timelineMatch.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
        if ($segmentStart -ne $expectedStart) { $issues.Add("TIMELINE_GAP_OR_OVERLAP: expected $expectedStart, found $segmentStart") }
        if ($segmentEnd -le $segmentStart) { $issues.Add("TIMELINE_SEGMENT_INVALID: $segmentStart-$segmentEnd") }
        $expectedStart = $segmentEnd
    }
    if ($ExpectedDurationSeconds -gt 0 -and $expectedStart -ne $ExpectedDurationSeconds) {
        $issues.Add("TIMELINE_DURATION_MISMATCH: $expectedStart != $ExpectedDurationSeconds")
    }
}

$result = [ordered]@{
    valid = ($issues.Count -eq 0)
    body_path = (Resolve-Path -LiteralPath $BodyPath).Path
    unicode_code_points = $charCount
    max_chars = if ($MaxChars -gt 0) { $MaxChars } else { $null }
    expected_duration_seconds = if ($ExpectedDurationSeconds -gt 0) { $ExpectedDurationSeconds } else { $null }
    zero_timeline_count = $zeroTimelineCount
    timeline_segment_count = $timelineMatches.Count
    mixed_token_count = $mixedTokens.Count
    issues = @($issues)
}

$result | ConvertTo-Json -Depth 4
if ($issues.Count -gt 0) {
    exit 1
}
exit 0
