# matrix.ps1 — 把 parsed.json / parsed-hard.json 合并成一张矩阵 CSV
$ROOT = 'D:\build-pq2\dflash3'
$rows = @()
foreach ($f in @('parsed.json','parsed-hard.json')) {
  $p = Join-Path $ROOT $f
  if (Test-Path $p) { $j = Get-Content $p -Raw | ConvertFrom-Json; if ($j) { $rows += $j } }
}
function Med($a) {
  $v = @($a | Where-Object { $_ -ne $null } | Sort-Object)
  if ($v.Count -eq 0) { return $null }
  if ($v.Count % 2 -eq 1) { return $v[[int](($v.Count-1)/2)] }
  return [math]::Round((($v[$v.Count/2 - 1]) + ($v[$v.Count/2]))/2, 2)
}
$kvOf = @{
  'dflash2-K7-32k-v2048'='nvfp4'; 'mtp-d4-32k-v2048'='nvfp4'; 'dflash2-K5-32k-v2048'='nvfp4'
  'mtp-d4-32k-v2048-b'='nvfp4'; 'dflash2-K11-32k-v2048'='nvfp4'; 'dflash2-K7-32k-v2048-b'='nvfp4'
  'dflash2-K7-32k-v8192'='nvfp4'; 'mtp-d4-163840-v2048'='nvfp4'; 'mtp-d4-163840-v8192'='nvfp4'
  'hd-dflash2-K7-32k-v2048'='nvfp4'; 'hd-mtp-d4-32k-v2048'='nvfp4'; 'hd-dflash2-K7-32k-fp8'='fp8'
  'hd-dflash2-K7-prose6'='nvfp4'; 'hd-dflash2-K5-prose4'='nvfp4'
  'hd-natstop-dflash2-K7'='nvfp4'; 'hd-natstop-mtp-d4'='nvfp4'
  'hd-dflash2-K7-32k-v2048-alt120a'='nvfp4'; 'hd-mtp-d4-32k-v2048-alt120a'='nvfp4'
}
$out = @()
foreach ($g in ($rows | Where-Object { $_.reqn -ne $null -and $_.label -notlike 'q*' -and $_.label -ne 'vision' } | Group-Object arm, label)) {
  $r = $g.Group[0]
  $out += [pscustomobject]@{
    arm=$r.arm; spec=$r.spec; K=$r.k; ctx=$r.ctx; vmt=$r.vmt; kv=$kvOf[$r.arm]; content=$r.label; n=$g.Count
    decode_med=(Med ($g.Group | ForEach-Object { $_.decode }))
    decode_all=(($g.Group | ForEach-Object { $_.decode }) -join '/')
    accept_med=(Med ($g.Group | ForEach-Object { $_.acc_pct }))
    out_all=(($g.Group | ForEach-Object { $_.output }) -join '/')
    ttft_med=(Med ($g.Group | ForEach-Object { $_.ttft_ms }))
  }
}
$out | Sort-Object arm, content | Export-Csv -Path (Join-Path $ROOT 'matrix.csv') -NoTypeInformation -Encoding utf8
$out | Sort-Object arm, content | Format-Table -AutoSize | Out-String
