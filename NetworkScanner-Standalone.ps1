# Network Scanner PowerShell - Versão Standalone para Windows 11
# Executa scan de rede local sem necessidade de Azure Functions

param(
    [Parameter(Mandatory=$false)]
    [string]$NetworkCIDR = "192.168.1.0/24",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxThreads = 50,
    
    [Parameter(Mandatory=$false)]
    [int]$PingTimeout = 2000,
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowDetails,
    
    [Parameter(Mandatory=$false)]
    [switch]$ContinuousMode,
    
    [Parameter(Mandatory=$false)]
    [int]$IntervalMinutes = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportToCSV,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Mostrar ajuda
if ($Help) {
    Write-Host @"
Network Scanner PowerShell - Versão Standalone para Windows 11

SINTAXE:
    .\NetworkScanner-Standalone.ps1 [parâmetros]

PARÂMETROS:
    -NetworkCIDR <string>       Rede no formato CIDR (padrão: 192.168.1.0/24)
    -MaxThreads <int>           Número máximo de threads paralelas (padrão: 50)
    -PingTimeout <int>          Timeout do ping em ms (padrão: 2000)
    -ShowDetails                Mostrar detalhes de cada host encontrado
    -ContinuousMode             Executar continuamente em intervalos
    -IntervalMinutes <int>      Intervalo em minutos para modo contínuo (padrão: 10)
    -ExportToCSV                Exportar resultados para CSV
    -OutputPath <string>        Caminho para salvar arquivos (padrão: diretório atual)
    -Help                       Mostrar esta ajuda

EXEMPLOS:
    # Scan básico
    .\NetworkScanner-Standalone.ps1 -NetworkCIDR "192.168.1.0/24"
    
    # Scan com detalhes e export CSV
    .\NetworkScanner-Standalone.ps1 -NetworkCIDR "10.0.0.0/24" -ShowDetails -ExportToCSV
    
    # Modo contínuo a cada 5 minutos
    .\NetworkScanner-Standalone.ps1 -ContinuousMode -IntervalMinutes 5
    
    # Scan rápido com mais threads
    .\NetworkScanner-Standalone.ps1 -NetworkCIDR "172.16.0.0/24" -MaxThreads 100 -PingTimeout 1000

"@ -ForegroundColor Cyan
    exit 0
}

# Verificar se está rodando no Windows
if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne "Win32NT") {
    Write-Warning "Este script foi otimizado para Windows 11. Pode não funcionar corretamente em outros sistemas."
}

# Função para detectar SO baseado no TTL
function Get-OSFromTTL {
    param([int]$TTL)
    
    if ($TTL -ge 120 -and $TTL -le 135) {
        return "Windows"
    }
    elseif ($TTL -ge 60 -and $TTL -le 70) {
        return "Linux"
    }
    elseif ($TTL -ge 250 -and $TTL -le 255) {
        return "Network Device"
    }
    elseif ($TTL -ge 100) {
        return "Windows (Decremented)"
    }
    elseif ($TTL -ge 50) {
        return "Linux (Decremented)"
    }
    else {
        return "Unknown"
    }
}

# Função para fazer ping em um host
function Test-HostWithTTL {
    param(
        [string]$IPAddress,
        [int]$Timeout = 2000
    )
    
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($IPAddress, $Timeout)
        
        if ($reply.Status -eq "Success") {
            $os = Get-OSFromTTL -TTL $reply.Options.Ttl
            return @{
                IP = $IPAddress
                Status = "Alive"
                TTL = $reply.Options.Ttl
                ResponseTime = $reply.RoundtripTime
                OSGuess = $os
                Success = $true
            }
        }
        else {
            return @{
                IP = $IPAddress
                Status = "Unreachable"
                TTL = $null
                ResponseTime = $null
                OSGuess = "Unknown"
                Success = $false
            }
        }
    }
    catch {
        return @{
            IP = $IPAddress
            Status = "Error"
            TTL = $null
            ResponseTime = $null
            OSGuess = "Unknown"
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Função para converter CIDR em range de IPs
function Get-IPRange {
    param([string]$CIDR)
    
    try {
        $parts = $CIDR -split '/'
        $networkIP = $parts[0]
        $maskBits = [int]$parts[1]
        
        # Converter IP para bytes
        $ipBytes = ([System.Net.IPAddress]::Parse($networkIP)).GetAddressBytes()
        
        # Calcular máscara
        $mask = [uint32]0xFFFFFFFF -shl (32 - $maskBits)
        $maskBytes = [System.BitConverter]::GetBytes($mask)
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($maskBytes)
        }
        
        # Calcular network address
        $networkBytes = @()
        for ($i = 0; $i -lt 4; $i++) {
            $networkBytes += $ipBytes[$i] -band $maskBytes[$i]
        }
        
        # Calcular broadcast address
        $broadcastBytes = @()
        for ($i = 0; $i -lt 4; $i++) {
            $broadcastBytes += $ipBytes[$i] -bor (255 - $maskBytes[$i])
        }
        
        # Converter para uint32 para facilitar iteração
        $networkUint = [BitConverter]::ToUInt32($networkBytes, 0)
        $broadcastUint = [BitConverter]::ToUInt32($broadcastBytes, 0)
        
        if ([System.BitConverter]::IsLittleEndian) {
            $networkUint = [System.Net.IPAddress]::NetworkToHostOrder([int]$networkUint)
            $broadcastUint = [System.Net.IPAddress]::NetworkToHostOrder([int]$broadcastUint)
        }
        
        # Gerar lista de IPs (excluindo network e broadcast)
        $ips = @()
        $current = $networkUint + 1
        $end = $broadcastUint - 1
        
        while ($current -le $end -and $ips.Count -lt 65000) {  # Limite de segurança
            $currentBytes = [System.BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$current))
            $ip = [System.Net.IPAddress]::new($currentBytes)
            $ips += $ip.ToString()
            $current++
        }
        
        return $ips
    }
    catch {
        Write-Error "Erro ao processar CIDR $CIDR : $($_.Exception.Message)"
        return @()
    }
}

