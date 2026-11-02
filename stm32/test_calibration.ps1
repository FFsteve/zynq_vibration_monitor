param(
    [string]$Gcc = 'D:\msys2\ucrt64\bin\gcc.exe',
    [string]$Python = 'python',
    [string]$Analysis = 'report/mpu6050_calibration_params_20261101.json'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$savedPath = $env:Path
Push-Location $root
try {
    # 使用与现有可移植测试一致的本机编译环境；不操作烧录器。
    $env:Path = (Split-Path -Parent $Gcc) + ';' + $env:Path
    $output = Join-Path $root 'build/stm32_calibration_test'
    New-Item -ItemType Directory -Force $output | Out-Null
    & $Gcc -std=c99 -Wall -Wextra -Werror -DAPP_ACCEL_CALIBRATION=1 -Istm32/app -Istm32/bsp stm32/tests/test_calibration.c stm32/app/accel_calibration.c stm32/app/acquisition.c stm32/app/sample_packet.c stm32/bsp/mpu6050.c -o "$output/test_calibration.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Calibration C compilation failed' }
    & "$output/test_calibration.exe" "$output/calibration_vectors.bin"
    if ($LASTEXITCODE -ne 0) { throw 'Calibration C test failed' }
    & $Python -X utf8 stm32/tests/check_calibration.py --analysis $Analysis --vectors "$output/calibration_vectors.bin"
    if ($LASTEXITCODE -ne 0) { throw 'Calibration C/Python comparison failed' }
} finally {
    $env:Path = $savedPath
    Pop-Location
}
