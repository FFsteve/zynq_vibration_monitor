param([string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'build/stage7_release'
New-Item -ItemType Directory -Force $out | Out-Null
$coeff=Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem'
if((Get-FileHash -LiteralPath $coeff -Algorithm SHA256).Hash -ne 'B9B74FB39759CF352D2B388EA15650B0A1522D1F15DD6F4861F622D7B580FC35'){throw 'Coefficient checksum mismatch'}
foreach($variant in @('raw','filtered','debug')){
    $folder=Join-Path $out $variant
    New-Item -ItemType Directory -Force $folder | Out-Null
    Copy-Item -LiteralPath $coeff -Destination (Join-Path $folder 'fir_lp_63_q16.mem')
    Set-Content -LiteralPath (Join-Path $folder 'release_result.txt') -Value 'NOT_RUN'
}
Push-Location $out
try{
    # 独立重建和生成下载文件；不打开原工程、不更改烧录设置、不连接硬件。
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source ((Join-Path $PSScriptRoot 'build_release.tcl').Replace('\','/')) -log vivado.log -journal vivado.jou
    if($LASTEXITCODE -ne 0){throw "Release build failed: $LASTEXITCODE"}
    foreach($variant in @('raw','filtered','debug')){
        $folder=Join-Path $out $variant
        $text=(Get-Content -LiteralPath (Join-Path $folder 'release_result.txt') -Raw).Trim()
        if($text -notmatch '^PASS stage7_release variant=\w+ mode=[01] setup_slack=[\d.]+ hold_slack=[\d.]+$'){throw "Invalid release result: $text"}
        if(-not(Test-Path -LiteralPath (Join-Path $folder 'system.bit'))){throw "Missing bitstream: $variant"}
        if($variant -eq 'debug' -and -not(Test-Path -LiteralPath (Join-Path $folder 'system.ltx'))){throw 'Missing debug probes'}
        Write-Host $text
    }
}finally{Pop-Location}