# Função principal de scan
function Start-NetworkScan {
    param(
        [string]$NetworkCIDR,
        [int]$MaxThreads,
        [int]$PingTimeout,
        [bool]$ShowDetails,
        [bool]$ExportToCSV,
        [string]$OutputPath
    )
    
    Write-Host "=== Network Scanner PowerShell - Windows 11 ===" -ForegroundColor Cyan
    Write-Host "Rede: $NetworkCIDR" -ForegroundColor Yellow
    Write-Host "Timeout: $PingTimeout ms" -ForegroundColor Yellow
    Write-Host "Max Threads: $MaxThreads" -ForegroundColor Yellow
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "Iniciando scan..." -ForegroundColor Green
    
    $startTime = Get-Date
    
    # Obter lista de IPs
    $ipList = Get-IPRange -CIDR $NetworkCIDR
    
    if ($ipList.Count -eq 0) {
        Write-Error "Nenhum IP válido encontrado para a rede $NetworkCIDR"
        return
    }
    
    Write-Host "Total de IPs para escanear: $($ipList.Count)" -ForegroundColor Yellow
    
    # Barra de progresso
    $progressParams = @{
        Activity = "Scanning Network"
        Status = "Preparando..."
        PercentComplete = 0
    }
    Write-Progress @progressParams
    
    # Executar pings em paralelo
    $results = $ipList | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
        # Recriar funções no contexto paralelo
        function Get-OSFromTTL {
            param([int]$TTL)
            if ($TTL -ge 120 -and $TTL -le 135) { return "Windows" }
            elseif ($TTL -ge 60 -and $TTL -le 70) { return "Linux" }
            elseif ($TTL -ge 250 -and $TTL -le 255) { return "Network Device" }
            elseif ($TTL -ge 100) { return "Windows (Decremented)" }
            elseif ($TTL -ge 50) { return "Linux (Decremented)" }
            else { return "Unknown" }
        }
        
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($_, $using:PingTimeout)
            
            if ($reply.Status -eq "Success") {
                $os = Get-OSFromTTL -TTL $reply.Options.Ttl
                return @{
                    IP = $_
                    Status = "Alive"
                    TTL = $reply.Options.Ttl
                    ResponseTime = $reply.RoundtripTime
                    OSGuess = $os
                    Success = $true
                }
            }
            else {
                return @{
                    IP = $_
                    Status = "Unreachable"
                    TTL = $null
                    ResponseTime = $null
                    OSGuess = "Unknown"
                    Success = $false
                }
            }
        }
        catch {
            return @{
                IP = $_
                Status = "Error"
                TTL = $null
                ResponseTime = $null
                OSGuess = "Unknown"
                Success = $false
            }
        }
    }
    
    Write-Progress -Activity "Scanning Network" -Completed
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    # Filtrar hosts ativos
    $aliveHosts = $results | Where-Object { $_.Status -eq "Alive" }
    
    # Contar sistemas operacionais
    $osCount = @{
        "Windows" = 0
        "Linux" = 0
        "Network Device" = 0
        "Unknown" = 0
    }
    
    foreach ($host in $aliveHosts) {
        $osType = $host.OSGuess -replace " \(Decremented\)", ""
        if ($osCount.ContainsKey($osType)) {
            $osCount[$osType]++
        } else {
            $osCount["Unknown"]++
        }
    }
    
    # Exibir resultados
    Write-Host "`n=== Resultados do Scan ===" -ForegroundColor Cyan
    Write-Host "Tempo de execução: $([math]::Round($duration, 2)) segundos" -ForegroundColor Yellow
    Write-Host "IPs escaneados: $($ipList.Count)" -ForegroundColor Yellow
    Write-Host "Hosts ativos: $($aliveHosts.Count)" -ForegroundColor Green
    Write-Host "`nDistribuição de Sistemas Operacionais:" -ForegroundColor Cyan
    Write-Host "  Windows: $($osCount['Windows'])" -ForegroundColor White
    Write-Host "  Linux: $($osCount['Linux'])" -ForegroundColor White
    Write-Host "  Dispositivos de Rede: $($osCount['Network Device'])" -ForegroundColor White
    Write-Host "  Desconhecidos: $($osCount['Unknown'])" -ForegroundColor White
    
    if ($ShowDetails -and $aliveHosts.Count -gt 0) {
        Write-Host "`n=== Detalhes dos Hosts Ativos ===" -ForegroundColor Cyan
        $aliveHosts | Sort-Object { [System.Version]$_.IP } | ForEach-Object {
            Write-Host "  $($_.IP): TTL=$($_.TTL), SO=$($_.OSGuess), Tempo=$($_.ResponseTime)ms" -ForegroundColor White
        }
    }
    
    # Exportar para CSV se solicitado
    if ($ExportToCSV -and $aliveHosts.Count -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvFile = Join-Path $OutputPath "NetworkScan_$timestamp.csv"
        
        $aliveHosts | Select-Object IP, TTL, OSGuess, ResponseTime | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-Host "`n📄 Resultados exportados para: $csvFile" -ForegroundColor Green
    }
    
    return @{
        Network = $NetworkCIDR
        ScanDuration = $duration
        TotalIPs = $ipList.Count
        AliveHosts = $aliveHosts.Count
        OSDistribution = $osCount
        DetailedResults = $aliveHosts
        Timestamp = $startTime
    }
}

