param(
    [ValidateSet('modelsim','xsim','both')][string]$Simulator='both',
    [string]$ModelSimBin='D:\modelsim\win64',
    [string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Run-Tool {
    param([string]$Program,[string[]]$Arguments)
    & $Program @Arguments
    if($LASTEXITCODE -ne 0){throw "Negative case tool failed: $Program"}
}
foreach($engine in @('modelsim','xsim')){
    if($Simulator -ne 'both' -and $Simulator -ne $engine){continue}
    foreach($name in @('missing_coeff','invalid_gap')){
        $out=Join-Path $root "build/${engine}_stage4/negative_$name"
        New-Item -ItemType Directory -Force $out | Out-Null
        $result=Join-Path $out 'negative_result.txt'
        Set-Content -LiteralPath $result -Value 'NOT_RUN'
        # 不删除旧哨兵：存在就明确失败，避免历史异常被清理后掩盖。
        if(Test-Path -LiteralPath (Join-Path $out 'unexpected_accept.txt')){throw 'Previous unexpected acceptance sentinel exists'}
        if(Test-Path -LiteralPath (Join-Path $out 'missing_stage4_test_coeff.mem')){throw 'Missing-coefficient fixture is not missing'}
        Copy-Item -LiteralPath (Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem') -Destination (Join-Path $out 'fir_lp_63_q16.mem')
        Push-Location $out
        try{
            if($engine -eq 'modelsim'){
                Run-Tool (Join-Path $ModelSimBin 'vsim.exe') @('-c','-l','negative.log','-do',
                    ('do {'+(Join-Path $root 'sim/modelsim/run_stage4_negative.do')+'} {'+$root+'} {'+$name+'}'))
                $log=Get-Content -LiteralPath 'negative.log' -Raw
            }else{
                $sources=@()
                foreach($module in @('dc_remove','fir_lp_serial','vibration_filter')){$sources+=Join-Path $root "rtl/$module.v"}
                $sources+=Join-Path $root 'sim/tb/stage4_negative_cases.v'
                Run-Tool (Join-Path $VivadoBin 'xvlog.bat') $sources
                Run-Tool (Join-Path $VivadoBin 'xelab.bat') @("work.tb_stage4_$name",'-s',"negative_$name")
                Run-Tool (Join-Path $VivadoBin 'xsim.bat') @("negative_$name",'-onfinish','stop','-tclbatch',
                    ((Join-Path $root 'sim/xsim/run_stage4_negative.tcl').Replace('\','/')))
                $log=Get-Content -LiteralPath 'xsim.log' -Raw
            }
            $marker='ERROR fir coefficients missing'
            if($name -eq 'invalid_gap'){$marker='ERROR filter gap must exceed latency'}
            if($log -notmatch [regex]::Escape($marker) -or (Test-Path -LiteralPath 'unexpected_accept.txt')){throw "Negative guard not observed: $name"}
            Set-Content -LiteralPath $result -Value "PASS negative $name"
            Write-Host "PASS $engine negative $name"
        }finally{Pop-Location}
    }
}
