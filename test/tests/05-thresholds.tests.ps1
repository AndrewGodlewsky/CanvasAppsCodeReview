# Task 5: overridable threshold constants
# Invokes the analyzer in __thresholds self-test mode via a child process,
# asserting both env-var override and hard-coded default behaviors.

$repo   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repo 'skills\canvas-app-analyzer\scripts\analyze-canvas.ps1'

# --- Test 1: env override is reflected in the returned thresholds ---------
[Environment]::SetEnvironmentVariable('CAA_LONG_FORMULA_BYTES', '120')
try {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '__thresholds'
    $t   = $raw | ConvertFrom-Json
} finally {
    [Environment]::SetEnvironmentVariable('CAA_LONG_FORMULA_BYTES', $null)
}
Assert-Equal $t.T_LongFormulaBytes 120 'CAA_LONG_FORMULA_BYTES env override applied'

# --- Test 2: default is returned when no override is set ------------------
# Ensure the env var is clear before this test.
[Environment]::SetEnvironmentVariable('CAA_LONG_FORMULA_BYTES', $null)
$raw2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '__thresholds'
$t2   = $raw2 | ConvertFrom-Json
Assert-Equal $t2.T_LongFormulaBytes 500 'T_LongFormulaBytes default is 500 when no override'

# --- Test 3: all nine keys are present in the output ----------------------
$expectedKeys = @(
    'T_LongFormulaBytes','T_DeepIfDepth','T_GodScreenControls','T_GodScreenBytes',
    'T_ControlTreeDepth','T_RepeatedLiteralMin','T_NearDupRatio','T_NearDupMinLen',
    'T_GlobalOveruse'
)
foreach ($key in $expectedKeys) {
    $val = $t2.PSObject.Properties[$key]
    Assert-True ($null -ne $val) "threshold key '$key' present in __thresholds output"
}

# --- Test 4: a normal analysis run (non-existent path) must NOT trigger the shim ----
# The shim must only fire when $Path -eq '__thresholds'.
$statusJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $script 'nonexistent_path_xyz'
$status = $statusJson | ConvertFrom-Json
Assert-Equal $status.status 'error' 'normal run with bad path returns status=error (shim not triggered)'