# Função para modo contínuo
function Start-ContinuousScanning {
    param(
        [string]$NetworkCIDR,
        [int]$MaxThreads,
        [int]$PingTimeout,
        [int]$IntervalMinutes,
        [bool]$ShowDetails,
        [bool]$ExportToCSV,
        [string]$OutputPath
    )
    
    Write-Host "=== Modo Contínuo Ativado ===" -ForegroundColor Magenta
    Write-Host "Intervalo: $IntervalMinutes minutos" -ForegroundColor Yellow
    Write-Host "Pressione Ctrl+C para parar`n" -ForegroundColor Red
    
    $iteration = 1
    $results = @()
    
    try {
        while ($true) {
            Write-Host "--- Iteração $iteration - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---" -ForegroundColor Magenta
            
            try {
                $result = Start-NetworkScan -NetworkCIDR $NetworkCIDR -MaxThreads $MaxThreads -PingTimeout $PingTimeout -ShowDetails $ShowDetails -ExportToCSV $ExportToCSV -OutputPath $OutputPath
                $results += $result
                
                # Salvar histórico se exportar CSV
                if ($ExportToCSV) {
                    $historyFile = Join-Path $OutputPath "NetworkScan_History.json"
                    $results | ConvertTo-Json -Depth 10 | Set-Content $historyFile -Encoding UTF8
                }
                
            }
            catch {
                Write-Error "Erro durante scan: $($_.Exception.Message)"
            }
            
            Write-Host "`nPróximo scan em $IntervalMinutes minutos..." -ForegroundColor Yellow
            Start-Sleep -Seconds ($IntervalMinutes * 60)
            $iteration++
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Host "`n🛑 Scan interrompido pelo usuário" -ForegroundColor Yellow
        Write-Host "Total de iterações executadas: $($iteration - 1)" -ForegroundColor White
    }
}

# Execução principal
try {
    # Verificar se o diretório de saída existe
    if ($ExportToCSV -and -not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "📁 Diretório criado: $OutputPath" -ForegroundColor Green
    }
    
    if ($ContinuousMode) {
        Start-ContinuousScanning -NetworkCIDR $NetworkCIDR -MaxThreads $MaxThreads -PingTimeout $PingTimeout -IntervalMinutes $IntervalMinutes -ShowDetails $ShowDetails -ExportToCSV $ExportToCSV -OutputPath $OutputPath
    }
    else {
        $result = Start-NetworkScan -NetworkCIDR $NetworkCIDR -MaxThreads $MaxThreads -PingTimeout $PingTimeout -ShowDetails $ShowDetails -ExportToCSV $ExportToCSV -OutputPath $OutputPath
        
        # Mostrar resumo final
        Write-Host "`n=== Resumo Final ===" -ForegroundColor Green
        Write-Host "Scan concluído com sucesso!" -ForegroundColor White
        Write-Host "Use -Help para ver todas as opções disponíveis." -ForegroundColor Gray
    }
}
catch {
    Write-Error "Erro durante execução: $($_.Exception.Message)"
    Write-Host "Use -Help para ver a sintaxe correta." -ForegroundColor Yellow
    exit 1
}

