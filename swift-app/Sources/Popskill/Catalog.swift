import Foundation

// 精选目录（v2.3）：热门常见 skill 的中文一句话简介 + 类型提示，编译进二进制。
// 显示优先级：目录简介 > frontmatter description（上游英文长文案不再直出卡片）；
// 本地完整文档不受影响——详情 peek 摘要与「在编辑器中打开」仍读真实文件。
// 类型优先级：frontmatter 显式 type: > 目录提示 > 名称特征。

struct CatalogEntry {
    let desc: String
    var type: CapType? = nil
    /// 来源提示（v2.4）：复制安装类 skill（如 guanskill 套娃）四级溯源全落空时，
    /// 由目录补一手——能归拢成套装；npm 源更新检查自动跳过
    var source: String? = nil
}

enum Catalog {
    static func entry(_ name: String) -> CatalogEntry? { skills[name] }

    static let skills: [String: CatalogEntry] = [
        // ── Anthropic 官方 ──────────────────────────────
        "skill-creator": .init(desc: "创建、改进与评测 Agent Skill 的官方脚手架"),
        "docx": .init(desc: "Word 文档读写创建（Anthropic 官方）"),
        "pdf": .init(desc: "PDF 读取、生成与处理（Anthropic 官方）"),
        "pptx": .init(desc: "PPT 幻灯片读写创建（Anthropic 官方）"),
        "xlsx": .init(desc: "Excel 表格读写创建（Anthropic 官方）"),
        "consolidate-memory": .init(desc: "记忆文件整理：去重、修正、修剪索引"),

        // ── 宝玉系（jimliu/baoyu-skills）────────────────
        "baoyu-article-illustrator": .init(desc: "文章配图：分析结构定位置，类型×风格×配色三维生成"),
        "baoyu-comic": .init(desc: "知识漫画：分镜脚本 + 多画风批量生成"),
        "baoyu-compress-image": .init(desc: "图片压缩：自动选工具转 WebP / PNG"),
        "baoyu-cover-image": .init(desc: "文章封面图：11 配色 × 7 渲染风格组合"),
        "baoyu-danger-gemini-web": .init(desc: "逆向 Gemini Web 的图文生成后端"),
        "baoyu-danger-x-to-markdown": .init(desc: "X 推文 / 文章转 Markdown（逆向 API）"),
        "baoyu-diagram": .init(desc: "深色系专业 SVG 图：架构 / 流程 / 时序 / 脑图全类型"),
        "baoyu-electron-extract": .init(desc: "拆 Electron 应用 asar 包，还原源码与资源"),
        "baoyu-format-markdown": .init(desc: "Markdown 美化：frontmatter / 标题 / 摘要 / 代码块"),
        "baoyu-image-cards": .init(desc: "信息图卡片组：12 风格 × 8 版式社媒种草图"),
        "baoyu-image-gen": .init(desc: "AI 生图聚合：GPT Image / Gemini / 即梦 / Seedream 等"),
        "baoyu-imagine": .init(desc: "AI 生图聚合：多供应商文生图 + 参考图"),
        "baoyu-infographic": .init(desc: "高密度信息大图：21 版式 × 22 视觉风格"),
        "baoyu-markdown-to-html": .init(desc: "Markdown 转微信兼容 HTML：高亮 / 公式 / Mermaid"),
        "baoyu-post-to-wechat": .init(desc: "发布微信公众号：文章 + 贴图双形态"),
        "baoyu-post-to-weibo": .init(desc: "发微博：普通帖 + 头条文章"),
        "baoyu-post-to-x": .init(desc: "发 X/Twitter：推文 + 长文 Article"),
        "baoyu-slide-deck": .init(desc: "内容转幻灯片图组：大纲 + 逐页生成"),
        "baoyu-summarize": .init(desc: "长文三段式摘要：结论 → 论据 → 关键引文"),
        "baoyu-translate": .init(desc: "三档翻译（快翻 / 普通 / 精翻），支持术语表"),
        "baoyu-url-to-markdown": .init(desc: "任意 URL 转 Markdown：X / YouTube / HN 专用适配"),
        "baoyu-wechat-summary": .init(desc: "微信群聊精华摘要（wx-cli 本地抓取）"),
        "baoyu-xhs-images": .init(desc: "小红书图文卡片组：12 风格社媒信息图"),
        "baoyu-youtube-transcript": .init(desc: "下载 YouTube 字幕与封面，支持翻译和章节"),

        // ── 飞书系（larksuite/cli）──────────────────────
        "lark-approval": .init(desc: "飞书审批：待办查询与处理"),
        "lark-apps": .init(desc: "本地 HTML 一键部署成飞书妙搭公网应用"),
        "lark-attendance": .init(desc: "飞书考勤：查自己的打卡记录"),
        "lark-base": .init(desc: "飞书多维表格全操作：表 / 字段 / 记录 / 视图 / 仪表盘"),
        "lark-calendar": .init(desc: "飞书日历：日程 / 会议室 / 忙闲查询"),
        "lark-contact": .init(desc: "飞书通讯录：姓名 ⇄ open_id 互查"),
        "lark-doc": .init(desc: "飞书云文档读写编辑（Docx / Wiki）"),
        "lark-drive": .init(desc: "飞书云空间：上传下载 / 导入在线文档 / 权限"),
        "lark-event": .init(desc: "飞书事件流监听：NDJSON 实时消费"),
        "lark-im": .init(desc: "飞书消息：收发 / 搜索 / 群管理 / 文件"),
        "lark-mail": .init(desc: "飞书邮箱：写发读搜 + 草稿 / 规则 / 附件"),
        "lark-markdown": .init(desc: "飞书 Markdown 文件查看、编辑与比较"),
        "lark-minutes": .init(desc: "飞书妙记：搜索 / 下载 / 上传生成"),
        "lark-okr": .init(desc: "飞书 OKR：周期 / 目标 / 关键结果管理"),
        "lark-openapi-explorer": .init(desc: "飞书原生 OpenAPI 探索（CLI 未封装接口）"),
        "lark-shared": .init(desc: "lark-cli 认证与身份切换基础件"),
        "lark-sheets": .init(desc: "飞书电子表格：建表 / 行列 / 数据 / 样式"),
        "lark-skill-maker": .init(desc: "把飞书 API 封装成自定义 Skill"),
        "lark-slides": .init(desc: "飞书幻灯片创建与编辑"),
        "lark-task": .init(desc: "飞书任务：待办 / 清单 / 子任务"),
        "lark-vc": .init(desc: "飞书视频会议：历史会议 / 纪要 / 参会人查询"),
        "lark-vc-agent": .init(desc: "飞书会议机器人：代入会 + 实时事件"),
        "lark-whiteboard": .init(desc: "飞书画板节点读取与导出"),
        "lark-wiki": .init(desc: "飞书知识库：空间 / 节点 / 成员管理"),
        "lark-workflow-meeting-summary": .init(desc: "工作流：批量汇总会议纪要成报告"),
        "lark-workflow-standup-report": .init(desc: "工作流：日程 + 待办生成站会摘要"),

        // ── 观远系（guanskill）──────────────────────────
        "guancli": .init(desc: "观远 BI 全能查询：ETL / 数据集 / 页面 / 血缘 / 指标", type: .cli, source: "npm:@guandata/guanskill"),
        "guands": .init(desc: "观远数据连接与数据集管理：增量 / 调度 / 计算字段", source: "npm:@guandata/guanskill"),
        "guanetl": .init(desc: "观远 ETL 全流程：拉取 / 编辑 / 预览 / 发布 / 调度", source: "npm:@guandata/guanskill"),
        "guanvis": .init(desc: "观远卡片与仪表板搭建：30+ 图表类型脚本化", source: "npm:@guandata/guanskill"),
        "guanwf": .init(desc: "观远工作流引擎数据流：创建 / 编辑 / 运行", source: "npm:@guandata/guanskill"),

        // ── 马甲自研 ────────────────────────────────────
        "majia-getnote": .init(desc: "得到 Get 笔记一站式：存搜管 + 订阅抓取总结"),
        "majia-guanyuan": .init(desc: "观远 BI 实战增益层：77 ETL 战例 + 30 条法则"),
        "majia-human-txt": .init(desc: "去 AI 味写作辅助：直写 / 陪写双角色"),
        "majia-ota-app": .init(desc: "Mac app 发布全链：签名 / 公证 / Sparkle / 落地页"),
        "majia-ota-skill": .init(desc: "Agent Skill 发布全链：同步 / 审计 / 发布 / 伞形"),
        "majia-quanyu-jpg": .init(desc: "飞书文章杂志水彩全套配图 + 公众号封面"),
        "majia-skill-manager": .init(desc: "本机 skill 服务台：装 / 删 / 链 / 巡检"),
        "majia-speech": .init(desc: "文字转语音合成（马甲定制）"),
        "majia-video-png": .init(desc: "视频抽帧转 PNG 截图集"),

        // ── 社区常用 ────────────────────────────────────
        "anything-to-notebooklm": .init(desc: "多源内容进 NotebookLM：转播客 / PPT / 思维导图"),
        "claude-to-im": .init(desc: "Claude Code 桥接到飞书 / TG / Discord，手机上聊"),
        "defuddle": .init(desc: "网页正文净化抽取：去广告导航留正文"),
        "knowledge-site-creator": .init(desc: "一句话生成领域知识学习网站并部署上线"),
        "nmem-cli": .init(desc: "Nowledge Mem 记忆库 CLI：存查 + 知识图谱", type: .cli),
        "qiaomu-design-advisor": .init(desc: "设计顾问：配色 / 排版 / 组件建议"),
        "qiaomu-music-player-spotify": .init(desc: "Spotify 播放控制"),
        "yt-search-download": .init(desc: "YouTube 搜索 + 下载"),
    ]
}
