
$ErrorActionPreference = "Stop"

$repo = "C:\NoC_Project"
$vivado = "C:\AMDDesignTools\2025.2\Vivado\bin"
$work = Join-Path $env:TEMP "NoC_Router_PostPatch"
$log = Join-Path $env:TEMP "NoC_Router_PostPatch.log"

Set-Location $repo

if ((git branch --show-current).Trim() -ne "integration/adwaith-bfs") {
    throw "Wrong branch. Stop without running tests."
}

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim  = Join-Path $vivado "xsim.bat"

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (!(Test-Path $tool)) {
        throw "Vivado tool not found: $tool"
    }
}

$tb = Join-Path $repo "tb\router_5port_tb.v"
$router = Join-Path $repo "rtl\router\router_5port.v"
$route = Join-Path $repo "rtl\routing\mesh_bfs_route.v"

foreach ($file in @($tb, $router, $route)) {
    if (!(Test-Path $file)) {
        throw "Required source file not found: $file"
    }
}

$tbText = Get-Content -LiteralPath $tb -Raw
$topMatch = [regex]::Match($tbText, '(?m)^\s*module\s+([A-Za-z_]\w*)')

if (!$topMatch.Success) {
    throw "Could not identify the testbench module name."
}

$top = $topMatch.Groups[1].Value

if (Test-Path $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Path $work | Out-Null

$allRtl = @(
    Get-ChildItem (Join-Path $repo "rtl") -Recurse -File -Filter "*.v" |
    ForEach-Object { $_.FullName }
)

$compileSources = @($allRtl) + @($tb)
$results = [System.Collections.Generic.List[string]]::new()

Push-Location $work
try {
    $results.Add("===== ROUTER POST-PATCH REGRESSION =====")
    $results.Add("Branch: $(git -C $repo branch --show-current)")
    $results.Add("Testbench: $top")
    $results.Add("")

    $results.Add("===== COMPILE =====")
    $compileOutput = & $xvlog -work work @compileSources 2>&1
    $compileExit = $LASTEXITCODE
    $results.AddRange([string[]]@($compileOutput | ForEach-Object { "$_" }))

    if ($compileExit -ne 0) {
        $results.Add("COMPILE RESULT: FAIL (exit $compileExit)")
        throw "Compilation failed. See copied log."
    }

    $results.Add("COMPILE RESULT: PASS")
    $results.Add("")

    $results.Add("===== ELABORATION =====")
    $elabOutput = & $xelab -debug typical $top -s router_post_patch_sim 2>&1
    $elabExit = $LASTEXITCODE
    $results.AddRange([string[]]@($elabOutput | ForEach-Object { "$_" }))

    if ($elabExit -ne 0) {
        $results.Add("ELABORATION RESULT: FAIL (exit $elabExit)")
        throw "Elaboration failed. See copied log."
    }

    $results.Add("ELABORATION RESULT: PASS")
    $results.Add("")

    $results.Add("===== SIMULATION =====")
    $simOutput = & $xsim router_post_patch_sim -runall 2>&1
    $simExit = $LASTEXITCODE
    $results.AddRange([string[]]@($simOutput | ForEach-Object { "$_" }))

    if ($simExit -ne 0) {
        $results.Add("SIMULATION RESULT: FAIL (exit $simExit)")
    } else {
        $results.Add("SIMULATION PROCESS EXIT: 0")
        $results.Add("Review testbench output above for PASS/FAIL assertions.")
    }
}
finally {
    Pop-Location
}

$results | Set-Content -LiteralPath $log
$summary = Get-Content -LiteralPath $log -Raw
Set-Clipboard -Value $summary
Write-Host $summary
Write-Host "`nFull log: $log"
