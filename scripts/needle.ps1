# needle.ps1 — 长文取针（针在长文中段），用于核对 dflash2 的深度检索能力
[CmdletBinding()]
param(
  [ValidateSet('dflash2','mtp')][string]$Spec = 'dflash2',
  [int]$K = 7,
  [int]$Ctx = 54272,
  [int]$Vmt = 2048,
  [int]$Chars = 98132,
  [int]$MaxTok = 512,
  [switch]$Raw,
  [int]$RawTrunc = 0,
  [string]$Tag = 'needle',
  [int]$Port = 8086
)
$ROOT   = 'D:\build-pq2\dflash3'
$LOGDIR = Join-Path $ROOT 'log'
$RESDIR = Join-Path $ROOT 'res'
$ENGINE = 'D:\ai\ninfer\pkg1-fast-pq2\engine\ninfer-serve-sm120.exe'
$BASE   = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2.ninfer'
$DFL    = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2-dflash2.ninfer'

$cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v13*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cuda) { $env:PATH = "$($cuda.FullName)\bin;$($cuda.FullName)\bin\x64;$env:PATH" }

function Stop-Engine {
  Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i=0;$i -lt 25;$i++){ if (-not (Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 400 }
  Start-Sleep -Milliseconds 600
}

# 构造取针长文：去掉原文里的针，自己插在保留文本的正中（深度恒为 50%）
$src = (Get-Content 'D:\build-pq2\pkg3\q.json' -Raw | ConvertFrom-Json).messages[0].content
$src = $src -replace '【关键编号：KX-7742-QN】',''
$question = "`n`n上面这段长文里嵌入的唯一关键编号是什么？只输出那个编号。"
$fixture = Join-Path $ROOT 'req\needle-dyn.json'

function New-Fixture([int]$n) {
  $m = [Math]::Min($n, $src.Length)
  $body = $src.Substring(0, $m)
  $half = [int]($body.Length / 2)
  return $body.Substring(0,$half) + "`n【关键编号：KX-7742-QN】`n" + $body.Substring($half) + $question
}
function Write-Fixture([int]$n) {
  $text = New-Fixture $n
  $obj = [ordered]@{ model='qwen3.8-27b'; temperature=0; max_tokens=$MaxTok; messages=@([ordered]@{ role='user'; content=$text }) }
  ($obj | ConvertTo-Json -Depth 6 -Compress) | Set-Content -Path $fixture -Encoding utf8
  return $text.Length
}

$model = if ($Spec -eq 'dflash2') { $DFL } else { $BASE }
$specArgs = if ($Spec -eq 'dflash2') { @('--spec','dflash2','--draft-tokens',"$K",'--lm-head-draft') } else { @('--spec','mtp','--draft-tokens',"$K") }
$argList = @($model,'--host','127.0.0.1','--port',"$Port",'--model-id','qwen3.8-27b',
  '--max-context',"$Ctx",'--kv-capacity',"$Ctx",'--kv-dtype','nvfp4',
  '--max-concurrency','1','--no-thinking','--default-max-tokens','32768','--default-thinking-budget','8192',
  '--host-kv-mib','2048','--wddm-evictable-budget','--vision','--vision-max-tokens',"$Vmt",'--cors') + $specArgs

$name = "$Tag-$Spec-K$K-ctx$Ctx"
$errPath = Join-Path $LOGDIR "$name.err"; $outPath = Join-Path $LOGDIR "$name.out"
('"' + $ENGINE + '" "' + ($argList -join '" "') + '"') | Set-Content -Path (Join-Path $LOGDIR "$name.cmd.txt") -Encoding utf8
Stop-Engine
$proc = Start-Process -FilePath $ENGINE -ArgumentList $argList -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru -NoNewWindow -WorkingDirectory (Split-Path $ENGINE)
$sw=[Diagnostics.Stopwatch]::StartNew(); $state='timeout'
while ($sw.Elapsed.TotalSeconds -lt 150) {
  if (Test-Path $errPath) {
    $t = Get-Content $errPath -Raw -ErrorAction SilentlyContinue
    if ($t -match 'listening on http') { $state='ready'; break }
    if ($t -match 'FATAL') { $state='fatal'; break }
  }
  if ($proc.HasExited) { $state='exited'; break }
  Start-Sleep -Milliseconds 250
}
Write-Host "state=$state"
if ($state -eq 'ready') {
  $try = 0; $done = $false; $chars = $Chars
  if ($Raw -or $RawTrunc -gt 0) {
    # 归档原封夹具：只改 model 字段；RawTrunc>0 时按字符截断并保留归档原提问句
    $rawObj = Get-Content 'D:\build-pq2\pkg3\q.json' -Raw | ConvertFrom-Json
    $rawObj.model = 'qwen3.8-27b'
    $rawText = $rawObj.messages[0].content
    if ($RawTrunc -gt 0 -and $RawTrunc -lt $rawText.Length) {
      $q = "`n`n上面这段长文里嵌入的唯一关键编号是什么？只输出那个编号。"
      $rawText = $rawText.Substring(0, $RawTrunc) + $q
      $rawObj.messages[0].content = $rawText
    }
    ($rawObj | ConvertTo-Json -Depth 6 -Compress) | Set-Content -Path $fixture -Encoding utf8
    Write-Host ("RAW 夹具：{0} 字符 | 针在 {1} 字符处（{2}% 深度）| max_tokens=256（归档值）" -f `
      $rawText.Length, $rawText.IndexOf('KX-7742-QN'), [math]::Round(100*$rawText.IndexOf('KX-7742-QN')/$rawText.Length,1))
  }
  while (-not $done -and $try -lt 8) {
    $try++
    $len = if ($Raw -or $RawTrunc -gt 0) { $rawText.Length } else { Write-Fixture $chars }
    Write-Host ("try{0}: fixture {1} 字符（针在正中）" -f $try, $len)
    $swq=[Diagnostics.Stopwatch]::StartNew()
    try {
      $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -InFile $fixture -ContentType 'application/json' -TimeoutSec 900 -Headers @{ Connection = 'close' }
      $swq.Stop()
      $ans = $r.choices[0].message.content
      Write-Host ("answer: " + ($ans -replace '\s+',' '))
      Write-Host ("wall {0}s | prompt_tokens {1} | completion {2}" -f [math]::Round($swq.Elapsed.TotalSeconds,2), $r.usage.prompt_tokens, $r.usage.completion_tokens)
      [pscustomobject]@{ tag=$Tag; spec=$Spec; k=$K; ctx=$Ctx; chars=$len; prompt_tokens=$r.usage.prompt_tokens; answer=$ans; wall_s=[math]::Round($swq.Elapsed.TotalSeconds,2); hit=([bool]($ans -match 'KX-7742-QN')) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $RESDIR "$name.json") -Encoding utf8
      $done = $true
    } catch {
      $msg = $_.Exception.Message
      Write-Host ("  REJECTED: " + $msg)
      if ($msg -match '400' -and $chars -gt 20000) { $chars = [int]($chars * 0.85); Start-Sleep -Milliseconds 400 }
      else { Write-Host "  放弃（非容量原因或已缩到下限）"; break }
    }
  }
  $m = Select-String -Path $errPath -Pattern 'req#\d+ done' | Select-Object -Last 1
  if ($m) { Write-Host ("engine: " + ($m.Line -replace '^.*INFO\s+','')) }
}
Stop-Engine
