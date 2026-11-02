[CmdletBinding()]
param(
    [ValidateSet('modelsim','xsim','both')][string]$Simulator='both',
    [string]$ModelSimBin='D:\modelsim\win64',
    [string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$modules=@('uart_rx','uart_tx','packet_parser','power_on_reset','return_controller','monitor_core',
    'dc_remove','fir_lp_serial','vibration_filter','filter_monitor_core','isqrt_u36','window_features',
    'threshold_alarm','feature_monitor_core','return_source_select','system_monitor_core','system_top',
    'alarm_buzzer','system_buzzer_top')
function Invoke-Checked {
    param([string]$Program,[string[]]$Arguments)
    & $Program @Arguments
    if($LASTEXITCODE -ne 0){throw "Tool failed: $Program ($LASTEXITCODE)"}
}
foreach($engine in @('modelsim','xsim')){
    if($Simulator -ne 'both' -and $Simulator -ne $engine){continue}
    foreach($name in @('alarm_buzzer','system_buzzer_top')){
        $out=Join-Path $root "build/buzzer_sim/${engine}_$name"
        New-Item -ItemType Directory -Force $out | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem') -Destination $out
        $result=Join-Path $out "${name}_result.txt"
        Set-Content -LiteralPath $result -Value 'NOT_RUN'
        $sources=@()
        foreach($module in $modules){$sources+=Join-Path $root "rtl/$module.v"}
        $sources+=Join-Path $root "sim/tb/tb_$name.v"
        Push-Location $out
        try{
            if($engine -eq 'modelsim'){
                $lines=@('onerror {quit -code 1}','onbreak {resume}','vlib work')
                foreach($source in $sources){$lines+='vlog {'+$source.Replace('\','/')+'}'}
                $lines+=@("vsim work.tb_$name",'onfinish stop','run -all','quit -force')
                Set-Content -LiteralPath (Join-Path $out 'run.do') -Encoding ASCII -Value $lines
                Invoke-Checked (Join-Path $ModelSimBin 'vsim.exe') @('-c','-l','modelsim.log','-do','do run.do')
            }else{
                Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') $sources
                Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('-debug','typical',"work.tb_$name",'-s',"buzzer_$name")
                Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @("buzzer_$name",'-onfinish','stop','-tclbatch',
                    ((Join-Path $root 'sim/xsim/run_buzzer.tcl').Replace('\','/')))
            }
            $text=(Get-Content -LiteralPath $result -Raw).Trim()
            if($text -notmatch ('^PASS '+$name+' checks=\d+ errors=0$')){throw "Simulation failed: $text"}
            Write-Host "PASS $engine $text"
        }finally{Pop-Location}
    }
}
