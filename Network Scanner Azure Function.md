# Network Scanner Azure Function PowerShell

Uma Azure Function em **PowerShell** que executa scan de rede periodicamente (a cada 10 minutos) para detectar máquinas Windows e Linux usando o valor TTL do ICMP/Ping. **Otimizado para Windows 11**.

## 🎯 Funcionalidades

- **Scan Automático**: Executa a cada 10 minutos via Timer Trigger
- **Detecção de SO**: Identifica Windows, Linux e dispositivos de rede baseado no TTL
- **API REST**: Endpoints para execução manual e health check
- **Paralelização**: Scan rápido usando ForEach-Object -Parallel
- **Logging**: Logs detalhados para Application Insights
- **Configurável**: Rede CIDR e parâmetros via variáveis de ambiente
- **100% PowerShell**: Sem dependências Python ou outras linguagens

## 🏗️ Arquitetura

```
network-scanner-powershell/
├── TimerTrigger/
│   ├── run.ps1              # Timer trigger (executa a cada 10 min)
│   └── function.json        # Configuração do timer
├── HttpTrigger/
│   ├── run.ps1              # HTTP trigger para scan manual
│   └── function.json        # Configuração HTTP
├── HealthCheck/
│   ├── run.ps1              # Health check endpoint
│   └── function.json        # Configuração health check
├── Modules/
│   └── NetworkScanner.ps1   # Módulo principal de scan
├── host.json                # Configuração do host
├── requirements.psd1        # Dependências PowerShell
├── local.settings.json      # Configurações locais
├── Deploy-Azure.ps1         # Script de deploy automatizado
├── Test-NetworkScanner.ps1  # Testes automatizados
└── README.md                # Esta documentação
```

## 🔧 Detecção de Sistema Operacional

A detecção é baseada nos valores típicos de TTL:

| Sistema Operacional | TTL Típico | Faixa Aceita |
|-------------------|------------|--------------|
| Windows 10/11/Server | 128 | 120-135 |
| Linux/Unix | 64 | 60-70 |
| Dispositivos de Rede | 255 | 250-255 |

**Nota**: O TTL pode ser decrementado por roteadores, então a função considera uma margem de tolerância.

## 📋 Pré-requisitos para Windows 11

### Software Necessário

1. **PowerShell 7+**
   ```powershell
   winget install Microsoft.PowerShell
   ```

2. **Azure CLI**
   ```powershell
   winget install Microsoft.AzureCLI
   ```

3. **Azure Functions Core Tools**
   ```powershell
   winget install Microsoft.Azure.FunctionsCoreTools
   # OU
   npm install -g azure-functions-core-tools@4 --unsafe-perm true
   ```

4. **Conta Azure** com permissões para criar recursos

### Verificar Instalação

```powershell
# Verificar PowerShell
$PSVersionTable.PSVersion

# Verificar Azure CLI
az --version

# Verificar Functions Core Tools
func --version
```

## 🚀 Deploy no Azure (Windows 11)

### Método 1: Deploy Automatizado (Recomendado)

```powershell
# 1. Fazer login no Azure
az login

# 2. Navegar para o diretório do projeto
cd network-scanner-powershell

# 3. Executar script de deploy
.\Deploy-Azure.ps1 -NetworkCIDR "10.1.2.0/24" -MaxWorkers 50
```

### Método 2: Deploy Manual

```powershell
# 1. Login no Azure
az login

# 2. Criar grupo de recursos
az group create --name "rg-network-scanner-ps" --location "East US"

# 3. Criar conta de armazenamento
az storage account create `
  --name "stnetscanner$(Get-Random)" `
  --resource-group "rg-network-scanner-ps" `
  --location "East US" `
  --sku Standard_LRS

# 4. Criar Function App PowerShell
az functionapp create `
  --resource-group "rg-network-scanner-ps" `
  --consumption-plan-location "East US" `
  --runtime powershell `
  --runtime-version 7.2 `
  --functions-version 4 `
  --name "func-netscanner-ps-$(Get-Random)" `
  --storage-account "stnetscanner$(Get-Random)" `
  --os-type Windows

# 5. Configurar variáveis de ambiente
az functionapp config appsettings set `
  --name "func-netscanner-ps-XXXX" `
  --resource-group "rg-network-scanner-ps" `
  --settings `
    NETWORK_CIDR="10.1.2.0/24" `
    MAX_WORKERS="50" `
    SAVE_DETAILED_RESULTS="false"

# 6. Deploy do código
func azure functionapp publish "func-netscanner-ps-XXXX"
```

