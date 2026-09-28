# ab-hard.ps1 — ab.ps1 的加固版：Connection: close + 失败重试 3 次
# 目的：判定上一批 dflash2 臂的 3 次 ok=False 是客户端 keep-alive 竞态，还是引擎侧真故障
[CmdletBinding()]
param(
  [string[]]$Only = @(),
  [int]$Port = 8086,
  [int]$Retries = 3,
  [string]$EnginePath = '',
  [string]$Suffix = ''
)

$ErrorActionPreference = 'Continue'
$ROOT   = 'D:\build-pq2\dflash3'
$REQDIR = Join-Path $ROOT 'req'
$LOGDIR = Join-Path $ROOT 'log'
$RESDIR = Join-Path $ROOT 'res'
$ENGINE = if ($EnginePath) { $EnginePath } else { 'D:\ai\ninfer\pkg1-fast-pq2\engine\ninfer-serve-sm120.exe' }
$ENGSHA = (Get-FileHash $ENGINE -Algorithm SHA256).Hash.Substring(0,16)
$BASE   = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2.ninfer'
$DFL    = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2-dflash2.ninfer'

$cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v13*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cuda) { $cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v12*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 }
if ($cuda) { $env:PATH = "$($cuda.FullName)\bin;$($cuda.FullName)\bin\x64;$env:PATH" }

$FULL  = @('vision','count','code','prose')
$QUAL  = @('q1-calc','q2-prob','q3-pct','q4-json','q5-neg')

