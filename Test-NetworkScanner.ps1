# Script de Teste para Network Scanner PowerShell
# Valida todas as funcionalidades do módulo

param(
    [Parameter(Mandatory=$false)]
    [string]$TestNetwork = "127.0.0.0/30",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Importar módulo
. "$PSScriptRoot\Modules\NetworkScanner.ps1"

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Details = ""
    )
    
    $status = if ($Success) { "✅ PASSOU" } else { "❌ FALHOU" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Details -and ($Verbose -or -not $Success)) {
        Write-Host "   $Details" -ForegroundColor Gray
    }
}

Write-Host "=== Teste do Network Scanner PowerShell ===" -ForegroundColor Cyan
Write-Host "Executando testes de validação..." -ForegroundColor Yellow
Write-Host ""

$totalTests = 0
$passedTests = 0

# Teste 1: Detecção de SO por TTL
Write-Host "🧪 Teste 1: Detecção de SO por TTL" -ForegroundColor Magenta
$totalTests++

$ttlTests = @(
    @{ TTL = 64; Expected = "Linux" },
    @{ TTL = 128; Expected = "Windows" },
    @{ TTL = 255; Expected = "Network Device" },
    @{ TTL = 63; Expected = "Linux" },
    @{ TTL = 127; Expected = "Windows" },
    @{ TTL = 50; Expected = "Linux" },
    @{ TTL = 100; Expected = "Windows" },
    @{ TTL = 30; Expected = "Unknown" }
)

$ttlPassed = $true
foreach ($test in $ttlTests) {
    $result = Get-OSFromTTL -TTL $test.TTL
    if ($result -ne $test.Expected) {
        $ttlPassed = $false
        if ($Verbose) {
            Write-Host "   TTL $($test.TTL): Esperado '$($test.Expected)', Obtido '$result'" -ForegroundColor Red
        }
    }
}

Write-TestResult -TestName "Detecção de SO por TTL" -Success $ttlPassed
if ($ttlPassed) { $passedTests++ }

# Teste 2: Ping para localhost
Write-Host "`n🧪 Teste 2: Ping para localhost" -ForegroundColor Magenta
$totalTests++

try {
    $pingResult = Test-HostWithTTL -IPAddress "127.0.0.1" -Timeout 3000
    $pingSuccess = $pingResult.Success -and $pingResult.Status -eq "Alive" -and $pingResult.TTL -gt 0
    
    $details = if ($pingSuccess) {
        "TTL=$($pingResult.TTL), SO=$($pingResult.OSGuess), Tempo=$($pingResult.ResponseTime)ms"
    } else {
        "Status=$($pingResult.Status), Erro=$($pingResult.Error)"
    }
    
    Write-TestResult -TestName "Ping para localhost" -Success $pingSuccess -Details $details
    if ($pingSuccess) { $passedTests++ }
} catch {
    Write-TestResult -TestName "Ping para localhost" -Success $false -Details $_.Exception.Message
}

# Teste 3: Conversão de CIDR
Write-Host "`n🧪 Teste 3: Conversão de CIDR para IPs" -ForegroundColor Magenta
$totalTests++

try {
    $ips = Get-IPRange -CIDR $TestNetwork
    $cidrSuccess = $ips.Count -gt 0 -and $ips.Count -le 10  # Rede pequena deve ter poucos IPs
    
    $details = "Rede: $TestNetwork, IPs encontrados: $($ips.Count)"
    if ($Verbose -and $ips.Count -le 5) {
        $details += " ($($ips -join ', '))"
    }
    
    Write-TestResult -TestName "Conversão de CIDR" -Success $cidrSuccess -Details $details
    if ($cidrSuccess) { $passedTests++ }
} catch {
    Write-TestResult -TestName "Conversão de CIDR" -Success $false -Details $_.Exception.Message
}

# Teste 4: Scan de rede pequena
Write-Host "`n🧪 Teste 4: Scan de rede pequena" -ForegroundColor Magenta
$totalTests++

try {
    Write-Host "   Executando scan de $TestNetwork..." -ForegroundColor Gray
    $scanResult = Invoke-NetworkScan -NetworkCIDR $TestNetwork -MaxThreads 10 -ShowProgress $false
    
    $scanSuccess = $scanResult.Success -and $scanResult.TotalIPs -gt 0
    
    $details = if ($scanSuccess) {
        "IPs: $($scanResult.TotalIPs), Ativos: $($scanResult.AliveHosts), Tempo: $([math]::Round($scanResult.ScanDuration, 2))s"
    } else {
        "Erro: $($scanResult.Error)"
    }
    
    Write-TestResult -TestName "Scan de rede pequena" -Success $scanSuccess -Details $details
    if ($scanSuccess) { $passedTests++ }
} catch {
    Write-TestResult -TestName "Scan de rede pequena" -Success $false -Details $_.Exception.Message
}

# Teste 5: Tratamento de erro (CIDR inválido)
Write-Host "`n🧪 Teste 5: Tratamento de erro (CIDR inválido)" -ForegroundColor Magenta
$totalTests++

try {
    $errorResult = Invoke-NetworkScan -NetworkCIDR "invalid.network" -ShowProgress $false
    $errorSuccess = -not $errorResult.Success -and $errorResult.Error
    
    $details = if ($errorSuccess) {
        "Erro capturado corretamente"
    } else {
        "Deveria ter falhado com CIDR inválido"
    }
    
    Write-TestResult -TestName "Tratamento de erro" -Success $errorSuccess -Details $details
    if ($errorSuccess) { $passedTests++ }
} catch {
    # Exceção também é aceitável para CIDR inválido
    Write-TestResult -TestName "Tratamento de erro" -Success $true -Details "Exceção capturada corretamente"
    $passedTests++
}

# Teste 6: Performance (opcional)
if ($Verbose) {
    Write-Host "`n🧪 Teste 6: Performance com múltiplas threads" -ForegroundColor Magenta
    $totalTests++
    
    try {
        $startTime = Get-Date
        $perfResult = Invoke-NetworkScan -NetworkCIDR "127.0.0.0/28" -MaxThreads 20 -ShowProgress $false
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        $perfSuccess = $perfResult.Success -and $duration -lt 30  # Deve completar em menos de 30s
        
        $details = "Duração: $([math]::Round($duration, 2))s, Hosts: $($perfResult.AliveHosts)"
        
        Write-TestResult -TestName "Performance" -Success $perfSuccess -Details $details
        if ($perfSuccess) { $passedTests++ }
    } catch {
        Write-TestResult -TestName "Performance" -Success $false -Details $_.Exception.Message
    }
}

# Resumo dos testes
Write-Host ""
Write-Host "=== Resumo dos Testes ===" -ForegroundColor Cyan
Write-Host "Total: $totalTests" -ForegroundColor White
Write-Host "Passou: $passedTests" -ForegroundColor Green
Write-Host "Falhou: $($totalTests - $passedTests)" -ForegroundColor Red

$successRate = [math]::Round(($passedTests / $totalTests) * 100, 1)
Write-Host "Taxa de Sucesso: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Yellow" })

if ($passedTests -eq $totalTests) {
    Write-Host ""
    Write-Host "🎉 Todos os testes passaram! O Network Scanner está funcionando corretamente." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠️  Alguns testes falharam. Verifique a configuração." -ForegroundColor Yellow
    exit 1
}

