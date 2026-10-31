[CmdletBinding()]
param(
    [ValidateSet('modelsim','xsim','both')][string]$Simulator='both',
    [string]$ModelSimBin='D:\modelsim\win64',
    [string]$VivadoBin='D:\Xilinx\Vivado\2020.2\bin',
    [string]$PythonExe='C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [string]$UV4='D:\Keil_v5\Main_Program\UV4\UV4.exe',
    [string]$Gcc='D:\msys2\ucrt64\bin\gcc.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'build/stage7_regression'
New-Item -ItemType Directory -Force $out | Out-Null
$result=Join-Path $out 'regression_result.json'
Set-Content -LiteralPath $result -Value '{"status":"NOT_RUN"}'
$steps=@()
function Invoke-Step {
    param([string]$Name,[string]$Program,[string[]]$Arguments)
    $log=Join-Path $out "$Name.log"
    $start=[DateTime]::UtcNow
    Write-Host "RUN $Name"
    if(-not(Get-Command $Program -ErrorAction SilentlyContinue)){throw "Tool not found: $Program"}
    # unittest正常进度写stderr；PowerShell 5.1不能把该文本当成进程失败。
    $savedPolicy=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & $Program @Arguments *> $log
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$savedPolicy}
    if($code -ne 0){Get-Content -LiteralPath $log -Tail 25;throw "Step failed: $Name exit=$code log=$log"}
    $script:steps+=@{name=$Name;exit_code=$code;log=$log;started_utc=$start.ToString('o');finished_utc=[DateTime]::UtcNow.ToString('o')}
    Write-Host "PASS $Name"
}
Push-Location $root
try{
    # 逐阶段独立重跑，不并行改写共享参考/向量文件，不读取历史PASS充数。
    $runners=@('sim/run_uart_rx.ps1','sim/run_stage2.ps1','sim/run_stage3.ps1','sim/run_stage4.ps1','sim/run_stage5.ps1','sim/run_stage6.ps1')
    for($i=0;$i -lt $runners.Count;$i++){
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root $runners[$i]),'-Simulator',$Simulator,'-ModelSimBin',$ModelSimBin,'-VivadoBin',$VivadoBin)
        if($i -ge 3){$arguments+=@('-PythonExe',$PythonExe)}
        Invoke-Step "stage$($i+1)" 'powershell.exe' $arguments
    }
    Invoke-Step 'host_unit' $PythonExe @('-X','utf8','-m','unittest','discover','-s','host','-p','test_*.py','-v')
    Invoke-Step 'stage3_captures' $PythonExe @('-X','utf8','host/check_stage3_captures.py')
    Invoke-Step 'stm32_portable' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'stm32/test_portable.ps1'),'-Gcc',$Gcc,'-Python',$PythonExe)
    Invoke-Step 'stm32_keil' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'stm32/build_keil.ps1'),'-UV4',$UV4)
    # JSON只在所有步骤实际成功后写PASS；不操作硬件。
    $summary=@{status='PASS_STAGE7_REGRESSION';simulator=$Simulator;steps=$steps;hardware_tested=$false}
    $json=$summary | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($result,$json+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Write-Host "PASS stage7 regression steps=$($steps.Count) result=$result"
}finally{Pop-Location}
