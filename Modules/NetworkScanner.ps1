# NetworkScanner PowerShell Module
# Módulo para scan de rede e detecção de SO por TTL para Azure Functions

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
        return "Windows"  # TTL decrementado
    }
    elseif ($TTL -ge 50) {
        return "Linux"    # TTL decrementado
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

# Função principal de scan de rede
function Invoke-NetworkScan {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NetworkCIDR,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxThreads = 50,
        
        [Parameter(Mandatory=$false)]
        [int]$PingTimeout = 2000,
        
        [Parameter(Mandatory=$false)]
        [bool]$ShowProgress = $true
    )
    
    try {
        if ($ShowProgress) {
            Write-Host "=== Network Scanner PowerShell ===" -ForegroundColor Cyan
            Write-Host "Rede: $NetworkCIDR" -ForegroundColor Yellow
            Write-Host "Max Threads: $MaxThreads" -ForegroundColor Yellow
            Write-Host "Timeout: $PingTimeout ms" -ForegroundColor Yellow
        }
        
        $startTime = Get-Date
        
        # Obter lista de IPs
        $ipList = Get-IPRange -CIDR $NetworkCIDR
        
        if ($ipList.Count -eq 0) {
            return @{
                Success = $false
                Error = "Nenhum IP válido encontrado para a rede $NetworkCIDR"
            }
        }
        
        if ($ShowProgress) {
            Write-Host "Total de IPs para escanear: $($ipList.Count)" -ForegroundColor Yellow
            Write-Host "Iniciando scan..." -ForegroundColor Green
        }
        
        # Executar pings em paralelo usando ForEach-Object -Parallel
        $results = $ipList | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
            # Recriar função no contexto paralelo
            function Get-OSFromTTL {
                param([int]$TTL)
                if ($TTL -ge 120 -and $TTL -le 135) { return "Windows" }
                elseif ($TTL -ge 60 -and $TTL -le 70) { return "Linux" }
                elseif ($TTL -ge 250 -and $TTL -le 255) { return "Network Device" }
                elseif ($TTL -ge 100) { return "Windows" }
                elseif ($TTL -ge 50) { return "Linux" }
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
        
        foreach ($hostScan in $aliveHosts) {
            $osType = $hostScan.OSGuess
            if ($osCount.ContainsKey($osType)) {
                $osCount[$osType]++
            } else {
                $osCount["Unknown"]++
            }
        }
        
        if ($ShowProgress) {
            Write-Host "`n=== Resultados do Scan ===" -ForegroundColor Cyan
            Write-Host "Tempo de execução: $([math]::Round($duration, 2)) segundos" -ForegroundColor Yellow
            Write-Host "IPs escaneados: $($ipList.Count)" -ForegroundColor Yellow
            Write-Host "Hosts ativos: $($aliveHosts.Count)" -ForegroundColor Green
            Write-Host "`nDistribuição de SOs:" -ForegroundColor Cyan
            Write-Host "  Windows: $($osCount['Windows'])" -ForegroundColor White
            Write-Host "  Linux: $($osCount['Linux'])" -ForegroundColor White
            Write-Host "  Dispositivos de Rede: $($osCount['Network Device'])" -ForegroundColor White
            Write-Host "  Desconhecidos: $($osCount['Unknown'])" -ForegroundColor White
        }
        
        return @{
            Success = $true
            Network = $NetworkCIDR
            ScanDuration = $duration
            TotalIPs = $ipList.Count
            AliveHosts = $aliveHosts.Count
            OSDistribution = $osCount
            DetailedResults = $aliveHosts
        }
        
    }
    catch {
        return @{
            Success = $false
            Error = "Erro durante scan: $($_.Exception.Message)"
        }
    }
}

# Função para teste rápido
function Test-NetworkScanner {
    Write-Host "=== Teste do Network Scanner ===" -ForegroundColor Magenta
    
    # Teste 1: Ping localhost
    Write-Host "`n1. Testando ping localhost..." -ForegroundColor Yellow
    $result = Test-HostWithTTL -IPAddress "127.0.0.1"
    if ($result.Success) {
        Write-Host "   ✅ Sucesso: TTL=$($result.TTL), SO=$($result.OSGuess)" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Falhou" -ForegroundColor Red
    }
    
    # Teste 2: Scan pequeno
    Write-Host "`n2. Testando scan pequeno (127.0.0.0/30)..." -ForegroundColor Yellow
    $scanResult = Invoke-NetworkScan -NetworkCIDR "127.0.0.0/30" -ShowProgress $false
    if ($scanResult.Success) {
        Write-Host "   ✅ Sucesso: $($scanResult.AliveHosts) hosts ativos" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Falhou: $($scanResult.Error)" -ForegroundColor Red
    }
    
    Write-Host "`n=== Teste Concluído ===" -ForegroundColor Magenta
}

