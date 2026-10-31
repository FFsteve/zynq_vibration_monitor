param([string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$output=Join-Path $root 'build/stage5_synthesis'
New-Item -ItemType Directory -Force $output | Out-Null
$coeff=Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem'
if((Get-FileHash -LiteralPath $coeff -Algorithm SHA256).Hash -ne 'B9B74FB39759CF352D2B388EA15650B0A1522D1F15DD6F4861F622D7B580FC35'){
    throw 'Coefficient checksum differs from approved design'
}
Copy-Item -LiteralPath $coeff -Destination (Join-Path $output 'fir_lp_63_q16.mem')
$result=Join-Path $output 'synthesis_result.txt'
Set-Content -LiteralPath $result -Value 'NOT_RUN'
Push-Location $output
try{
    # 检查通信、滤波、窗口与报警的完整内部计算链，不更改板级顶层或原Vivado缓存。
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source ((Join-Path $PSScriptRoot 'check_stage5_synthesis.tcl').Replace('\','/')) -log vivado.log -journal vivado.jou
    if($LASTEXITCODE -ne 0){throw "Vivado failed: $LASTEXITCODE"}
    $text=(Get-Content -LiteralPath $result -Raw).Trim()
    if($text -notmatch '^PASS stage5_ooc setup_slack=[\d.]+ hold_slack=[\d.]+$'){throw "OOC failed: $text"}
    Write-Host $text
}finally{Pop-Location}
