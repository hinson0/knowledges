# URL 标准结构与 Starlette URL 对象

## URL 完整格式（RFC 3986）

```
scheme://username:password@hostname:port/path?query#fragment
```

各部分除了 `scheme` 和 `hostname` 外均为可选，最常见的简化形式：

```
scheme://hostname/path?query
```

---

## Starlette URL 对象属性对照

| 部分 | 属性 | 示例 | 说明 |
|------|------|------|------|
| scheme | `url.scheme` | `https` | 协议，常见 http / https / ws / wss |
| username | `url.username` | `admin` | URL 中的用户名，实际开发中很少使用 |
| password | `url.password` | `secret` | URL 中的密码，明文传输不安全 |
| hostname | `url.hostname` | `example.com` | 主机名 |
| port | `url.port` | `8000` | 端口号，省略时使用协议默认端口（http=80, https=443） |
| path | `url.path` | `/api/users` | 请求路径 |
| query | `url.query` | `page=1&size=10` | 查询字符串 |
| fragment | `url.fragment` | `section1` | 片段标识符 |

---

## 其他属性

### `url.is_secure`

判断是否使用安全协议，即 scheme 为 `https` 或 `wss` 时返回 `True`。

```python
request.url.is_secure  # True → https/wss，False → http/ws
```

---

## 注意事项

1. **`username:password@`** 在 URL 中明文传递凭据不安全，浏览器会警告。常见于数据库连接串等内部场景（如 `postgresql://user:pass@localhost/db`），而非 HTTP 请求。
2. **`fragment` 不会发送到服务端**，它仅在浏览器端使用（如页面锚点跳转），所以在 FastAPI 中 `request.url.fragment` 通常为空字符串。
3. **`port` 省略时**，使用协议默认端口：HTTP 为 80，HTTPS 为 443。
