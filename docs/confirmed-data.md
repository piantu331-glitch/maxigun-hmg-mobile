# M-1000 Maxigun ← E/MG-101 HMG Emplacement 射弹替换 —— 已确认数据

> 构建 **25480438 / exe 1.8.46015.0**，`game.dll` SHA-256
> `2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e`
>
> 状态：**规格已确认，字节级定位未完成**（原因见 §6）

---

## 1. 两个武器的真实身份

| 用户说法 | 真实武器 | 内部机制 |
|---|---|---|
| 「加特林背包」 | **M-1000 Maxigun** | 射弹名 `M-1000 P`；游戏内部实体/组件名 `Minigun` |
| 「重机枪部署支架」 | **E/MG-101 HMG Emplacement** | 射弹名 `Rifle 12.5x100mm Full Metal Jacket` |

**关键更正**：之前那个 Minigun mod 内部用 `Minigun.*` 命名，容易误以为是未发布实体。
实际游戏商品名是 **M-1000 Maxigun**（Python Commandos 债券 P3，1.005.000 加入）。

> 注意区分三个东西：
> - **M-1000 Maxigun** —— 背包加特林（本次目标）
> - **A/G-16 Gatling Sentry** —— 加特林炮塔战备（无关）
> - **MG-206 HMG** —— 手持重机枪（无关）
> - **E/MG-101 HMG Emplacement** —— 重机枪部署支架（本次源）

---

## 2. 两发射弹的权威对比（wiki.gg，逐项核对）

| 参数 | **M-1000 Maxigun**（目标） | **E/MG-101 HMG Emplacement**（源） |
|---|---|---|
| 攻击名 | `M-1000 P` | `Rifle 12.5x100mm Full Metal Jacket` |
| **质量** | **11 g** | **52 g** |
| **初速** | **920 m/s** | **880 m/s** |
| 阻力 | 30% | 30% |
| 重力 | 100% | 100% |
| 穿甲减速 | 25% | 25% |
| **伤害 / 耐久** | **80 / 18** | **200 / 40** |
| **穿甲** | **AP3（中）** | **AP4（重）** |
| 拆迁 / 硬直 / 推力 | 10 / 15 / 12 | 20 / 25 / 15 |

### 结论：两者是**完全不同的射弹族**，不共用任何记录

- Maxigun：**11 g** → 8x60mm 族
- HMG Emplacement：**52 g** → 12.5×100mm 族

> ⚠️ **重要**：这意味着本次改动是**跨射弹族的复制**，是实质性增强：
> 80→200 伤害（2.5×）、AP3→AP4、质量 11→52 g、初速 920→880 m/s。
> 质量增加 4.7× 会让弹道下坠和命中反馈明显不同。

---

## 3. 已解析的枚举索引（本机工具 `tools/enumidx.js` 可复算）

### 源：HMG Emplacement 的射弹

| 枚举 | 索引 | 十六进制 |
|---|---|---|
| `ProjectileType_Rifle_12p5x100mm_fmj` | **58** | 0x3A |
| `DamageInfoType_Projectile_Rifle_12p5x100mm_fmj` | **133** | 0x85 |

### 目标：Maxigun 的射弹（8x60mm 族候选）

| 枚举 | 索引 |
|---|---|
| `ProjectileType_Rifle_8x60mm_fmj` | **106** (0x6A) |
| `ProjectileType_Rifle_8x60mm_fmj_NoCrack` | 118 (0x76) |
| `ProjectileType_Rifle_8x60mm_tracer` | 173 (0xAD) |
| `ProjectileType_Rifle_8x60mm_tracer_NoCrack` | 73 (0x49) |
| `DamageInfoType_Projectile_Rifle_8x60mm_fmj` | **73** (0x49) |

> **未确认**：Maxigun 究竟用四个 8x60mm 候选中的哪一个。
> 必须从数据表读出，不能猜。

