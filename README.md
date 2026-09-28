# ninfer / Bonsai-2-27B 三元量化 · RTX 5070 Ti Laptop 12G 实测

> 一台 **12 GB 笔记本卡**（RTX 5070 Ti Laptop，cc 12.0 / SM 46）上，对 Bonsai-2-27B 三元量化离线推理包的
> **两条投机路线（MTP / DFlash2）做的同口径 A/B 实测**，含**原始引擎日志、每臂完整命令行、合并矩阵**。
>
> 目的：让后来者不必重跑一遍就能知道"在 12 GB 卡上该选哪条路、能开到多少上下文、哪些读数会骗人"。

---

## 结论速览

| 问题 | 实测答案 |
|---|---|
| 同 ctx（32768）下谁快？ | dflash2 K=7 在**结构化内容**上领先：**写代码 158.5 vs 105.6（+50%）**、数数字 **229.4 vs 134.6（+70%）**；散文基本相当 |
| 那 dflash2 该当日常档吗？ | **不该**：开放生成时墙钟只快 11%（代码）/6%（散文），且**上下文天花板只有 54272**（MTP 是 163840）|
| dflash2 的上下文天花板 | **54272**（视觉预算 2048）／ **41984**（视觉预算 8192）—— **不是** 32768，也不是传言的 16384 |
| dflash2 的 K 取多少 | **K=7**（K=5 更慢；K=11 在 code/prose 上崩）|
| 上下文影响速度吗 | **不影响**（MTP：32K → 163840 差 0.3%）|
| 质量 | 四档配置全部通过（847×293→`248171` / `3/5` / `21` / JSON / 负控拒答），长文取针 57,750 token 逐字取回 |

**最终决策（本机）**：`MTP d4 + ctx 163840` 为日常档；dflash2 K=7 只在"短上下文 + 固定长度结构化输出"场景另开一档。

---

## 你会在这里找到什么

| 路径 | 内容 |
|---|---|
| `reports/dflash2-vs-MTP-实测.md` | ★ **主报告**（14 节：速度矩阵 / 墙钟修正 / 上下文天花板 / K 与 KV 调优 / 质量与取针 / 勘误 / 复现 / 跨架构互证）|
| `scripts/ab.ps1` | 主矩阵测试台（15 臂）：启动引擎 → 跑固定请求电池 → 停服 |
| `scripts/ab-hard.ps1` | 加固版（`Connection: close` + 失败重试 3 次），可指定引擎/臂名后缀 |
| `scripts/probe.ps1` | 只做启动探测，把 **ctx 天花板钉到页（512 token）粒度** |
| `scripts/needle.ps1` | 长文取针（`-Raw` 用原封夹具；被拒自动缩容重试）|
| `scripts/analyze.ps1` | 解析引擎日志 → 可对齐矩阵（含每请求 decode / 接受率 / TTFT / cache）|
| `scripts/matrix.ps1` | 合并多次运行 → `matrix.csv` |
| `data/logs/*.err` | ★ **54 份引擎原始日志**（权威读数在 `req#N done` 行里）|
| `data/logs/*.cmd.txt` | ★ **每臂的完整命令行**（可复现的关键 —— 本项目的前身就是因为没存它而无法对齐读数）|
| `data/matrix.csv` | 合并矩阵：臂 × 内容类型的 decode 中位 / 接受率 / 输出长度 / TTFT |
| `data/meta-*.json`、`data/parsed-*.json` | 机器可读的元数据与解析结果 |
| `data/res/*.json` | 每个请求的完整响应（含生成内容）、耗时、错误信息 |
| `data/req/*.json` | 全部请求夹具（提示词、max_tokens、temperature）|

---

## 复现

**硬件/制品**（读数只在同口径下可比）：

```
GPU    NVIDIA GeForce RTX 5070 Ti Laptop GPU · 12,227 MiB · cc 12.0 · SM 46
引擎   ninfer-serve-sm120.exe   sha256 FE170EB23FFDBFF5EB9F9D70A390EC639910BEAB420F30DCB937AF2CD0269C42
权重   bonsai2_27b_ternary_v2.ninfer            sha256 05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C
       bonsai2_27b_ternary_v2-dflash2.ninfer    sha256 F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148
```

