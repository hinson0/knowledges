# Starlette Request 对象属性与方法全解

`Request` 继承自 `HTTPConnection`，而 `HTTPConnection` 实现了 `Mapping` 接口，因此 `Request` 同时具备属性访问和字典式访问能力。

```
Request -> HTTPConnection -> Mapping
```

---

## 一、来自 HTTPConnection（父类）的属性/方法

### `scope` — 属性（直接赋值）

ASGI scope 字典，包含请求的全部底层元数据（`type`、`method`、`path`、`headers`、`client` 等）。这是 ASGI 协议的核心数据结构。

### `app` — Property

返回当前应用实例，来自 `scope["app"]`。可以用它访问应用级别的状态或配置。

### `url` — Property（带缓存）

完整的请求 URL，返回 `starlette.datastructures.URL` 对象，包含 scheme、host、path、query string 等。

```python
request.url              # URL('http://localhost:8000/info?page=1')
request.url.path         # '/info'
request.url.query        # 'page=1'
request.url.scheme       # 'http'
```

### `base_url` — Property（带缓存）

应用的根 URL（不含请求路径），末尾带 `/`。用于生成绝对链接。

### `headers` — Property（带缓存）

请求头的多值字典（`Headers` 对象），支持 `getlist()` 获取同名多值头。

```python
request.headers["content-type"]       # 'application/json'
request.headers.getlist("x-custom")   # ['val1', 'val2']
```

### `query_params` — Property（带缓存）

URL 查询参数的多值字典（`QueryParams` 对象）。

```python
# GET /info?page=1&tag=a&tag=b
request.query_params["page"]         # '1'
request.query_params.getlist("tag")  # ['a', 'b']
```

### `path_params` — Property

路由器从 URL 中提取的路径参数字典。

```python
# @app.get("/users/{user_id}")
request.path_params  # {'user_id': '123'}
```

### `cookies` — Property（带缓存）

解析后的 Cookie 字典 `dict[str, str]`。

### `client` — Property

客户端连接信息，返回 `Address(host, port)` 命名元组，可能为 `None`。

```python
request.client.host  # '127.0.0.1'
request.client.port  # 52341
```

### `session` — Property

会话数据字典。**必须安装 `SessionMiddleware`**，否则抛出 `AssertionError`。

### `auth` — Property

认证上下文/凭据。**必须安装 `AuthenticationMiddleware`**，否则抛出 `AssertionError`。

### `user` — Property

当前已认证的用户对象。**必须安装 `AuthenticationMiddleware`**，否则抛出 `AssertionError`。

### `state` — Property（带缓存）

请求级别的状态存储对象，可以在中间件和路由之间传递任意数据。

```python
# 在中间件中
request.state.start_time = time.time()
# 在路由中
elapsed = time.time() - request.state.start_time
```

### `url_for` — 方法

```python
url_for(name: str, /, **path_params) -> URL
```

根据路由名称反向生成绝对 URL。

```python
request.url_for("get_user", user_id=42)
# URL('http://localhost:8000/users/42')
```

### `get`、`keys`、`values`、`items` — Mapping 接口方法

`HTTPConnection` 实现了 `Mapping` 协议，这四个方法直接操作底层的 `scope` 字典：

```python
request["type"]     # 'http'  （__getitem__）
request.get("type") # 'http'
request.keys()      # dict_keys(['type', 'asgi', 'http_version', ...])
request.items()     # dict_items([('type', 'http'), ...])
request.values()    # dict_values(['http', ...])
```

---

## 二、Request 自身的属性/方法

### `method` — Property

HTTP 请求方法字符串：`GET`、`POST`、`PUT`、`DELETE`、`PATCH` 等。

### `receive` — Property

ASGI receive 通道的可调用对象。通常不直接使用，由 `stream()` 和 `body()` 内部调用。

### `body()` — 异步方法

```python
data: bytes = await request.body()
```

一次性读取并**缓存**整个请求体。后续调用直接返回缓存内容。

### `json()` — 异步方法

```python
payload: Any = await request.json()
```

读取请求体并按 JSON 解析，结果被缓存。解析失败抛出 `JSONDecodeError`。

### `form()` — 方法（返回可 await / async context manager）

```python
# 方式一：await
form_data = await request.form()

# 方式二：async with（推荐，自动清理临时文件）
async with request.form() as form_data:
    file = form_data["upload"]
```

解析 `application/x-www-form-urlencoded` 和 `multipart/form-data`。需要安装 `python-multipart`。

### `stream()` — 异步生成器

```python
async for chunk in request.stream():
    process(chunk)
```

逐块（chunk）接收请求体，适合处理大文件上传。如果之前已调用 `body()`，则直接 yield 缓存内容。客户端断开时抛出 `ClientDisconnect`。

### `is_disconnected()` — 异步方法

```python
if await request.is_disconnected():
    return  # 客户端已断开，提前退出
```

检查客户端是否已断开连接，适用于长时间运行的请求中周期性检查。

### `send_push_promise()` — 异步方法

```python
await request.send_push_promise("/static/style.css")
```

发送 HTTP/2 Server Push 推送承诺，主动向客户端推送资源。需要服务器支持 `http.response.push` 扩展。

### `close()` — 异步方法

清理请求资源（主要是关闭 `FormData` 中的临时文件）。

---

## 三、速查分类表

| 分类 | 成员 |
|------|------|
| **URL 相关** | `url`, `base_url`, `query_params`, `path_params`, `method` |
| **头部/Cookie** | `headers`, `cookies` |
| **请求体** | `body()`, `json()`, `form()`, `stream()` |
| **连接信息** | `client`, `is_disconnected()`, `receive` |
| **应用/状态** | `app`, `state`, `scope` |
| **需要中间件** | `session`（SessionMiddleware）, `auth`/`user`（AuthenticationMiddleware） |
| **工具方法** | `url_for()`, `send_push_promise()`, `close()` |
| **Mapping 接口** | `get()`, `keys()`, `values()`, `items()` |

---

## 四、注意事项

1. **缓存机制**：`url`、`base_url`、`headers`、`query_params`、`cookies`、`state`、`body()`、`json()` 都有内部缓存，首次访问后不会重复解析。
2. **互斥关系**：`body()` 和 `stream()` 不能混用——`stream()` 消费后再调 `body()` 会抛 `RuntimeError`；反过来 `body()` 先调用则 `stream()` 直接 yield 缓存。
3. **中间件依赖**：`session`、`auth`、`user` 三个属性必须安装对应中间件后才能使用，否则会直接 `AssertionError`。
4. **Mapping 接口**：`Request` 可以像字典一样通过 `request["key"]` 访问 scope 中的值，`get/keys/values/items` 也都是操作 scope 字典。
