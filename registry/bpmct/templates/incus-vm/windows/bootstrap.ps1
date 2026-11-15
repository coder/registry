# Runs at every boot from the CoderAgent scheduled task (see setup.cmd).
# Incus has no Windows guest agent, so the template passes the agent token
# on a small seed ISO. This script reads it and starts the Coder agent.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\coder\bootstrap.log'
function Log($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $m) }
Log 'bootstrap start'

try {
  $max = (Get-PartitionSupportedSize -DriveLetter C -ErrorAction Stop).SizeMax
  $cur = (Get-Partition -DriveLetter C -ErrorAction Stop).Size
  if ($max - $cur -gt 1GB) {
    Resize-Partition -DriveLetter C -Size $max -ErrorAction Stop
    Log "resized C: from $cur to $max"
  }
} catch { Log "resize skipped: $_" }

# The template attaches the seed ISO before it starts the VM.
# Windows can take some time to mount it.
$cfg = @{}
$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline) {
  $drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=5' | Select-Object -ExpandProperty DeviceID)
  foreach ($d in $drives) {
    $envPath = Join-Path $d 'init.env'
    if (Test-Path $envPath) {
      Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
      }
    }
  }
  if ($cfg.ContainsKey('CODER_AGENT_TOKEN') -and $cfg.ContainsKey('CODER_AGENT_URL')) { break }
  Start-Sleep 5
}
if (-not ($cfg.ContainsKey('CODER_AGENT_TOKEN') -and $cfg.ContainsKey('CODER_AGENT_URL'))) {
  Log 'no init.env found on any CD-ROM drive; exiting'
  exit 0
}
$url = $cfg['CODER_AGENT_URL'].TrimEnd('/')
Log "url=$url"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# VS Code Remote needs the agent process to have the name sshd.exe.
# The Windows bootstrap script from Coder uses the same name.
$bin = 'C:\coder\sshd.exe'
$ok = $false
for ($i = 0; $i -lt 120 -and -not $ok; $i++) {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$url/bin/coder-windows-amd64.exe" -OutFile "$bin.tmp" -ErrorAction Stop
    Move-Item -Force -Path "$bin.tmp" -Destination $bin -ErrorAction Stop
    $ok = $true
  } catch {
    Log "agent download failed, will retry: $_"
    Start-Sleep 5
  }
}
if (-not $ok) { Log 'agent download failed'; exit 1 }
Log 'downloaded agent'

$env:CODER_AGENT_URL = $url
$env:CODER_AGENT_TOKEN = $cfg['CODER_AGENT_TOKEN']
$env:CODER_AGENT_AUTH = 'token'
while ($true) {
  Log 'starting agent'
  cmd.exe /c "$bin agent >> C:\coder\agent.log 2>&1"
  Log "agent exited: $LASTEXITCODE"
  Start-Sleep 5
}
