# Network Scanner Azure Function

Uma Azure Function em Python que executa scan de rede periodicamente (a cada 10 minutos) para detectar máquinas Windows e Linux usando o valor TTL do ICMP/Ping.

## 🎯 Funcionalidades

- **Scan Automático**: Executa a cada 10 minutos automaticamente
- **Detecção de SO**: Identifica Windows, Linux e dispositivos de rede baseado no TTL
- **API REST**: Endpoint para execução manual e consulta de status
- **Paralelização**: Scan rápido usando múltiplas threads
- **Logging**: Logs detalhados para monitoramento
- **Configurável**: Rede CIDR e parâmetros configuráveis via variáveis de ambiente

## 🏗️ Arquitetura

```
network-scanner/
├── function_app.py          # Função principal Azure Functions
├── network_scanner.py       # Lógica de scan de rede
├── requirements.txt         # Dependências Python
├── host.json               # Configuração do host
├── local.settings.json     # Configurações locais
├── test_scanner.py         # Testes automatizados
├── .funcignore             # Arquivos ignorados no deploy
└── README.md               # Esta documentação
```

## 🔧 Detecção de Sistema Operacional

A detecção é baseada nos valores típicos de TTL:

| Sistema Operacional | TTL Típico | Faixa Aceita |
|-------------------|------------|--------------|
| Windows 10/11/Server | 128 | 120-135 |
| Linux/Unix | 64 | 60-70 |
| Dispositivos de Rede | 255 | 250-255 |

**Nota**: O TTL pode ser decrementado por roteadores, então a função considera uma margem de tolerância.

## 📋 Pré-requisitos

### Desenvolvimento Local
- Python 3.8 ou superior
- Azure Functions Core Tools v4
- Azure CLI
- Conta Azure com permissões para criar recursos

### Instalação das Ferramentas

```bash
# Azure CLI (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Azure Functions Core Tools
npm install -g azure-functions-core-tools@4 --unsafe-perm true

# Verificar instalação
func --version
az --version
```

## 🚀 Deploy no Azure

### 1. Preparar o Ambiente

```bash
# Login no Azure
az login

# Criar grupo de recursos
az group create --name rg-network-scanner --location "East US"

# Criar conta de armazenamento
az storage account create \
  --name stnetworkscanner001 \
  --resource-group rg-network-scanner \
  --location "East US" \
  --sku Standard_LRS

# Criar Function App
az functionapp create \
  --resource-group rg-network-scanner \
  --consumption-plan-location "East US" \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --name func-network-scanner-001 \
  --storage-account stnetworkscanner001 \
  --os-type Linux
```

### 2. Configurar Variáveis de Ambiente

```bash
# Configurar rede a ser escaneada
az functionapp config appsettings set \
  --name func-network-scanner-001 \
  --resource-group rg-network-scanner \
  --settings NETWORK_CIDR="10.1.2.0/24"

# Configurar número máximo de workers
az functionapp config appsettings set \
  --name func-network-scanner-001 \
  --resource-group rg-network-scanner \
  --settings MAX_WORKERS="50"

# Habilitar logs detalhados (opcional)
az functionapp config appsettings set \
  --name func-network-scanner-001 \
  --resource-group rg-network-scanner \
  --settings SAVE_DETAILED_RESULTS="true"
```

### 3. Deploy da Função

```bash
# Navegar para o diretório do projeto
cd network-scanner

# Deploy
func azure functionapp publish func-network-scanner-001 --python
```

## 🧪 Desenvolvimento Local

### 1. Configurar Ambiente Local

```bash
# Clonar/baixar o projeto
cd network-scanner

# Instalar dependências
pip install -r requirements.txt

# Configurar settings locais (editar local.settings.json)
{
  "Values": {
    "NETWORK_CIDR": "192.168.1.0/24",
    "MAX_WORKERS": "30",
    "SAVE_DETAILED_RESULTS": "false"
  }
}
```

### 2. Executar Localmente

```bash
# Iniciar Azure Functions runtime
func start

# A função estará disponível em:
# Timer: Executa automaticamente a cada 10 minutos
# HTTP: http://localhost:7071/api/scan
# Health: http://localhost:7071/api/health
```

### 3. Executar Testes

