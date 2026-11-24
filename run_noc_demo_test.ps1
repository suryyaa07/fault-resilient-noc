param(
    [int]$Source = 0,
    [int]$Destination = 3,
    [int]$FaultA = 1,
    [int]$FaultB = 2
)

$ErrorActionPreference = "Stop"
$repo = "C:\NoC_Project"
$vivado = "C:\AMDDesignTools\2025.2\Vivado\bin"
$work = Join-Path $env:TEMP "NoC_Fault_Reroute_Demo"

foreach ($id in @($Source, $Destination, $FaultA, $FaultB)) {
    if ($id -lt 0 -or $id -gt 15) { throw "Router IDs must be between 0 and 15." }
}

$distance = [Math]::Abs(($FaultA % 4) - ($FaultB % 4)) +
            [Math]::Abs([Math]::Floor($FaultA / 4) - [Math]::Floor($FaultB / 4))
if ($distance -ne 1) { throw "Fault endpoints must be neighboring routers in the 4x4 mesh." }
if ($Source -eq $Destination) { throw "Choose different source and destination routers for this demo." }

New-Item -ItemType Directory -Force -Path $work | Out-Null
Set-Location $work

$rtlFiles = @(Get-ChildItem "$repo\rtl" -Recurse -Filter "*.v" | ForEach-Object { $_.FullName })
$tbTemplatePath = "$repo\tb\noc_fault_reroute_demo_tb.v"
$tbTemplate = [System.IO.File]::ReadAllText($tbTemplatePath)

$tbTemplate = $tbTemplate.Replace('reg [3:0] fault_router_a = 1;', "reg [3:0] fault_router_a = $FaultA;")
$tbTemplate = $tbTemplate.Replace('reg [3:0] fault_router_b = 2;', "reg [3:0] fault_router_b = $FaultB;")
$tbTemplate = $tbTemplate.Replace('integer source_router = 0;', "integer source_router = $Source;")
$tbTemplate = $tbTemplate.Replace('integer dest_router = 3;', "integer dest_router = $Destination;")

# Remove runtime plus-argument parsing; values are configured above.
$tbTemplate = [regex]::Replace($tbTemplate, '(?m)^\s*if \(!\$value\$plusargs.*\r?\n', '')

$tbFile = "$work\noc_fault_reroute_demo_tb.v"
[System.IO.File]::WriteAllText($tbFile, $tbTemplate, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n=== COMPILE ===" -ForegroundColor Yellow
& "$vivado\xvlog.bat" -work work @rtlFiles $tbFile 2>&1 | Tee-Object "$work\compile.log"
if ($LASTEXITCODE -ne 0) { throw "Compilation failed. See $work\compile.log" }

Write-Host "`n=== ELABORATE ===" -ForegroundColor Yellow
& "$vivado\xelab.bat" noc_fault_reroute_demo_tb -s noc_fault_reroute_demo_sim 2>&1 | Tee-Object "$work\elaboration.log"
if ($LASTEXITCODE -ne 0) { throw "Elaboration failed. See $work\elaboration.log" }

Write-Host "`n=== SIMULATE ===" -ForegroundColor Yellow
& "$vivado\xsim.bat" noc_fault_reroute_demo_sim -runall 2>&1 | Tee-Object "$work\simulation.log"

if ($LASTEXITCODE -ne 0) { throw "Simulation process failed. See $work\simulation.log" }
if (-not (Select-String -Path "$work\simulation.log" -SimpleMatch "ALL FAULT REROUTING TESTS PASSED")) {
    throw "Simulation did not report success. See $work\simulation.log"
}
if (Select-String -Path "$work\simulation.log" -SimpleMatch "FAIL:") {
    throw "Simulation reported a failure. See $work\simulation.log"
}

Write-Host "`nDEMO SIMULATION PASSED" -ForegroundColor Green
Write-Host "Logs: $work"