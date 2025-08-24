# Verificar PowerShell
$PSVersionTable.PSVersion
# Verificar Azure CLI
az --version
# Verificar Functions Core Tools
func --version

# Cria local.settings.json
@{
  "Values" = @{
    "NETWORK_CIDR" = "10.1.1.0/24"
    "MAX_WORKERS" = "30"
    "SAVE_DETAILED_RESULTS" = "false"
  }
} | ConvertTo-Json | Set-Content local.settings.json

func start