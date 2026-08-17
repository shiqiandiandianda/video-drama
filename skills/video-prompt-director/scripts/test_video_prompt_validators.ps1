[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('video-prompt-validator-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()
$bodyValidator = Join-Path $PSScriptRoot 'validate_body.ps1'
$sequenceValidator = Join-Path $PSScriptRoot 'validate_prompt_sequence.ps1'

function Write-Text([string]$Name, [string]$Content) {
    $path = Join-Path $script:tempRoot $Name
    [IO.File]::WriteAllText($path, $Content, $script:utf8NoBom)
    return $path
}

function Write-Json([string]$Name, $Value) {
    return Write-Text $Name ($Value | ConvertTo-Json -Depth 50)
}

function Invoke-Expected([string]$Name, [string]$ScriptPath, [string[]]$Arguments, [int]$ExpectedExitCode) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Host $line }
    if ($exitCode -ne $ExpectedExitCode) {
        $script:failures.Add("$Name expected exit $ExpectedExitCode but received $exitCode.")
    }
    else {
        Write-Host "[TEST PASS] $Name" -ForegroundColor Green
    }
}

try {
    $secondsUnit = [char]0x79D2
    $emDash = [char]0x2014
    $body20 = @(
        'References: HEROINE{{Mixed 1}}, LIVING_ROOM{{Mixed 2}}.'
        ''
        "【镜头1｜0${emDash}5${secondsUnit}】HEROINE walks to the table and settles."
        "【镜头2｜5${emDash}15${secondsUnit}】She looks at the letter and settles her breath and gaze."
    ) -join "`n"
    $body20Path = Write-Text 'body-20.txt' $body20
    Invoke-Expected 'Seedance 2.0 accepts Mixed slots and exactly 15 seconds' $bodyValidator @('-BodyPath',$body20Path,'-MaxChars','0','-ExpectedDurationSeconds','15') 0

    $body25 = @(
        'References: HEROINE{{Mixed 1}}, PURSUER{{Mixed 2}}, RAINY_ALLEY{{Mixed 3}}.'
        ''
        "【镜头1｜0${emDash}10${secondsUnit}】HEROINE runs through the alley while PURSUER holds distance."
        "【镜头2｜10${emDash}30${secondsUnit}】Their motion and breath continue to a stable corner landing."
    ) -join "`n"
    $body25Path = Write-Text 'body-25.txt' $body25
    Invoke-Expected 'Seedance 2.5 accepts Mixed slots and exactly 30 seconds' $bodyValidator @('-BodyPath',$body25Path,'-MaxChars','5000','-ExpectedDurationSeconds','30') 0

    $noSlotPath = Write-Text 'body-no-slot.txt' "References: HEROINE.`n`n【镜头1｜0${emDash}15${secondsUnit}】HEROINE maintains natural motion."
    Invoke-Expected 'Body without a Mixed slot is rejected' $bodyValidator @('-BodyPath',$noSlotPath,'-ExpectedDurationSeconds','15') 1

    $slotGapPath = Write-Text 'body-slot-gap.txt' "References: HEROINE{{Mixed 1}}, LIVING_ROOM{{Mixed 3}}.`n`n【镜头1｜0${emDash}15${secondsUnit}】HEROINE maintains natural motion."
    Invoke-Expected 'Body with a Mixed slot gap is rejected' $bodyValidator @('-BodyPath',$slotGapPath,'-ExpectedDurationSeconds','15') 1

    $wrongDurationPath = Write-Text 'body-wrong-duration.txt' "References: HEROINE{{Mixed 1}}.`n`n【镜头1｜0${emDash}14${secondsUnit}】HEROINE maintains natural motion."
    Invoke-Expected 'Seedance 2.0 body ending before 15 seconds is rejected' $bodyValidator @('-BodyPath',$wrongDurationPath,'-ExpectedDurationSeconds','15') 1

    $handoff = [ordered]@{
        characters=@([ordered]@{ name='HEROINE'; position='DOOR_WEST'; action_stage='RECOVERY'; breath='FAST' })
        props=@([ordered]@{ name='LETTER'; owner='HEROINE'; hand='RIGHT'; state='INTACT' })
        spatial_world=@('HEROINE_WEST_OF_TABLE')
        camera='FIXED_EYE_LEVEL'
        lighting='WINDOW_KEY_LEFT'
        sound='ROOM_TONE_CONTINUES'
    }
    $checkedFields = @('CHARACTERS','PROPS','SPATIAL_WORLD','CAMERA','LIGHTING','SOUND')
    $sequence = [ordered]@{ artifacts=@(
        [ordered]@{
            segment_id='SEG-E01-001'; start_state=[ordered]@{ state_id='SS-E01-001-V1' }; final_state=[ordered]@{ state_id='PE-E01-001-V1' }
            continuity_checks=[ordered]@{
                window=2
                incoming=[ordered]@{ status='BOUNDARY'; neighbor_segment_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$handoff; boundary_reason='PROJECT_START' }
                outgoing=[ordered]@{ status='PASS'; neighbor_segment_id='SEG-E01-002'; compared_state_ids=@('PE-E01-001-V1','SS-E01-002-V1'); checked_fields=$checkedFields; mismatches=@(); handoff_signature=$handoff; boundary_reason=$null }
                window_checks=@()
            }
        },
        [ordered]@{
            segment_id='SEG-E01-002'; start_state=[ordered]@{ state_id='SS-E01-002-V1' }; final_state=[ordered]@{ state_id='PE-E01-002-V1' }
            continuity_checks=[ordered]@{
                window=2
                incoming=[ordered]@{ status='PASS'; neighbor_segment_id='SEG-E01-001'; compared_state_ids=@('PE-E01-001-V1','SS-E01-002-V1'); checked_fields=$checkedFields; mismatches=@(); handoff_signature=$handoff; boundary_reason=$null }
                outgoing=[ordered]@{ status='BOUNDARY'; neighbor_segment_id=$null; compared_state_ids=@(); checked_fields=@(); mismatches=@(); handoff_signature=$handoff; boundary_reason='PROJECT_END' }
                window_checks=@()
            }
        }
    ) }
    $sequencePath = Write-Json 'sequence.json' $sequence
    Invoke-Expected 'Bidirectional adjacent handoff passes' $sequenceValidator @('-Path',$sequencePath) 0

    $brokenSequence = $sequence | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $brokenSequence.artifacts[1].continuity_checks.incoming.handoff_signature.sound = 'SILENCE'
    $brokenSequencePath = Write-Json 'sequence-broken.json' $brokenSequence
    Invoke-Expected 'Mismatched adjacent handoff is rejected' $sequenceValidator @('-Path',$brokenSequencePath) 1
}
finally {
    if ((Test-Path -LiteralPath $tempRoot) -and ([IO.Path]::GetFullPath($tempRoot)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($tempRoot, $true)
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "[TEST FAIL] $failure" -ForegroundColor Red }
    exit 1
}
Write-Host '[PASS] All video prompt validator tests passed.' -ForegroundColor Green
exit 0
