[CmdletBinding()]
param(
    [ValidateSet('modelsim', 'xsim', 'both')]
    [string]$Simulator = 'both',
    [string]$ModelSimBin = 'D:\modelsim\win64',
    [string]$VivadoBin = 'D:\Xilinx\Vivado\2020.2\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-SimTool {
    param([string]$Executable, [string[]]$ToolArguments)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Tool not found: $Executable. Supply -ModelSimBin or -VivadoBin."
    }
    & $Executable @ToolArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Tool failed (exit $LASTEXITCODE): $Executable"
    }
}

function Assert-SimResult {
    param([string]$ResultPath)
    if (-not (Test-Path -LiteralPath $ResultPath)) {
        throw "Simulation did not produce a result: $ResultPath"
    }
    $resultText = (Get-Content -LiteralPath $ResultPath -Raw).Trim()
    if ($resultText -notmatch '^PASS bytes=\d+ framing=\d+ errors=0$') {
        throw "Simulation failed: $resultText"
    }
    Write-Host $resultText
}

foreach ($engine in @('modelsim', 'xsim')) {
    if (($Simulator -ne 'both') -and ($Simulator -ne $engine)) { continue }
    $outputDir = Join-Path $repoRoot "build/${engine}_uart_rx"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    # 启动前将旧结果标记为未运行，防止旧 PASS 造成假通过；保留既有产物。
    Set-Content -LiteralPath (Join-Path $outputDir 'uart_rx_result.txt') -Value 'NOT_RUN'
    Push-Location $outputDir
    try {
        if ($engine -eq 'modelsim') {
            Invoke-SimTool (Join-Path $ModelSimBin 'vsim.exe') @(
                '-c', '-l', 'modelsim.log', '-do',
                ('do {' + (Join-Path $repoRoot 'sim/modelsim/run_uart_rx.do') +
                 '} {' + $repoRoot + '}')
            )
        } else {
            Invoke-SimTool (Join-Path $VivadoBin 'xvlog.bat') @(
                (Join-Path $repoRoot 'rtl/uart_rx.v'),
                (Join-Path $repoRoot 'sim/tb/tb_uart_rx.v')
            )
            Invoke-SimTool (Join-Path $VivadoBin 'xelab.bat') @(
                '-debug', 'all', 'work.tb_uart_rx', '-s', 'tb_uart_rx_sim'
            )
            Invoke-SimTool (Join-Path $VivadoBin 'xsim.bat') @(
                'tb_uart_rx_sim', '-onfinish', 'stop', '-tclbatch',
                ((Join-Path $repoRoot 'sim/xsim/run_uart_rx.tcl').Replace('\', '/'))
            )
        }
        Assert-SimResult (Join-Path $outputDir 'uart_rx_result.txt')
        Write-Host "PASS $engine (artifacts: $outputDir)"
    } finally {
        Pop-Location
    }
}
