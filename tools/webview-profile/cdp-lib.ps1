# Minimal Chrome DevTools Protocol client for the mirror's WebView (via `adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>`).
# Dot-source this file, then: $ws = Cdp-Open; Cdp-Call $ws 'Runtime.evaluate' @{expression='1+1'; returnByValue=$true}
$ErrorActionPreference = 'Stop'   # a dead socket must end the script, not loop
$script:cdpId = 0
function Cdp-Open {
  $pages = (Invoke-WebRequest -UseBasicParsing http://localhost:9333/json -TimeoutSec 15).Content | ConvertFrom-Json
  $page = @($pages | Where-Object { $_.type -eq 'page' })[0]
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  return $ws
}
function Cdp-Recv($ws, [int]$timeoutMs = 60000) {
  $cts = New-Object Threading.CancellationTokenSource
  $cts.CancelAfter($timeoutMs)
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 262144
  do {
    $seg = New-Object ArraySegment[byte] -ArgumentList @(,$buf)
    $r = $ws.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $r.Count)
  } while (-not $r.EndOfMessage)
  return [Text.Encoding]::UTF8.GetString($ms.ToArray())
}
function Cdp-Call($ws, [string]$method, $params = @{}, [int]$timeoutMs = 60000, [switch]$Raw) {
  $script:cdpId++
  $id = $script:cdpId
  $json = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 30 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  $ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
  while ($true) {
    $msg = Cdp-Recv $ws $timeoutMs
    if ($msg.StartsWith('{"id":' + $id + ',')) {
      if ($Raw) { return $msg }
      $o = $msg | ConvertFrom-Json
      if ($o.error) { throw ("CDP error: " + ($o.error | ConvertTo-Json -Compress)) }
      return $o.result
    }
  }
}
function Cdp-Eval($ws, [string]$expr, [int]$timeoutMs = 60000) {
  $r = Cdp-Call $ws 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true } $timeoutMs
  if ($r.exceptionDetails) { return "EXCEPTION: " + ($r.exceptionDetails | ConvertTo-Json -Compress -Depth 5) }
  return $r.result.value
}
