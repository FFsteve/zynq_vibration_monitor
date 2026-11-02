param([string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'build/buzzer_release'
$debugOut=Join-Path $out 'debug'
New-Item -ItemType Directory -Force $debugOut | Out-Null
$coeff=Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem'
if((Get-FileHash -LiteralPath $coeff -Algorithm SHA256).Hash -ne 'B9B74FB39759CF352D2B388EA15650B0A1522D1F15DD6F4861F622D7B580FC35'){throw 'Coefficient checksum mismatch'}
Copy-Item -LiteralPath $coeff -Destination $debugOut
Set-Content -LiteralPath (Join-Path $debugOut 'release_result.txt') -Value 'NOT_RUN'
Push-Location $out
try{
    # 单独生成蜂鸣器版本，不操作Hardware Manager、不修改旧工程或冻结包。
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source ((Join-Path $PSScriptRoot 'build_buzzer.tcl').Replace('\','/')) -log vivado.log -journal vivado.jou
    if($LASTEXITCODE -ne 0){throw "Buzzer build failed: $LASTEXITCODE"}
    $text=(Get-Content -LiteralPath (Join-Path $debugOut 'release_result.txt') -Raw).Trim()
    if($text -notmatch '^PASS buzzer_release variant=debug mode=1 setup_slack=[\d.]+ hold_slack=[\d.]+$'){throw "Invalid build result: $text"}
    foreach($file in @('system.bit','system.ltx')){
        if(-not(Test-Path -LiteralPath (Join-Path $debugOut $file))){throw "Missing output: $file"}
    }
    Write-Host $text
}finally{Pop-Location}
