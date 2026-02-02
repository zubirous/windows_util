# Get-SystemSpecs.ps1
# Script para gerar especificações do sistema em Markdown bonito para Jira

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

@"
# Especificações do Sistema

**Sistema Operacional:** $os.Caption  
**Processador:** $cpu  
**Memória RAM:** $ramInfo  
**Armazenamento (C:):** $discoInfo  
**Conexão de Internet:** $internet  
**Antivírus:** $antivirus  
**Hostname:** $hostname

"@
