param(
    [Parameter(Mandatory = $true)]
    [string]$BodyPath,

    [int]$MaxChars = 0
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
    'OS_LABEL_FORBIDDEN' = '(?m)(?:^|[\s\u3010\[])OS(?:[\s\u3011\]:\uFF1A]|$)'
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

$zeroTimelinePattern = '(?m)^\s*0(?:\.0+)?\s*(?:-|\u2013|\u2014|\u81F3|\u5230)\s*\d+(?:\.\d+)?\s*\u79D2\s*[\uFF1A:]'
$zeroTimelineCount = [regex]::Matches($body, $zeroTimelinePattern).Count
if ($zeroTimelineCount -gt 1) {
    $issues.Add("MULTIPLE_ZERO_TIMELINES: $zeroTimelineCount")
}

$result = [ordered]@{
    valid = ($issues.Count -eq 0)
    body_path = (Resolve-Path -LiteralPath $BodyPath).Path
    unicode_code_points = $charCount
    max_chars = if ($MaxChars -gt 0) { $MaxChars } else { $null }
    zero_timeline_count = $zeroTimelineCount
    mixed_token_count = $mixedTokens.Count
    issues = @($issues)
}

$result | ConvertTo-Json -Depth 4
if ($issues.Count -gt 0) {
    exit 1
}
exit 0
