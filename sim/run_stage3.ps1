[CmdletBinding()]
param(
    [ValidateSet('modelsim','xsim','both')]
    [string]$Simulator = 'both',
    [ValidateSet('all','power_on_reset','return_controller','monitor_core','top')]
    [string]$Test = 'all',
    [string]$ModelSimBin = 'D:\modelsim\win64',
    [string]$VivadoBin = 'D:\Xilinx\Vivado\2020.2\bin'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tests = @('power_on_reset','return_controller','monitor_core','top')
if ($Test -ne 'all') { $tests = @($Test) }

function Invoke-SimTool {
    param([string]$Executable,[string[]]$ToolArguments)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Tool not found: $Executable" }
    & $Executable @ToolArguments
    if ($LASTEXITCODE -ne 0) { throw "Tool failed ($LASTEXITCODE): $Executable" }
}

foreach ($engine in @('modelsim','xsim')) {
    if ($Simulator -ne 'both' -and $Simulator -ne $engine) { continue }
    foreach ($testName in $tests) {
        $outputDir = Join-Path $repoRoot "build/${engine}_stage3/$testName"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        $resultPath = Join-Path $outputDir "${testName}_result.txt"
        # 先作废旧结果，失败或提前退出时不得沿用历史 PASS。
        Set-Content -LiteralPath $resultPath -Value 'NOT_RUN'
        Push-Location $outputDir
        $previousTestEnv = $env:UART_STAGE3_TEST
        try {
            if ($engine -eq 'modelsim') {
                Invoke-SimTool (Join-Path $ModelSimBin 'vsim.exe') @(
                    '-c','-l','modelsim.log','-do',
                    ('do {' + (Join-Path $repoRoot 'sim/modelsim/run_stage3.do') + '} {' + $repoRoot + '} {' + $testName + '}')
                )
            } else {
                Invoke-SimTool (Join-Path $VivadoBin 'xvlog.bat') @(
                    (Join-Path $repoRoot 'rtl/uart_rx.v'),
                    (Join-Path $repoRoot 'rtl/uart_tx.v'),
                    (Join-Path $repoRoot 'rtl/packet_parser.v'),
                    (Join-Path $repoRoot 'rtl/power_on_reset.v'),
                    (Join-Path $repoRoot 'rtl/return_controller.v'),
                    (Join-Path $repoRoot 'rtl/monitor_core.v'),
                    (Join-Path $repoRoot 'rtl/top.v'),
                    (Join-Path $repoRoot 'sim/tb/stage3_serial_case.v'),
                    (Join-Path $repoRoot "sim/tb/tb_${testName}.v")
                )
                Invoke-SimTool (Join-Path $VivadoBin 'xelab.bat') @(
                    '-debug','all',"work.tb_$testName",'-s',"stage3_$testName"
                )
                $env:UART_STAGE3_TEST = $testName
                Invoke-SimTool (Join-Path $VivadoBin 'xsim.bat') @(
                    "stage3_$testName",'-onfinish','stop','-tclbatch',
                    ((Join-Path $repoRoot 'sim/xsim/run_stage3.tcl').Replace('\','/'))
                )
            }
            $resultText = (Get-Content -LiteralPath $resultPath -Raw).Trim()
            if ($resultText -notmatch ('^PASS ' + $testName + ' checks=\d+ errors=0$')) {
                throw "Simulation failed: $resultText"
            }
            Write-Host "PASS $engine : $resultText"
        } finally {
            $env:UART_STAGE3_TEST = $previousTestEnv
            Pop-Location
        }
    }
}