**口径**：贪心（`temperature=0`）、`--no-thinking`、`--kv-dtype nvfp4`、`--host-kv-mib 2048`、
`--wddm-evictable-budget`、带视觉、每读数 3 次取中位、报数必带**内容类型 + 接受率**。

```powershell
# 主矩阵（15 臂，约 20 分钟；每臂独立引擎，命令行写入 data/logs/<臂>.cmd.txt）
pwsh -File scripts\ab.ps1

# 只跑指定臂（注意：-Only 传数组要用 & 调用，不要用 pwsh -File）
& scripts\ab-hard.ps1 -Only 'hd-mtp-d5','hd-mtp-d3'

# ctx 天花板逐页上探
& scripts\probe.ps1 -Ctx 54272,54784 -Vmt 2048 -Tag myprobe

# 解析日志出矩阵
& scripts\analyze.ps1 -MetaFile meta-run1.json -ParsedFile parsed.json
```

> 脚本里写死的路径（`D:\ai\ninfer\...`、`D:\build-pq2\...`）是**作者机器的布局**，复用时请改成本机路径。

---

## 已知的测量陷阱（都踩过，别再踩）

1. **短输出会伪造低接受率**：4-token 的视觉探针"接受率"42.9%，同引擎 400-token 样本 96.9%。
   ⇒ 判接受率必须 `output ≥ 400 token` 且以 output-limit 收尾；**短样本一律丢弃**。
2. **换 K / 换 KV 精度 / 换引擎会换答案**：同一配置重复逐字相同，但 `--draft-tokens` d3/d4/d5 在开放题上输出各不相同
   （同题写代码 3990 / 3996 / 4171 字符）；**前缀缓存命中与否也会改变输出**。
   ⇒ 别宣称"投机只提速不改文本"；只有高置信、固定长度任务才逐字一致。
3. **同一端口只能有一台引擎**：本项目的原始运行就被另一个进程在 8086 上抢过端口 —— 它先杀掉我们的引擎，
   又**接走**了后续请求（客户端报成功、引擎日志里却没有对应记录）。识别方法：**每臂独立日志 + 命令行固化 + 内容哈希**。
   跑分前先确认端口上只有一台引擎。
4. **`--lm-head-draft` 是 dflash2 的强制项**，不加启动即 `FATAL ... linear_topk: unsupported head profile`；
   `--spec dflash` **不能**配 dflash2 制品（`FATAL ... masked draft backend is not supported by this target`）。
5. **`--kv-capacity auto` 会预扣 1 GiB** sizing headroom（引擎 `--help` 原文），12 GB 卡上很容易因此拒启。
6. **同一配置跨会话有 ~1% 漂移**，所以头部对比用了两个独立会话合并（n=6），单会话 n=3 只用于 K/KV 对照。

---

## 不包含什么（重要）

| 不含 | 原因 |
|---|---|
| **模型权重**（`*.ninfer`，7.9 GB / 10 GB）| 第三方制品，且体积不适合进仓库；请从上游获取 |
| **引擎二进制**（`ninfer-serve*.exe`，190/252 MB）| 同上。本仓库通过 **sha256** 与之对齐 |
| 推理包自带的说明书/手册 | 版权属原作者；本报告只做引用，未整篇复制 |
| 另一台机器（RTX 3060）的归档 | **不是本项目的产出**，未经其作者同意不转分发（主报告 §十四 仅引用其公开读数并标注来源）|

---

## 许可与署名

- **本仓库自有内容**（报告、脚本、实测数据）：`reports/` 与 `data/` 采用 **CC BY 4.0**；`scripts/` 采用 **MIT**（见 `LICENSE`）。
- **上游署名**（依其 `NOTICE.txt` 要求）：
  - 模型：**Created using Bonsai by Prism ML.**（Prism ML, Apache-2.0）
  - 底座：Qwen3.8-27B, Copyright 2026 Alibaba Cloud（Apache-2.0）
  - 引擎：ninfer（本仓库不重分发其二进制，仅记录 sha256）
- 第三方组件与出处见 `NOTICE.md`。

> 本实测**不构成对性能的普适承诺**：所有数字都是在上述硬件 + 上述 sha 的制品 + 上述口径下取得，
> **跨卡不可比**（同一推理由不同卡得出不同结论是正常的，详见主报告 §十四 的跨架构互证）。

