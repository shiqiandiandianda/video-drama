[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

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
    foreach ($field in @('shot_id','start_state','end_state','continuity_checks')) {
        if (-not (Has-Property $artifact $field)) { $errors.Add("$context.$field is required.") }
    }
    if (-not (Has-Property $artifact 'continuity_checks')) { continue }
    $checks = $artifact.continuity_checks
    if (-not (Has-Property $checks 'sequence_index') -or [int]$checks.sequence_index -ne ($index + 1)) {
        $errors.Add("$context.continuity_checks.sequence_index must be $($index + 1).")
    }
    foreach ($direction in @('incoming','outgoing')) {
        if (-not (Has-Property $checks $direction)) { $errors.Add("$context.continuity_checks.$direction is required.") }
    }
}

if ($artifacts.Count -gt 0) {
    $first = $artifacts[0]
    if ((Has-Property $first 'continuity_checks') -and (Has-Property $first.continuity_checks 'incoming') -and $first.continuity_checks.incoming.status -ne 'BOUNDARY') {
        $errors.Add('The first prompt incoming continuity check must be BOUNDARY.')
    }
    $last = $artifacts[$artifacts.Count - 1]
    if ((Has-Property $last 'continuity_checks') -and (Has-Property $last.continuity_checks 'outgoing') -and $last.continuity_checks.outgoing.status -ne 'BOUNDARY') {
        $errors.Add('The last prompt outgoing continuity check must be BOUNDARY.')
    }
}

for ($index = 0; $index -lt ($artifacts.Count - 1); $index++) {
    $current = $artifacts[$index]
    $next = $artifacts[$index + 1]
    if (-not (Has-Property $current 'continuity_checks') -or -not (Has-Property $next 'continuity_checks')) { continue }
    if (-not (Has-Property $current.continuity_checks 'outgoing') -or -not (Has-Property $next.continuity_checks 'incoming')) { continue }

    $outgoing = $current.continuity_checks.outgoing
    $incoming = $next.continuity_checks.incoming
    if ($outgoing.status -ne 'PASS') { $errors.Add("$($current.shot_id) outgoing continuity check must be PASS.") }
    if ($incoming.status -ne 'PASS') { $errors.Add("$($next.shot_id) incoming continuity check must be PASS.") }
    if ($outgoing.neighbor_shot_id -ne $next.shot_id) { $errors.Add("$($current.shot_id) outgoing neighbor_shot_id must equal $($next.shot_id).") }
    if ($incoming.neighbor_shot_id -ne $current.shot_id) { $errors.Add("$($next.shot_id) incoming neighbor_shot_id must equal $($current.shot_id).") }

    if ((Has-Property $current 'end_state') -and (Has-Property $current.end_state 'state_id') -and @($outgoing.compared_state_ids) -notcontains $current.end_state.state_id) {
        $errors.Add("$($current.shot_id) outgoing compared_state_ids must include its end_state.state_id.")
    }
    if ((Has-Property $next 'start_state') -and (Has-Property $next.start_state 'state_id') -and @($outgoing.compared_state_ids) -notcontains $next.start_state.state_id) {
        $errors.Add("$($current.shot_id) outgoing compared_state_ids must include the next start_state.state_id.")
    }
    if ((Has-Property $current 'end_state') -and (Has-Property $current.end_state 'state_id') -and @($incoming.compared_state_ids) -notcontains $current.end_state.state_id) {
        $errors.Add("$($next.shot_id) incoming compared_state_ids must include the previous end_state.state_id.")
    }
    if ((Has-Property $next 'start_state') -and (Has-Property $next.start_state 'state_id') -and @($incoming.compared_state_ids) -notcontains $next.start_state.state_id) {
        $errors.Add("$($next.shot_id) incoming compared_state_ids must include its start_state.state_id.")
    }

    if ((Has-Property $outgoing 'handoff_signature') -and (Has-Property $incoming 'handoff_signature')) {
        if ((Get-CanonicalJson $outgoing.handoff_signature) -cne (Get-CanonicalJson $incoming.handoff_signature)) {
            $errors.Add("Handoff signature mismatch between $($current.shot_id) and $($next.shot_id).")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }
    Write-Host "[FAIL] Video prompt sequence validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] Video prompt sequence is bidirectionally connected: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
