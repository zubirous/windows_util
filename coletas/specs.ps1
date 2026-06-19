# Get-SystemSpecs.ps1 – Inventário detalhado sem julgamento

# ---------- Sistema ----------
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS

$hostname    = $cs.Name
$fabricante  = $cs.Manufacturer
$modelo      = $cs.Model
$usuario     = $cs.UserName
$uptime      = (Get-Date) - $os.LastBootUpTime
$instaladoEm = $os.InstallDate
$timezone    = (Get-TimeZone).DisplayName
$osArch      = $os.OSArchitecture

# ---------- CPU ----------
$cpu = (Get-CimInstance Win32_Processor).Name -join ', '

# ---------- Memória RAM ----------
$ramTotal   = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$ramLivre   = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
# sticks físicos
$memSticks  = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    "$($_.Capacity/1GB)GB $($_.Speed)MHz"
}
$memInfo    = if ($memSticks) { ($memSticks -join ', ') } else { 'Não disponível' }

# ---------- Armazenamento ----------
$discosLogicos = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$discosInfo = @()
foreach ($d in $discosLogicos) {
    $livre   = [math]::Round($d.FreeSpace / 1GB, 2)
    $total   = [math]::Round($d.Size / 1GB, 2)
    $fs      = $d.FileSystem

    # Mapear para disco físico (tenta, mas não quebra se falhar)
    $part = Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq $d.DeviceID.Trim(':') }
    $physDisk = if ($part) {
        Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $part.DiskNumber }
    } else { $null }

    $tipo   = if ($physDisk) {
        if ($physDisk.MediaType -eq 'SSD') {
            if ($physDisk.BusType -eq 'NVMe') { 'SSD NVMe' } else { 'SSD' }
        } elseif ($physDisk.MediaType -eq 'HDD') { 'HD' } else { 'Desconhecido' }
    } else { 'Desconhecido' }

    $modelo = if ($physDisk) { $physDisk.FriendlyName } else { '-' }

    $discosInfo += "$($d.DeviceID) $livre GB livre de $total GB ($fs, $tipo, Modelo: $modelo)"
}
$armazenamentoTexto = $discosInfo -join "`n"

# ---------- GPU ----------
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notlike '*Microsoft Basic*' }
$gpuInfo = ($gpus | ForEach-Object { "$($_.Name) (Driver: $($_.DriverVersion))" }) -join "`n"
if (-not $gpuInfo) { $gpuInfo = 'Nenhuma GPU dedicada detectada' }

# ---------- Rede ----------
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike '*Bluetooth*' }
$netInfo = foreach ($a in $adapters) {
    $speed = if ($a.LinkSpeed) { "$($a.LinkSpeed / 1Gb) Gbps" } else { 'Desconhecida' }
    "$($a.Name) ($($a.InterfaceDescription)) – MAC: $($a.MacAddress) – Velocidade: $speed"
}
$internet = if ($adapters.Name -like '*Wi-Fi*' -or $adapters.Name -like '*Wireless*') { 'Wi-Fi' } else { 'Cabeada' }
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress

# ---------- USB ----------
$usbControllers = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
$usbHubs = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like '*USB Hub*' -and $_.Status -eq 'OK' }
$totalUSB = $usbHubs.Count
$usb3 = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    ($_.FriendlyName -like '*USB 3.*' -or 
     $_.FriendlyName -like '*xHCI*' -or 
     $_.FriendlyName -like '*Extensible Host Controller*') -and 
    $_.Status -eq 'OK'
}
$temUSB3 = if ($usb3) { 'Sim' } else { 'Não' }

# ---------- Software ----------
# Windows original/ativado
$winProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
$ativacao = if ($winProduct.LicenseStatus -eq 1) { 'Ativado' } else { 'Não ativado' }

# Antivírus
$av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
$antivirus = if ($av) { $av.displayName -join ', ' } else { 'Não detectado' }

# Zscan7
$zscanPath = 'C:\Zscan7'
$zscanSize = if (Test-Path $zscanPath) {
    [math]::Round((Get-ChildItem -Path $zscanPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
} else { 0 }
$zscanInfo = if ($zscanSize -gt 0) { "Migração Zscan7: $zscanSize GB" } else { '' }

# ---------- Firewall (nota neutra) ----------
$firewallNote = @'
Necessário garantir acesso às portas 80 e 443 para:
- api.zscansoftware.com
- cloud.zscansoftware.com
'@

# ---------- Monta saída ----------
@"
========================================
INVENTÁRIO DO SISTEMA: $hostname
========================================

Sistema
  Fabricante/Modelo: $fabricante $modelo
  BIOS: $($bios.SMBIOSBIOSVersion) ($($bios.Manufacturer))
  Sistema Operacional: $($os.Caption) ($osArch)
  Instalado em: $instaladoEm
  Última inicialização: $($os.LastBootUpTime)
  Tempo ligado: $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)min
  Fuso horário: $timezone
  Usuário logado: $usuario

Processador
  $cpu

Memória RAM
  Total: $ramTotal GB | Livre: $ramLivre GB
  Módulos: $memInfo

Armazenamento
$armazenamentoTexto

Placa(s) de vídeo
$gpuInfo

Rede
  Tipo de conexão: $internet
  IP principal: $ip
$($netInfo -join "`n")

USB
  Total de portas (hubs): $totalUSB
  USB 3.0 presente: $temUSB3

Software
  Ativação do Windows: $ativacao
  Antivírus: $antivirus
  $zscanInfo

Firewall
$firewallNote

========================================
"@
