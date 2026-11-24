
$ErrorActionPreference = "Stop"
Set-Location "C:\NoC_Project"

# Safety check: only work on the experimental branch.
$branch = (git branch --show-current).Trim()
if ($branch -ne "integration/adwaith-bfs") {
    throw "Wrong branch '$branch'. No changes made."
}

$path = "rtl\router\router_5port.v"
$text = Get-Content -LiteralPath $path -Raw
$text = $text -replace "`r`n", "`n"
$original = $text

# ------------------------------------------------------------
# 1. Find the router module declaration without relying on
#    its exact whitespace or line formatting.
# ------------------------------------------------------------

$headerPattern = '(?s)module\s+router_5port\s*#\s*\((.*?)\)\s*\((.*?)\)\s*;'
$header = [regex]::Match($text, $headerPattern)

if (!$header.Success) {
    throw "Could not safely identify the router module declaration. No file written."
}

$params = $header.Groups[1].Value
$ports  = $header.Groups[2].Value

if ($params -match '\bADAPTIVE_ROUTING\b' -or
    $ports -match '\blink_up_map\b' -or
    $ports -match '\bcongestion_map\b') {
    throw "Adaptive-routing changes may already exist. No file written."
}

# Add the optional parameter.
$params = $params.TrimEnd()
if ($params -notmatch ',\s*$') {
    $params += ","
}
$params += "`n    parameter ADAPTIVE_ROUTING = 0`n"

# Add the routing-map inputs immediately after the reset input.
$rstPattern = '(?im)(input\s+(?:wire\s+)?rst\s*,)'
$rstMatch = [regex]::Matches($ports, $rstPattern)

if ($rstMatch.Count -ne 1) {
    throw "Expected exactly one reset input in the router header. No file written."
}

$ports = [regex]::Replace(
    $ports,
    $rstPattern,
    ('$1' + "`n    input wire [63:0] link_up_map,`n    input wire [127:0] congestion_map,"),
    1
)

$newHeader = "module router_5port #(`n$params`n)(`n$ports`n);"

$text = $text.Substring(0, $header.Index) +
        $newHeader +
        $text.Substring($header.Index + $header.Length)

# ------------------------------------------------------------
# 2. Prepare the remaining three changes.
#    Each source section must match exactly once.
# ------------------------------------------------------------

$old2 = @'
    wire advance;
'@

$new2 = @'
    wire advance;
    wire [2:0] adaptive_port;
    wire adaptive_route_valid;
    wire adaptive_destination_reached;
'@

$old3 = @'
    genvar p;
'@

$new3 = @'
    generate
        if (ADAPTIVE_ROUTING != 0) begin : ADAPTIVE_ROUTER_ROUTE
            mesh_bfs_route route_inst (
                .current_router(ROUTER_ID),
                .dest_router(selected_packet[51:48]),
                .link_up_map(link_up_map),
                .congestion_map(congestion_map),
                .next_port(adaptive_port),
                .route_valid(adaptive_route_valid),
                .destination_reached(adaptive_destination_reached)
            );
        end else begin : FIXED_ROUTER_ROUTE
            assign adaptive_port = 3'd4;
            assign adaptive_route_valid = 1'b0;
            assign adaptive_destination_reached = 1'b0;
        end
    endgenerate

    genvar p;
'@

$old4 = @'
        selected_out = 5'b00000;

        if (|grant) begin
            if (dest_x > here_x)
                selected_out[2] = 1'b1;
            else if (dest_x < here_x)
                selected_out[3] = 1'b1;
            else if (dest_y > here_y)
                selected_out[1] = 1'b1;
            else if (dest_y < here_y)
                selected_out[0] = 1'b1;
            else
                selected_out[4] = 1'b1;
        end
'@

$new4 = @'
        selected_out = 5'b00000;

        if (|grant) begin
            if (ADAPTIVE_ROUTING != 0) begin
                if (adaptive_route_valid) begin
                    case (adaptive_port)
                        3'd0: selected_out[0] = 1'b1;
                        3'd1: selected_out[1] = 1'b1;
                        3'd2: selected_out[2] = 1'b1;
                        3'd3: selected_out[3] = 1'b1;
                        3'd4: selected_out[4] = 1'b1;
                        default: selected_out = 5'b00000;
                    endcase
                end
            end else begin
                if (dest_x > here_x)
                    selected_out[2] = 1'b1;
                else if (dest_x < here_x)
                    selected_out[3] = 1'b1;
                else if (dest_y > here_y)
                    selected_out[1] = 1'b1;
                else if (dest_y < here_y)
                    selected_out[0] = 1'b1;
                else
                    selected_out[4] = 1'b1;
            end
        end
'@

$replacements = @(
    @{ Old = $old2; New = $new2; Name = "adaptive route wires" },
    @{ Old = $old3; New = $new3; Name = "route selector instance" },
    @{ Old = $old4; New = $new4; Name = "output route selection" }
)

foreach ($r in $replacements) {
    $old = $r.Old -replace "`r`n", "`n"
    $new = $r.New -replace "`r`n", "`n"

    $count = [regex]::Matches(
        $text,
        [regex]::Escape($old)
    ).Count

    if ($count -ne 1) {
        throw "Expected exactly one match for '$($r.Name)', found $count. No file written."
    }

    $text = $text.Replace($old, $new)
}

# ------------------------------------------------------------
# 3. Validate all expected changes before touching the file.
# ------------------------------------------------------------

$required = @(
    'parameter ADAPTIVE_ROUTING = 0',
    'input wire [63:0] link_up_map',
    'input wire [127:0] congestion_map',
    'mesh_bfs_route route_inst',
    'if (ADAPTIVE_ROUTING != 0)',
    'wire [2:0] adaptive_port'
)

foreach ($item in $required) {
    if (!$text.Contains($item)) {
        throw "Validation failed: missing '$item'. Original file unchanged."
    }
}

# Ensure fixed XY routing is still present.
if (!$text.Contains('if (dest_x > here_x)')) {
    throw "Fixed XY route logic was not found. Original file unchanged."
}

# ------------------------------------------------------------
# 4. Write only after all checks pass; preserve a backup.
# ------------------------------------------------------------

$backup = Join-Path $env:TEMP "router_5port.v.before_adaptive"

Copy-Item -LiteralPath $path -Destination $backup -Force
Set-Content -LiteralPath $path -Value $text -Encoding UTF8

$written = Get-Content -LiteralPath $path -Raw

if (!$written.Contains('parameter ADAPTIVE_ROUTING = 0') -or
    !$written.Contains('mesh_bfs_route route_inst')) {
    Copy-Item -LiteralPath $backup -Destination $path -Force
    throw "Post-write validation failed. Original router restored."
}

$result = @(
    "PATCH RESULT: SUCCESS",
    "BRANCH: $branch",
    "BACKUP: $backup",
    "ROUTER: $path",
    "Adaptive routing default: disabled",
    "Fixed XY routing: preserved",
    "",
    "===== GIT STATUS =====",
    (git status --short --branch)
)

$resultText = $result -join "`r`n"
Set-Clipboard -Value $resultText
Write-Host $resultText
