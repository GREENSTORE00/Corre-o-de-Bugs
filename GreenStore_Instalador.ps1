# ==============================
# Green Store - Instalador de Correção
# ==============================
$Host.UI.RawUI.WindowTitle = "Green Store | Instalador de Correção do Steam"

# ===================== SISTEMA DE LOG =====================
function Registrar {
    param (
        [string]$Tipo,
        [string]$Mensagem,
        [boolean]$SemNovaLinha = $false
    )
    $Tipo = $Tipo.ToUpper()
    $cor = switch ($Tipo) {
        "OK"      { "Green" }
        "INFO"    { "Cyan" }
        "ERRO"    { "Red" }
        "AVISO"   { "Yellow" }
        "LOG"     { "Magenta" }
        default   { "White" }
    }
    $hora = Get-Date -Format "HH:mm:ss"
    $prefixo = if ($SemNovaLinha) { "`r[$hora] " } else { "[$hora] " }
    Write-Host $prefixo -ForegroundColor Cyan -NoNewline
    Write-Host "[$Tipo] $Mensagem" -ForegroundColor $cor -NoNewline:$SemNovaLinha
}

# ===================== BANNER DA GREEN STORE =====================
Write-Host ""
Write-Host "  ██████╗ ██████╗ ███████╗███████╗███╗   ██╗" -ForegroundColor Green
Write-Host " ██╔════╝ ██╔══██╗██╔════╝██╔════╝████╗  ██║" -ForegroundColor Green
Write-Host " ██║  ███╗██████╔╝█████╗  █████╗  ██╔██╗ ██║" -ForegroundColor Green
Write-Host " ██║   ██║██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║" -ForegroundColor Green
Write-Host " ╚██████╔╝██║  ██║███████╗███████╗██║ ╚████║" -ForegroundColor Green
Write-Host "  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝" -ForegroundColor Green
Write-Host ""
Write-Host "        S T O R E" -ForegroundColor DarkGreen
Write-Host ""
Write-Host " ==========================================" -ForegroundColor DarkGreen
Write-Host "   Instalador Oficial - Green Store" -ForegroundColor White
Write-Host " ==========================================" -ForegroundColor DarkGreen
Write-Host ""

# ===================== DETECÇÃO DO STEAM =====================
Registrar "INFO" "Procurando instalação do Steam..."

