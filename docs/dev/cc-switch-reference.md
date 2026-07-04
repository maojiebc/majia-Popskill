# cc-switch 参考笔记（2026-07-05，v2.14 迭代时整理）

> 源：github.com/farion1231/cc-switch（Tauri：React 前端 + Rust 后端，260+ command）。
> Popskill v1 曾借鉴其 skills 管理；本次为补产品完成度细节通读。已吸收与备选如下。

## v2.14 已吸收

- **工具版本矩阵**（AboutSection + ToolInstallRow）：工具名 | 当前版本 | 最新版本 | 状态 | 操作 → Popskill 的 CliSheet（CLI 巡检）。
- **手动检查更新入口显性化**：它在 Settings→About；Popskill 更进一步放 hero 常驻。
- **异步操作反馈链**：按钮禁用 → 后台执行 → toast → 状态刷新（CLI 升级流照此实现）。

## 备选（未来迭代按需取）

| 细节 | cc-switch 实现 | 适配 Popskill 的做法 |
|---|---|---|
| 更新徽标 dismiss（跳过此版本） | UpdateContext + localStorage 存 dismissedVersion，旧 key 迁移 | meta 存 skippedLatest，checkUpdate 结果等于它则不亮徽标 |
| 深链接 | `ccswitch://` scheme（deeplink.rs），配置分享一键导入 | `popskill://install?src=...` → onOpenURL 进添加流程 |
| 确认弹窗「不再提示」 | ConfirmDialog 可选勾选框 | NSAlert suppressionButton（系统原生） |
| 拖拽排序 | @dnd-kit + sortIndex 字段 | SwiftUI onMove；但矩阵有固定排序语义（套装置顶/类型/名称），价值存疑 |
| 备份/回滚 | DB 级备份列表：自动+手动+恢复+重命名 | store 已有回收站（200 份 FIFO）；差「整 store 快照」概念，可用 git（store 本身可 git 化） |
| 环境警告横幅 | EnvWarningBanner（PATH 冲突检测 + 修复按钮） | 已有健康横幅；可加「npm 不在 PATH」类环境探测项 |
| 托盘菜单 | tray.rs 动态分区菜单、轻量模式 | Popskill 刻意无托盘（一个主屏哲学），保持 |
| 设置页签记忆 | defaultTab + localStorage | 设置弹层单页，暂无需求 |
| 多语言 | 4 语言 JSON（zh/zh-TW/en/ja） | xcstrings 已支持扩语言，等真实需求 |

## 结构速记（找代码用）

- 更新流：`src/contexts/UpdateContext.tsx`（启动 1s 后自动检查 / dismiss 机制）
- 版本矩阵：`src/components/settings/AboutSection.tsx`
- 确认弹窗：`src/components/ConfirmDialog.tsx`（zIndex 分层 base/nested/alert/top）
- 备份：`src/hooks/useBackupManager.ts` + `src-tauri/src/database/backup.rs`
- 深链接：`src-tauri/src/deeplink.rs`
- 本地克隆在会话 scratchpad（临时），要看代码重新 clone。
