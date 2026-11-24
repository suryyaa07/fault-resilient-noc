$ErrorActionPreference = "Stop"

$repo = "C:\NoC_Project"
$vivado = "C:\AMDDesignTools\2025.2\Vivado\bin"
$work = Join-Path $env:TEMP "NoC_Fault_Reroute_Test"

New-Item -ItemType Directory -Force -Path $work | Out-Null
Set-Location $work

$rtlFiles = @(
    Get-ChildItem "$repo\rtl" -Recurse -Filter "*.v" |
    ForEach-Object { $_.FullName }
)
$tbFile = "$repo\tb\noc_fault_reroute_tb.v"

Write-Host "`n=== COMPILE ===" -ForegroundColor Yellow
& "$vivado\xvlog.bat" -work work @rtlFiles $tbFile 2>&1 |
    Tee-Object "$work\compile.log"

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed. See $work\compile.log"
}

Write-Host "`n=== ELABORATE ===" -ForegroundColor Yellow
& "$vivado\xelab.bat" noc_fault_reroute_tb -s noc_fault_reroute_sim 2>&1 |
    Tee-Object "$work\elaboration.log"

if ($LASTEXITCODE -ne 0) {
    throw "Elaboration failed. See $work\elaboration.log"
}

Write-Host "`n=== SIMULATE ===" -ForegroundColor Yellow
& "$vivado\xsim.bat" noc_fault_reroute_sim -runall 2>&1 |
    Tee-Object "$work\simulation.log"

if ($LASTEXITCODE -ne 0) {
    throw "Simulation process failed. See $work\simulation.log"
}

$pass = Select-String -Path "$work\simulation.log" `
    -SimpleMatch "ALL FAULT REROUTING TESTS PASSED"

$fail = Select-String -Path "$work\simulation.log" `
    -SimpleMatch "FAIL:"

if (-not $pass -or $fail) {
    throw "Fault-rerouting verification failed. See $work\simulation.log"
}

Write-Host "`nFAULT REROUTING VERIFICATION PASSED" -ForegroundColor Green
Write-Host "Logs: $work"