
$ErrorActionPreference = "Stop"
Set-Location "C:\NoC_Project"

if ((git branch --show-current).Trim() -ne "integration/adwaith-bfs") {
    throw "Wrong branch. Stopping."
}

$xvlog = "C:\AMDDesignTools\2025.2\Vivado\bin\xvlog.bat"
$xelab = "C:\AMDDesignTools\2025.2\Vivado\bin\xelab.bat"
$xsim  = "C:\AMDDesignTools\2025.2\Vivado\bin\xsim.bat"
$bfs = (Resolve-Path "rtl\routing\mesh_bfs_route.v").Path

$names = @(
    "mesh_bfs_congestion_tb",
    "mesh_bfs_fault_tb",
    "mesh_bfs_no_route_tb",
    "mesh_bfs_path_tb",
    "mesh_bfs_route_regression_tb",
    "mesh_bfs_route_tb",
    "mesh_bfs_trace_tb"
)

$root = Join-Path $env:TEMP "NoC_BFS_Verification"
New-Item -ItemType Directory -Force $root | Out-Null
$summary = @("BRANCH: $(git branch --show-current)", "LOGS: $root")

foreach ($name in $names) {
    $tb = (Resolve-Path "tb\$name.v").Path
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    Push-Location $dir

    try {
        & $xvlog $bfs $tb *> compile.log
        $c = $LASTEXITCODE

        if ($c -ne 0) {
            $summary += "$name : COMPILE FAILED ($c)"
            $summary += (Get-Content compile.log | Select-Object -Last 5)
            continue
        }

        & $xelab $name -s "sim_$name" *> elaborate.log
        $e = $LASTEXITCODE

        if ($e -ne 0) {
            $summary += "$name : ELABORATION FAILED ($e)"
            $summary += (Get-Content elaborate.log | Select-Object -Last 5)
            continue
        }

        & $xsim "sim_$name" -runall *> simulation.log
        $s = $LASTEXITCODE
        $summary += "$name : xsim exit code $s"
        $summary += (Get-Content simulation.log |
            Select-String -Pattern 'PASS|FAIL|ERROR|FATAL|failure|failures|checks|PASSED|route' |
            ForEach-Object { $_.Line } | Select-Object -Last 8)

        if ($s -ne 0) {
            $summary += "Inspect: $dir\simulation.log"
        }
    }
    finally {
        Pop-Location
    }
}

$summary += "===== GIT STATUS ====="
$summary += (git status --short --branch)
Set-Clipboard -Value ($summary -join "`r`n")
Write-Host "Finished. Summary copied to clipboard."
Write-Host "Logs: $root"
