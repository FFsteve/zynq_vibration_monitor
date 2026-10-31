param(
    [ValidateSet('both','FixedSource','SensorSource','SensorCalibratedTrial')]
    [string]$Target = 'both',
    [string]$UV4 = 'D:\Keil_v5\Main_Program\UV4\UV4.exe',
    [string]$FromElf = 'D:\Keil_v5\Main_Program\ARM\ARMCC\bin\fromelf.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot 'keil/vibration_monitor.uvprojx'
# 实验校准使用独立工程，不改原工程的目标和下载配置。
if ($Target -eq 'SensorCalibratedTrial') { $project = Join-Path $PSScriptRoot 'keil/vibration_calibration.uvprojx' }
if (-not (Test-Path -LiteralPath $UV4 -PathType Leaf)) { throw "Keil not found: $UV4" }
$targets = @('FixedSource','SensorSource')
if ($Target -ne 'both') { $targets = @($Target) }
foreach ($name in $targets) {
    $output = Join-Path $root "build/stm32/$name"
    New-Item -ItemType Directory -Force $output | Out-Null
    $log = Join-Path $output 'keil_build.log'
    # 使用全量重建并先作废日志，避免把旧构建当作本次成功；不调用下载参数。
    Set-Content -LiteralPath $log -Value 'NOT_RUN'
    $arguments = '-r "{0}" -t "{1}" -o "{2}" -j0' -f $project,$name,$log
    $process = Start-Process -FilePath $UV4 -WorkingDirectory (Split-Path -Parent $project) -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $result = Get-Content -LiteralPath $log -Raw
    Write-Host $result
    if ($process.ExitCode -ne 0 -or $result -notmatch '0 Error\(s\), 0 Warning\(s\)' -or -not (Test-Path "$output/vibration_monitor.axf")) {
        throw "Keil build failed: $name exit=$($process.ExitCode)"
    }
    Write-Host "PASS Keil $name"
    if ($name -eq 'SensorCalibratedTrial') {
        # 为实验目标同时生成HEX，避免手工使用与AXF不同版本的文件。
        if (-not (Test-Path -LiteralPath $FromElf -PathType Leaf)) { throw "fromelf not found: $FromElf" }
        & $FromElf --i32combined --output "$output/vibration_monitor.hex" "$output/vibration_monitor.axf"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$output/vibration_monitor.hex")) { throw 'Trial HEX generation failed' }
        Write-Host 'PASS trial_hex generated'
    }
}