function Encontrar-CaminhoSteam {
    $CaminhosPossiveis = @()

    try {
        $registro = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($registro.InstallPath) { $CaminhosPossiveis += $registro.InstallPath }
    } catch {}

    try {
        $registro = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($registro.SteamPath) { $CaminhosPossiveis += $registro.SteamPath -replace '\\\\', '\' }
    } catch {}

    $CaminhoPadrao = "C:\Program Files (x86)\Steam"
    if (Test-Path $CaminhoPadrao) { $CaminhosPossiveis += $CaminhoPadrao }

    $CaminhosPossiveis = $CaminhosPossiveis | Select-Object -Unique | Where-Object { Test-Path $_ }

    if ($CaminhosPossiveis.Count -eq 0) {
        Registrar "ERRO" "Instalação do Steam não encontrada. Por favor, instale o Steam primeiro."
        Write-Host ""
        Write-Host " Baixe o Steam em: https://store.steampowered.com/about/" -ForegroundColor Yellow
        Write-Host ""
        Read-Host " Pressione ENTER para sair"
        exit 1
    }

    $CaminhoSteam = $CaminhosPossiveis[0]
    Registrar "OK" "Steam encontrado em: $CaminhoSteam"
    return $CaminhoSteam
}

$steam = Encontrar-CaminhoSteam

# ===================== FECHAR O STEAM =====================
Registrar "INFO" "Encerrando o Steam, aguarde..."
Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""

# ===================== DOWNLOAD DOS ARQUIVOS =====================
Registrar "INFO" "Buscando os arquivos mais recentes da Green Store..."

$UrlApi = "https://api.github.com/repos/GREENSTORE00/Corre-o-de-Bugs/releases/latest"
$ArquivoCLI = Join-Path $env:TEMP "GreenStoreCLI.exe"
$ArquivoDLL = Join-Path $env:TEMP "cloud_redirect.dll"

try {
    $Release = Invoke-RestMethod -Uri $UrlApi -UseBasicParsing -ErrorAction Stop
    Registrar "LOG" "Versão mais recente: $($Release.tag_name)"

    # Download do GreenStoreCLI.exe
    $AssetCLI = $Release.assets | Where-Object { $_.name -eq "GreenStoreCLI.exe" } | Select-Object -First 1
    if ($AssetCLI) {
        Registrar "LOG" "Baixando GreenStoreCLI.exe..."
        Invoke-WebRequest -Uri $AssetCLI.browser_download_url -OutFile $ArquivoCLI -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "GreenStoreCLI.exe baixado com sucesso"
    } else {
        Registrar "AVISO" "Arquivo GreenStoreCLI.exe não encontrado na release"
    }

    # Download do greenstore_patch.dll
    $AssetDLL = $Release.assets | Where-Object { $_.name -eq "greenstore_patch.dll" } | Select-Object -First 1
    if ($AssetDLL) {
        Registrar "LOG" "Baixando greenstore_patch.dll..."
        Invoke-WebRequest -Uri $AssetDLL.browser_download_url -OutFile $ArquivoDLL -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        Registrar "OK" "greenstore_patch.dll baixado com sucesso"
    } else {
        Registrar "AVISO" "Arquivo greenstore_patch.dll não encontrado na release"
    }
}
catch {
    Registrar "ERRO" "Falha ao baixar os arquivos mais recentes"
    Registrar "ERRO" $_.Exception.Message
    Write-Host ""
    Write-Host " Entre em contato com o suporte da Green Store." -ForegroundColor Yellow
    Write-Host ""
    Read-Host " Pressione ENTER para sair"
    exit 1
}

# ===================== EXECUTAR O CORRETOR =====================
for ($i = 5; $i -ge 1; $i--) {
    Registrar "INFO" "Iniciando o Corretor da Green Store em $i segundo$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

Registrar "INFO" "Executando o Corretor da Green Store..."
try {
    & $ArquivoCLI /stfixer
    Registrar "OK" "Corretor executado com sucesso"
}
catch {
    Registrar "ERRO" "Erro ao executar o Corretor"
    Registrar "ERRO" $_.Exception.Message
}

# ===================== INSTALAR A DLL =====================
Registrar "INFO" "Instalando greenstore_patch.dll na pasta do Steam..."
$DllDestino = Join-Path $steam "cloud_redirect.dll"

try {
    Copy-Item -Path $ArquivoDLL -Destination $DllDestino -Force -ErrorAction Stop
    Registrar "OK" "greenstore_patch.dll instalada com sucesso"
}
catch {
    Registrar "ERRO" "Falha ao copiar greenstore_patch.dll"
    Registrar "ERRO" $_.Exception.Message
}

# ===================== LIMPEZA =====================
Start-Sleep -Seconds 2
Registrar "INFO" "Removendo arquivos temporários..."
Remove-Item -Path $ArquivoCLI -Force -ErrorAction SilentlyContinue
Remove-Item -Path $ArquivoDLL -Force -ErrorAction SilentlyContinue
Registrar "OK" "Arquivos temporários removidos"

Write-Host ""

# ===================== FINALIZAÇÃO =====================
Write-Host " ==========================================" -ForegroundColor DarkGreen
Registrar "OK" "Operação concluída com sucesso!"
Registrar "AVISO" "A inicialização do Steam pode demorar mais que o normal na primeira vez."
Write-Host " ==========================================" -ForegroundColor DarkGreen
Write-Host ""

$executavel = Join-Path $steam "steam.exe"
if (Test-Path $executavel) {
    Registrar "INFO" "Iniciando o Steam..."
    Start-Process $executavel -ArgumentList "-clearbeta"
}

Write-Host ""
Write-Host " Obrigado por usar a Green Store!" -ForegroundColor Green
Write-Host " Suporte: suporte@greenstore.com.br" -ForegroundColor DarkGreen
Write-Host ""
Registrar "INFO" "Pressione qualquer tecla para fechar esta janela..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
