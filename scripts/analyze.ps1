# analyze.ps1 — 解析 ab.ps1 的引擎日志，产出可对齐的矩阵
[CmdletBinding()]
param([string]$MetaFile = 'meta.json', [string]$ParsedFile = 'parsed.json')
$ROOT   = 'D:\build-pq2\dflash3'
$LOGDIR = Join-Path $ROOT 'log'
$meta   = Get-Content (Join-Path $ROOT $MetaFile) -Raw | ConvertFrom-Json
if ($meta -isnot [array]) { $meta = @($meta) }

$rows = @()
foreach ($m in $meta) {
  $errPath = Join-Path $LOGDIR "$($m.arm).err"
  if (-not (Test-Path $errPath)) { continue }
  $text = Get-Content $errPath -Raw

  $fatal = ''; $mm = [regex]::Match($text, 'FATAL[^\r\n]*'); if ($mm.Success) { $fatal = $mm.Value.Trim() }
  $capTok = $null; $capRuntime = $null; $free = ''
  $mm = [regex]::Match($text, 'capacity \| KV ([\d,]+) tokens, (\S+), \S+ \| pages ([\d,]+)/([\d,]+) \| runtime ([\d.]+) GiB \| free ([^\r\n]*)')
  if ($mm.Success) { $capTok = [int]($mm.Groups[1].Value -replace ',',''); $capRuntime = [double]$mm.Groups[5].Value; $free = $mm.Groups[6].Value.Trim() }
  $total = $null; $mm = [regex]::Match($text, 'engine ready \| \S+ \| total ([\d.]+)s'); if ($mm.Success) { $total = [double]$mm.Groups[1].Value }

  $reqs = @($m.reqs -split '\+' | Where-Object { $_ -ne '' })
  $lines = [regex]::Matches($text, '[^\r\n]*req#\d+ done[^\r\n]*') | ForEach-Object { $_.Value }
  $i = 0
  foreach ($ln in $lines) {
    $i++
    $g = [regex]::Match($ln, 'req#(\d+) done')
    $n = [int]$g.Groups[1].Value
    $label = if ($reqs.Count -gt 0) { $reqs[($n-1) % $reqs.Count] } else { "req$n" }
    $rep   = if ($reqs.Count -gt 0) { [math]::Floor(($n-1)/$reqs.Count)+1 } else { 1 }
    $pr = [regex]::Match($ln, 'prompt ([\d,]+)');   $ou = [regex]::Match($ln, 'output ([\d,]+)')
    $ca = [regex]::Match($ln, 'cache ([\d,]+) \(([\d.]+)%')
    $tt = [regex]::Match($ln, 'TTFT ([\d.]+)\s*(ms|s)')
    $ttft = $null
    if ($tt.Success) { $ttft = [double]$tt.Groups[1].Value; if ($tt.Groups[2].Value -eq 's') { $ttft = $ttft * 1000 } }
    $pf = [regex]::Match($ln, 'prefill ([\d.]+)(k?) tok/s')
    $prefill = $null
    if ($pf.Success) { $prefill = [double]$pf.Groups[1].Value; if ($pf.Groups[2].Value -eq 'k') { $prefill = $prefill * 1000 } }
    $dc = [regex]::Match($ln, 'decode ([\d.]+) tok/s')
    $ac = [regex]::Match($ln, '(mtp|dflash2) accepted ([\d,]+)/([\d,]+) \(([\d.]+)%\)')
    $rows += [pscustomobject]@{
      arm = $m.arm; spec = $m.spec; k = $m.k; ctx = $m.ctx; vmt = $m.vmt
      rep = $rep; label = $label; reqn = $n
      prompt = if ($pr.Success) { [int]($pr.Groups[1].Value -replace ',','') } else { $null }
      output = if ($ou.Success) { [int]($ou.Groups[1].Value -replace ',','') } else { $null }
      cache_hit = if ($ca.Success) { [int]($ca.Groups[1].Value -replace ',','') } else { $null }
      cache_pct = if ($ca.Success) { [double]$ca.Groups[2].Value } else { $null }
      ttft_ms = $ttft; prefill_tps = $prefill
      decode = if ($dc.Success) { [double]$dc.Groups[1].Value } else { $null }
      acc_n = if ($ac.Success) { [int]($ac.Groups[2].Value -replace ',','') } else { $null }
      acc_d = if ($ac.Success) { [int]($ac.Groups[3].Value -replace ',','') } else { $null }
      acc_pct = if ($ac.Success) { [double]$ac.Groups[4].Value } else { $null }
      state = $m.state; fatal = $fatal; weights = $m.weights_gib; cap_tokens = $capTok; runtime_gib = $capRuntime; free = $free; ready_s = $m.ready_s
    }
  }
  if ($lines.Count -eq 0) {
    $rows += [pscustomobject]@{
      arm = $m.arm; spec = $m.spec; k = $m.k; ctx = $m.ctx; vmt = $m.vmt
      rep = $null; label = '(仅启动)'; reqn = $null; prompt = $null; output = $null
      cache_hit = $null; cache_pct = $null; ttft_ms = $null; prefill_tps = $null; decode = $null
      acc_n = $null; acc_d = $null; acc_pct = $null
      state = $m.state; fatal = $fatal; weights = $m.weights_gib; cap_tokens = $capTok; runtime_gib = $capRuntime; free = $free; ready_s = $m.ready_s
    }
  }
}

