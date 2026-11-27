# bigwildleg · 原型预览仓库

把各公司、各项目的原型集中放在这里，通过 GitHub Pages 生成可直接发给客户的在线预览地址。

**在线入口：** <https://wildbigleg-hub.github.io/bigwildleg/>

仓库是公开的（GitHub Pages 免费版要求），所以只放可对外展示的预览版本，不要放需求文档、报价、客户资料。

## 目录约定

```
bigwildleg/
├── index.html                 # 自动生成的入口页，列出所有原型
├── projects.json              # 公司显示名、项目显示名、更新时间
├── publish.ps1                # 一键发布脚本
├── .nojekyll                  # 关闭 Jekyll，避免 Axure 资源目录被忽略
├── robots.txt                 # 禁止搜索引擎收录
├── MTH/                       # 公司缩写（英文/拼音，不要用中文）
│   ├── aixiangxinsheng/       # 项目名（英文/拼音）
│   │   ├── index.html
│   │   └── resources/ data/ ...
│   └── zaokouwuyou/
│       └── index.html
└── 其他公司缩写/
```

访问地址规则：

```
https://wildbigleg-hub.github.io/bigwildleg/<公司>/<项目>/
```

例如 <https://wildbigleg-hub.github.io/bigwildleg/MTH/aixiangxinsheng/>

文件夹名用英文/拼音，是为了地址干净、复制给客户不会变成一串 `%E8%89%BE...`。中文显示名写在 `projects.json` 里，首页会用它。

## 日常发布

### 1. Axure 9 原型

Axure 里 **发布 → 生成 HTML 文件**，选一个空文件夹（例如 `D:\导出\艾享新生`），生成后不要只拷 `index.html`，整个文件夹里所有内容都要带上（`resources`、`data`、`plugins` 等）。

然后在仓库目录执行：

```powershell
cd "C:\AI desktop\bigwildleg"
.\publish.ps1 -Company MTH -Project aixiangxinsheng -Source "D:\导出\艾享新生" -ProjectName "艾享新生"
```

### 2. Agent 生成的 HTML

如果只有一个 html 文件：

```powershell
.\publish.ps1 -Company MTH -Project zaokouwuyou -Source "C:\临时\zaokouwuyou.html" -ProjectName "早口无忧"
```

如果是一个带图片/CSS 的目录（目录里有 `index.html`），直接把目录传给 `-Source`。

### 3. 脚本做了什么

1. 把源目录复制到 `<公司>/<项目>/`，旧版本自动备份到 `%TEMP%\bigwildleg-backup\`
2. 更新 `projects.json` 里的显示名和更新时间
3. 重新生成首页 `index.html`
4. `git add / commit / push`

推送成功约 1 分钟后线上生效。

### 4. 手动加了目录

如果自己手动往仓库里放了 `<公司>/<项目>/index.html`，运行一次重建首页即可：

```powershell
.\publish.ps1 -Rebuild
```

### 5. 修改显示名

打开 `projects.json`：

```json
{
  "companies": { "MTH": { "displayName": "明泰和" } },
  "projects": [
    { "company": "MTH", "project": "aixiangxinsheng", "title": "艾享新生", "updated": "2026-11-27" }
  ]
}
```

改完执行 `.\publish.ps1 -Rebuild` 即可。

## 首次配置（只做一次）

### 1. 创建仓库

GitHub → New repository：

- Repository name：`bigwildleg`
- 可见性：**Public**（Private 仓库开不了免费 Pages）
- 不要勾选 Add a README / .gitignore / license，保持空仓库

### 2. 添加 SSH 公钥

GitHub → 右上角头像 → Settings → SSH and GPG keys → New SSH key → 粘贴：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINX0ZmerzXiaFcq9KR+TJSghBHj4GRYujW+lr3tom8nE wildbigleg-hub
```

标题随便写，例如 `Windows-工作机`。

### 3. 关联远程仓库并推送

```powershell
cd "C:\AI desktop\bigwildleg"
git remote add origin git@github.com:wildbigleg-hub/bigwildleg.git
git push -u origin main
```

### 4. 开启 GitHub Pages

仓库 → **Settings → Pages**：

- Source：**Deploy from a branch**
- Branch：**main**，目录选 **/ (root)**
- 点 **Save**

等 1～2 分钟，访问 <https://wildbigleg-hub.github.io/bigwildleg/> 即可。

## 常见问题

**打开项目地址是 404**
确认该项目目录里有 `index.html`；再看 Actions 里 `pages build and deployment` 是否跑完。

**页面样式错乱 / 图片丢失**
多半是导出不全，只复制了 html 没复制资源目录。重新把整个导出文件夹发布一次。

**Axure 页面能开但内部跳转 404**
Windows 文件名不区分大小写，GitHub 区分。检查是否有同名不同大小写的文件（Axure 极少出现），或页面里引用了本机绝对路径。

**想加密**
GitHub Pages 本身不支持密码。需要给客户设访问密码时，可以把同一份文件再部署到 Netlify / Vercel 并用它们的密码保护，或加 Cloudflare Access。

**单个文件超过 100MB**
GitHub 会拒绝推送。Axure 原型里的高清大图建议压缩后再导出。
