## Python `match/case` 类型匹配

### 核心区别：捕获模式 vs 类型模式

```python
match chunk:
    case bytes:      # ❌ 捕获模式 — 把 chunk 赋值给变量 bytes，永远匹配
    case bytes():    # ✅ 类型模式 — 等同于 isinstance(chunk, bytes)
```

### 捕获模式（Capture Pattern）

裸名字 = 无条件赋值，**永远成功**，后续分支全部死代码：

```python
match value:
    case x:          # x = value，任何值都匹配 → 后面不可达
    case _:          # ⚠️ 永远不会执行
```

编辑器/linter 会警告：

> `name capture 'bytes' makes remaining patterns unreachable`

### 类型模式（Class Pattern）

加括号 = 类型检查，等同于 `isinstance`：

```python
match chunk:
    case bytes():       # isinstance(chunk, bytes)
    case str():         # isinstance(chunk, str)
    case memoryview():  # isinstance(chunk, memoryview)
    case _:             # 兜底
```

### 更多用法

#### 1. 提取属性

```python
from dataclasses import dataclass

@dataclass
class Point:
    x: float
    y: float

match shape:
    case Point(x=0, y=0):          # 匹配原点
    case Point(x=x, y=y) if x > 0: # 匹配 x > 0 并提取
```

#### 2. 字面量匹配

```python
match status_code:
    case 200:            # 字面量，精确匹配
    case 404:
    case _:
```

#### 3. 常量匹配（必须用点号访问）

```python
match method:
    case "GET":              # 字符串字面量 ✅
    case HttpMethod.POST:    # 点号访问的常量 ✅
    case POST:               # ❌ 这是捕获，不是常量匹配！
```

#### 4. 序列匹配

```python
match command:
    case ["quit"]:                   # 单元素列表
    case ["go", direction]:          # 提取第二个元素
    case ["drop", *objects]:         # 提取剩余所有
```

#### 5. OR 模式

```python
match chunk:
    case bytes() | memoryview():     # 两种类型合并处理
        original_body += bytes(chunk)
    case str():
        original_body += chunk.encode()
```

### 记忆口诀

| 写法               | 含义               | 等同于                      |
| ------------------ | ------------------ | --------------------------- |
| `case bytes`       | 捕获到变量 `bytes` | `bytes = value`（永远成功） |
| `case bytes()`     | 类型检查           | `isinstance(value, bytes)`  |
| `case 200`         | 字面量匹配         | `value == 200`              |
| `case Enum.MEMBER` | 常量匹配           | `value == Enum.MEMBER`      |
| `case _`           | 通配符             | `else`（不绑定变量）        |

**一句话总结**：裸名字是捕获，加括号是类型，加点号是常量。
