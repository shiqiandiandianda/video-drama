[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$validatorPath = Join-Path $scriptDirectory "validate_plot_progression.ps1"
$comparatorPath = Join-Path $scriptDirectory "compare_locked_fields.ps1"
$powershellExe = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path -LiteralPath $powershellExe)) {
    $powershellExe = (Get-Command powershell -ErrorAction Stop).Source
}

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("script-plot-progression-tests-" + [guid]::NewGuid().ToString("N"))
[System.IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$testFailures = New-Object 'System.Collections.Generic.List[string]'

function New-State {
    param(
        [hashtable]$Characters = @{},
        [hashtable]$Props = @{},
        [hashtable]$Environment = @{},
        [hashtable]$Knowledge = @{}
    )
    return [ordered]@{
        characters = $Characters
        props = $Props
        environment = $Environment
        knowledge = $Knowledge
    }
}

function Write-JsonFixture {
    param($Value, [string]$FilePath)
    $json = $Value | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($FilePath, $json, $script:utf8NoBom)
}

function Read-JsonFixture {
    param([string]$FilePath)
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 100
    return $serializer.DeserializeObject((Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8))
}

function Invoke-ScriptProcess {
    param([string]$ScriptPath, [string[]]$Arguments)
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $childOutput = & $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
        $childExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    foreach ($line in @($childOutput)) {
        Write-Host $line
    }
    return [int]$childExitCode
}

function Assert-ExitCode {
    param([string]$Name, [int]$Actual, [int]$Expected)
    if ($Actual -ne $Expected) {
        $script:testFailures.Add("$Name expected exit code $Expected but received $Actual.")
    }
    else {
        Write-Host "[TEST PASS] $Name"
    }
}

try {
    $valid = [ordered]@{
        schema_version = "1.0"
        project_id = "PROJECT-TEST"
        flow_authorization_id = "FLOW-AUTH-PROJECT-TEST-0001"
        artifact_id = "PLOT-E01"
        artifact_version = "V1"
        full_id = "PLOT-E01-V1"
        source_artifact_id = "SCRIPT-E01"
        source_version = "V1"
        source_full_id = "SCRIPT-E01-V1"
        source_artifacts = @(
            [ordered]@{
                source_id = "SCRIPT-E01"
                source_type = "SCRIPT"
                version = "V1"
                scope = "E01"
                locator_type = "LINE"
                path = "episode-01.txt"
            }
        )
        status = "DRAFT"
        scope = [ordered]@{
            episode_id = "E01"
            scene_ids = @("SCENE-E01-S01")
        }
        coverage_summary = [ordered]@{
            total_story_events = 1
            covered_story_events = 1
            total_dialogue_lines = 1
            preserved_dialogue_lines = 1
        }
        source_coverage = @(
            [ordered]@{
                coverage_id = "COV-E01-0001"
                source_range = "SCRIPT-E01-V1:L1"
                content_type = "EVENT"
                source_text = "The daughter places the letter down; the father looks at it."
                covered_by = @("BEAT-E01-S01-001")
                coverage = "FULL"
                note = $null
            },
            [ordered]@{
                coverage_id = "COV-E01-0002"
                source_range = "SCRIPT-E01-V1:L2"
                content_type = "DIALOGUE"
                source_text = "Dad, I got in."
                covered_by = @("BEAT-E01-S01-001")
                coverage = "FULL"
                note = $null
            }
        )
        decision_overrides = @()
        conflicts = @()
        unknowns = @()
        scenes = @(
            [ordered]@{
                scene_id = "SCENE-E01-S01"
                scene_number = 1
                source_ranges = @("SCRIPT-E01-V1:L1-L3")
                heading = [ordered]@{
                    time = "DAY"
                    interior_exterior = "INT"
                    location = "DINING_ROOM"
                }
                characters_present = @("DAUGHTER", "FATHER")
                scene_start_state = New-State -Characters @{ "DAUGHTER" = "holds the letter"; "FATHER" = "has not seen the letter" } -Props @{ "LETTER" = "held by DAUGHTER" } -Knowledge @{ "FATHER" = "does not know the result" }
                beats = @(
                    [ordered]@{
                        beat_id = "BEAT-E01-S01-001"
                        source_ranges = @("SCRIPT-E01-V1:L1-L3")
                        source_status = "CONFIRMED"
                        start_state = New-State -Characters @{ "DAUGHTER" = "holds the letter"; "FATHER" = "has not seen the letter" } -Props @{ "LETTER" = "held by DAUGHTER" } -Knowledge @{ "FATHER" = "does not know the result" }
                        trigger = [ordered]@{
                            event = "DAUGHTER decides to reveal the result"
                            source_range = "SCRIPT-E01-V1:L1"
                        }
                        actions = @(
                            [ordered]@{
                                order = 1
                                actor = "DAUGHTER"
                                action = "places the letter in front of FATHER"
                                target = "FATHER"
                                source_range = "SCRIPT-E01-V1:L1"
                            }
                        )
                        reactions = @(
                            [ordered]@{
                                order = 3
                                actor = "FATHER"
                                reaction = "looks down at the letter"
                                source_range = "SCRIPT-E01-V1:L3"
                            }
                        )
                        dialogue = @(
                            [ordered]@{
                                order = 2
                                speaker = "DAUGHTER"
                                text = "Dad, I got in."
                                timing = "after the letter is placed"
                                source_range = "SCRIPT-E01-V1:L2"
                            }
                        )
                        emotion_change = @()
                        end_state = New-State -Characters @{ "DAUGHTER" = "waits for a response"; "FATHER" = "has seen the letter" } -Props @{ "LETTER" = "in front of FATHER" } -Knowledge @{ "FATHER" = "knows the result" }
                        continuity = [ordered]@{
                            must_carry_forward = @("The letter remains in front of FATHER")
                            open_actions = @()
                        }
                        decision_overrides = @()
                        notes = @()
                    }
                )
                scene_end_state = New-State -Characters @{ "DAUGHTER" = "waits for a response"; "FATHER" = "has seen the letter" } -Props @{ "LETTER" = "in front of FATHER" } -Knowledge @{ "FATHER" = "knows the result" }
            }
        )
        impact_scope = [ordered]@{
            changed_beats = @()
            stale_downstream = @()
        }
    }

    $validPath = Join-Path $tempDirectory "valid.json"
    Write-JsonFixture $valid $validPath
    $exitCode = Invoke-ScriptProcess $validatorPath @("-Path", $validPath)
    Assert-ExitCode "valid artifact passes structural validation" $exitCode 0

    $gated = Read-JsonFixture $validPath
    $gated["status"] = "HUMAN_GATE"
    $gated["conflicts"] = @(
        [ordered]@{
            conflict_id = "CONFLICT-E01-001"
            source_refs = @("DEC-001", "DEC-002")
            summary = "Two confirmed decisions conflict."
            affected_scope = @("SCENE-E01-S01")
            status = "UNRESOLVED"
            question = "Which decision supersedes the other?"
        }
    )
    $gated["source_coverage"] = @(
        @($gated["source_coverage"]) + @(
            [ordered]@{
                coverage_id = "COV-E01-0003"
                source_range = "SCRIPT-E01-V1:L3"
                content_type = "EVENT"
                source_text = "Blocked event."
                covered_by = @()
                coverage = "OMITTED"
                note = "Blocked by CONFLICT-E01-001."
            }
        )
    )
    $gated["coverage_summary"]["total_story_events"] = 2
    $gatedPath = Join-Path $tempDirectory "gated.json"
    Write-JsonFixture $gated $gatedPath
    $exitCode = Invoke-ScriptProcess $validatorPath @("-Path", $gatedPath)
    Assert-ExitCode "gated artifact permits tracked omitted coverage" $exitCode 0

    $ungatedOmission = Read-JsonFixture $gatedPath
    $ungatedOmission["status"] = "DRAFT"
    $ungatedOmissionPath = Join-Path $tempDirectory "ungated-omission.json"
    Write-JsonFixture $ungatedOmission $ungatedOmissionPath
    $exitCode = Invoke-ScriptProcess $validatorPath @("-Path", $ungatedOmissionPath)
    Assert-ExitCode "ungated artifact rejects omitted coverage" $exitCode 1

    $invalid = Read-JsonFixture $validPath
    $invalid["shot_id"] = "SHOT-E01-S01-001"
    $invalidPath = Join-Path $tempDirectory "invalid-shot-field.json"
    Write-JsonFixture $invalid $invalidPath
    $exitCode = Invoke-ScriptProcess $validatorPath @("-Path", $invalidPath)
    Assert-ExitCode "forbidden shot field fails structural validation" $exitCode 1

    $beforePath = Join-Path $tempDirectory "before.json"
    Copy-Item -LiteralPath $validPath -Destination $beforePath

    $after = Read-JsonFixture $validPath
    $after.artifact_version = "V2"
    $after.full_id = "PLOT-E01-V2"
    $after.scenes[0].beats[0].actions[0].action = "places the letter flat in front of FATHER"
    $after.impact_scope.changed_beats = @("BEAT-E01-S01-001")
    $afterPath = Join-Path $tempDirectory "after-allowed.json"
    Write-JsonFixture $after $afterPath

    $changeSet = [ordered]@{
        change_id = "CS-PLOT-TEST-001"
        source = "HUMAN_DIRECTOR"
        status = "CONFIRMED"
        affected_scope = @("BEAT-E01-S01-001")
        allowed_paths = @(
            "/scenes/0/beats/0/actions/0/action"
        )
        locked_fields = @(
            "/scenes/0/beats/0/reactions",
            "/scenes/0/beats/0/dialogue"
        )
        instruction = "Clarify that the document is placed flat."
    }
    $changeSetPath = Join-Path $tempDirectory "changeset.json"
    Write-JsonFixture $changeSet $changeSetPath

    $exitCode = Invoke-ScriptProcess $comparatorPath @(
        "-BeforePath", $beforePath,
        "-AfterPath", $afterPath,
        "-ChangeSetPath", $changeSetPath
    )
    Assert-ExitCode "authorized local change passes locked-field comparison" $exitCode 0

    $unauthorized = Read-JsonFixture $afterPath
    $unauthorized.scenes[0].beats[0].reactions[0].reaction = "FATHER looks up quickly"
    $unauthorizedPath = Join-Path $tempDirectory "after-unauthorized.json"
    Write-JsonFixture $unauthorized $unauthorizedPath
    $exitCode = Invoke-ScriptProcess $comparatorPath @(
        "-BeforePath", $beforePath,
        "-AfterPath", $unauthorizedPath,
        "-ChangeSetPath", $changeSetPath
    )
    Assert-ExitCode "locked and unauthorized change fails comparison" $exitCode 1
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempDirectory)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("script-plot-progression-tests-")) {
        [System.IO.Directory]::Delete($resolvedTemp, $true)
    }
}

if ($testFailures.Count -gt 0) {
    foreach ($failure in $testFailures) {
        Write-Host "[TEST FAIL] $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "[PASS] All skill script tests passed." -ForegroundColor Green
exit 0
