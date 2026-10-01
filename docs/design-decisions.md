# 设计决策记录：M-1000 Maxigun ← E/MG-101 HMG Emplacement 射弹替换

> 本文记录已**核实**的事实与关键决策，供实现与排查参照。

## 1. 确认的构建信息

| 项 | 值 | 来源 |
|---|---|---|
| 游戏 exe | 1.8.46015.0 | 本机 `bin/helldivers2.exe` |
| 构建号 | 25480438 | README / loader 日志 |
| `game.dll` SHA-256 | `2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e` | 本机实测 |
| Loader | Bingus Shared Loader **v18 / API 1** | 本机日志首行 |
| 反作弊 | nProtect GameGuard（`bin/GameGuard` 存在） | 本机 |

> `game.dll` 哈希与用户先前提供的 Minigun mod 硬编码值**完全一致** → 本机就在该 mod 的目标构建上。

## 2. 两个武器的真实身份（本次最大发现）

| 用户说法 | 真实武器 | 内部/机制名 |
|---|---|---|
| 「加特林背包」 | **M-1000 Maxigun**（Python Commandos 债券，1.005.000 加入） | 射弹 `M-1000 P`；mod 内部组件名 `Minigun` |
| 「重机枪部署支架」 | **E/MG-101 HMG Emplacement**（战备，Bridge 解锁） | 射弹 `Rifle 12.5x100mm Full Metal Jacket` |

⚠️ **「加特林背包」不是** Gatling Sentry（A/G-16），也不是未发布的 MINIGUN 实体。
先前的 Minigun mod 内部用 `Minigun.*` 命名，但游戏内商品名是 **M-1000 Maxigun**。

## 3. 两发射弹的权威数据（wiki.gg，逐项核对）

| 参数 | **M-1000 Maxigun** | **E/MG-101 HMG Emplacement** |
|---|---|---|
| 攻击名 | `M-1000 P` | `Rifle 12.5x100mm Full Metal Jacket` |
| 质量 Mass | **11 g** | **52 g** |
| 初速 | **920 m/s** | **880 m/s** |
| 阻力 Drag | 30% | 30% |
| 重力 | 100% | 100% |
| 穿甲减速 | 25% | 25% |
| 伤害 / 耐久 | **80 / 18** | **200 / 40** |
| 穿甲 | **AP3（中）** | **AP4（重）** |
| 拆迁 / 硬直 / 推力 | 10 / 15 / 12 | 20 / 25 / 15 |

**结论：两者是完全不同的射弹族**（11 g vs 52 g）。
早期假设「Maxigun 也用 8x60mm 族」**已被证伪**——8x60mm 是 MG-43 机枪的弹（90 dmg / AP3），
质量虽同为 11 g 但初速 820 m/s，与 Maxigun 的 920 m/s 不符。

## 4. 射弹枚举索引（ProjectileType）

| 枚举名 | 索引 | 用途 |
|---|---|---|
| `ProjectileType_Rifle_12p5x100mm_fmj` | **58** | **HMG Emplacement 的射弹（源）** |
| `ProjectileType_Rifle_12p5x100mm_bchp` | 194 | 同族变体 |
| `ProjectileType_Rifle_12p5x100mm_eit` | 162 | 同族变体 |
| `ProjectileType_Rifle_8x60mm_fmj` | 106 | MG-43 的弹（**不是**目标） |

枚举总条目 247（不含末尾 `ProjectileType_Count`）。

> ⚠️ **枚举索引会被版本回收**（技能文档 6.26/6.35）。实现里**不要**把 58 当硬性准入，
> 只用它当提示，必须靠 `name_upper` + 物理量指纹定位记录。

## 5. 目标射弹记录的识别指纹

来自 wiki 的 `Rifle 12.5x100mm FMJ`：

| 字段 | 偏移 | 期望值 |
|---|---|---|
| `calibre` | +24 | 12.5 |
| `speed` | +32 | 880 |
| `mass` | +36 | 52 |
| `drag` | +40 | 0.30 |
| `gravity_multiplier` | +44 | 1.0 |
| `penetration_slowdown` | +64 | 0.25 |
| `damage_info_type` | +60 | `DamageInfoType_Projectile_Rifle_12p5x100mm_fmj` |

**判据设计（按技能文档 6.34 分层）**：
- **主键**：`name_upper`（本地化键哈希，跨构建稳定）——必须命中
- **硬判据**：`mass == 52`、`calibre == 12.5`、`drag ≈ 0.3`、`gravity == 1.0`（物理量，各 2~3 分）
- **弱提示**：`speed`（平衡性会动，留 ±40 容差）、`damage_info_type`（枚举会漂移，只丢分不改结论）
- **通过条件**：硬判据 ≥ 4/5 **且** 总分 ≥ 阈值 **且** 唯一最高分
- ⚠️ **绝不**用表大小 / 记录数当准入条件（技能文档 6.33）

