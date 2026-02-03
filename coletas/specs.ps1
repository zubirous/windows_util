# Get-SystemSpecs.ps1
# Script para gerar especificações do sistema em Markdown bonito para Jira + verificações

$os = Get-CimInstance Win32_OperatingSystem

$cpu = (Get-CimInstance Win32_Processor).Name -join ', '

$ramLivre = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$ramTypeCode = (Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).SMBIOSMemoryType
$ramTipo = switch($ramTypeCode) {
    20 {'DDR'}
    21 {'DDR2'}
    24 {'DDR3'}
    26 {'DDR4'}
    34 {'DDR5'}
    default {'Desconhecido'}
}
$ramInfo = "$ramLivre GB livre de $ramTotal GB total ($ramTipo)"

$disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$discoLivre = [math]::Round($disco.FreeSpace / 1GB, 2)
$discoTotal = [math]::Round($disco.Size / 1GB, 2)
$discoFisico = Get-PhysicalDisk | Where-Object {$_.DeviceID -eq 0}
$discoTipo = if($discoFisico.MediaType -eq 'SSD') {
    if($discoFisico.BusType -eq 'NVMe') {'NVMe'} else {'SSD'}
} elseif($discoFisico.MediaType -eq 'HDD') {'HD'} else {'Desconhecido'}
$discoInfo = "$discoLivre GB livre de $discoTotal GB total ($discoTipo)"

$net = Get-NetAdapter | Where-Object {$_.Status -eq 'Up' -and $_.Name -notlike '*Bluetooth*'}
$internet = if($net.Name -like '*Wi-Fi*' -or $net.Name -like '*Wireless*') {'Wi-Fi'} else {'Cabeada'}

$av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
$antivirus = if($av) {$av.displayName -join ', '} else {'Não detectado'}

$hostname = $os.CSName

# === Verificação de ativação do Windows ===
$winProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
$winAtivado = if($winProduct.LicenseStatus -eq 1) {'Sim'} else {'Não'}

# === Verificação de portas (Test-NetConnection) ===
$portasTeste = @(
    @{Host = 'api.zscansoftware.com';   Port = 80;  Nome = 'api.zscansoftware.com (80)'}
    @{Host = 'api.zscansoftware.com';   Port = 443; Nome = 'api.zscansoftware.com (443)'}
    @{Host = 'cloud.zscansoftware.com'; Port = 80;  Nome = 'cloud.zscansoftware.com (80)'}
    @{Host = 'cloud.zscansoftware.com'; Port = 443; Nome = 'cloud.zscansoftware.com (443)'}
    @{Host = '127.0.0.1';               Port = 4914; Nome = 'localhost (4914)'}
)

$portasStatus = foreach($item in $portasTeste) {
    $ok = Test-NetConnection -ComputerName $item.Host -Port $item.Port -InformationLevel Quiet -WarningAction SilentlyContinue
    "$($item.Nome): $(if($ok){'Liberada'}else{'Bloqueada'})"
}

# === Verificação de requisitos mínimos (CPU, RAM, Disco) ===
$motivos = @()

# CPU: i5 10ª gen ou superior, ou i7/i9 qualquer gen
$cpuOk = $false
$gen = 0
if ($cpu -match '(\d+)th Gen') {
    $gen = [int]$matches[1]
} elseif ($cpu -match 'i[5-9]-(\d{4,5})') {
    $model = $matches[1]
    if ($model.Length -ge 4) { $gen = [int]$model.Substring(0,2) }
}

$serie = ''
if ($cpu -match 'i([5-9])') { $serie = $matches[1] }

if ($gen -ge 10 -and $serie -ge 5) {
    $cpuOk = $true
} elseif ($serie -in '7','9') {
    $cpuOk = $true
}

if (-not $cpuOk) { $motivos += 'CPU' }

# RAM: ≥ 14 GB total
$ramOk = $ramTotal -ge 14
if (-not $ramOk) { $motivos += 'RAM' }

# Disco: ≥ 40 GB livre
$discoOk = $discoLivre -ge 40
if (-not $discoOk) { $motivos += 'Armazenamento' }

if ($motivos.Count -eq 0) {
    $status = '*Ambiente aprovado*'
} else {
    $status = "*Ambiente reprovado por: $($motivos -join ' | ')*"
}

@"
# Especificações do Sistema

**Sistema Operacional:** $($os.Caption)  
**Processador:** $cpu  
**Memória RAM:** $ramInfo  
**Armazenamento (C:):** $discoInfo  
**Conexão de Internet:** $internet  
**Antivírus:** $antivirus  
**Hostname:** $hostname  

**Windows Ativado:** $winAtivado  

**Portas no Firewall:**
$( $portasStatus -join "  
" )

**Verificação de Requisitos:** $status

"@
