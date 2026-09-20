# tclaw-marketplace

tclaw 技能市场仓库：registry 索引 + 技能包构建 + 多平台发布（GitHub / 公司内网 GitLab / Gitee 镜像）。

完整设计见主仓库 `tclaw/docs/技能市场技术实现方案.md`。

## 仓库结构

```
tclaw-marketplace/
├── scripts/
│   ├── build-registry.sh     # CI 用（bash + jq + zip）：扫描技能目录 → zip + registry.json
│   └── build-registry.ps1    # Windows 本地验证版（产物一致）
├── public/                   # 构建产物（本地验证输出；CI 发布到 gh-pages 分支，不入 main）
├── skills/                   # 市场自有技能（community 免费 / premium 付费，Phase 2/3 启用）
├── .github/workflows/        # GitHub Actions（当前生效）
└── .gitlab-ci.yml            # 公司内网 GitLab CI（迁移后生效）
```

## 技能源

- 当前：主仓库 [hustcsh/tclaw_project](https://github.com/hustcsh/tclaw_project) 的 `tclaw/skills/`（11 个内置免费技能）
- 内网迁移后：`http://10.10.10.204/ai_projects/tclaw_project` 的 `tclaw/skills/`（CI 内改 `TCLAW_REPO` 变量）

每个技能目录需含 `manifest.json`（市场索引消费，字段规范见方案 §4.2）。

## 构建与发布

push 到 main → CI 自动：

1. checkout 主仓库技能源
2. `build-registry.sh`：每个含 manifest.json 的技能 → `dist/<name>-<version>.zip`（zip 根 = 技能目录内容）+ sha256
3. 生成 `registry.json`（`downloads[].url` 存**相对路径**，客户端按 registry 自身 base URL 解析，天然适配多平台）
4. 强推到 `gh-pages` 分支

### 各平台 registry 访问地址

| 平台 | registry.json |
|------|---------------|
| GitHub raw | `https://raw.githubusercontent.com/hustcsh/tclaw-marketplace/gh-pages/registry.json` |
| 内网 GitLab raw | `http://10.10.10.204/ai_projects/tclaw-marketplace/-/raw/gh-pages/registry.json` |
| Gitee 镜像 raw | `https://gitee.com/hustcsh/tclaw-marketplace/raw/gh-pages/registry.json` |

客户端（tclaw-control `skill_market.rs`）按上述顺序多源探测，可用环境变量 `TCLAW_MARKET_REGISTRY_URLS`（分号分隔）覆盖。

### 本地验证（Windows）

```powershell
pwsh ./scripts/build-registry.ps1 -SkillsDir d:\ai_projects\tclaw_project\tclaw\skills
```

输出 `public/registry.json` + `public/dist/*.zip`。

### Gitee 镜像

1. 在 Gitee 创建 `hustcsh/tclaw-marketplace`，类型选「从 GitHub/GitLab 导入」或手动镜像
2. GitHub 仓库 Settings → Secrets → 添加 `GITEE_TOKEN`（Gitee 私人令牌）
3. CI 的 `sync-gitee` job 自动触发镜像强制同步

## 发布新版本技能

1. 主仓库技能目录内改代码，bump `manifest.json` 与 `SKILL.toml` 的 `version`
2. push 主仓库 main → 市场 CI 下次构建自动纳入新版本
