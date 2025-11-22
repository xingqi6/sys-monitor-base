```
// 配置区域
const UPSTREAM_URL = 'https://baixiao112-upstar.hf.space';
const ORG_HOST = 'baixiao112-ti258.hf.space';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // ================= 核心修复 1: 拦截内部和无效请求 =================
    // 阻止代理 Cloudflare 自己的路径
    if (url.pathname.startsWith('/cdn-cgi/')) {
      return new Response(null, { status: 404, statusText: 'Not Found' });
    }
    // 可选：优雅处理 favicon.ico 请求，避免控制台报错
    if (url.pathname === '/favicon.ico') {
      return new Response(null, { status: 204, statusText: 'No Content' });
    }
    // =================================================================

    // 强制 HTTPS (如果需要)
    if (url.protocol === 'http:') {
      url.protocol = 'https-';
      return Response.redirect(url.href, 301);
    }

    const workerDomain = url.host;

    // 1. 处理 CORS 预检请求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS, PATCH',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Requested-With, Upgrade',
        },
      });
    }

    // 2. 确定上游目标 URL
    const targetUrl = `${UPSTREAM_URL}${url.pathname}${url.search}`;

    // 3. 构建请求头，进行伪装
    const newHeaders = new Headers(request.headers);
    newHeaders.delete('Cookie');
    newHeaders.set('Host', ORG_HOST);
    newHeaders.set('Origin', UPSTREAM_URL);
    newHeaders.set('Referer', UPSTREAM_URL + '/');

    const newRequest = new Request(targetUrl, {
      method: request.method,
      headers: newHeaders,
      body: request.body,
      redirect: 'manual'
    });

    try {
      const response = await fetch(newRequest);

      // ================= 核心修复 2: 优化响应处理 =================
      // 直接克隆响应以修改头部，这比新建 Response 更安全
      const modifiedResponse = new Response(response.body, response);
      modifiedResponse.headers.set('Access-Control-Allow-Origin', '*');
      modifiedResponse.headers.set('Access-Control-Expose-Headers', '*');
      modifiedResponse.headers.delete('Content-Security-Policy'); // 删除 CSP 以免冲突

      // 如果是错误响应 (如 404)，直接返回修改过头部的响应，不再尝试读取 body
      if (modifiedResponse.status >= 400) {
        return modifiedResponse;
      }
      
      // WebSocket 升级
      if (modifiedResponse.status === 101) {
        return modifiedResponse;
      }

      const contentType = modifiedResponse.headers.get('Content-Type') || '';

      // 对 HTML 和 JSON 进行域名替换
      if (contentType.includes('text/html') || contentType.includes('application/json')) {
        let text = await response.text(); // 从原始响应读取
        text = text.replace(new RegExp(`https://${ORG_HOST}`, 'g'), `https://${workerDomain}`);
        text = text.replace(new RegExp(`http://${ORG_HOST}`, 'g'), `https://${workerDomain}`);
        
        modifiedResponse.headers.delete('Content-Length'); // 内容已更改，长度失效
        
        return new Response(text, modifiedResponse);
      }

      // 其他所有内容直接流式传输
      return modifiedResponse;

    } catch (e) {
      return new Response(`Worker fetch failed: ${e.message}`, { status: 502 });
    }
  },
};
```
### 新版反代代码
```
// 配置区域
const UPSTREAM_URL = 'https://baixiao112-upwenda.hf.space';
const ORG_HOST = 'baixiao112-upwenda.hf.space';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const workerDomain = url.host;

    // ================= 拦截内部和无效请求 =================
    if (url.pathname.startsWith('/cdn-cgi/')) {
      return new Response(null, { status: 404, statusText: 'Not Found' });
    }
    if (url.pathname === '/favicon.ico') {
      return new Response(null, { status: 204, statusText: 'No Content' });
    }

    // 强制 HTTPS
    if (url.protocol === 'http:') {
      url.protocol = 'https-';
      return Response.redirect(url.href, 301);
    }

    // 1. 处理 CORS 预检请求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS, PATCH',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Requested-With, Upgrade, Cookie', // 允许 Cookie
          'Access-Control-Allow-Credentials': 'true', // 允许携带凭证
        },
      });
    }

    // 2. 确定上游目标 URL
    const targetUrl = `${UPSTREAM_URL}${url.pathname}${url.search}`;

    // 3. 构建请求头
    const newHeaders = new Headers(request.headers);
    
    // ================= 核心修复 1: 必须保留 Cookie =================
    // newHeaders.delete('Cookie');  <-- 这一行被删除了，绝对不能删 Cookie
    // =============================================================

    // 伪装 Host 和 Origin
    newHeaders.set('Host', ORG_HOST);
    newHeaders.set('Origin', UPSTREAM_URL);
    newHeaders.set('Referer', UPSTREAM_URL + '/');

    // 构建新请求
    const newRequest = new Request(targetUrl, {
      method: request.method,
      headers: newHeaders,
      body: request.body,
      redirect: 'manual' // 禁止自动跳转，我们需要手动处理 302 跳转的 Location
    });

    try {
      const response = await fetch(newRequest);

      // ================= 核心修复 2: 处理响应头 =================
      // 必须克隆 headers 才能修改
      const newResponseHeaders = new Headers(response.headers);

      // a. 修复 CORS
      newResponseHeaders.set('Access-Control-Allow-Origin', request.headers.get('Origin') || '*');
      newResponseHeaders.set('Access-Control-Allow-Credentials', 'true');
      newResponseHeaders.delete('Content-Security-Policy'); // 删除 CSP
      newResponseHeaders.delete('Content-Security-Policy-Report-Only');
      newResponseHeaders.delete('Clear-Site-Data');

      // b. 修复 Location 重定向 (处理登录后的跳转)
      const location = newResponseHeaders.get('Location');
      if (location) {
        // 将跳转地址中的上游域名替换为 Worker 域名
        const newLocation = location.replace(UPSTREAM_URL, `https://${workerDomain}`)
                                    .replace(ORG_HOST, workerDomain);
        newResponseHeaders.set('Location', newLocation);
      }

      // c. 修复 Set-Cookie (最关键的一步)
      // 上游发出的 Cookie 域名是 .hf.space，浏览器在 worker.dev 下会拒绝接收
      // 我们需要移除 Domain 属性，让 Cookie 默认属于当前 Worker 域名
      // 注意：Fetch API 的 Headers 对象对 Set-Cookie 支持有限，这里做简化处理
      // 如果有多个 Set-Cookie，这种处理方式在某些 Worker 环境可能不完美，但通常够用
      const setCookie = newResponseHeaders.get('Set-Cookie');
      if (setCookie) {
        // 移除 Domain=... 部分，保留其他属性
        const newCookie = setCookie.replace(/Domain=[^;]+;?/gi, '');
        newResponseHeaders.set('Set-Cookie', newCookie);
      }

      // 构建基础响应对象
      const responseInit = {
        status: response.status,
        statusText: response.statusText,
        headers: newResponseHeaders
      };

      // WebSocket 处理
      if (response.status === 101) {
        return new Response(null, {
          status: 101,
          statusText: 'Switching Protocols',
          headers: response.headers, // WebSocket 握手不需要修改 headers
          webSocket: response.webSocket
        });
      }

      // 4. 内容替换 (仅针对 HTML 和 JSON)
      const contentType = newResponseHeaders.get('Content-Type') || '';
      if (contentType.includes('text/html') || contentType.includes('application/json')) {
        let text = await response.text();
        
        // 替换域名
        const regexH = new RegExp(`https://${ORG_HOST}`, 'g');
        const regexP = new RegExp(`http://${ORG_HOST}`, 'g');
        // 有些 Cookie 设置可能写在 HTML 的 meta 标签或 JS 里，也需要替换 Domain
        // 但为了安全，主要替换 URL
        text = text.replace(regexH, `https://${workerDomain}`);
        text = text.replace(regexP, `https://${workerDomain}`);
        
        // 移除 text 中的 Secure 标记 (如果 Worker 是 http 访问) 或 Domain 设置
        // 这一步可选，防止 JS 操作 Cookie 出错
        // text = text.replace(/Domain=[^;"']+/gi, ''); 

        newResponseHeaders.delete('Content-Length');
        return new Response(text, responseInit);
      }

      // 5. 直接流式传输其他内容
      return new Response(response.body, responseInit);

    } catch (e) {
      return new Response(JSON.stringify({ error: `Worker Error: ${e.message}` }), { status: 500 });
    }
  },
};
```
