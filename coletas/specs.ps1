# Get-SystemSpecs.ps1
# Script para gerar especificações do sistema em Markdown bonito para Jira + verificação de requisitos

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

# === Verificação de requisitos mínimos ===
$motivos = @()

# CPU: pelo menos Intel Core i5 10ª geração ou superior (i7/i9 também aprovam por serem superiores)
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

if ($gen -ge 10 -and $serie -ge 5) {  # i5/i7/i9 com 10ª gen ou superior
    $cpuOk = $true
} elseif ($serie -in '7','9') {        # i7 ou i9 (mesmo gerações mais antigas são geralmente fortes)
    $cpuOk = $true
}

if (-not $cpuOk) { $motivos += 'CPU' }

# RAM: pelo menos 16 GB total
$ramOk = $ramTotal -ge 16
if (-not $ramOk) { $motivos += 'RAM' }

# Armazenamento: pelo menos 40 GB livre no C:
$discoOk = $discoLivre -ge 40
if (-not $discoOk) { $motivos += 'Armazenamento' }

# Resultado da verificação
if ($motivos.Count -eq 0) {
    $status = '*Ambiente aprovado*'
} else {
    $status = "*Ambiente reprovado por: $($motivos -join ' | ')*"
}

@"
# Especificações do Sistema

**Sistema Operacional:** $os.Caption  
**Processador:** $cpu  
**Memória RAM:** $ramInfo  
**Armazenamento (C:):** $discoInfo  
**Conexão de Internet:** $internet  
**Antivírus:** $antivirus  
**Hostname:** $hostname  

**Verificação de Requisitos:** $status

"@