$rows | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ROOT $ParsedFile) -Encoding utf8

function Median($a) {
  $v = @($a | Where-Object { $_ -ne $null } | Sort-Object)
  if ($v.Count -eq 0) { return $null }
  if ($v.Count % 2 -eq 1) { return $v[[int](($v.Count-1)/2)] }
  return [math]::Round((($v[$v.Count/2 - 1]) + ($v[$v.Count/2]))/2, 2)
}

"=== 启动状态 / 天花板 ==="
$rows | Where-Object { $_.label -eq '(仅启动)' -or $_.reqn -eq 1 } |
  Group-Object arm | ForEach-Object {
    $r = $_.Group[0]
    "{0,-26} state={1,-7} ready={2}s weights={3} cap={4} runtime={5} free={6} {7}" -f $r.arm,$r.state,$r.ready_s,$r.weights,$r.cap_tokens,$r.runtime_gib,$r.free,$r.fatal
  }

""
"=== 速度矩阵（引擎 decode t/s，中位数）==="
$labels = @('vision','count','code','prose','q1-calc','q2-prob','q3-pct','q4-json','q5-neg')
$arms = $rows | Select-Object -ExpandProperty arm -Unique
$hdr = "{0,-26}" -f 'arm'
foreach ($l in $labels) { $hdr += ("{0,10}" -f $l) }
$hdr + ("{0,10}" -f 'accept%')
$hdr
foreach ($a in $arms) {
  $line = "{0,-26}" -f $a
  foreach ($l in $labels) {
    $sel = $rows | Where-Object { $_.arm -eq $a -and $_.label -eq $l }
    $med = Median ($sel | ForEach-Object { $_.decode })
    $cell = '-'
    if ($med -ne $null) { $cell = [string][math]::Round($med,1) }
    $line += ("{0,10}" -f $cell)
  }
  $accs = $rows | Where-Object { $_.arm -eq $a -and $_.label -in @('count','code','prose') -and $_.acc_pct -ne $null }
  $accMed = Median ($accs | ForEach-Object { $_.acc_pct })
  $cell2 = '-'
  if ($accMed -ne $null) { $cell2 = [string][math]::Round($accMed,1) }
  $line += ("{0,10}" -f $cell2)
  $line
}

""
"=== 逐条明细 ==="
$rows | Where-Object { $_.reqn -ne $null } | Sort-Object arm,reqn |
  ForEach-Object { "{0,-26} r{1} {2,-8} dec={3,7} acc={4,6} accN={5}/{6} ttft={7,7} pf={8,7} out={9,5}" -f `
    $_.arm,$_.rep,$_.label,$_.decode,$_.acc_pct,$_.acc_n,$_.acc_d,$_.ttft_ms,$_.prefill_tps,$_.output }
