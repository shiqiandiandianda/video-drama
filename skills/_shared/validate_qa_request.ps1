[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$errors = [System.Collections.Generic.List[string]]::new()
function Has-Property($Object, [string]$Name) { return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] }

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Error "QA request not found: $Path"; exit 2 }
try { $request = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
catch { Write-Error "Invalid JSON: $($_.Exception.Message)"; exit 2 }

foreach ($field in @('qa_mode','artifact','approved_upstream','project_constraints','change_set','previous_version')) { if (-not (Has-Property $request $field)) { $errors.Add("root.$field is required.") } }
if ((Has-Property $request 'qa_mode') -and @('PLOT','STORYBOARD_TABLE','STORYBOARD_PROMPT','STORYBOARD_IMAGE','VIDEO_PROMPT') -notcontains $request.qa_mode) { $errors.Add('root.qa_mode is invalid.') }
if ((Has-Property $request 'artifact') -and $null -eq $request.artifact) { $errors.Add('root.artifact must contain the complete current artifact.') }
if ((Has-Property $request 'approved_upstream') -and -not ($request.approved_upstream -is [System.Array])) { $errors.Add('root.approved_upstream must be an array.') }
if ((Has-Property $request 'project_constraints') -and $null -eq $request.project_constraints) { $errors.Add('root.project_constraints must be an object; use an empty object when no constraints apply.') }

if ($errors.Count -gt 0) { foreach ($validationError in $errors) { Write-Host "[ERROR] $validationError" -ForegroundColor Red }; Write-Host "[FAIL] QA request validation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "[PASS] QA request is valid: $((Resolve-Path -LiteralPath $Path).Path)" -ForegroundColor Green
exit 0