### 其他同族变体（源侧参考）

| 枚举 | 索引 |
|---|---|
| `ProjectileType_Rifle_12p5x100mm_eit` | 162 |
| `ProjectileType_Rifle_12p5x100mm_bchp` | 194 |
| `ProjectileType_Rifle_12p5x100mm_eit_mk2` | 76 |

枚举总条目 **247**（不含末尾 `ProjectileType_Count`）。

---

## 4. ProjectileInfo 记录布局（步长 272 字节）

步长由本机文件算术**实测确认**：
```
generated_projectile_settings.dl_bin = 95292 字节
95292 - 76 = 95216 = 16 + 350 × 272   ✅
```

字段偏移（与游戏 typelib 核对过的锚点，来自技能文档案例）：

| 偏移 | 类型 | 字段 | 本 mod 是否修改 |
|---|---|---|---|
| +0 | u32 | ProjectileType（全表唯一） | ❌ **绝不改** |
| +4/+8/+12 | u32 | NameUpper / NameCased / ShortName | ❌ 保留 |
| +16 | u64 | HudIcon | ❌ 保留 |
| +24 | f32 | Calibre | ✅ 写 |
| +28 | u32 | NumProjectiles | ✅ 写 |
| +32 | f32 | Speed | ✅ 写 |
| +36 | f32 | Mass | ✅ 写 |
| +40 | f32 | Drag | ✅ 写 |
| +44 | f32 | GravityMultiplier | ✅ 写 |
| +56 | f32 | LifeTime | ✅ 写 |
| +60 | u32 | **DamageInfoType** | ✅ 写 |
| +64 | f32 | PenetrationSlowdown | ✅ 写 |
| +72…+128 | u64 | 粒子 / ProjectileUnitPath | ❌ 保留 |
| +136 | f32 | ExplosionThresholdAngle | ✅ 写 |
| +140 | u8 | CanExpireAfterImpact（+3 填充） | ✅ 写 |
| +144 | u32 | **ExplosionTypeOnImpact** | ✅ 写 |
| +148/+152 | f32 | ExplosionProximity / ExplosionDelay | ✅ 写 |
| +156 | u32 | ExplosionTypeExpire | ✅ 写 |
| +160 | f32 | ArmingDistance | ✅ 写 |
| +164 | f32 | DecalSize | ✅ 写 |
| +176…+196 | u32/f32 | 跳弹参数组 | ✅ 写 |
| +200…+268 | — | 音频 / 模板 / 尾部 | ❌ 保留 |

> **决策：按白名单逐字段写入，不做整条 272 字节 memcpy。**
> 原因：`+200` 之后的尾部布局**未经独立验证**（我的结构推算得 280 而非 272，
> 说明尾部至少有一个假设是错的）。逐字段写入天然规避这个未知区域。

---

## 5. 必须遵守的安全约束

- 先**只读侦察**，确认位置后再写
- 写入前校验值域，写入后**回读逐字段复查**
- 校验 `game.dll` SHA-256 = `2e2c3b7c...`，不符**拒绝写入**
- **不从外部进程读内存**（本机有 nProtect GameGuard）
- 目标记录的**每一份副本都要打**，且持续维护
- **不用表大小 / 记录数当准入条件**（构建更新会静默失效）
- 任何校验不符 → 记日志拒绝写入，绝不猜测

---

## 6. ⛔ 未完成：为什么还不能出成品

**缺一份解密的 `generated_projectile_settings.dl_bin`。**

本机 `data/game/generated_projectile_settings.dl_bin`（95292 字节）**是加密的** ——
实测熵极高，全文件 `LDLD` 出现 **0** 次。改不了，也不在 mod 管线里。

需要的是 FileDiver 模块里打包的**明文镜像**，但本沙箱：

