# probe.ps1 — 只做启动探测，把 ctx 天花板钉到页粒度
[CmdletBinding()]
param(
  [int[]]$Ctx = @(46080,47104,48128,48640,49152),
  [int]$Vmt = 2048,
  [int]$Port = 8086,
  [string]$Tag = 'probe2'
)
$ROOT   = 'D:\build-pq2\dflash3'
$LOGDIR = Join-Path $ROOT 'log'
$ENGINE = 'D:\ai\ninfer\pkg1-fast-pq2\engine\ninfer-serve-sm120.exe'
$DFL    = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2-dflash2.ninfer'

$cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v13*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cuda) { $env:PATH = "$($cuda.FullName)\bin;$($cuda.FullName)\bin\x64;$env:PATH" }

function Stop-Engine {
  Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i=0;$i -lt 25;$i++){ if (-not (Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 400 }
  Start-Sleep -Milliseconds 600
}

$out = @()
foreach ($c in $Ctx) {
  $name = "$Tag-dflash2-$c"
  $errPath = Join-Path $LOGDIR "$name.err"
  $outPath = Join-Path $LOGDIR "$name.out"
  Remove-Item $errPath,$outPath -ErrorAction SilentlyContinue
  $argList = @($DFL,'--host','127.0.0.1','--port',"$Port",'--model-id','qwen3.8-27b',
    '--max-context',"$c",'--kv-capacity',"$c",'--kv-dtype','nvfp4',
    '--max-concurrency','1','--no-thinking','--default-max-tokens','32768','--default-thinking-budget','8192',
    '--host-kv-mib','2048','--wddm-evictable-budget','--vision','--vision-max-tokens',"$Vmt",'--cors',
    '--spec','dflash2','--draft-tokens','7','--lm-head-draft')
  ('"' + $ENGINE + '" "' + ($argList -join '" "') + '"') | Set-Content -Path (Join-Path $LOGDIR "$name.cmd.txt") -Encoding utf8

  Stop-Engine
  $proc = Start-Process -FilePath $ENGINE -ArgumentList $argList -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru -NoNewWindow -WorkingDirectory (Split-Path $ENGINE)
  $sw=[Diagnostics.Stopwatch]::StartNew(); $state='timeout'
  while ($sw.Elapsed.TotalSeconds -lt 120) {
    if (Test-Path $errPath) {
      $t = Get-Content $errPath -Raw -ErrorAction SilentlyContinue
      if ($t -match 'listening on http') { $state='ready'; break }
      if ($t -match 'FATAL') { $state='fatal'; break }
    }
    if ($proc.HasExited) { $state='exited'; break }
    Start-Sleep -Milliseconds 250
  }
  $cap=''; $fatal=''
  if (Test-Path $errPath) {
    $t = Get-Content $errPath -Raw
    $m = [regex]::Match($t,'capacity \|[^\r\n]*'); if ($m.Success) { $cap = $m.Value }
    $m2 = [regex]::Match($t,'FATAL[^\r\n]*'); if ($m2.Success) { $fatal = $m2.Value.Trim() }
  }
  $line = "ctx={0,-7} vmt={1,-5} state={2,-6} {3} {4}" -f $c,$Vmt,$state,$cap,$fatal
  Write-Host $line
  $out += [pscustomobject]@{ ctx=$c; vmt=$Vmt; state=$state; capacity=$cap; fatal=$fatal }
  Stop-Engine
}
Stop-Engine
$out | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $ROOT "$Tag-summary.json") -Encoding utf8
