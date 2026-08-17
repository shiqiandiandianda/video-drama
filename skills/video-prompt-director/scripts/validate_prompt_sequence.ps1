[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# 段序列校验（schema 2.0）：段间承接签名 + 窗口 ±2 弱规则交叉核对
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()

function Has-Property($Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function ConvertTo-CanonicalValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary] -and $Value -isnot [pscustomobject]) {
        return @($Value | ForEach-Object { ConvertTo-CanonicalValue $_ })
    }

    $ordered = [ordered]@{}
    $properties = if ($Value -is [System.Collections.IDictionary]) {
        @($Value.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $Value[$_] } })
    }
    else {
        @($Value.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
    }
    foreach ($property in @($properties | Sort-Object Name)) {
        $ordered[$property.Name] = ConvertTo-CanonicalValue $property.Value
    }
    return [pscustomobject]$ordered
}

function Get-CanonicalJson($Value) {
    return (ConvertTo-CanonicalValue $Value | ConvertTo-Json -Depth 50 -Compress)
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "Video prompt sequence not found: $Path"
    exit 2
}

try {
    $root = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}
catch {
    Write-Error "Invalid JSON: $($_.Exception.Message)"
    exit 2
}

$artifacts = if ($root -is [System.Array]) {
    @($root)
}
elseif (Has-Property $root 'artifacts') {
    @($root.artifacts)
}
else {
    @($root)
}

if ($artifacts.Count -eq 0) {
    $errors.Add('Sequence must contain at least one VideoPromptSpec.')
}

for ($index = 0; $index -lt $artifacts.Count; $index++) {
    $artifact = $artifacts[$index]
    $context = "artifacts[$index]"
    foreach ($field in @('segment_id','start_state','final_state','continuity_checks')) {
        if (-not (Has-Property $artifact $field)) { $errors.Add("$context.$field is required.") }
    }
    if ((Has-Property $artifact 'segment_id') -and [string]$artifact.segment_id -notmatch '^SEG-E[0-9]{2,4}-[0-9]{3}$') {
        $errors.Add("$context.segment_id must match SEG-E##-###.")
    }
    if (-not (Has-Property $artifact 'continuity_checks')) { continue }
    $checks = $artifact.continuity_checks
    foreach ($direction in @('incoming','outgoing')) {
        if (-not (Has-Property $checks $direction)) { $errors.Add("$context.continuity_checks.$direction is required.") }
    }
}

# 段号连续递增
$segmentNumbers = @($artifacts | ForEach-Object { if (Has-Property $_ 'segment_id') { [int]([string]$_.segment_id).Substring([string]$_.segment_id.Length - 3) } })
for ($index = 1; $index -lt $segmentNumbers.Count; $index++) {
    if ($segmentNumbers[$index] -ne $segmentNumbers[$index - 1] + 1) {
        $errors.Add("Segment IDs must be contiguous: artifacts[$index] is out of sequence.")
        break
    }
}

if ($artifacts.Count -gt 0) {
    $first = $artifacts[0]
    if ((Has-Property $first 'continuity_checks') -and (Has-Property $first.continuity_checks 'incoming') -and $first.continuity_checks.incoming.status -ne 'BOUNDARY') {
        $errors.Add('The first segment incoming continuity check must be BOUNDARY.')
    }
    $last = $artifacts[$artifacts.Count - 1]
    if ((Has-Property $last 'continuity_checks') -and (Has-Property $last.continuity_checks 'outgoing') -and $last.continuity_checks.outgoing.status -ne 'BOUNDARY') {
        $errors.Add('The last segment outgoing continuity check must be BOUNDARY.')
    }
}

