# ab.ps1 — dflash2 vs MTP 同 ctx A/B（可复现测试台）
# 用法: pwsh -File D:\build-pq2\dflash3\ab.ps1 [-Only <子串>]
# 设计: 每臂 = 一次引擎启动 + N 轮固定请求电池；命令行原样写入 log\<臂>.cmd.txt
[CmdletBinding()]
param(
  [string[]]$Only = @(),
  [int]$Port = 8086
)

$ErrorActionPreference = 'Continue'
$ROOT   = 'D:\build-pq2\dflash3'
$REQDIR = Join-Path $ROOT 'req'
$LOGDIR = Join-Path $ROOT 'log'
$RESDIR = Join-Path $ROOT 'res'
$ENGINE = 'D:\ai\ninfer\pkg1-fast-pq2\engine\ninfer-serve-sm120.exe'
$BASE   = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2.ninfer'
$DFL    = 'D:\ai\ninfer\pkg1-fast-pq2\model\bonsai2_27b_ternary_v2-dflash2.ninfer'

# CUDA bin 上 PATH（照抄包内启动件）
$cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v13*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cuda) { $cuda = Get-ChildItem "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA\v12*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 }
if ($cuda) { $env:PATH = "$($cuda.FullName)\bin;$($cuda.FullName)\bin\x64;$env:PATH" }

$FULL  = @('vision','count','code','prose')
$SPEED = @('count','code','prose')
$QUAL  = @('q1-calc','q2-prob','q3-pct','q4-json','q5-neg')

$arms = @(
  [pscustomobject]@{ Name='dflash2-K7-32k-v2048';   Model=$DFL;  Spec='dflash2'; K=7;  Ctx=32768;  Vmt=2048; Reps=3; Reqs=$FULL  },
  [pscustomobject]@{ Name='mtp-d4-32k-v2048';       Model=$BASE; Spec='mtp';     K=4;  Ctx=32768;  Vmt=2048; Reps=3; Reqs=$FULL  },
  [pscustomobject]@{ Name='dflash2-K5-32k-v2048';   Model=$DFL;  Spec='dflash2'; K=5;  Ctx=32768;  Vmt=2048; Reps=3; Reqs=$SPEED },
  [pscustomobject]@{ Name='mtp-d4-32k-v2048-b';     Model=$BASE; Spec='mtp';     K=4;  Ctx=32768;  Vmt=2048; Reps=3; Reqs=$FULL  },
  [pscustomobject]@{ Name='dflash2-K11-32k-v2048';  Model=$DFL;  Spec='dflash2'; K=11; Ctx=32768;  Vmt=2048; Reps=3; Reqs=$SPEED },
  [pscustomobject]@{ Name='dflash2-K7-32k-v2048-b'; Model=$DFL;  Spec='dflash2'; K=7;  Ctx=32768;  Vmt=2048; Reps=3; Reqs=$FULL  },
  [pscustomobject]@{ Name='dflash2-K7-32k-v8192';   Model=$DFL;  Spec='dflash2'; K=7;  Ctx=32768;  Vmt=8192; Reps=2; Reqs=$FULL  },
  [pscustomobject]@{ Name='mtp-d4-163840-v2048';    Model=$BASE; Spec='mtp';     K=4;  Ctx=163840; Vmt=2048; Reps=3; Reqs=$FULL  },
  [pscustomobject]@{ Name='mtp-d4-163840-v8192';    Model=$BASE; Spec='mtp';     K=4;  Ctx=163840; Vmt=8192; Reps=1; Reqs=$FULL  },
  [pscustomobject]@{ Name='qual-dflash2-K7-32k';    Model=$DFL;  Spec='dflash2'; K=7;  Ctx=32768;  Vmt=2048; Reps=1; Reqs=$QUAL  },
  [pscustomobject]@{ Name='qual-mtp-d4-32k';        Model=$BASE; Spec='mtp';     K=4;  Ctx=32768;  Vmt=2048; Reps=1; Reqs=$QUAL  },
  [pscustomobject]@{ Name='qual-mtp-d4-163840';     Model=$BASE; Spec='mtp';     K=4;  Ctx=163840; Vmt=2048; Reps=1; Reqs=$QUAL  },
  [pscustomobject]@{ Name='probe-dflash2-36864';    Model=$DFL;  Spec='dflash2'; K=7;  Ctx=36864;  Vmt=2048; Reps=0; Reqs=@()   },
  [pscustomobject]@{ Name='probe-dflash2-40960';    Model=$DFL;  Spec='dflash2'; K=7;  Ctx=40960;  Vmt=2048; Reps=0; Reqs=@()   },
  [pscustomobject]@{ Name='probe-dflash2-45056';    Model=$DFL;  Spec='dflash2'; K=7;  Ctx=45056;  Vmt=2048; Reps=0; Reqs=@()   }
)

function Stop-Engine {
  Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i=0; $i -lt 20; $i++) {
    $p = Get-Process -Name 'ninfer-serve-sm120','ninfer-serve' -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Milliseconds 500
}

function Get-GpuUsed {
  try { (nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) -replace '\s','' } catch { 'n/a' }
}

$allPlan = @()
$allMeta = @()

foreach ($arm in $arms) {
  if ($Only.Count -gt 0 -and -not ($Only | Where-Object { $arm.Name -like "*$_*" })) { continue }

  $errPath = Join-Path $LOGDIR "$($arm.Name).err"
  $outPath = Join-Path $LOGDIR "$($arm.Name).out"
  $cmdPath = Join-Path $LOGDIR "$($arm.Name).cmd.txt"
  Remove-Item $errPath,$outPath -ErrorAction SilentlyContinue

  $specArgs = if ($arm.Spec -eq 'dflash2') {
    @('--spec','dflash2','--draft-tokens',"$($arm.K)",'--lm-head-draft')
  } else {
    @('--spec','mtp','--draft-tokens',"$($arm.K)")
  }
  $argList = @(
    $arm.Model,
    '--host','127.0.0.1','--port',"$Port",'--model-id','qwen3.8-27b',
    '--max-context',"$($arm.Ctx)",'--kv-capacity',"$($arm.Ctx)",'--kv-dtype','nvfp4',
    '--max-concurrency','1','--no-thinking',
    '--default-max-tokens','32768','--default-thinking-budget','8192',
    '--host-kv-mib','2048','--wddm-evictable-budget',
    '--vision','--vision-max-tokens',"$($arm.Vmt)",
    '--cors'
  ) + $specArgs

  $cmdLine = '"' + $ENGINE + '" "' + ($argList -join '" "') + '"'
  $cmdLine | Set-Content -Path $cmdPath -Encoding utf8
  Write-Host ""
  Write-Host ("[ARM] {0}  (spec={1} K={2} ctx={3} vmt={4} reps={5} reqs={6})" -f $arm.Name,$arm.Spec,$arm.K,$arm.Ctx,$arm.Vmt,$arm.Reps,($arm.Reqs -join '+'))

  Stop-Engine
  $proc = Start-Process -FilePath $ENGINE -ArgumentList $argList `
            -RedirectStandardOutput $outPath -RedirectStandardError $errPath `
            -PassThru -NoNewWindow -WorkingDirectory (Split-Path $ENGINE)

  # 等就绪 / 等失败
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $state = 'timeout'
  while ($sw.Elapsed.TotalSeconds -lt 150) {
    if (Test-Path $errPath) {
      $t = Get-Content $errPath -Raw -ErrorAction SilentlyContinue
      if ($t -match 'listening on http') { $state = 'ready'; break }
      if ($t -match 'FATAL')             { $state = 'fatal'; break }
    }
    if ($proc.HasExited) { $state = 'exited'; break }
    Start-Sleep -Milliseconds 250
  }
  $readyS = [math]::Round($sw.Elapsed.TotalSeconds,1)
  $gpu = Get-GpuUsed
  $fatal = ''
  if (Test-Path $errPath) {
    $t = Get-Content $errPath -Raw -ErrorAction SilentlyContinue
    $m = [regex]::Match($t, 'FATAL[^\r\n]*')
    if ($m.Success) { $fatal = $m.Value.Trim() }
    $m2 = [regex]::Match($t, 'loading weights \| ([\d.]+) GiB')
    $wts = if ($m2.Success) { [double]$m2.Groups[1].Value } else { $null }
  } else { $wts = $null }
  Write-Host ("       state={0} readyIn={1}s gpu={2}MiB weights={3}GiB {4}" -f $state,$readyS,$gpu,$wts,$fatal)

  $meta = [pscustomobject]@{ arm=$arm.Name; spec=$arm.Spec; k=$arm.K; ctx=$arm.Ctx; vmt=$arm.Vmt; reps=$arm.Reps;
                            reqs=($arm.Reqs -join '+'); state=$state; ready_s=$readyS; gpu_used_mib=$gpu;
                            weights_gib=$wts; fatal=$fatal; exe=$ENGINE; model=$arm.Model; cmdline=$cmdLine }
  $allMeta += $meta

  if ($state -eq 'ready' -and $arm.Reps -gt 0) {
    for ($r=1; $r -le $arm.Reps; $r++) {
      foreach ($q in $arm.Reqs) {
        $f = Join-Path $REQDIR "$q.json"
        $swq = [Diagnostics.Stopwatch]::StartNew()
        $ok = $true; $body = $null; $emsg = ''
        try {
          $body = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
                    -InFile $f -ContentType 'application/json' -TimeoutSec 900
        } catch { $ok = $false; $emsg = $_.Exception.Message }
        $swq.Stop()
        $content = ''; $usage = $null
        if ($ok -and $body) {
          $content = $body.choices[0].message.content
          $usage   = $body.usage
        }
        $rec = [pscustomobject]@{ arm=$arm.Name; rep=$r; req=$q; ok=$ok; wall_s=[math]::Round($swq.Elapsed.TotalSeconds,2);
                                  err=$emsg; usage=$usage; content=$content }
        $allPlan += $rec
        ($rec | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $RESDIR ("{0}-r{1}-{2}.json" -f $arm.Name,$r,$q)) -Encoding utf8
        $short = if ($content.Length -gt 60) { $content.Substring(0,60) } else { $content }
        $short = $short -replace '\s+',' '
        Write-Host ("       r{0} {1,-8} ok={2} wall={3}s  {4}" -f $r,$q,$ok,$rec.wall_s,$short)
      }
    }
  }

  Stop-Engine
}

Stop-Engine
$allMeta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ROOT 'meta.json') -Encoding utf8
$allPlan | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $ROOT 'plan.json') -Encoding utf8
Write-Host ""
Write-Host "[DONE] meta.json / plan.json 已写出"
