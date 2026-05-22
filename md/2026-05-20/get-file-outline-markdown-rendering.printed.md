# get_file_outline 的 markdown 渲染设计

## 触发提问

> "get_file_outline 这个 mock 一下,我看一下它的使用和输出的情况"

> "为什么 outline 返回 markdown 字符串,其他工具返回 list[dict]?"

## 关键结论

- **outline 返回 markdown 字符串 ≠ 其他 3 个工具(返回结构化 list)** —— 这是有意背离 tool calling 主流。outline **本来就是给 LLM"读概览"的**,markdown 比 raw dict 解析快 5~10 倍。
- **核心信号密度**:`L24` 行号标注(LLM 后续 apply_patch 直接用)+ `🔸` / `🔹` emoji 区分 class/function(视觉解析比 `kind` 字段快)+ ` ` 包裹 signature(LLM 解析熟悉)。
- **空段跳过渲染**:`if target["symbols"]` / `if target["imports"]` —— 空 `__init__.py` 输出只有 `# path` 标题,**少干扰信号比"格式完整"更重要**。
- **imports 截断到 `[:10]`** —— 不告诉 LLM 是有意为之,真要完整 imports 有 `find_imports` 工具。**分工:outline = 概览,find_imports = 详细**。
- **错误也返回字符串**(`❌ file not found: ...`)而不是 raise,return 类型统一 —— tool calling framework 不需要分两路处理。

## Schema / 字段表

### outline 字符串的 4 段结构

```markdown
# <file_path>            ← 标题(必有)

## Symbols              ← 空 symbols 跳过此段
- 🔸 L8: `class User(...)`
- 🔹 L42: `def user(...)`

## Depends on           ← 空 imports 跳过此段
- from `sqlalchemy` (3 names)
- from `pydantic` (1 names)
```

### emoji 选择

| kind | icon | Why |
|---|---|---|
| `"function"` | 🔹(蓝色钻石) | 函数像"小水滴" |
| `"class"` | 🔸(橙色钻石) | 类是"结构体" |

**视觉记忆**:LLM 看到 🔸 立刻知道 class,看到 🔹 立刻知道 function,**比解析 `kind: "class"` 字段快**。

## 代码示例

### 完整实现

```python
def get_file_outline(
    index: CodebaseIndex,
    file_path: str,
) -> str:
    # Step 1: 找 file
    target: FileIndex | None = next(
        (file for file in index["files"] if file["path"] == file_path),
        None,
    )
    if target is None:
        return f"❌ file not found: {file_path}"

    # Step 2: 标题
    lines: list[str] = [f"# {file_path}", ""]

    # Step 3: Symbols 段(空跳过)
    if target["symbols"]:
        lines.append("## Symbols")
        for sym in target["symbols"]:
            icon = "🔸" if sym["kind"] == "class" else "🔹"
            lines.append(f"- {icon} L{sym['start_line']}: `{sym['signature']}`")

    # Step 4: Depends on 段(空跳过 + 截断 [:10])
    if target["imports"]:
        lines.append("")
        lines.append("## Depends on")
        for imp in target["imports"][:10]:
            from_str = "from " if imp["is_from"] else ""
            lines.append(f"- {from_str}`{imp['module']}` ({len(imp['names'])} names)")

    return "\n".join(lines)   # 不是 "\\n"!
```

### 4 种典型输出形态

#### 1. 正常 file(2 symbols + 3 imports)

````markdown
# app/models/user.py

## Symbols
- 🔸 L8: `class User(BaseModel)`
- 🔹 L42: `def user(db: Session) -> User`

## Depends on
- from `sqlalchemy` (3 names)
- from `pydantic` (1 names)
- from `app.db` (2 names)
````

#### 2. 空 `__init__.py`(0 symbols / 0 imports)

```markdown
# app/auth/__init__.py
```

只剩标题,**对 LLM 也是有效信号**:"这是个空 namespace package,删了不影响"。

#### 3. file 不存在

```
❌ file not found: app/totally/fake.py
```

#### 4. 大 file(8 symbols + 12 imports → 截断到 10)

```markdown
# app/api/routes.py

## Symbols
- 🔹 L18: `async def list_users() -> list[User]`
- 🔹 L28: `async def get_user(user_id: int) -> User`
... 8 条 symbols 全列 ...
- 🔸 L95: `class UserCreate(BaseModel)`

## Depends on
- from `fastapi` (3 names)
- from `sqlalchemy.orm` (1 names)
... 共 10 条 imports ...
```

**剩余 2 条 imports 不显示**(`datetime` / `structlog`),要看完整 imports 用 `find_imports`。

## 坑 / Why

### Why markdown 而不是 dict

LLM 读 raw dict 的 mental work:
1. 看 `symbols` 字段,iterate 每个 dict
2. 每个 dict lookup `kind` / `name` / `start_line` / `signature` 4 字段
3. **字段名的"语义解析"消耗 token 注意力**

LLM 读 markdown outline 的 mental work:
1. 看到 🔸 立刻知道 class
2. 看到 L8 立刻知道行号
3. 看到 ` ` 内是 signature
4. **一行 = 一个 symbol,零 lookup**

**正确判断"该结构化 vs 该 markdown"是 tool 设计高阶技能**:
- 给 LLM"读概览"用 markdown
- 给 LLM"继续推理的数据"用结构化 dict

### Why "\n".join 而不是 += / "\\n"

```python
# ❌ 慢且不 Pythonic
s = ""
for line in lines:
    s += line + "\n"

# ❌ 转义错误,实际输出字面 \n
return "\\n".join(lines)

# ✅ Pythonic + 高效 + 正确
return "\n".join(lines)
```

### Why 截断到 [:10]

- import 段太长会**挤掉 symbols 的视觉重点**(LLM 注意力被 import 列表吸走)
- 真要看完整 imports 有专门工具(`find_imports`)
- **分工原则**:outline = 概览(精简),find_imports = 详细(全量)

### Why 错误也用 string 返回

```python
# ❌ raise Exception
def get_file_outline_bad(...):
    if target is None:
        raise FileNotFoundError(...)

# ✅ return 字符串错误
def get_file_outline(...) -> str:
    if target is None:
        return f"❌ file not found: {file_path}"
```

- raise 让 tool calling framework 把异常 string 化丢给 LLM,信号噪音多
- 返回结构化错误字符串,LLM 读起来跟正常 outline 一致 —— **同一个 return 类型,处理逻辑统一**
- emoji `❌` 让 LLM 一眼识别"这是错误不是正常输出"

## 关联

- [[day4-llm-lookup-tools-architecture]] — 4 个工具整体设计,outline 是"反主流的字符串输出"