| 障碍 | 表现 |
|---|---|
| shell 网络全挂 | `curl` 返回 000；`Invoke-WebRequest` TLS 报错；DNS 把 `raw.githubusercontent.com` 解析到 127.0.0.1 |
| 未装 Go / git / 真 Python | 无法 `go mod download`；`python` 只是 Microsoft Store 占位符 |
| `web_fetch` 有 ~50KB 硬截断 | 1 MB 的 `generated_projectile_settings.json` **永远读不到 Rifle_* 段**（按字母序在 Cyborg_* 处被截断） |
| 换过的镜像全部失败 | ghproxy / jsdelivr / statically / githack / allorigins / Wayback / gitee —— 403、404 或同样截断 |

**已确认的**（不依赖明文表）：
- 两个武器身份、全部物理参数（wiki 数据挖掘表，与游戏数据同源）
- 全部枚举索引（从发布的枚举顺序算出）
- 记录步长 272、字段偏移锚点
- 本机构建号、game.dll 哈希、loader 版本

**未确认的**（必须读明文表）：
- Maxigun 射弹在表中的**记录索引**
- HMG Emplacement 射弹的**记录索引**
- Maxigun 用四个 8x60mm 候选中的**哪一个**（`fmj` / `fmj_NoCrack` / `tracer` / `tracer_NoCrack`）
- 两个 `name_upper` 值（定位记录的主键）
- 是否存在多份副本

### 解除阻塞的办法（任选其一）

1. **在有网机器上**取 FileDiver 明文镜像：
   ```
   go mod download github.com/xypwn/filediver
   # 文件在 <GOMODCACHE>/github.com/xypwn/filediver@<ver>/datalibrary/
   # 取 generated_projectile_settings.dl_bin（约 95 KB）
   ```
   放到 `ref/filediver/datalibrary/`。

2. **解本机那个加密文件**：需要游戏自己的解密路径（FileDiver 实现）。

3. **退一步的替代方案**（不需要明文表）：写一个**只读侦察 addon**，
   在内存里扫描 `LDLD` 块定位 ProjectileSettings 表，把目标记录 dump 成 hex 落盘
   (`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`)。
   拿到 dump 后我用本机 Node 工具离线解析、算出偏移，再做写入版。
   —— **这只需要你进一次游戏**，是目前最快的路。

---

## 7. 建议的下一步

推荐走**方案 3**：先交一个**绝不写内存**的只读侦察 addon。
它符合技能文档「先只读、后写入」的硬性要求，而且能一次性拿到：
- 表在内存里的形态（DLArray 是相对偏移还是绝对指针——这是必踩的坑）
- 两条记录的完整原始字节
- Maxigun 究竟用哪个 8x60mm 变体
- 副本数量

拿到 dump 后，写入版就是纯粹的离线工作，一次上机即可验证。

---

## 8. 本机环境现状（已探明）

| 项 | 状态 |
|---|---|
| 游戏 | `C:\AAAyingyong\steam\steamapps\common\Helldivers 2` |
| 构建 | 1.8.46015.0 / 25480438 |
| Bingus Shared Loader | **v18 / API 1，运行正常** |
| 已加载 addon | **29 个**（含 Vanilla Plus Megapack、`mods/starm/minigun_backpack_heavy_mobile`） |
| GameGuard | 存在（`bin/GameGuard`） |
| 日期 | 日志显示 2026-09-30 |
| Node.js | ✅ v24.9.0（本机工具链用这个） |
| Go / git / 真 Python | ❌ 均未安装 |

> ⚠️ 你当前**已经装着** `mods/starm/minigun_backpack_heavy_mobile`（patch_38），
> 它把 Maxigun 的 `DamageInfo` 穿甲从 AP3 改成了 AP4（`+12` 偏移处 3 字节 → 4）。
> 本 mod 改的是**射弹表**，与它**不冲突但会叠加**：
> 两者同时启用时，穿甲以射弹表的 `damage_info_type` 为准。
> 如果要干净的对照测试，建议先禁用那个 mod。