## 🧪 Desenvolvimento Local (Windows 11)

### 1. Configurar Ambiente Local

```powershell
# Clonar/baixar o projeto
cd network-scanner-powershell

# Configurar settings locais (editar local.settings.json)
@{
  "Values" = @{
    "NETWORK_CIDR" = "192.168.1.0/24"
    "MAX_WORKERS" = "30"
    "SAVE_DETAILED_RESULTS" = "false"
  }
} | ConvertTo-Json | Set-Content local.settings.json
```

### 2. Executar Localmente

```powershell
# Iniciar Azure Functions runtime
func start

# A função estará disponível em:
# Timer: Executa automaticamente a cada 10 minutos
# HTTP: http://localhost:7071/api/scan
# Health: http://localhost:7071/api/health
```

### 3. Executar Testes

```powershell
# Executar testes automatizados
.\Test-NetworkScanner.ps1

# Teste com verbose
.\Test-NetworkScanner.ps1 -Verbose

# Teste com rede específica
.\Test-NetworkScanner.ps1 -TestNetwork "192.168.1.0/28"
```

## 📡 API Endpoints

### GET/POST /api/scan
Executa scan manual da rede.

**Parâmetros Query String:**
- `network`: Rede CIDR (padrão: configuração da função)
- `max_workers`: Número de workers (padrão: 50)
- `details`: Incluir detalhes dos hosts (true/false)

**Exemplos PowerShell:**

```powershell
# Scan com parâmetros padrão
Invoke-RestMethod -Uri "https://func-netscanner-ps-XXXX.azurewebsites.net/api/scan" -Method GET

# Scan com rede específica
$uri = "https://func-netscanner-ps-XXXX.azurewebsites.net/api/scan?network=192.168.1.0/24&details=true"
Invoke-RestMethod -Uri $uri -Method GET

# POST com JSON
$body = @{
    network = "10.0.0.0/24"
    max_workers = 30
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://func-netscanner-ps-XXXX.azurewebsites.net/api/scan" `
                  -Method POST `
                  -Body $body `
                  -ContentType "application/json"
```

**Exemplo de Resposta:**
```json
{
  "success": true,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "network": "10.1.2.0/24",
  "scan_duration": 2.45,
  "total_hosts_scanned": 254,
  "alive_hosts": 12,
  "os_distribution": {
    "windows": 8,
    "linux": 3,
    "network_device": 1,
    "unknown": 0
  },
  "summary": {
    "windows_count": 8,
    "linux_count": 3,
    "network_devices": 1,
    "unknown_count": 0
  }
}
```

### GET /api/health
Verifica status da função.

```powershell
Invoke-RestMethod -Uri "https://func-netscanner-ps-XXXX.azurewebsites.net/api/health" -Method GET
```

## 📊 Monitoramento (Windows 11)

### Logs em Tempo Real

```powershell
# Ver logs da função
func azure functionapp logstream "func-netscanner-ps-XXXX"

# Ou via Azure CLI
az webapp log tail --name "func-netscanner-ps-XXXX" --resource-group "rg-network-scanner-ps"
```

### Application Insights

A função automaticamente envia telemetria para Application Insights. Acesse o portal Azure para:

- Métricas de execução
- Logs estruturados
- Alertas personalizados
- Dashboards de monitoramento

### Consultas KQL Úteis

```kql
// Resumos de scan nas últimas 24 horas
traces
| where timestamp > ago(24h)
| where message contains "SCAN_SUMMARY"
| project timestamp, message
| order by timestamp desc

