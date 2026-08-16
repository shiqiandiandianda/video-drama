[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BeforePath,

    [Parameter(Mandatory = $true)]
    [string]$AfterPath,

    [Parameter(Mandatory = $true)]
    [string]$ChangeSetPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$errors = New-Object 'System.Collections.Generic.List[string]'

function Add-ComparisonError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Test-HasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.PSObject.Methods.Name -contains "ContainsKey") {
            return $Object.ContainsKey($Name)
        }
        return $Object.Contains($Name)
    }
    return $Object.PSObject.Properties.Name -contains $Name
}

function Read-JsonFile {
    param([string]$FilePath, [string]$Label)
    try {
        $resolved = (Resolve-Path -LiteralPath $FilePath).Path
        $raw = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
        Add-Type -AssemblyName System.Web.Extensions
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        $serializer.RecursionLimit = 100
        return $serializer.DeserializeObject($raw)
    }
    catch {
        Write-Error "$Label is missing or invalid JSON: $($_.Exception.Message)"
        exit 2
    }
}

function ConvertTo-JsonPointerSegment {
    param([string]$Value)
    return $Value.Replace("~", "~0").Replace("/", "~1")
}

function Add-FlattenedValues {
    param(
        $Value,
        [string]$Pointer,
        [hashtable]$Map
    )

    if ($null -eq $Value) {
        $Map[$Pointer] = "__NULL__"
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($keys.Count -eq 0) {
            $Map[$Pointer] = "__EMPTY_OBJECT__"
            return
        }
        foreach ($key in $keys) {
            $segment = ConvertTo-JsonPointerSegment ([string]$key)
            Add-FlattenedValues $Value[$key] "$Pointer/$segment" $Map
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        $properties = @($Value.PSObject.Properties)
        if ($properties.Count -eq 0) {
            $Map[$Pointer] = "__EMPTY_OBJECT__"
            return
        }
        foreach ($property in $properties) {
            $segment = ConvertTo-JsonPointerSegment $property.Name
            Add-FlattenedValues $property.Value "$Pointer/$segment" $Map
        }
        return
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            $Map[$Pointer] = "__EMPTY_ARRAY__"
            return
        }
        for ($i = 0; $i -lt $items.Count; $i++) {
            Add-FlattenedValues $items[$i] "$Pointer/$i" $Map
        }
        return
    }

    $Map[$Pointer] = $Value | ConvertTo-Json -Compress
}

function Test-PointerWithin {
    param([string]$Candidate, [string]$Container)
    if ($Container -eq "") { return $false }
    if ($Candidate -eq $Container) { return $true }
    return $Candidate.StartsWith("$Container/", [System.StringComparison]::Ordinal)
}

function Test-PointerAllowed {
    param([string]$Candidate, [string[]]$AllowedPaths)
    foreach ($allowed in $AllowedPaths) {
        if (Test-PointerWithin $Candidate $allowed) { return $true }
    }
    return $false
}

function Get-VersionNumber {
    param([string]$Version)
    if ($Version -notmatch '^V([1-9][0-9]*)$') { return $null }
    return [int]$Matches[1]
}

$before = Read-JsonFile $BeforePath "Before artifact"
$after = Read-JsonFile $AfterPath "After artifact"
$changeSet = Read-JsonFile $ChangeSetPath "ChangeSet or RepairTicket"

foreach ($artifact in @($before, $after)) {
    foreach ($required in @("artifact_id", "artifact_version", "full_id")) {
        if (-not (Test-HasProperty $artifact $required)) {
            Add-ComparisonError "Both artifacts must contain '$required'."
        }
    }
}

if ((Test-HasProperty $before "artifact_id") -and (Test-HasProperty $after "artifact_id") -and $before.artifact_id -ne $after.artifact_id) {
    Add-ComparisonError "artifact_id changed from '$($before.artifact_id)' to '$($after.artifact_id)'."
}