```bash
# Executar testes automatizados
python test_scanner.py

# Teste manual do scanner
python -c "from network_scanner import scan_network_segment; print(scan_network_segment('127.0.0.0/28'))"
```

## 📡 API Endpoints

### GET/POST /api/scan
Executa scan manual da rede.

**Parâmetros Query String:**
- `network`: Rede CIDR (padrão: configuração da função)
- `max_workers`: Número de workers (padrão: 50)
- `details`: Incluir detalhes dos hosts (true/false)

**Exemplo de Requisição:**
```bash
# Scan com parâmetros padrão
curl https://func-network-scanner-001.azurewebsites.net/api/scan

# Scan com rede específica
curl "https://func-network-scanner-001.azurewebsites.net/api/scan?network=192.168.1.0/24&details=true"

# POST com JSON
curl -X POST https://func-network-scanner-001.azurewebsites.net/api/scan \
  -H "Content-Type: application/json" \
  -d '{"network": "10.0.0.0/24", "max_workers": 30}'
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

```bash
curl https://func-network-scanner-001.azurewebsites.net/api/health
```

## 📊 Monitoramento

### Logs no Azure

```bash
# Ver logs em tempo real
func azure functionapp logstream func-network-scanner-001

# Ou via Azure CLI
az webapp log tail --name func-network-scanner-001 --resource-group rg-network-scanner
```

### Application Insights

A função automaticamente envia telemetria para Application Insights. Acesse o portal Azure para visualizar:

- Métricas de execução
- Logs de aplicação
- Alertas personalizados
- Dashboards de monitoramento

## ⚙️ Configurações Avançadas

### Personalizar Intervalo do Timer

Edite o decorator `@app.timer_trigger` em `function_app.py`:

```python
# A cada 5 minutos
@app.timer_trigger(schedule="0 */5 * * * *", ...)

# A cada hora
@app.timer_trigger(schedule="0 0 * * * *", ...)

# Diariamente às 9:00
@app.timer_trigger(schedule="0 0 9 * * *", ...)
```

### Ajustar Timeout da Função

Edite `host.json`:

```json
{
  "functionTimeout": "00:15:00"  // 15 minutos
}
```

### Configurar Alertas

```bash
# Criar alerta para falhas
az monitor metrics alert create \
  --name "Network Scanner Failures" \
  --resource-group rg-network-scanner \
  --scopes "/subscriptions/{subscription-id}/resourceGroups/rg-network-scanner/providers/Microsoft.Web/sites/func-network-scanner-001" \
  --condition "count 'requests/failed' > 5" \
  --window-size 5m \
  --evaluation-frequency 1m
```

## 🔒 Segurança

### Autenticação da API

Para proteger os endpoints HTTP:

```bash
# Habilitar autenticação
az functionapp auth update \
  --name func-network-scanner-001 \
  --resource-group rg-network-scanner \
  --enabled true \
  --action LoginWithAzureActiveDirectory
```

### Rede Virtual

Para executar em rede privada:

```bash
# Integrar com VNet
az functionapp vnet-integration add \
  --name func-network-scanner-001 \
  --resource-group rg-network-scanner \
  --subnet /subscriptions/{subscription-id}/resourceGroups/{vnet-rg}/providers/Microsoft.Network/virtualNetworks/{vnet-name}/subnets/{subnet-name}
```

## 🐛 Solução de Problemas

### Problemas Comuns

1. **Timeout nos pings**
   - Ajustar `MAX_WORKERS` para um valor menor
   - Verificar conectividade de rede
   - Aumentar timeout da função

2. **Detecção incorreta de SO**
   - Verificar se há roteadores decrementando TTL
   - Ajustar lógica de detecção se necessário

3. **Função não executa**
   - Verificar logs no Application Insights
   - Validar configuração do timer
   - Verificar permissões de rede

### Debug Local

```bash
# Executar com logs detalhados
func start --verbose

# Testar função específica
func start --functions network_scanner_timer
```

## 📝 Licença

Este projeto é fornecido como exemplo educacional. Adapte conforme suas necessidades específicas.

## 🤝 Contribuições

Para melhorias ou correções:

1. Teste localmente
2. Execute os testes automatizados
3. Documente as mudanças
4. Considere impactos de segurança e performance

