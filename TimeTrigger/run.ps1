# Azure Function PowerShell - Network Scanner Timer Trigger
# Executa scan de rede a cada 10 minutos para detectar SOs por TTL

using namespace System.Net

# Input bindings are passed in via param block.
param($Timer)

# Importar módulo de scan
. "$PSScriptRoot\..\Modules\NetworkScanner.ps1"

# Obter timestamp atual
$currentUTCtime = (Get-Date).ToUniversalTime()

# Log de início
Write-Host "Network Scanner Timer Trigger executado em: $currentUTCtime"

try {
    # Obter configurações do ambiente
    $networkCIDR = $env:NETWORK_CIDR
    if (-not $networkCIDR) {
        $networkCIDR = "10.1.1.0/24"
        Write-Warning "NETWORK_CIDR não configurado, usando padrão: $networkCIDR"
    }

    $maxWorkers = $env:MAX_WORKERS
    if (-not $maxWorkers) {
        $maxWorkers = 50
    } else {
        $maxWorkers = [int]$maxWorkers
    }

    $saveDetailedResults = $env:SAVE_DETAILED_RESULTS
    $showDetails = ($saveDetailedResults -eq "true")

    Write-Host "Configurações:"
    Write-Host "  Rede CIDR: $networkCIDR"
    Write-Host "  Max Workers: $maxWorkers"
    Write-Host "  Salvar Detalhes: $showDetails"

    # Executar scan de rede
    Write-Host "Iniciando scan da rede: $networkCIDR"
    $scanResult = Invoke-NetworkScan -NetworkCIDR $networkCIDR -MaxThreads $maxWorkers -ShowProgress $false

    if ($scanResult.Success) {
        # Log dos resultados principais
        Write-Host "✅ Scan concluído com sucesso!"
        Write-Host "📊 Resultados:"
        Write-Host "   Rede: $($scanResult.Network)"
        Write-Host "   Tempo de scan: $([math]::Round($scanResult.ScanDuration, 2))s"
        Write-Host "   Hosts ativos: $($scanResult.AliveHosts)"
        Write-Host "   Windows: $($scanResult.OSDistribution.Windows)"
        Write-Host "   Linux: $($scanResult.OSDistribution.Linux)"
        Write-Host "   Dispositivos de rede: $($scanResult.OSDistribution.'Network Device')"
        Write-Host "   Desconhecidos: $($scanResult.OSDistribution.Unknown)"

        # Log detalhado se habilitado
        if ($showDetails -and $scanResult.DetailedResults.Count -gt 0) {
            Write-Host "🔍 Detalhes dos hosts ativos:"
            foreach ($host in $scanResult.DetailedResults) {
                Write-Host "   $($host.IP): TTL=$($host.TTL), SO=$($host.OSGuess), Tempo=$($host.ResponseTime)ms"
            }
        }

        # Criar resumo para logs estruturados
        $summary = @{
            Timestamp = $currentUTCtime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            Network = $scanResult.Network
            ScanDuration = [math]::Round($scanResult.ScanDuration, 2)
            AliveHosts = $scanResult.AliveHosts
            WindowsCount = $scanResult.OSDistribution.Windows
            LinuxCount = $scanResult.OSDistribution.Linux
            NetworkDevices = $scanResult.OSDistribution.'Network Device'
            UnknownCount = $scanResult.OSDistribution.Unknown
        }

        # Log estruturado para Application Insights
        Write-Host "SCAN_SUMMARY: $($summary | ConvertTo-Json -Compress)"

    } else {
        Write-Error "❌ Erro durante scan: $($scanResult.Error)"
        throw $scanResult.Error
    }

} catch {
    Write-Error "❌ Erro na Azure Function: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    throw
}

Write-Host "Network Scanner Timer Trigger concluído em: $((Get-Date).ToUniversalTime())"