if ((Test-HasProperty $before "artifact_version") -and (Test-HasProperty $after "artifact_version")) {
    $beforeVersion = Get-VersionNumber $before.artifact_version
    $afterVersion = Get-VersionNumber $after.artifact_version
    if ($null -eq $beforeVersion -or $null -eq $afterVersion) {
        Add-ComparisonError "artifact_version must match V<number> in both artifacts."
    }
    elseif ($afterVersion -ne ($beforeVersion + 1)) {
        Add-ComparisonError "After artifact version must increment exactly once."
    }
}

if ((Test-HasProperty $after "artifact_id") -and (Test-HasProperty $after "artifact_version") -and (Test-HasProperty $after "full_id")) {
    $expectedFullId = "$($after.artifact_id)-$($after.artifact_version)"
    if ($after.full_id -ne $expectedFullId) {
        Add-ComparisonError "After full_id must equal '$expectedFullId'."
    }
}

$allowedPaths = @()
$lockedPaths = @()
if (Test-HasProperty $changeSet "allowed_paths") {
    if ($changeSet.allowed_paths -isnot [System.Array]) {
        Add-ComparisonError "allowed_paths must be a JSON array."
    }
    else {
        $allowedPaths = @($changeSet.allowed_paths)
    }
}
else {
    Add-ComparisonError "ChangeSet or RepairTicket must contain allowed_paths."
}

if (Test-HasProperty $changeSet "locked_fields") {
    if ($changeSet.locked_fields -isnot [System.Array]) {
        Add-ComparisonError "locked_fields must be a JSON array."
    }
    else {
        $lockedPaths = @($changeSet.locked_fields)
    }
}
else {
    Add-ComparisonError "ChangeSet or RepairTicket must contain locked_fields."
}

if ((Test-HasProperty $changeSet "status") -and $changeSet.status -ne "CONFIRMED") {
    Add-ComparisonError "A ChangeSet must have status CONFIRMED."
}
if ((Test-HasProperty $changeSet "verdict") -and $changeSet.verdict -ne "REPAIR") {
    Add-ComparisonError "A RepairTicket must have verdict REPAIR."
}
if (-not (Test-HasProperty $changeSet "status") -and -not (Test-HasProperty $changeSet "verdict")) {
    Add-ComparisonError "Input must be a CONFIRMED ChangeSet or REPAIR ticket."
}

foreach ($pointer in @($allowedPaths + $lockedPaths)) {
    if (($pointer -isnot [string]) -or -not $pointer.StartsWith("/")) {
        Add-ComparisonError "JSON Pointer paths must start with '/': $pointer"
    }
}

$automaticPaths = @(
    "/artifact_version",
    "/full_id",
    "/status",
    "/impact_scope"
)
$allAllowedPaths = @($allowedPaths + $automaticPaths | Sort-Object -Unique)

$beforeMap = @{}
$afterMap = @{}
Add-FlattenedValues $before "" $beforeMap
Add-FlattenedValues $after "" $afterMap

$allKeys = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
$changedPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($key in $allKeys) {
    $beforeContains = $beforeMap.ContainsKey($key)
    $afterContains = $afterMap.ContainsKey($key)
    if (-not $beforeContains -or -not $afterContains -or $beforeMap[$key] -cne $afterMap[$key]) {
        $changedPaths.Add($key)
    }
}

foreach ($changedPath in $changedPaths) {
    foreach ($lockedPath in $lockedPaths) {
        if (Test-PointerWithin $changedPath $lockedPath) {
            Add-ComparisonError "Locked field changed: $changedPath (locked by $lockedPath)."
            break
        }
    }
    if (-not (Test-PointerAllowed $changedPath $allAllowedPaths)) {
        Add-ComparisonError "Unauthorized field changed: $changedPath."
    }
}

if ($changedPaths.Count -eq 0) {
    Add-ComparisonError "No changes were detected between versions."
}

if ($errors.Count -gt 0) {
    foreach ($comparisonError in $errors) {
        Write-Host "[ERROR] $comparisonError" -ForegroundColor Red
    }
    Write-Host "[FAIL] Locked-field comparison failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] Only authorized fields changed ($($changedPaths.Count) leaf value(s))." -ForegroundColor Green
foreach ($changedPath in $changedPaths) {
    Write-Host "[CHANGED] $changedPath"
}
exit 0
