# 产品网站

[English](README.md) · **简体中文**

双语产品网站生成静态 HTML，通过 Cloudflare Workers Static Assets 部署。英文位于 `/`，简体中文位于 `/zh/`，与 Xcode 构建相互独立。

## 本地预览

需要 Node.js 22 或更新版本。在本目录执行：

```sh
npm ci
npm run dev
```

打开[本地网站](http://localhost:8787/zh/)。修改源码后需运行 `npm run build` 重新生成，并刷新浏览器。

```sh
npm run build
npm run check
npx wrangler deploy --dry-run
```

检查脚本验证本地链接、语言元数据、截图版本、字体许可证与安全响应头。试运行只验证部署配置，不发布。

## 配置与部署

`src/content.mjs` 保存双语文案和下载版本。下载链接指向公开的 GitHub Release。构建读取 `../docs/images/` 中的应用截图、`../Design/` 中的应用图标，以及应用设计目录里的字体和原始许可证。生成的 WebP、字体和 HTML 放入已忽略的 `dist/`，不提交生成产物。

`SITE_URL` 设置规范 HTTPS 域名，默认 `https://mi-remote.yangpan.com`。这是构建默认值，不代表已发布域名。可选的 `GA_MEASUREMENT_ID` 接入现有 GA4 ID；不设置时关闭统计。每次构建及部署均需设置所需变量：

```sh
SITE_URL=https://mi-remote.yangpan.com npm run deploy
# 可选统计：
SITE_URL=https://mi-remote.yangpan.com GA_MEASUREMENT_ID=G-YOURID npm run deploy
```

`npm run deploy` 会将网站发布到所选 Cloudflare 账户，并可能更新已有的 `mi-remote-helper-website` Worker。先用 `npx wrangler login` 登录，Wrangler 在沙箱外运行。发布前确认目标账户，并将 `SITE_URL` 改为选定域名。发布后在 Cloudflare 绑定自定义域名。仓库未配置域名路由或账户标识。

网站不需要动态处理函数或密钥。`_headers` 提供安全策略。HTML 包含规范链接、互相对应的语言链接和结构化数据，并生成 `robots.txt` 和 `sitemap.xml`。当前布局面向域名根路径；部署到子路径时需调整资源地址和语言路由。

## 权利说明

网站代码遵循仓库的 GPL-3.0-only 许可证。应用截图包含第三方小米产品图片，其权利与移除说明独立于 GPL。生成资源保留字体的原始 SIL Open Font License。参见[第三方声明](../THIRD_PARTY_NOTICES.zh-CN.md)。
