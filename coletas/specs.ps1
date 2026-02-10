# Get-SystemSpecs.ps1
$hostname = (Get-CimInstance Win32_OperatingSystem).CSName
$os = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor).Name -join ', '

# RAM
$ramLivre = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

# Armazenamento
$discos = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$discosInfo = @()

foreach($d in $discos) {
    $livre = [math]::Round($d.FreeSpace / 1GB, 2)
    $total = [math]::Round($d.Size / 1GB, 2)
    
    # Obter informações do disco físico
    $partition = Get-Partition | Where-Object {$_.DriveLetter -eq $d.DeviceID.Trim(':')}
    $discoFisico = Get-PhysicalDisk | Where-Object {$_.DeviceID -eq $partition.DiskNumber}
    
    $discoTipo = if($discoFisico) {
        if($discoFisico.MediaType -eq 'SSD') {
            if($discoFisico.BusType -eq 'NVMe') {'SSD NVMe'} else {'SSD'}
        } elseif($discoFisico.MediaType -eq 'HDD') {'HD'} else {'Desconhecido'}
    } else {'Desconhecido'}
    
    $discosInfo += "$($d.DeviceID) $livre GB Livre | $total GB Total ($discoTipo)"
}

$armazenamentoTexto = if($discosInfo.Count -gt 1) {
    "`n" + ($discosInfo | ForEach-Object { "  $_" }) -join "`n"
} else {
    " $($discosInfo[0])"
}

# USB
$usbControllers = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'}
$usbHubs = Get-PnpDevice | Where-Object {$_.FriendlyName -like '*USB Hub*' -and $_.Status -eq 'OK'}
$totalUSB = $usbHubs.Count

# Verificar USB 3.0
$usb3 = Get-PnpDevice | Where-Object {
    ($_.FriendlyName -like '*USB 3.*' -or 
     $_.FriendlyName -like '*xHCI*' -or 
     $_.FriendlyName -like '*Extensible Host Controller*') -and 
    $_.Status -eq 'OK'
}
$temUSB3 = if($usb3) {'Sim'} else {'Não'}

# Firewall
$portas = @(
    @{Host='api.zscansoftware.com'; Ports=@(80,443)}
    @{Host='cloud.zscansoftware.com'; Ports=@(80,443)}
)
$firewallInfo = foreach($p in $portas) {
    $status80 = if(Test-NetConnection -ComputerName $p.Host -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue){'Liberada'}else{'Bloqueada'}
    $status443 = if(Test-NetConnection -ComputerName $p.Host -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue){'Liberada'}else{'Bloqueada'}
    "$($p.Host) (80 | 443): $status80 | $status443"
}

# Windows Original
$winProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
$winOriginal = if($winProduct.LicenseStatus -eq 1){'Sim'}else{'Não'}

# Antivírus
$av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
$antivirus = if($av){$av.displayName -join ', '}else{'Não detectado'}

# Internet
$net = Get-NetAdapter | Where-Object {$_.Status -eq 'Up' -and $_.Name -notlike '*Bluetooth*'}
$internet = if($net.Name -like '*Wi-Fi*' -or $net.Name -like '*Wireless*'){'Wi-Fi'}else{'Cabeada'}

# IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress

# Zscan7
$zscanPath = 'C:\Zscan7'
$zscanSize = 0
$zscanInfo = ''
if(Test-Path $zscanPath) {
    $zscanSize = [math]::Round((Get-ChildItem -Path $zscanPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    $zscanInfo = "`nMigração Zscan7: $zscanSize GB"
}

# Parecer Técnico
$motivos = @()
$discoC = $discos | Where-Object {$_.DeviceID -eq 'C:'}
$discoCLivre = [math]::Round($discoC.FreeSpace / 1GB, 2)

# CPU: i5 12ª geração ou superior
$cpuOk = $false
$gen = 0
$serie = 0

# Detectar geração
if($cpu -match '(\d+)th Gen') {
    $gen = [int]$matches[1]
} elseif($cpu -match 'i[5-9]-(\d{4,5})') {
    $modelo = $matches[1]
    if($modelo.Length -eq 4) {
        $gen = [int]$modelo.Substring(0,1)
    } elseif($modelo.Length -eq 5) {
        $gen = [int]$modelo.Substring(0,2)
    }
}

# Detectar série
if($cpu -match 'i([5-9])') {
    $serie = [int]$matches[1]
}

# Verificar aprovação
if($serie -eq 5 -and $gen -ge 12) {
    $cpuOk = $true
} elseif($serie -in 7,9 -and $gen -ge 12) {
    $cpuOk = $true
}

if(-not $cpuOk) { 
    $motivos += 'processador estar abaixo dos requisitos técnicos (i5 12ª geração ou superior)' 
}

# RAM: 12GB
if($ramTotal -lt 12) { 
    $falta = [math]::Ceiling(12 - $ramTotal)
    $motivos += "requisitos mínimos de 12GB de RAM não atendidos, é necessário adicionar pelo menos $falta GB de RAM" 
}

# Armazenamento: 30GB + (Zscan7 * 1.5)
$necessario = 30 + ($zscanSize * 1.5)
if($discoCLivre -lt $necessario) { 
    $falta = [math]::Ceiling($necessario - $discoCLivre)
    $motivos += "falta de Armazenamento, é necessário adicionar pelo menos $falta GB" 
}

# Windows Original
if($winOriginal -eq 'Não') { 
    $motivos += 'Windows não estar ativado, é necessário adquirir uma licença. Nosso time comercial é parceiro oficial da Microsoft caso desejam obter conosco' 
}

# Firewall
$portasBloqueadas = @()
foreach($p in $portas) {
    if(-not (Test-NetConnection -ComputerName $p.Host -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        $portasBloqueadas += "$($p.Host):80"
    }
    if(-not (Test-NetConnection -ComputerName $p.Host -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        $portasBloqueadas += "$($p.Host):443"
    }
}
if($portasBloqueadas.Count -gt 0) {
    $motivos += "bloqueios das portas $($portasBloqueadas -join ', ') no Firewall do Windows. Necessário o responsável de TI da clínica realizar as liberações"
}

# Resultado
$parecer = if($motivos.Count -eq 0) {
    'Ambiente aprovado no geral'
} else {
    "Ambiente reprovado por:`n" + (1..$motivos.Count | ForEach-Object { "$_. $($motivos[$_-1])" }) -join "`n"
}

@"
----------------------------------------
COMPUTADOR: $hostname
----------------------------------------
Geral
Sistema Operacional: $($os.Caption)
Processador: $cpu
Memória RAM: $ramLivre GB Livre | $ramTotal GB Total
Armazenamento:$armazenamentoTexto

Firewall
$($firewallInfo -join "`n")

Extras
Windows Original: $winOriginal
Antivírus: $antivirus
Conexão de Internet: $internet
Endereço IP: $ip
Portas USB: $totalUSB
USB 3.0: $temUSB3$zscanInfo

Parecer técnico
$parecer
----------------------------------------
"@
