param([int[]]$Rates = @(10, 25, 50, 100))
$ErrorActionPreference = 'Stop'
if ($Rates.Count -eq 0 -or @($Rates | Where-Object { $_ -lt 1 }).Count -gt 0) {
    throw 'Rates debe contener enteros positivos.'
}
Get-Command k6 -ErrorAction Stop | Out-Null
$runDirectory = Join-Path $PSScriptRoot ('results\k6-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$rows = @()
foreach ($rate in $Rates) {
    foreach ($mode in @('off', 'on')) {
        $resultFile = Join-Path $runDirectory "$mode-${rate}rps.json"
        Write-Host "Prueba CACHE=$mode RPS=$rate"
        & k6 run -e "CACHE=$mode" -e "RPS=$rate" --summary-export $resultFile (Join-Path $PSScriptRoot 'load-test.js')
        $runExitCode = $LASTEXITCODE
        # 99 indica umbrales incumplidos: conservar resultados y continuar comparacion.
        if ($runExitCode -notin @(0, 99)) {
            throw "k6 fallo con codigo $runExitCode. Se detiene la carga; revisa la salida."
        }
        $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        $metrics = $result.metrics
        $count = $metrics.report_requests.values.count
        $dropped = $metrics.dropped_iterations.values.count
        if ($null -eq $dropped) { $dropped = 0 }
        $rows += [pscustomobject]@{
            Cache = $mode
            ProductId = $(if ($mode -eq 'on') { 3 } else { 2 })
            TargetRPS = $rate
            Completed = $count
            Expected = $rate * 60
            AverageMs = [math]::Round($metrics.report_latency.values.avg, 2)
            ErrorsPct = [math]::Round(100 * $metrics.report_errors.values.rate, 2)
            HitsPct = [math]::Round(100 * $metrics.cache_hit_ratio.values.rate, 2)
            Dropped = $dropped
            ThresholdsPassed = ($runExitCode -eq 0)
        }
        $rows | Export-Csv -LiteralPath (Join-Path $runDirectory 'comparison.csv') -NoTypeInformation -Encoding UTF8
    }
}
$rows | Format-Table -AutoSize
Write-Host "Resultados guardados en $runDirectory"
Write-Host 'Completed puede incluir respuestas durante los 15s de cierre. Revisar Dropped y errores junto con la latencia.'
