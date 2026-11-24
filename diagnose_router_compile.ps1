
$ErrorActionPreference = "Stop"

$repo = "C:\NoC_Project"
$vivado = "C:\AMDDesignTools\2025.2\Vivado\bin"
$work = Join-Path $env:TEMP "NoC_Router_Compile_Diagnostics"
$log = Join-Path $env:TEMP "NoC_Router_Compile_Diagnostics.txt"

Set-Location $repo

if ((git branch --show-current).Trim() -ne "integration/adwaith-bfs") {
    throw "Wrong branch. No compilation performed."
}

$xvlog = Join-Path $vivado "xvlog.bat"
if (!(Test-Path $xvlog)) {
    throw "Cannot find Vivado xvlog: $xvlog"
}

if (Test-Path $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Path $work | Out-Null

$rtl = @(
    Get-ChildItem (Join-Path $repo "rtl") -Recurse -File -Filter "*.v" |
    ForEach-Object { $_.FullName }
)

$tb = Join-Path $repo "tb\router_5port_tb.v"

if (!(Test-Path $tb)) {
    throw "Router testbench not found: $tb"
}

Push-Location $work
try {
    $output = @(
        "===== ROUTER COMPILATION DIAGNOSTICS ====="
        "Branch: $(git -C $repo branch --show-current)"
        "Testbench: $tb"
        "RTL Verilog files: $($rtl.Count)"
        ""
        "===== XVLOG OUTPUT ====="
    )

    $compilerOutput = & $xvlog -work work @rtl $tb 2>&1
    $compileExit = $LASTEXITCODE

    $output += @($compilerOutput | ForEach-Object { "$_" })
    $output += ""
    $output += "XVLOG EXIT CODE: $compileExit"

    $output | Set-Content -LiteralPath $log

    Write-Host (Get-Content -LiteralPath $log -Raw)
    Set-Clipboard -Value (Get-Content -LiteralPath $log -Raw)
    Write-Host "`nDiagnostics saved and copied to clipboard."
    Write-Host "Log path: $log"
}
finally {
    Pop-Location
}
