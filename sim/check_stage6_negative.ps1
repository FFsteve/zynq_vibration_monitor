param(
    [ValidateSet('modelsim','xsim','both')][string]$Simulator='both',
    [string]$ModelSimBin='D:\modelsim\win64',
    [string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Program,[string[]]$Arguments)
    & $Program @Arguments
    if($LASTEXITCODE -ne 0){throw "Tool failed: $Program ($LASTEXITCODE)"}
}
$cases=@('mode_low','mode_high')
foreach($engine in @('modelsim','xsim')){
    if($Simulator -ne 'both' -and $Simulator -ne $engine){continue}
    foreach($case in $cases){
        $out=Join-Path $root "build/${engine}_stage6/negative_$case"
        New-Item -ItemType Directory -Force $out | Out-Null
        $result=Join-Path $out 'negative_result.txt'
        Set-Content -LiteralPath $result -Value 'NOT_RUN'
        Push-Location $out
        try{
            $top="stage6_bad_$case"
            if($engine -eq 'modelsim'){
                Invoke-Checked (Join-Path $ModelSimBin 'vsim.exe') @('-c','-l','negative.log','-do',
                    ('do {'+(Join-Path $root 'sim/modelsim/run_stage6_negative.do')+'} {'+$root+'} {'+$top+'}'))
            }else{
                $sources=@()
                foreach($name in @('return_source_select')){$sources+=Join-Path $root "rtl/$name.v"}
                $sources+=Join-Path $root 'sim/tb/stage6_negative_cases.v'
                Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') $sources
                Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @("work.$top",'-s',"negative_$case")
                Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @("negative_$case",'-onfinish','stop','-log','negative.log','-tclbatch',
                    ((Join-Path $root 'sim/xsim/run_stage6_negative.tcl').Replace('\','/')))
            }
            $log=Get-Content -LiteralPath (Join-Path $out 'negative.log') -Raw
            $marker='ERROR stage6 invalid return mode'
            if(-not $log.Contains($marker) -or $log.Contains('UNEXPECTED_ACCEPT')){throw "Negative test failed: $engine $case"}
            Set-Content -LiteralPath $result -Value "PASS negative $case"
            Write-Host "PASS $engine negative $case"
        }finally{Pop-Location}
    }
}