// Erros nas funções
exceptions
| where timestamp > ago(24h)
| project timestamp, operation_Name, problemId, details
```

## ⚙️ Configurações Avançadas

### Personalizar Intervalo do Timer

Edite `TimerTrigger/function.json`:

```json
{
  "bindings": [
    {
      "schedule": "0 */5 * * * *"  // A cada 5 minutos
    }
  ]
}
```

Exemplos de schedule:
- `"0 */5 * * * *"` - A cada 5 minutos
- `"0 0 * * * *"` - A cada hora
- `"0 0 9 * * *"` - Diariamente às 9:00
- `"0 0 9 * * 1-5"` - Dias úteis às 9:00

### Ajustar Timeout da Função

Edite `host.json`:

```json
{
  "functionTimeout": "00:15:00"  // 15 minutos
}
```

### Configurar Alertas (PowerShell)

```powershell
# Criar alerta para falhas
az monitor metrics alert create `
  --name "Network Scanner PS Failures" `
  --resource-group "rg-network-scanner-ps" `
  --scopes "/subscriptions/{subscription-id}/resourceGroups/rg-network-scanner-ps/providers/Microsoft.Web/sites/func-netscanner-ps-XXXX" `
  --condition "count 'requests/failed' > 5" `
  --window-size 5m `
  --evaluation-frequency 1m
```

## 🔒 Segurança

### Autenticação da API

```powershell
# Habilitar autenticação Azure AD
az functionapp auth update `
  --name "func-netscanner-ps-XXXX" `
  --resource-group "rg-network-scanner-ps" `
  --enabled true `
  --action LoginWithAzureActiveDirectory
```

### Rede Virtual

```powershell
# Integrar com VNet
az functionapp vnet-integration add `
  --name "func-netscanner-ps-XXXX" `
  --resource-group "rg-network-scanner-ps" `
  --subnet "/subscriptions/{subscription-id}/resourceGroups/{vnet-rg}/providers/Microsoft.Network/virtualNetworks/{vnet-name}/subnets/{subnet-name}"
```

## 🐛 Solução de Problemas

### Problemas Comuns

1. **PowerShell 5.1 vs 7+**
   - Certifique-se de usar PowerShell 7+
   - Verifique: `$PSVersionTable.PSVersion`

2. **Timeout nos pings**
   - Ajustar `MAX_WORKERS` para valor menor
   - Verificar conectividade de rede
   - Aumentar timeout da função

3. **Função não executa**
   - Verificar logs no Application Insights
   - Validar configuração do timer
   - Verificar permissões de rede

4. **Erro de módulo não encontrado**
   - Verificar se `Modules/NetworkScanner.ps1` existe
   - Verificar sintaxe do PowerShell

### Debug Local

```powershell
# Executar com logs detalhados
func start --verbose

# Testar função específica
func start --functions TimerTrigger

# Testar módulo diretamente
. .\Modules\NetworkScanner.ps1
Test-NetworkScanner
```

### Comandos de Diagnóstico

```powershell
# Verificar configuração da função
az functionapp config show --name "func-netscanner-ps-XXXX" --resource-group "rg-network-scanner-ps"

# Verificar logs recentes
az functionapp log download --name "func-netscanner-ps-XXXX" --resource-group "rg-network-scanner-ps"

# Testar conectividade
Test-NetConnection -ComputerName "func-netscanner-ps-XXXX.azurewebsites.net" -Port 443
```

## 📈 Performance

### Benchmarks Típicos

- **Rede /24 (254 IPs)**: ~30-60 segundos
- **Rede /28 (14 IPs)**: ~5-10 segundos
- **Rede /16 (65k IPs)**: ~20-30 minutos

### Otimizações

```powershell
# Para redes grandes, ajustar configurações
$env:MAX_WORKERS = "100"        # Mais threads
$env:PING_TIMEOUT = "1000"      # Timeout menor
```

## 🔄 Atualizações e Manutenção

### Atualizar Código

```powershell
# Re-deploy após mudanças
func azure functionapp publish "func-netscanner-ps-XXXX"
```

### Backup da Configuração

```powershell
# Exportar configurações
az functionapp config appsettings list `
  --name "func-netscanner-ps-XXXX" `
  --resource-group "rg-network-scanner-ps" `
  --output json > backup-settings.json
```

## 📝 Licença

Este projeto é fornecido como exemplo educacional. Adapte conforme suas necessidades específicas.

## 🤝 Contribuições

Para melhorias ou correções:

1. Teste localmente com `.\Test-NetworkScanner.ps1`
2. Execute os testes automatizados
3. Documente as mudanças
4. Considere impactos de segurança e performance

## 📞 Suporte

- **Issues**: Problemas de configuração ou bugs
- **Documentação**: Este README.md
- **Testes**: Execute `.\Test-NetworkScanner.ps1 -Verbose`
- **Logs**: Use Application Insights no portal Azure

