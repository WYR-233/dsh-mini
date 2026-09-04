# Build the tray launcher exe from src\DshTray.cs
# Uses the classic .NET Framework CodeDom compiler (works on Windows
# PowerShell 5.1 and on machines with customized Add-Type, zero extras).
# Source must stay pure ASCII (csc reads it with the ANSI codepage).
param(
    [string]$Icon = ""
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$srcPath = Join-Path $repoRoot 'src\DshTray.cs'
$out = Join-Path $repoRoot 'assets\DshMini.exe'
if ($Icon -eq "") { $Icon = Join-Path $repoRoot 'src\whale-tray.ico' }

New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
if (Test-Path $out) { Remove-Item $out -Force }

$src = Get-Content $srcPath -Raw
$refs = @('System.dll', 'System.Core.dll', 'System.Windows.Forms.dll',
          'System.Drawing.dll', 'System.Management.dll')

$cp = New-Object System.CodeDom.Compiler.CompilerParameters
$cp.GenerateExecutable = $true
$cp.OutputAssembly = $out
$cp.CompilerOptions = '/target:winexe /optimize+ /win32icon:"' + $Icon + '"'
foreach ($r in $refs) { [void]$cp.ReferencedAssemblies.Add($r) }

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$res = $provider.CompileAssemblyFromSource($cp, $src)

if ($res.Errors.Count -gt 0) {
    Write-Output "COMPILE ERRORS ($($res.Errors.Count)):"
    foreach ($e in $res.Errors) { Write-Output $e.ToString() }
    exit 1
}
if (Test-Path $out) {
    Write-Output ("OK " + $out + " (" + (Get-Item $out).Length + " bytes)")
} else {
    Write-Output "FAIL: no output exe"
    exit 1
}
