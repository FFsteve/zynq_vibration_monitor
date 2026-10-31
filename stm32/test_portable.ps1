param(
    [string]$Gcc = 'D:\msys2\ucrt64\bin\gcc.exe',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$savedPath = $env:Path
Push-Location $root
try {
    # MSYS2 编译器的子进程需要在 PATH 中找到同目录的运行库。
    $env:Path = (Split-Path -Parent $Gcc) + ';' + $env:Path
    $output = Join-Path $root 'build/stm32_portable'
    New-Item -ItemType Directory -Force $output | Out-Null
    & $Gcc -std=c99 -Wall -Wextra -Werror -Istm32/app -Istm32/bsp stm32/tests/test_portable.c stm32/app/sample_packet.c stm32/app/acquisition.c stm32/bsp/mpu6050.c -o "$output/test_portable.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Portable compilation failed' }
    & "$output/test_portable.exe" "$output/vectors.bin"
    if ($LASTEXITCODE -ne 0) { throw 'Portable C tests failed' }
    & $Python -X utf8 stm32/tests/check_vectors.py "$output/vectors.bin"
    if ($LASTEXITCODE -ne 0) { throw 'C/Python protocol comparison failed' }
} finally {
    $env:Path = $savedPath
    Pop-Location
}