# 段间承接（distance=1，严格签名）
for ($index = 0; $index -lt ($artifacts.Count - 1); $index++) {
    $current = $artifacts[$index]
    $next = $artifacts[$index + 1]
    if (-not (Has-Property $current 'continuity_checks') -or -not (Has-Property $next 'continuity_checks')) { continue }
    if (-not (Has-Property $current.continuity_checks 'outgoing') -or -not (Has-Property $next.continuity_checks 'incoming')) { continue }

    $outgoing = $current.continuity_checks.outgoing
    $incoming = $next.continuity_checks.incoming
    if ($outgoing.status -ne 'PASS') { $errors.Add("$($current.segment_id) outgoing continuity check must be PASS.") }
    if ($incoming.status -ne 'PASS') { $errors.Add("$($next.segment_id) incoming continuity check must be PASS.") }
    if ($outgoing.neighbor_segment_id -ne $next.segment_id) { $errors.Add("$($current.segment_id) outgoing neighbor_segment_id must equal $($next.segment_id).") }
    if ($incoming.neighbor_segment_id -ne $current.segment_id) { $errors.Add("$($next.segment_id) incoming neighbor_segment_id must equal $($current.segment_id).") }

    if ((Has-Property $current 'final_state') -and (Has-Property $current.final_state 'state_id') -and @($outgoing.compared_state_ids) -notcontains $current.final_state.state_id) {
        $errors.Add("$($current.segment_id) outgoing compared_state_ids must include its final_state.state_id.")
    }
    if ((Has-Property $next 'start_state') -and (Has-Property $next.start_state 'state_id') -and @($outgoing.compared_state_ids) -notcontains $next.start_state.state_id) {
        $errors.Add("$($current.segment_id) outgoing compared_state_ids must include the next start_state.state_id.")
    }
    if ((Has-Property $current 'final_state') -and (Has-Property $current.final_state 'state_id') -and @($incoming.compared_state_ids) -notcontains $current.final_state.state_id) {
        $errors.Add("$($next.segment_id) incoming compared_state_ids must include the previous final_state.state_id.")
    }
    if ((Has-Property $next 'start_state') -and (Has-Property $next.start_state 'state_id') -and @($incoming.compared_state_ids) -notcontains $next.start_state.state_id) {
        $errors.Add("$($next.segment_id) incoming compared_state_ids must include its start_state.state_id.")
    }

    if ((Has-Property $outgoing 'handoff_signature') -and (Has-Property $incoming 'handoff_signature')) {
        if ((Get-CanonicalJson $outgoing.handoff_signature) -cne (Get-CanonicalJson $incoming.handoff_signature)) {
            $errors.Add("Handoff signature mismatch between $($current.segment_id) and $($next.segment_id).")
        }
    }
}

# 窗口 ±2（distance=2，弱规则交叉核对）
for ($index = 0; $index -lt ($artifacts.Count - 2); $index++) {
    $current = $artifacts[$index]
    $distant = $artifacts[$index + 2]
    if (-not (Has-Property $current 'continuity_checks') -or -not (Has-Property $distant 'continuity_checks')) { continue }
    $currentWindows = @()
    if (Has-Property $current.continuity_checks 'window_checks') { $currentWindows = @($current.continuity_checks.window_checks) }
    $distantWindows = @()
    if (Has-Property $distant.continuity_checks 'window_checks') { $distantWindows = @($distant.continuity_checks.window_checks) }

    $forward = @($currentWindows | Where-Object { $_.neighbor_segment_id -eq $distant.segment_id -and [int]$_.distance -eq 2 })
    if ($forward.Count -ne 1) { $errors.Add("$($current.segment_id) must declare a distance=2 window_check for $($distant.segment_id).") }
    $backward = @($distantWindows | Where-Object { $_.neighbor_segment_id -eq $current.segment_id -and [int]$_.distance -eq 2 })
    if ($backward.Count -ne 1) { $errors.Add("$($distant.segment_id) must declare a distance=2 window_check for $($current.segment_id).") }

    foreach ($wc in @($forward + $backward)) {
        if ((Has-Property $wc 'mismatches') -and @($wc.mismatches).Count -gt 0) {
            $errors.Add("window_check between $($current.segment_id) and $($distant.segment_id) has unresolved mismatches.")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    Write-Host "[FAIL] Segment sequence validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] Segment sequence is bidirectionally connected with window checks: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