$arms = @(
  [pscustomobject]@{ Name='hd-dflash2-K7-32k-v2048';     Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-mtp-d4-32k-v2048';         Model=$BASE; Spec='mtp';     K=4; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-dflash2-K7-32k-fp8';       Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='fp8';   Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-dflash2-K7-prose6';        Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=6; Reqs=@('prose') },
  [pscustomobject]@{ Name='hd-dflash2-K5-prose4';        Model=$DFL;  Spec='dflash2'; K=5; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=4; Reqs=@('prose') },
  [pscustomobject]@{ Name='hd-natstop-dflash2-K7';       Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=2; Reqs=@('prose-long','code-long') },
  [pscustomobject]@{ Name='hd-natstop-mtp-d4';           Model=$BASE; Spec='mtp';     K=4; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=2; Reqs=@('prose-long','code-long') },
  [pscustomobject]@{ Name='hd-dflash2-K7-nolmd';         Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; NoLmd=$true; Reps=1; Reqs=@('count','code','prose') },
  [pscustomobject]@{ Name='hd-qual-dflash2-32k';         Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=$QUAL },
  [pscustomobject]@{ Name='hd-qual-dflash2-54272';       Model=$DFL;  Spec='dflash2'; K=7; Ctx=54272; Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=$QUAL },
  [pscustomobject]@{ Name='hd-qual-mtp-32k';             Model=$BASE; Spec='mtp';     K=4; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=$QUAL },
  [pscustomobject]@{ Name='hd-qual-mtp-163840';          Model=$BASE; Spec='mtp';     K=4; Ctx=163840;Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=$QUAL },
  [pscustomobject]@{ Name='hd-specdflash-K7-32k';        Model=$DFL;  Spec='dflash';  K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=@('count','code','prose') }
  [pscustomobject]@{ Name='hd-qual-mtp-d5';                 Model=$BASE; Spec='mtp';     K=5; Ctx=32768;  Vmt=2048; Kv='nvfp4'; Reps=1; Reqs=$QUAL },
  [pscustomobject]@{ Name='hd-mtp-d4-prose6';               Model=$BASE; Spec='mtp';     K=4; Ctx=32768;  Vmt=2048; Kv='nvfp4'; Reps=6; Reqs=@('prose') },
  [pscustomobject]@{ Name='hd-mtp-d5-prose6';               Model=$BASE; Spec='mtp';     K=5; Ctx=32768;  Vmt=2048; Kv='nvfp4'; Reps=6; Reqs=@('prose') },
  [pscustomobject]@{ Name='hd-mtp-d5-32k-v2048';          Model=$BASE; Spec='mtp';     K=5; Ctx=32768;  Vmt=2048; Kv='nvfp4'; Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-mtp-d5-163840-v2048';       Model=$BASE; Spec='mtp';     K=5; Ctx=163840; Vmt=2048; Kv='nvfp4'; Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-mtp-d3-32k-v2048';          Model=$BASE; Spec='mtp';     K=3; Ctx=32768;  Vmt=2048; Kv='nvfp4'; Reps=3; Reqs=$FULL },
  [pscustomobject]@{ Name='hd-mtp-d4-32k-fp8';            Model=$BASE; Spec='mtp';     K=4; Ctx=32768;  Vmt=2048; Kv='fp8';   Reps=3; Reqs=$FULL },  [pscustomobject]@{ Name='hd-dflash2-K7-32k-t1';       Model=$DFL;  Spec='dflash2'; K=7; Ctx=32768; Vmt=2048; Kv='nvfp4'; Reps=2; Reqs=@('code-t1') }
)

function Get-Kv($arm) { if ($arm.PSObject.Properties.Name -contains 'Kv' -and $arm.Kv) { return $arm.Kv } else { return 'nvfp4' } }

function Stop-Engine {
  Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i=0; $i -lt 25; $i++) {
    $p = Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Milliseconds 600
}

$allMeta = @()
foreach ($arm in $arms) {
  if ($Only.Count -gt 0 -and -not ($Only | Where-Object { $arm.Name -like "*$_*" })) { continue }
  if ($Suffix) { $arm.Name = $arm.Name + $Suffix }

  $errPath = Join-Path $LOGDIR "$($arm.Name).err"
  $outPath = Join-Path $LOGDIR "$($arm.Name).out"
  $cmdPath = Join-Path $LOGDIR "$($arm.Name).cmd.txt"
  Remove-Item $errPath,$outPath -ErrorAction SilentlyContinue

  $specArgs = if ($arm.Spec -eq 'dflash2' -or $arm.Spec -eq 'dflash') {
    $base = @('--spec',$arm.Spec,'--draft-tokens',"$($arm.K)")
    if (-not ($arm.PSObject.Properties.Name -contains 'NoLmd' -and $arm.NoLmd)) { $base += '--lm-head-draft' }
    $base
  } else { @('--spec','mtp','--draft-tokens',"$($arm.K)") }
  $kv = Get-Kv $arm
  $argList = @(
    $arm.Model,'--host','127.0.0.1','--port',"$Port",'--model-id','qwen3.8-27b',
    '--max-context',"$($arm.Ctx)",'--kv-capacity',"$($arm.Ctx)",'--kv-dtype',$kv,
    '--max-concurrency','1','--no-thinking','--default-max-tokens','32768','--default-thinking-budget','8192',
    '--host-kv-mib','2048','--wddm-evictable-budget','--vision','--vision-max-tokens',"$($arm.Vmt)",'--cors'
  ) + $specArgs
  $cmdLine = '"' + $ENGINE + '" "' + ($argList -join '" "') + '"'
  $cmdLine | Set-Content -Path $cmdPath -Encoding utf8
  Write-Host ""
  Write-Host ("[ARM] {0}" -f $arm.Name)

  Stop-Engine
  $proc = Start-Process -FilePath $ENGINE -ArgumentList $argList -RedirectStandardOutput $outPath `
            -RedirectStandardError $errPath -PassThru -NoNewWindow -WorkingDirectory (Split-Path $ENGINE)

  $sw = [Diagnostics.Stopwatch]::StartNew(); $state='timeout'
  while ($sw.Elapsed.TotalSeconds -lt 150) {
    if (Test-Path $errPath) {
      $t = Get-Content $errPath -Raw -ErrorAction SilentlyContinue
      if ($t -match 'listening on http') { $state='ready'; break }
      if ($t -match 'FATAL') { $state='fatal'; break }
    }
    if ($proc.HasExited) { $state='exited'; break }
    Start-Sleep -Milliseconds 250
  }
  Write-Host ("       state={0} readyIn={1}s" -f $state,[math]::Round($sw.Elapsed.TotalSeconds,1))
  $allMeta += [pscustomobject]@{ engsha=$ENGSHA; arm=$arm.Name; spec=$arm.Spec; k=$arm.K; ctx=$arm.Ctx; vmt=$arm.Vmt; reps=$arm.Reps;
                                 reqs=($arm.Reqs -join '+'); state=$state; ready_s=[math]::Round($sw.Elapsed.TotalSeconds,1);
                                 weights_gib=$null; fatal=''; cmdline=$cmdLine }

  if ($state -eq 'ready' -and $arm.Reps -gt 0) {
    for ($r=1; $r -le $arm.Reps; $r++) {
      foreach ($q in $arm.Reqs) {
        $f = Join-Path $REQDIR "$q.json"
        $swq = [Diagnostics.Stopwatch]::StartNew()
        $ok=$false; $body=$null; $errs=@(); $tries=0
        while ($tries -lt $Retries -and -not $ok) {
          $tries++
          try {
            $body = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
                      -InFile $f -ContentType 'application/json' -TimeoutSec 900 `
                      -Headers @{ Connection = 'close' }
            $ok = $true
          } catch {
            $msg = $_.Exception.Message
            if (-not $msg) { $msg = $_.Exception.GetType().FullName }
            if ($_.Exception.InnerException) { $msg += ' << ' + $_.Exception.InnerException.Message }
            $errs += ("try{0} [{1}] {2}" -f $tries, $_.Exception.GetType().Name, $msg)
            Start-Sleep -Milliseconds 900
          }
        }
        $swq.Stop()
        $content=''; $usage=$null
        if ($ok -and $body) { $content = $body.choices[0].message.content; $usage = $body.usage }
        $rec = [pscustomobject]@{ arm=$arm.Name; rep=$r; req=$q; ok=$ok; tries=$tries; wall_s=[math]::Round($swq.Elapsed.TotalSeconds,2);
                                  err=($errs -join ' | '); usage=$usage; content=$content }
        ($rec | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $RESDIR ("{0}-r{1}-{2}.json" -f $arm.Name,$r,$q)) -Encoding utf8
        $short = if ($content.Length -gt 50) { $content.Substring(0,50) } else { $content }
        Write-Host ("       r{0} {1,-8} ok={2} tries={3} wall={4}s  {5}" -f $r,$q,$ok,$tries,$rec.wall_s,($short -replace '\s+',' '))
      }
    }
  }
  Stop-Engine
}
Stop-Engine
$allMeta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ROOT ("meta-hard$Suffix.json")) -Encoding utf8
Write-Host ""
Write-Host "[DONE-HARD]"





