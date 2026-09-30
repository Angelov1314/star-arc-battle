# 星轨弹斗 · Star Arc Battle

一个原创的 Godot 4 单机弹射对战游戏源码快照。当前工程版本是 **0.5.2**，包含主城、三章九关、精英变体、永久成长、装备与强化、补给、宝石、分解、AI 对战、训练和同机双人模式。

## 运行

使用 Godot 4.6 或更新的 4.x 版本打开本目录中的 `project.godot`，然后运行主场景。项目只使用本地资源，没有网络服务、账号、云存档或付费系统。当前快照不包含可运行的 macOS 压缩包；需要匹配的 Godot 导出模板才能自行导出。

核心逻辑测试可以在项目根目录运行：

```sh
Godot --headless --path . --script tests/test_power_core.gd
Godot --headless --path . --script tests/test_power_economy.gd
Godot --headless --path . --script tests/test_power_integrity_audit.gd
Godot --headless --path . --script tests/test_power_battle.gd
Godot --headless --path . --script tests/test_power_ui.gd
```

如果系统命令名为小写 `godot`，将上面的 `Godot` 替换为 `godot`。`SNAPSHOT_MANIFEST.txt` 记录了本次公开快照执行的验证结果；`docs/validation/` 保留了历史测试、流程、性能和截图证据。

## 当前状态与验证边界

源码中的 `project.godot` 版本为 0.5.2。仓库里的 `docs/validation/REPORT.md` 和相关文本主要记录 2026-09-06 至 2026-09-09 的历史版本验收，其中包含 90 项断言、10 局自动模拟、23 项按钮流程、渲染截图和 Apple Silicon Metal 性能样本；这些记录不能单独证明 0.5.2 在所有硬件上的完整验收。自动对战由同一搜索逻辑驱动，不能代表真人胜率或真人平均局长。主观听音、跨硬件性能和 Intel 实机验证也没有被宣称完成。

macOS 构建曾使用本地 ad-hoc 签名，未做 Apple 公证。公开快照没有包含构建包、Godot 导入缓存或本机用户存档。

## 资产来源

- `assets/art/` 中的图片是为本项目生成的原创提示图，提示词与逐项状态见 `assets/art/manifest.json`。清单明确记录这些生成资产尚未经过独立法律审查。
- `assets/sound/original/` 中的音乐和音效由 `tools/generate_original_audio.py` 离线程序合成，不使用外部采样；重建说明和参数见该目录的 README 与 manifest。
- 旧原型 MP3 音频、旧 UI 资源、构建产物、导入缓存和本机日志已从公开快照移除。
- 资产与代码没有在本快照中附带一个涵盖所有内容的开源许可证。请先阅读 `LICENSE.md` 和 `docs/ASSET_PROVENANCE.md`，再复制或再分发任何内容。

## 目录

- `scripts/`：游戏流程、战斗、成长、存档、装备、UI 和音频服务。
- `scenes/`：主场景。
- `tests/`：核心规则、战斗、存档、流程和 UI 测试。
- `data/`：地图点击区域与运行契约。
- `assets/`：当前版本实际引用的生成图片和程序合成音频。
- `docs/validation/`：精选历史验证报告、日志和截图。
