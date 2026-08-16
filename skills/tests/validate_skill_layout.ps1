[CmdletBinding()]
param(
    [string]$SkillsRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
if ([string]::IsNullOrWhiteSpace($SkillsRoot)) { $SkillsRoot = Split-Path -Parent $PSScriptRoot }
$resolvedRoot = [IO.Path]::GetFullPath($SkillsRoot)
$skillDirectories = @(Get-ChildItem -LiteralPath $resolvedRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') })

if ($skillDirectories.Count -eq 0) { $errors.Add('No skill directories were found.') }
foreach ($directory in $skillDirectories) {
    $skillPath = Join-Path $directory.FullName 'SKILL.md'
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $skillPath
    if ($content -notmatch '(?s)^---\r?\nname:\s*([a-z0-9-]+)\r?\ndescription:\s*(.+?)\r?\n---') {
        $errors.Add("$($directory.Name): invalid or unsupported frontmatter.")
        continue
    }
    $name = $Matches[1]
    $description = $Matches[2].Trim()
    if ($name -ne $directory.Name) { $errors.Add("$($directory.Name): frontmatter name must match folder name.") }
    if ($name.Length -gt 64 -or $name.StartsWith('-') -or $name.EndsWith('-') -or $name.Contains('--')) { $errors.Add("${name}: invalid skill name.") }
    if ([string]::IsNullOrWhiteSpace($description) -or $description.Length -gt 1024 -or $description -match '[<>]') { $errors.Add("${name}: invalid description.") }
    foreach ($link in [regex]::Matches($content,'\]\(([^)#]+)')) {
        $target = $link.Groups[1].Value
        if ($target -match '^(https?:|mailto:)') { continue }
        $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $directory.FullName $target))
        if (-not (Test-Path -LiteralPath $resolvedTarget)) { $errors.Add("${name}: missing direct reference $target") }
    }
    $agentMetadata = Join-Path $directory.FullName 'agents\openai.yaml'
    if (-not (Test-Path -LiteralPath $agentMetadata -PathType Leaf)) { $errors.Add("${name}: agents/openai.yaml is missing.") }
}

$workspaceRoot = Split-Path -Parent $resolvedRoot
$rootLevelSkills = @(Get-ChildItem -LiteralPath $workspaceRoot -Directory | Where-Object { $_.FullName -ne $resolvedRoot -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) })
foreach ($rootSkill in $rootLevelSkills) { $errors.Add("Skill remains outside skills/: $($rootSkill.FullName)") }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; exit 1 }
foreach ($directory in $skillDirectories) { Write-Host "[PASS] $($directory.Name)" -ForegroundColor Green }
Write-Host '[PASS] Skill layout, metadata, direct references, and placement are valid.' -ForegroundColor Green
exit 0