## 6. ProjectileInfo 记录布局

**步长 = 272 字节**（本机实测推导：`95292 - 76 = 95216 = 16 + 350 × 272`）。

已与游戏 typelib 核对过的锚点偏移（技能文档 `hd2-eruptor-dominator-案例.md`）：

| 偏移 | 类型 | 字段 |
|---|---|---|
| +0 | u32 | ProjectileType（全表唯一） |
| +4 / +8 / +12 | u32 | NameUpper / NameCased / ShortName |
| +16 | u64 | HudIcon |
| +24 | f32 | Calibre |
| +28 | u32 | NumProjectiles |
| +32 | f32 | Speed |
| +36 | f32 | Mass |
| +40 | f32 | Drag |
| +44 | f32 | GravityMultiplier |
| +56 | f32 | LifeTime |
| +60 | u32 | **DamageInfoType** |
| +64 | f32 | PenetrationSlowdown |
| +136 | f32 | ExplosionThresholdAngle |
| +140 | u8 | CanExpireAfterImpact（+ 3 字节填充） |
| +144 | u32 | **ExplosionTypeOnImpact** |
| +148 / +152 | f32 | ExplosionProximity / ExplosionDelay |
| +156 | u32 | ExplosionTypeExpire |
| +160 | f32 | ArmingDistance |
| +164 | f32 | DecalSize |

> **本 mod 只动 ≤ +164 的字段**，尾部布局不确定**不影响**正确性。
> 实现时**不复制整条 272 字节**，只按白名单逐字段写入，避免踩到未验证的尾部。

## 7. 实现策略（关键决策）

**用户选择：拷贝整条射弹记录（速度、质量、伤害类型、爆炸全照搬）。**

具体做法——**白名单字段复制，而非整条 memcpy**：

```
写入字段（源 = HMG Emplacement 射弹记录）：
  +24  calibre                  12.5
  +32  speed                    880
  +36  mass                     52
  +40  drag                     0.30
  +44  gravity_multiplier       1.0
  +60  damage_info_type         <源记录的枚举值>
  +64  penetration_slowdown     0.25
  +136 explosion_threshold_angle
  +144 explosion_type_on_impact
  +148 explosion_proximity
  +152 explosion_delay
  +156 explosion_type_expire
  +160 arming_distance
  +164 decal_size
  +176 max_ricochets
  +180 ricochet_threshold_angle
  +184 ricochet_threshold_speed
  +188 ricochet_angle_loss
  +192 ricochet_spread_vertical
  +196 ricochet_spread_horizontal

保留目标自己的：
  +0   type             ← 绝不改！全表唯一，改了会撞车
  +4/+8/+12 名字        ← 保留，否则 HUD/图标显示错乱
  +16  hud_icon
  +72..+128 粒子/单位路径 ← 保留，否则子弹外观/曳光弹变样
```

**理由**：技能文档案例四第 4 节的做法同源——"把记录 261 整条拷到记录 258，
**保留目标自己的 Type 值**（维持全表唯一）"。保留 `type` 是硬要求。

## 8. 必须遵守的安全约束（技能文档 §10）

- 先**只读侦察**，确认位置后再写
- 写入前校验值域，写入后**回读逐字段复查**
- 校验 `game.dll` SHA-256，不符**拒绝写入**
- **不从外部进程读内存**（GameGuard）
- 目标记录的**每一份副本都要打**，且持续维护（6.17）
- 任何校验不符 → **记日志拒绝写入**，绝不猜测
- 主动向用户说明：改动是客户端本地的，联机时队友多半看不到；存在反作弊风险

## 9. 相对技能文档的构建漂移（本机 vs 文档）

| 项 | 文档（案例） | 本机 |
|---|---|---|
| 构建 | 24826606 / 1.8.45317.0 | **25480438 / 1.8.46015.0** |
| ProjectileSettings | 93312 / 343 条 | **95216 / 350 条** |
| game.dll SHA | `A09FF526...` | `2e2c3b7c...` |

→ **所有偏移必须运行时推导 + 内容校验**，不能照抄文档。

## 10. 待确认事项

- [ ] 目标记录（Maxigun 射弹）在表中的确切记录索引 —— 需要明文镜像解出
- [ ] 源记录（HMG Emplacement 射弹）的确切记录索引
- [ ] Maxigun 的 `damage_info_type` 当前值（mod 之前）
- [ ] 是否存在多份副本需要同时打
