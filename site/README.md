# MoliShot Site

MoliShot 官网，使用 [Astro](https://astro.build) 构建。

## 技术栈

- [Astro](https://astro.build) — 静态站点生成器
- [Tailwind CSS](https://tailwindcss.com) — 样式框架
- [@astrojs/cloudflare](https://docs.astro.build/en/guides/integrations-guide/cloudflare/) — Cloudflare Pages 适配器

## 功能

- 中英文双语切换（zh-CN / en）
- 深色/浅色主题切换
- 响应式设计
- SEO 优化（JSON-LD、OG Meta）

## 目录结构

```
site/
├── public/              # 静态资源（直接复制到 dist/）
│   ├── assets/          # SVG 图标
│   ├── screenshots/     # 截图
│   ├── llms.txt         # AI 爬虫摘要
│   ├── robots.txt
│   └── sitemap.xml
├── src/
│   ├── components/      # Nav, Footer, SEO
│   ├── layouts/         # BaseLayout
│   ├── pages/           # index, about, changelog
│   ├── styles/          # global.css
│   └── i18n/            # 多语言数据
├── astro.config.mjs
├── tailwind.config.mjs
└── package.json
```

## 开发

```bash
# 安装依赖
npm install

# 启动开发服务器
npm run dev

# 构建
npm run build

# 预览构建结果
npm run preview
```

## 部署到 Cloudflare Pages

### 方式一：通过 Git 自动部署（推荐）

1. 将代码推送到 GitHub / GitLab

2. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)，进入 **Workers & Pages**

3. 点击 **Create application → Pages → Connect to Git**

4. 选择仓库，配置构建参数：
   - **Build command**: `cd site && npm install && npm run build`
   - **Build output directory**: `site/dist`

5. 点击 **Save and Deploy**

### 方式二：通过 Wrangler CLI 手动部署

```bash
# 安装 Wrangler
npm install -g wrangler

# 登录
wrangler login

# 构建并部署
npm run build
npx wrangler pages deploy dist
```

### 环境变量（无需额外配置）

当前为纯静态站点，无需设置环境变量。

### 自定义域名

1. 进入 Pages 项目 → **Custom domains**
2. 添加域名 `molishot.eztoolab.com`
3. 按提示在域名 DNS 中添加 CNAME 记录指向 Cloudflare

## 多语言

翻译数据集中在 `src/i18n/index.ts`。页面通过 `data-i18n` 属性标记需要翻译的元素，客户端 JavaScript 在 BaseLayout 中自动处理切换。

主题和语言偏好保存在 `localStorage` 中：
- `molishot-lang` — 语言选择
- `molishot-theme` — 主题选择

## 添加新版本日志

编辑 [src/pages/changelog.astro](src/pages/changelog.astro)，在对应位置添加新的 `<article>` 块，同步更新 `src/i18n/index.ts` 中的翻译。

## License

[MIT](https://github.com/gusibi/MoliShot/blob/main/LICENSE)
