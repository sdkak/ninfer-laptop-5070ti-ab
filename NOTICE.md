# NOTICE · 第三方与出处

本仓库**只包含作者自己的实测产出**（报告、脚本、日志、数据）。下列第三方内容**未被重分发**，此处仅作署名与溯源。

---

## 1. 模型（未被本仓库分发）

| 项 | 说明 |
|---|---|
| 制品 | Bonsai-2-27B 三元量化 `bonsai2_27b_ternary_v2.ninfer` / `bonsai2_27b_ternary_v2-dflash2.ninfer` |
| 版权 | **Prism ML, Inc.**（Apache-2.0）|
| 上游 | https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf |
| 底座 | **Qwen3.8-27B**, Copyright 2026 Alibaba Cloud（Apache-2.0）https://huggingface.co/Qwen/Qwen3.8-27B |
| 作者要求的署名 | **"Created using Bonsai by Prism ML."** |
| 本仓库引用其 sha256 | 基座 `05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C`<br>dflash2 `F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148` |

> 原包 `licenses/NOTICE.txt` 原文要点：*"This software is copyright 2026-present Prism ML, Inc.
> It is available under the Apache 2.0 license. If you publicly deploy or redistribute this software,
> we would appreciate attribution such as: 'Created using Bonsai by Prism ML.'"*
> 原包 `09-声明与链接.md` 要求：**再分发请保留署名与许可全文；若上游另有附加条款，以上游为准。**

## 2. 推理引擎（未被本仓库分发）

| 项 | 说明 |
|---|---|
| 二进制 | `ninfer-serve-sm120.exe`（官方 sm_120 构建）sha256 `FE170EB23FFDBFF5EB9F9D70A390EC639910BEAB420F30DCB937AF2CD0269C42` |
| 来源 | 由推理包提供方随包分发；本仓库**不重分发**，仅记录 sha256 供他人核对是否跑在**同一制品**上 |
| 运行时依赖 | 引擎旁需 FFmpeg 系列 DLL（`avcodec-63` / `avformat-63` / `avutil-61` / `swresample-7` / `swscale-10` / `avfilter-12` / `avdevice-63`）与 UCRT，随包提供；本仓库不重分发 |

## 3. 被引用但未重分发的第三方资料

| 来源 | 本仓库如何引用 |
|---|---|
| 推理包自带说明书（`00-从这里开始.md` … `11-按卡差异速查.md`、`判据.txt`、`README.md`、`MUST-DO.md`）| 主报告仅**摘要引用**其结论（如"K=8 起单轮成本跳 3 倍"、"`auto` 预扣 sizing headroom"），未整篇复制 |
| 另一台机器（RTX 3060 12G / sm_86）的调优归档 | 主报告 **§十四** 引用其**公开读数**用于跨架构互证，并标注来源；**该归档本身不在本仓库内**（非本项目产出，未经其作者同意不转分发）|

## 4. 本仓库自有内容的许可

| 内容 | 许可 |
|---|---|
| `reports/`、`data/`（报告与实测数据）| **CC BY 4.0** — https://creativecommons.org/licenses/by/4.0/ |
| `scripts/`（脚本）| **MIT**（见 `LICENSE`）|

转载/引用请保留本 NOTICE 与上述署名。

## 5. 许可范围（原 LICENSE 里那段说明，挪到此处）

- `scripts/` 下的脚本：**MIT**（`LICENSE` 即 MIT 全文，GitHub 由此识别仓库许可为 MIT）。
- `reports/` 与 `data/` 下的报告与实测数据：**CC BY 4.0** —— https://creativecommons.org/licenses/by/4.0/
- 第三方内容（模型、引擎二进制、运行库）**不在本仓库内**，其许可见本文件 §1–§3。