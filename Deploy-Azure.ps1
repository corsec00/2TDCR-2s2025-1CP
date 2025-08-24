# Script de Deploy Automatizado para Azure Functions PowerShell - Network Scanner
# Para Windows 11 com PowerShell

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-network-scanner-Fiap",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "CentralUS",
    
    [Parameter(Mandatory=$false)]
    [string]$NetworkCIDR = "10.1.1.0/24",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxWorkers = 50,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPrerequisites
)

# Configurações
$StorageAccount = "stnetscanner$(Get-Random -Minimum 1000 -Maximum 9999)"
$FunctionApp = "func-netscanner-ps-$(Get-Random -Minimum 1000 -Maximum 9999)"

Write-Host "=== Network Scanner PowerShell - Deploy Automatizado ===" -ForegroundColor Cyan
Write-Host "Grupo de Recursos: $ResourceGroup" -ForegroundColor Yellow
Write-Host "Localização: $Location" -ForegroundColor Yellow
Write-Host "Conta de Armazenamento: $StorageAccount" -ForegroundColor Yellow
Write-Host "Function App: $FunctionApp" -ForegroundColor Yellow
Write-Host "Rede CIDR: $NetworkCIDR" -ForegroundColor Yellow
Write-Host ""

# Verificar pré-requisitos
if (-not $SkipPrerequisites) {
    Write-Host "🔍 Verificando pré-requisitos..." -ForegroundColor Cyan
    
    # Verificar Azure CLI
    try {
        $azVersion = az --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Azure CLI encontrado" -ForegroundColor Green
        } else {
            throw "Azure CLI não encontrado"
        }
    } catch {
        Write-Host "❌ Azure CLI não encontrado" -ForegroundColor Red
        Write-Host "Instale com: winget install Microsoft.AzureCLI" -ForegroundColor Yellow
        exit 1
    }
    
    # Verificar Azure Functions Core Tools
    try {
        $funcVersion = func --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Azure Functions Core Tools encontrado" -ForegroundColor Green
        } else {
            throw "Azure Functions Core Tools não encontrado"
        }
    } catch {
        Write-Host "❌ Azure Functions Core Tools não encontrado" -ForegroundColor Red
        Write-Host "Instale com: npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor Yellow
        Write-Host "Ou: winget install Microsoft.Azure.FunctionsCoreTools" -ForegroundColor Yellow
        exit 1
    }
    
    # Verificar PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "❌ PowerShell 7+ necessário (versão atual: $($PSVersionTable.PSVersion))" -ForegroundColor Red
        Write-Host "Instale com: winget install Microsoft.PowerShell" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "✅ PowerShell $($PSVersionTable.PSVersion) encontrado" -ForegroundColor Green
    }
}

# Verificar login no Azure
Write-Host "🔐 Verificando login no Azure..." -ForegroundColor Cyan
try {
    $account = az account show --query "name" -o tsv 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Logado no Azure: $account" -ForegroundColor Green
    } else {
        throw "Não logado"
    }
} catch {
    Write-Host "❌ Não logado no Azure" -ForegroundColor Red
    Write-Host "Execute: az login" -ForegroundColor Yellow
    exit 1
}

# Criar grupo de recursos
Write-Host "📁 Criando grupo de recursos..." -ForegroundColor Cyan
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "true") {
    Write-Host "⚠️  Grupo de recursos já existe" -ForegroundColor Yellow
} else {
    az group create --name $ResourceGroup --location $Location
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Grupo de recursos criado" -ForegroundColor Green
    } else {
        Write-Host "❌ Erro ao criar grupo de recursos" -ForegroundColor Red
        exit 1
    }
}

# Criar conta de armazenamento
Write-Host "💾 Criando conta de armazenamento..." -ForegroundColor Cyan
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Conta de armazenamento criada" -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao criar conta de armazenamento" -ForegroundColor Red
    exit 1
}

