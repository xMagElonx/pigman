# 验收台账

一行 = 一次验收。**结果只五档**（口径见下），不确定就写进备注，别留空。

- `PASS` —— 判据全过
- `部分` —— 过一部分，备注写清缺哪条
- `FAIL` —— 判据没过，要修
- `BLOCKED` —— **依赖尚未产出的东西**（例：音色还没录），跑不了
- `待做` —— **人还没验过**（＝未做），只用在「必须肉眼 / 耳朵验」的项

证据：截图存本目录（`documents/acceptance/`）；录屏大文件存本地 `clips/`，这里只写文件名。纯机器的项（headless）没有截图，就写可追溯的文件/输出。

| 日期 | 验收项 | 版本(commit 7位) | 结果 | 证据 | 备注 |
|---|---|---|---|---|---|
| 2026-10-14 | 常驻自检门（`checks/selfcheck.tscn` · headless 8 项断言） | `6d71fdc` | PASS | `check.cmd` 输出 · 退出码 0 | 8/8；收尾提交 `e1c6d5f`。双击 `check.cmd` 即跑，全绿才可提交 |
| 2026-10-14 | 存档不变性（`user://tuning.cfg` md5 自检前后一致） | `6d71fdc` | PASS | 见 `../project-review-2026-10-14.md` 附二 | 自检进场只读不写；cfg 的 mtime 02:20:05 早于所有自检运行，未被污染 |
| 2026-10-14 | M2 验收 · 闭眼分辨「切中 / 挥空」 | `6d71fdc` | BLOCKED | `../../assets/audio/README.md`（待放两条音色） | **M2 唯一未过项 → M2 记「条件通过 · 欠此一条」，本条挂进 M3 质量门。** 缺 `sfx_swing_whoosh`（无低频）+ `sfx_swing_hit`（有低频冲击）；管道已通（`scripts/sfx.gd` + autoload + 两处钩子），只差音色文件 |
| — | 屠刀视觉卡 F1–F5（`documents/knife-visual-check.svg`） | `6d71fdc` | 待做 | `../knife-visual-check.svg` | 需用户在渲染窗口肉眼验收。口径在卡上：五条都在→通过；只缺 F5→说一声（材质，我调）；缺 F2 或 F3→形状没生效，说一声。**验收请在 roll ≈ −45° 做** |
| — | 柄部验收卡 H1–H5（`documents/knife-handle-check.svg`） | `6d71fdc` | 待做 | `../knife-handle-check.svg` | 需用户在渲染窗口肉眼验收。口径在卡上：**缺 H1 或 H4 → 说一声；只缺 H5 → 我调材质**。柄那组滑条在面板最下面 |

| 2026-10-14 | P1-1 · 调参键分组修正（`tuning_store.gd` / `main.gd`） | `84b6c24` | PASS | 自检门 12/12 · 退出码 0 | 新增 ⑦ 键全局唯一、⑧ 旧档迁移；仍 35 根滑条；main.gd 仅加 `group` 字段 8 行 |
| 2026-10-14 | P1-1 · 旧档迁移不得丢用户调参值（**真实存档端到端**） | `84b6c24` | PASS | `../project-review-2026-10-14.md` 附三 | **14/14 无损**：blade_len 0.58 / handle_len 0.16 / blade_width 0.1383 / jump 6.7 / hold_pitch 40 / recovery 0.17；`world.*` 键数归零；`tuning.cfg` md5 前后一致 |
| — | P1 · 冻结移动基线（12 参数只剩 jump 待定 6.7 vs 7.0） | `84b6c24` | 待做 | `../movement-freeze-sheet.md` | **只有用户能定**；他已把其余 11 项拖回出厂值 |

> 用法见同目录 `README.md`。
