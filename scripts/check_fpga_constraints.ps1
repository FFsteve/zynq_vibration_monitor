param([string]$VivadoBin = 'D:\Xilinx\Vivado\2020.2\bin')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'build/fpga_constraints_check'
$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado -PathType Leaf)) { throw "Vivado not found: $vivado" }
New-Item -ItemType Directory -Force $output | Out-Null
$result = Join-Path $output 'constraints_result.txt'
Set-Content -LiteralPath $result -Value 'NOT_RUN'
Push-Location $output
try {
    # 只在新的隔离目录做综合和实现，不读取或写入原工程缓存。
    & $vivado -mode batch -source ((Join-Path $PSScriptRoot 'check_fpga_constraints.tcl').Replace('\','/')) -log vivado.log -journal vivado.jou
    if ($LASTEXITCODE -ne 0) { throw "Vivado failed: $LASTEXITCODE" }
    $text = (Get-Content -LiteralPath $result -Raw).Trim()
    if ($text -notmatch '^PASS constraints part=xc7z010clg400-1 ports=3 setup_slack=[\d.]+ hold_slack=[\d.]+$') {
        throw "Constraints validation failed: $text"
    }
    Write-Host $text
} finally {
    Pop-Location
}
