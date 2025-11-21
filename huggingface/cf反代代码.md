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
