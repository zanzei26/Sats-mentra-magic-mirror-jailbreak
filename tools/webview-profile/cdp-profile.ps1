# CPU-profile a page in Fully's WebView over the DevTools protocol while an on-device script drives the touch screen.
#
# Setup (once, see docs/home-assistant-wall-panel.md, section 3):
#   1. adb shell sh /data/local/tmp/fully-debug.sh on        (flips Fully's "webviewDebugging" preference, restarts Fully)
#   2. adb forward tcp:9333 localabstract:webview_devtools_remote_<fully pid>      (the socket name is in /proc/net/unix)
#   3. .\cdp-profile.ps1 -Device <mirror-ip>:5555 -Url http://<ha>:8123/<dashboard>/<view>?kiosk -Tag base
#   4. wsl python3 -I prof-analyze.py prof\profile-base.json 30          (self time; add the word "incl" for inclusive time)
#   5. adb shell sh /data/local/tmp/fully-debug.sh off        (do not leave the debugging socket open)
param(
  [Parameter(Mandatory)][string]$Device,
  [Parameter(Mandatory)][string]$Url,
  [string]$Tag = 'base',
  [int]$Seconds = 36,
  [string]$Swipe = 'sh /data/local/tmp/bench-sf.sh',   # on-device script that swipes (or leave the screen alone with -Swipe '')
  [string]$Js = ''                                      # optional JavaScript to run in the page before profiling
)
. "$PSScriptRoot\cdp-lib.ps1"
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
$out = "$PSScriptRoot\prof"
New-Item -ItemType Directory -Force $out | Out-Null
$ws = Cdp-Open
Cdp-Eval $ws "location.href = '$Url'; 'navigating'" | Out-Null
$ws.Dispose(); Start-Sleep -Seconds 20; $ws = Cdp-Open        # give the page time to build its scene
if ($Js) { "js: " + (Cdp-Eval $ws $Js) }
Cdp-Call $ws 'Profiler.enable' | Out-Null
Cdp-Call $ws 'Profiler.setSamplingInterval' @{ interval = 2000 } | Out-Null
Cdp-Call $ws 'Profiler.start' | Out-Null
$p = $null
if ($Swipe) { $p = Start-Process -FilePath $adb -ArgumentList "-s $Device shell $Swipe" -RedirectStandardOutput "$out\swipe-$Tag.txt" -PassThru -WindowStyle Hidden }
Start-Sleep -Seconds $Seconds
$raw = Cdp-Call $ws 'Profiler.stop' @{} 120000 -Raw
Set-Content -Path "$out\profile-$Tag.json" -Value $raw -Encoding UTF8
"profile: $out\profile-$Tag.json ($($raw.Length) bytes)"
if ($p) { $p.WaitForExit(30000) | Out-Null; Get-Content "$out\swipe-$Tag.txt" }
$ws.Dispose()
