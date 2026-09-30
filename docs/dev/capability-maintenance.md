# 能力维护迭代：技能、Agent CLI 与更多工具

本轮目标是让已有维护中心能回答三个实际问题：哪些内容需要更新、应该更新哪份安装、执行后发生了什么。保留纯 Swift、文件系统库存和 `~/.agents` 唯一真源。

## 对照来源

调研时 CC Switch Latest 为 v3.20.4；Magpie Latest 为 v0.1.456。Magpie 发布非常频繁，下面固定源码提交，避免把本次结论当成永久的“最新版”比较。

| 参考 | 固定源码 | 吸收点 |
| --- | --- | --- |
| [Magpie](https://github.com/yetone/magpie/tree/60e4591315962cbfb20a6e7a2178d30374dcc436) | `60e4591315962cbfb20a6e7a2178d30374dcc436` | `internal/agent/cliupdate.go` 的按实际安装渠道更新；`internal/library/targets.go` 的工具能力目录 |
| [CC Switch](https://github.com/farion1231/cc-switch/tree/43e1d99084ed9b2f5dc252fd35c5adaf29d6876e) | `43e1d99084ed9b2f5dc252fd35c5adaf29d6876e` | `src-tauri/src/services/skill.rs` 的来源匹配、更新前检查、安装身份复核；Hermes 技能目录 |

本轮以 Swift 重新实现适用于 Popskill 的维护流程。致谢与原项目 MIT 许可位于 `docs/licenses/`；原项目均保留各自版权。

## 交付行为

维护中心增加技能更新、CLI 升级、上游新增的汇总入口，以及“检查技能和 CLI”。每个技能来源展开后按成员显示可更新内容；上游新增技能可逐项安装，沿用原有安装预检与挂载策略。CLI 详情显示安装渠道、实际文件、计划更新命令；“重新读取本机”仅盘点本地安装。

CLI 盘点覆盖 npm、Homebrew、pipx、uv，以及已确认的原生、bun、pnpm 安装。原生 Claude Code / Codex / OpenCode 使用自己的 updater；Magpie 的官方本机路径使用 `magpie update`，最新版来自其官方 Release。bun 与 pnpm 保留其全局安装位置；Homebrew 区分 formula 与 cask，并向官方 API 查询版本，不把过期本地元数据当成最新。

pnpm 先从标准启动脚本的实际目标确定安装，再以 `pnpm root --global` 和对应的全局根配置核对管理器将使用的目录。更新配置传入 generation 的父目录；这是 [pnpm 的目录规则](https://github.com/pnpm/pnpm/blob/v10.17.1/config/config/src/index.ts#L296-L311)。旧 generation、含动态 shell 表达式的脚本或无法确认的目标仅展示，不提供升级按钮。本机 pnpm 10.30.3 已只读验证该规则。

OpenCode 的官方 npm 包使用 `opencode-ai`；Pi 同时识别新旧官方包名。新增 Copilot、Crush、Goose、Magpie 的 CLI 说明；Copilot、Crush、Hermes 可在设置中按需加入技能挂载矩阵，新工具默认不占首页列。

技能上游丢失或变成别的技能会报检查失败，保留本地内容。更新前验证所有成员，下载后在 Store 写锁内复核目录身份、内容哈希、逐成员来源路径和当前套装成员；来源丢失也会阻止旧计划。拷贝完新版、备份旧版之前再次检查该成员，防止在拷贝期间发生的本地编辑被覆盖。well-known 更新使用同样的提交前复核。

CLI 批量资格按渠道及官方包名识别，显示名不能借用 Agent 身份。排队操作复核真实路径与 updater；版本比较支持 stable / prerelease，无法解析版本时不推定升级。更新结果继续区分完成、失败、跳过与版本待确认，技能收据列出实际更新的成员。

## 保留的边界

打开页面、搜索、筛选、本地重扫不授权全量 npm 版本查询。手动全量检查仍沿用会话授权，自动检查仍沿用已保存偏好。未知安装渠道只显示，不推测 updater；基础工具没有批量升级按钮。

技能更新保留旧版备份和软链；CLI 更新的恢复能力由其安装渠道决定。well-known 协议仍只分发 SKILL.md，不推定附属文件已同步。MCP 配置编辑、模型网关和账号切换不属于本轮交付。

CLI 盘点以常用包及 PATH 命中的额外安装为主，不承诺穷举本机所有 inactive 安装。Homebrew 当前按官方版本号比较，不处理仅 revision 变化或第三方 tap 的同名版本。新工具目录采用官方默认位置；自定义环境变量目录仍需现有手动设置。

## 验证

运行 `scripts/test.sh`，并以 `POPSKILL_UI_SNAPSHOT_DIR` / `POPSKILL_UI_SNAPSHOT_LANG` 开启中英文原生渲染验证。运行本地化双向覆盖检查、严格并发且零警告的 release build、打包应用冷启动验证。测试全部使用临时技能目录；可选真实环境盘点只读执行，避免验证过程升级用户工具。

开发预览不等同于 Apple 公证、公共 Release 或 Sparkle 上线；正式发布仍走原有 `scripts/release.sh`。
