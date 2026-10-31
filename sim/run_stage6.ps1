[CmdletBinding()]
param(
    [ValidateSet('modelsim','xsim','both')][string]$Simulator='both',
    [ValidateSet('all','return_source_select','system_monitor_core','system_top','return_controller','packet_parser')][string]$Test='all',
    [string]$ModelSimBin='D:\modelsim\win64',
    [string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin',
    [string]$PythonExe='C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Program,[string[]]$Arguments)
    if(-not(Test-Path -LiteralPath $Program -PathType Leaf)){throw "Tool not found: $Program"}
    & $Program @Arguments
    if($LASTEXITCODE -ne 0){throw "Tool failed: $Program ($LASTEXITCODE)"}
}
# 参考向量来自Python；先验证数值及系数，禁止仿真器互相生成期望。
Invoke-Checked $PythonExe @('-X','utf8',(Join-Path $root 'host/stage6_reference.py'))
Invoke-Checked $PythonExe @('-X','utf8',(Join-Path $root 'host/stage6_vectors.py'))
$coeff=Join-Path $root 'data/reference/stage4/fir_lp_63_q16.mem'
if((Get-FileHash -LiteralPath $coeff -Algorithm SHA256).Hash -ne 'B9B74FB39759CF352D2B388EA15650B0A1522D1F15DD6F4861F622D7B580FC35'){
    throw 'Coefficient checksum differs from approved design'
}
$tests=@('return_source_select','system_monitor_core','system_top','return_controller','packet_parser')
if($Test -ne 'all'){$tests=@($Test)}
$modules=@('uart_rx','uart_tx','packet_parser','power_on_reset','return_controller','monitor_core','top',
    'dc_remove','fir_lp_serial','vibration_filter','filter_monitor_core',
    'isqrt_u36','window_features','threshold_alarm','feature_monitor_core',
    'return_source_select','system_monitor_core','system_top')
foreach($engine in @('modelsim','xsim')){
    if($Simulator -ne 'both' -and $Simulator -ne $engine){continue}
    foreach($name in $tests){
        $output=Join-Path $root "build/${engine}_stage6/$name"
        New-Item -ItemType Directory -Force $output | Out-Null
        Copy-Item -LiteralPath $coeff -Destination (Join-Path $output 'fir_lp_63_q16.mem')
        foreach($file in @('system_vectors.txt','system_features.txt')){
            Copy-Item -LiteralPath (Join-Path $root "build/stage6_vectors/$file") -Destination (Join-Path $output $file)
        }
        Copy-Item -LiteralPath (Join-Path $root 'build/stage6_reference/selector_vectors.txt') -Destination (Join-Path $output 'selector_vectors.txt')
        $result=Join-Path $output "${name}_result.txt"
        Set-Content -LiteralPath $result -Value 'NOT_RUN'
        Push-Location $output
        $previousTest=$env:UART_STAGE6_TEST
        try{
            if($engine -eq 'modelsim'){
                Invoke-Checked (Join-Path $ModelSimBin 'vsim.exe') @('-c','-l','modelsim.log','-do',
                    ('do {'+(Join-Path $root 'sim/modelsim/run_stage6.do')+'} {'+$root+'} {'+$name+'}'))
            }else{
                $sources=@('-i',(Join-Path $root 'sim/tb'))
                foreach($module in $modules){$sources+=Join-Path $root "rtl/$module.v"}
                $sources+=Join-Path $root "sim/tb/tb_$name.v"
                $sources+=Join-Path $root 'sim/tb/stage6_system_case.v'
                Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') $sources
                Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('-debug','typical',"work.tb_$name",'-s',"stage6_$name")
                $env:UART_STAGE6_TEST=$name
                Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @("stage6_$name",'-onfinish','stop','-tclbatch',
                    ((Join-Path $root 'sim/xsim/run_stage6.tcl').Replace('\','/')))
            }
            $text=(Get-Content -LiteralPath $result -Raw).Trim()
            if($text -notmatch ('^PASS '+$name+' checks=\d+ errors=0$')){throw "Simulation failed: $text"}
            Write-Host "PASS $engine : $text"
        }finally{$env:UART_STAGE6_TEST=$previousTest;Pop-Location}
    }
    if($Test -eq 'all'){
        Invoke-Checked $PythonExe @('-X','utf8',(Join-Path $root 'host/check_stage6_captures.py'),'--simulator',$engine)
        & (Join-Path $PSScriptRoot 'check_stage6_negative.ps1') -Simulator $engine -ModelSimBin $ModelSimBin -VivadoBin $VivadoBin
    }
}
