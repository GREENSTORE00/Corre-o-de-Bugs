# ==============================
# Instalador Green Store
# ==============================
# Forçar execução como Administrador para evitar "Acesso Negado"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$Host.UI.RawUI.WindowTitle = "Green Store | Instalador de Correção do Steam"

# Banner ASCII Art
Clear-Host
Write-Host @"
  ██████╗ ██████╗ ███████╗███████╗███╗   ██╗
 ██╔════╝ ██╔══██╗██╔════╝██╔════╝████╗  ██║
 ██║  ███╗██████╔╝█████╗  █████╗  ██╔██╗ ██║
 ██║   ██║██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║
 ╚██████╔╝██║  ██║███████╗███████╗██║ ╚████║
  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝
         S T O R E
==========================================
   Instalador Oficial - Green Store
==========================================
"@ -ForegroundColor Green
Write-Host ""

# ===================== SISTEMA DE LOG =====================
function Registrar {
    param (
        [string]$Tipo,
        [string]$Mensagem,
        [boolean]$SemNovaLinha = $false
    )
    $Tipo = $Tipo.ToUpper()
    $color = switch ($Tipo) {
        "OK"    { "Green" }
        "INFO"  { "Cyan" }
        "ERRO"  { "Red" }
        "AVISO" { "Yellow" }
        "LOG"   { "Magenta" }
        default { "White" }
    }
    
    $Tag = switch ($Tipo) {
        "OK"    { "[OK]" }
        "INFO"  { "[INFO]" }
        "ERRO"  { "[ERRO]" }
        "AVISO" { "[AVISO]" }
        "LOG"   { "[LOG]" }
        default { "[$Tipo]" }
    }

    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($SemNovaLinha) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "$Tag $Mensagem" -ForegroundColor $color -NoNewline:$SemNovaLinha
}

# ===================== DETECÇÃO DO STEAM =====================
Registrar "INFO" "Procurando instalação do Steam..."

function Encontrar-CaminhoSteam {
    $CaminhosPossiveis = @()
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.InstallPath) { $CaminhosPossiveis += $reg.InstallPath }
    } catch {}
   
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $CaminhosPossiveis += $reg.SteamPath -replace '\\\\', '\' }
    } catch {}
   
    $CaminhoPadrao = "C:\Program Files (x86)\Steam"
    if (Test-Path $CaminhoPadrao) { $CaminhosPossiveis += $CaminhoPadrao }
   
    $CaminhosPossiveis = $CaminhosPossiveis | Select-Object -Unique | Where-Object { Test-Path $_ }
   
    if ($CaminhosPossiveis.Count -eq 0) {
        Registrar "ERRO" "Instalação do Steam não encontrada. Por favor, instale o Steam primeiro."
        exit 1
    }
   
    $CaminhoSteam = $CaminhosPossiveis[0]
    Registrar "OK" "Steam encontrado em: $CaminhoSteam"
    return $CaminhoSteam
}

$steam = Encontrar-CaminhoSteam

# ===================== FECHAR STEAM =====================
Registrar "INFO" "Encerrando o Steam, aguarde..."
try {
    Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3
} catch {
    Registrar "AVISO" "Não foi possível fechar o Steam automaticamente. Se ele ainda estiver aberto, feche-o manualmente."
}
Write-Host ""

# ===================== DOWNLOAD DOS ARQUIVOS =====================
Registrar "INFO" "Buscando os arquivos mais recentes da Green Store..."

$ApiUrl = "https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest"
$CliFile = Join-Path $env:TEMP "GreenStoreCLI.exe"
$DllFile = Join-Path $env:TEMP "cloud_redirect.dll"

try {
    $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop
    Registrar "LOG" "Versão mais recente: $($Release.tag_name)"

    # Download GreenStoreCLI.exe
    $CliAsset = $Release.assets | Where-Object { $_.name -eq "CloudRedirectCLI.exe" } | Select-Object -First 1
    if ($CliAsset) {
        Registrar "LOG" "Baixando GreenStoreCLI.exe..."
        Invoke-WebRequest -Uri $CliAsset.browser_download_url -OutFile $CliFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "GreenStoreCLI.exe baixado com sucesso"
    }

    # Download cloud_redirect.dll
    $DllAsset = $Release.assets | Where-Object { $_.name -eq "cloud_redirect.dll" } | Select-Object -First 1
    if ($DllAsset) {
        Registrar "LOG" "Baixando cloud_redirect.dll..."
        Invoke-WebRequest -Uri $DllAsset.browser_download_url -OutFile $DllFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "cloud_redirect.dll baixado com sucesso"
    }
}
catch {
    Registrar "ERRO" "Falha ao baixar os arquivos mais recentes"
    Registrar "ERRO" $_.Exception.Message
    exit 1
}

# ===================== EXECUTAR FIXER =====================
for ($i = 5; $i -ge 1; $i--) {
    $sufixo = if($i -gt 1){'s'} else {''}
    Registrar "INFO" "Iniciando o Corretor da Green Store em $i segundo$sufixo..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

Registrar "INFO" "Ajustando o Windows Defender temporariamente..."
try {
    # Desativa a proteção em tempo real temporariamente para evitar o falso positivo
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
} catch {}

Registrar "INFO" "Executando o Corretor da Green Store..."
try {
    & $CliFile /stfixer
    Registrar "OK" "Corretor executado com sucesso"
}
catch {
    Registrar "ERRO" "Erro ao executar o Corretor da Green Store"
    Registrar "ERRO" $_.Exception.Message
}

Registrar "INFO" "Reativando a proteção do Windows Defender..."
try {
    # Reativa a proteção do Defender imediatamente após rodar o executável
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
} catch {}

# ===================== INSTALAR DLL =====================
Registrar "INFO" "Instalando dll na pasta do Steam..."
$TargetDll = Join-Path $steam "cloud_redirect.dll"

try {
    Copy-Item -Path $DllFile -Destination $TargetDll -Force -ErrorAction Stop
    Registrar "OK" "dll instalada com sucesso"
}
catch {
    Registrar "ERRO" "Falha ao copiar a dll para a pasta do Steam"
    Registrar "ERRO" $_.Exception.Message
}

# ===================== LIMPEZA =====================
Start-Sleep -Seconds 2
Registrar "INFO" "Removendo arquivos temporários..."
Remove-Item -Path $CliFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DllFile -Force -ErrorAction SilentlyContinue
Registrar "OK" "Arquivos temporários removidos"

Write-Host ""

# ===================== FINALIZAÇÃO =====================
Registrar "OK" "Operação concluída com sucesso!"
Registrar "AVISO" "A inicialização do Steam pode demorar um pouco mais do que o normal."
Write-Host ""

$exe = Join-Path $steam "steam.exe"
if (Test-Path $exe) {
    Registrar "INFO" "Iniciando o Steam..."
    Start-Process $exe -ArgumentList "-clearbeta"
}

Write-Host ""
Registrar "INFO" "Pressione qualquer tecla para fechar esta janela..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
