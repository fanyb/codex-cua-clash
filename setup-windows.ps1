[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',
    [ValidateRange(1, 65535)]
    [int]$Port = 7890
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this script with Windows PowerShell 5.1 (powershell.exe).'
}

$key = 'CODEX_NODE_REPL_PATH'
$folder = Join-Path $env:LOCALAPPDATA 'CodexCuaClash'
$wrapper = Join-Path $folder 'codex-cua-clash.exe'
$existing = [Environment]::GetEnvironmentVariable($key, 'User')

if ($Action -eq 'uninstall') {
    if ($existing -ne $wrapper -or !(Test-Path -LiteralPath $wrapper -PathType Leaf)) {
        throw 'The current setting does not match this installation.'
    }
    Remove-Item -LiteralPath $wrapper
    [Environment]::SetEnvironmentVariable($key, $null, 'User')
    if (!(Get-ChildItem -LiteralPath $folder -Force)) {
        Remove-Item -LiteralPath $folder
    }
    Write-Host 'Removed. Restart Codex from the Start menu.'
    return
}

if ($existing -or [Environment]::GetEnvironmentVariable($key, 'Machine')) {
    throw 'CODEX_NODE_REPL_PATH already exists. Review that setting before installing.'
}
if (Test-Path -LiteralPath $folder) {
    throw "Installation directory already exists: $folder"
}

$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$cache = Join-Path $codexRoot 'plugins\cache\openai-bundled\unified-computer-use'
if (!(Test-Path -LiteralPath $cache -PathType Container)) {
    throw 'Open native Windows Codex with the Browser plugin enabled once, then retry.'
}

$configs = Get-ChildItem -Path (Join-Path $cache '*\.mcp.json') -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
$nativeRuntime = foreach ($config in $configs) {
    $mcp = (Get-Content -LiteralPath $config.FullName -Raw | ConvertFrom-Json).mcpServers.cua_repl
    $node = $mcp.env.NODE_REPL_NODE_PATH
    if ($node -and [IO.Path]::IsPathRooted($node) -and
        (Test-Path -LiteralPath $node -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $node) 'node_repl.exe') -PathType Leaf)) {
        $node
        break
    }
}
if (!$nativeRuntime) {
    throw 'Could not locate a native node.exe and node_repl.exe in the Codex browser plugin runtime.'
}

$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $connection = $tcp.ConnectAsync('127.0.0.1', $Port)
    if (!$connection.Wait(2000) -or !$tcp.Connected) { throw 'Connection failed.' }
} catch {
    throw "Cannot connect to 127.0.0.1:$Port. Start Clash and check its HTTP or mixed port."
} finally {
    $tcp.Dispose()
}

$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'windows\NodeReplProxy.cs') -Raw
$source = $source.Replace('"http://127.0.0.1:7890"', ('"http://127.0.0.1:{0}"' -f $Port))
New-Item -Path $folder -ItemType Directory | Out-Null
try {
    Add-Type -TypeDefinition $source -OutputAssembly $wrapper -OutputType ConsoleApplication
    [Environment]::SetEnvironmentVariable($key, $wrapper, 'User')
    if ([Environment]::GetEnvironmentVariable($key, 'User') -ne $wrapper) {
        throw 'The Windows user environment setting failed verification.'
    }
} catch {
    if ([Environment]::GetEnvironmentVariable($key, 'User') -eq $wrapper) {
        [Environment]::SetEnvironmentVariable($key, $null, 'User')
    }
    if (Test-Path -LiteralPath $wrapper) { Remove-Item -LiteralPath $wrapper }
    Remove-Item -LiteralPath $folder
    throw
}

Write-Host "Configured 127.0.0.1:$Port. Fully quit Codex and reopen it from the Start menu."
