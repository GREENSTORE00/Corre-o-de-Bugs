# ==============================
# Instalador CloudRedirect
# ==============================
$Host.UI.RawUI.WindowTitle = "Instalador CloudRedirect"

# ===================== SISTEMA DE LOGS =====================
function Registrar {
    param (
        [string]$Tipo,
        [string]$Mensagem,
        [boolean]$SemNovaLinha = $false
    )
    $Tipo = $Tipo.ToUpper()
    $cor = switch ($Tipo) {
        "OK"    { "Green" }
        "INFO"  { "Cyan" }
        "ERRO"  { "Red" }
        "AVISO" { "Yellow" }
        "LOG"   { "Magenta" }
        default { "White" }
    }
    $data = Get-Date -Format "HH:mm:ss"
    $prefixo = if ($SemNovaLinha) { "`r[$data] " } else { "[$data] " }
    Write-Host $prefixo -ForegroundColor Cyan -NoNewline
    Write-Host "[$Tipo] $Mensagem" -ForegroundColor $cor -NoNewline:$SemNovaLinha
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
Registrar "INFO" "Encerrando o Steam se estiver em execução..."
Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""

# ===================== BAIXAR ARQUIVOS MAIS RECENTES =====================
Registrar "INFO" "Buscando os arquivos mais recentes do CloudRedirect..."

$ApiUrl = "https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest"
$CliFile = Join-Path $env:TEMP "CloudRedirectCLI.exe"
$DllFile = Join-Path $env:TEMP "cloud_redirect.dll"

try {
    $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop
    Registrar "LOG" "Versão mais recente: $($Release.tag_name)"

    # Baixar CloudRedirectCLI.exe
    $CliAsset = $Release.assets | Where-Object { $_.name -eq "CloudRedirectCLI.exe" } | Select-Object -First 1
    if ($CliAsset) {
        Registrar "LOG" "Baixando CloudRedirectCLI.exe..."
        Invoke-WebRequest -Uri $CliAsset.browser_download_url -OutFile $CliFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "CloudRedirectCLI.exe baixado"
    }

    # Baixar cloud_redirect.dll
    $DllAsset = $Release.assets | Where-Object { $_.name -eq "cloud_redirect.dll" } | Select-Object -First 1
    if ($DllAsset) {
        Registrar "LOG" "Baixando cloud_redirect.dll..."
        Invoke-WebRequest -Uri $DllAsset.browser_download_url -OutFile $DllFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "cloud_redirect.dll baixado"
    }
}
catch {
    Registrar "ERRO" "Falha ao baixar os arquivos mais recentes"
    Registrar "ERRO" $_.Exception.Message
    exit 1
}

# ===================== EXECUTAR CLI =====================
for ($i = 5; $i -ge 1; $i--) {
    Registrar "INFO" "Iniciando o Corretor CloudRedirect em $i segundo$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

Registrar "INFO" "Executando o Corretor CloudRedirect..."
try {
    & $CliFile /stfixer
    Registrar "OK" "CloudRedirectCLI executado com sucesso"
}
catch {
    Registrar "ERRO" "Erro ao executar o CloudRedirectCLI"
    Registrar "ERRO" $_.Exception.Message
}

# ===================== INSTALAR DLL =====================
Registrar "INFO" "Instalando cloud_redirect.dll na pasta do Steam..."
$TargetDll = Join-Path $steam "cloud_redirect.dll"

try {
    Copy-Item -Path $DllFile -Destination $TargetDll -Force -ErrorAction Stop
    Registrar "OK" "cloud_redirect.dll instalada com sucesso"
}
catch {
    Registrar "ERRO" "Falha ao copiar cloud_redirect.dll"
    Registrar "ERRO" $_.Exception.Message
}

# ===================== LIMPEZA =====================
Start-Sleep -Seconds 2
Registrar "INFO" "Limpando arquivos temporários..."
Remove-Item -Path $CliFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DllFile -Force -ErrorAction SilentlyContinue
Registrar "OK" "Arquivos temporários removidos"

Write-Host ""

# ===================== FINAL =====================
Registrar "OK" "Operação concluída com sucesso!"
Registrar "AVISO" "A inicialização do Steam pode demorar mais que o normal."
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