# Criar Function App
Write-Host "⚡ Criando Azure Function App PowerShell..." -ForegroundColor Cyan
az functionapp create --resource-group $ResourceGroup --consumption-plan-location $Location --runtime powershell --runtime-version 7.4 --functions-version 4 --name $FunctionApp --storage-account $StorageAccount --os-type Windows

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Function App criada" -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao criar Function App" -ForegroundColor Red
    exit 1
}

# Configurar variáveis de ambiente
Write-Host "⚙️  Configurando variáveis de ambiente..." -ForegroundColor Cyan
az functionapp config appsettings set `
    --name $FunctionApp `
    --resource-group $ResourceGroup `
    --settings `
        NETWORK_CIDR="$NetworkCIDR" `
        MAX_WORKERS="$MaxWorkers" `
        SAVE_DETAILED_RESULTS="false"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Variáveis configuradas" -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao configurar variáveis" -ForegroundColor Red
    exit 1
}

# Deploy do código
Write-Host "🚀 Fazendo deploy do código PowerShell..." -ForegroundColor Cyan
func azure functionapp publish $FunctionApp --powershell

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Deploy concluído!" -ForegroundColor Green
} else {
    Write-Host "❌ Erro durante deploy" -ForegroundColor Red
    exit 1
}

# URLs finais
$FunctionURL = "https://$FunctionApp.azurewebsites.net"
$ApiURL = "$FunctionURL/api/scan"
$HealthURL = "$FunctionURL/api/health"

Write-Host ""
Write-Host "=== Deploy Concluído com Sucesso! ===" -ForegroundColor Green
Write-Host "Function App: $FunctionApp" -ForegroundColor White
Write-Host "URL Base: $FunctionURL" -ForegroundColor White
Write-Host "API Scan: $ApiURL" -ForegroundColor White
Write-Host "Health Check: $HealthURL" -ForegroundColor White
Write-Host ""

# Testar endpoints
Write-Host "🧪 Testando endpoints..." -ForegroundColor Cyan
Start-Sleep -Seconds 30  # Aguardar deploy

try {
    $healthResponse = Invoke-RestMethod -Uri $HealthURL -Method GET -TimeoutSec 30
    if ($healthResponse.status -eq "healthy") {
        Write-Host "✅ Health check OK" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Health check: $($healthResponse.status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Health check falhou (pode levar alguns minutos para ficar disponível)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📋 Comandos úteis para Windows 11:" -ForegroundColor Cyan
Write-Host ""
Write-Host "# Ver logs em tempo real:" -ForegroundColor White
Write-Host "func azure functionapp logstream $FunctionApp" -ForegroundColor Gray
Write-Host ""
Write-Host "# Executar scan manual:" -ForegroundColor White
Write-Host "Invoke-RestMethod -Uri '$ApiURL?network=$NetworkCIDR&details=true' -Method GET" -ForegroundColor Gray
Write-Host ""
Write-Host "# Monitorar execuções:" -ForegroundColor White
Write-Host "az functionapp log tail --name $FunctionApp --resource-group $ResourceGroup" -ForegroundColor Gray
Write-Host ""
Write-Host "# Deletar recursos (quando não precisar mais):" -ForegroundColor White
Write-Host "az group delete --name $ResourceGroup --yes" -ForegroundColor Gray
Write-Host ""
Write-Host "🎉 Network Scanner PowerShell está rodando no Azure!" -ForegroundColor Green
Write-Host "A função executará automaticamente a cada 10 minutos." -ForegroundColor Yellow

# Salvar informações em arquivo
$deployInfo = @{
    ResourceGroup = $ResourceGroup
    FunctionApp = $FunctionApp
    StorageAccount = $StorageAccount
    FunctionURL = $FunctionURL
    ApiURL = $ApiURL
    HealthURL = $HealthURL
    NetworkCIDR = $NetworkCIDR
    DeployDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$deployInfo | ConvertTo-Json -Depth 5 | Out-File -FilePath "deploy-info.json" -Encoding UTF8
Write-Host ""
Write-Host "📄 Informações do deploy salvas em: deploy-info.json" -ForegroundColor Cyan

