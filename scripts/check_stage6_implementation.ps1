param([string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'build/stage6_implementation'
New-Item -ItemType Directory -Force $out | Out-Null
$coeff=Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem'
if((Get-FileHash -LiteralPath $coeff -Algorithm SHA256).Hash -ne 'B9B74FB39759CF352D2B388EA15650B0A1522D1F15DD6F4861F622D7B580FC35'){throw 'Coefficient checksum mismatch'}
foreach($mode in @('raw','filtered')){
    $folder=Join-Path $out $mode
    New-Item -ItemType Directory -Force $folder | Out-Null
    Copy-Item -LiteralPath $coeff -Destination (Join-Path $folder 'fir_lp_63_q16.mem')
    Set-Content -LiteralPath (Join-Path $folder 'implementation_result.txt') -Value 'NOT_RUN'
}
Push-Location $out
try{
    # 完整约束的独立构建；不生成比特流、不接硬件、不写原工程缓存。
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source ((Join-Path $PSScriptRoot 'check_stage6_implementation.tcl').Replace('\','/')) -log vivado.log -journal vivado.jou
    if($LASTEXITCODE -ne 0){throw "Vivado failed: $LASTEXITCODE"}
    foreach($mode in @('raw','filtered')){
        $text=(Get-Content -LiteralPath (Join-Path $out "$mode/implementation_result.txt") -Raw).Trim()
        if($text -notmatch '^PASS stage6_implementation mode=[01] setup_slack=[\d.]+ hold_slack=[\d.]+$'){throw "Implementation failed: $text"}
        Write-Host $text
    }
}finally{Pop-Location}
