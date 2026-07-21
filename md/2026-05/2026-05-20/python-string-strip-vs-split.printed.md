# Python 字符串 strip vs split 与不可变陷阱

## 触发提问

> "`s1 = 'login()'; s1.strip('()')` 关于括弧的那个 strip 可以用我上面的那两行代码吗?"

> 跟 `find_references` P0 bug 紧密相关:`module.removesuffix(".__init__")` 没赋值

## 关键结论

- **`str.strip(chars)` 和 `str.split(sep)[0]` 是两种完全不同的语义** —— **`strip` 是字符集 strip**(从两端逐字符剥,只要 char ∈ chars 集合就剥,遇到不在集合的字符停止);**`split` 是子串切分**(找到第一个 sep,从这里一刀切)。
- **`strip` 对"对称包裹"友好**(`'***hello***'.strip('*')` → `'hello'`),**对"带内容的括号"完全无效**(`'login(a, b)'.strip('()')` → `'login(a, b'`,中间逗号挡住)。
- **Python 字符串不可变** = 所有 `str.xxx()` 方法**返回新字符串**,**必须 `s = s.xxx()` 赋值**。`s.replace()` / `s.strip()` / `s.removesuffix()` / `s.split()` 都是这种语义。
- **Python list 是可变的**(`list.append` in-place),所以容易混淆 —— 写 `s.replace('a', 'b')` 看起来"像在改对象",其实没动。
- **find_references 的 `module.removesuffix(".__init__")` 漏赋值 = `__init__` 归一化失效**,详见 [[find-references-init-normalization-bug]]。

## Schema / 字段表

### strip vs split 行为对照

| 输入 | `s.strip('()')` | `s.split('(')[0].strip()` |
|---|---|---|
| `'login()'` | `'login'` ✅ | `'login'` ✅ |
| `'login(username, password)'` | `'login(username, password'` ❌ | `'login'` ✅ |
| `'login(a: str) -> Token'` | `'login(a: str) -> Token'` ❌(右端 `n` 不在 `()` 集合,完全不剥) | `'login'` ✅ |
| `'((login))'` | `'login'` ✅ | `''` ❌(split 后第一段是空) |

### 字符串方法是否 in-place(全部不 in-place)

| 方法 | 返回 | 改原 str? |
|---|---|---|
| `s.strip()` / `s.strip(chars)` | 新字符串 | ❌ |
| `s.split(sep)` | 新 list | ❌(原 s 不动) |
| `s.replace(a, b)` | 新字符串 | ❌ |
| `s.removesuffix(suf)` / `s.removeprefix(pre)` | 新字符串 | ❌ |
| `s.upper()` / `s.lower()` | 新字符串 | ❌ |
| `s.format()` | 新字符串 | ❌ |
| **结论** | — | **全部要赋值!** |

### list vs str 对比

| 操作 | str(不可变) | list(可变) |
|---|---|---|
| 追加 | `s = s + "x"` 或 `s += "x"`(实际产生新对象) | `lst.append("x")` in-place |
| 排序 | `s = "".join(sorted(s))` | `lst.sort()` in-place 或 `sorted(lst)` 新 list |
| 替换 | `s = s.replace(a, b)` | `lst[i] = "x"` in-place |
| 删除 | `s = s.replace(c, "")` 或 `s = s[:i] + s[i+1:]` | `lst.remove(x)` / `del lst[i]` in-place |

## 代码示例

### strip(chars) 的字符集语义(深入)

```python
>>> 'abcabXXXabcabc'.strip('abc')
'XXX'                  # 从两端逐字符,∈ {a, b, c} 就剥,遇 X 停

>>> 'hello'.strip('helo')
''                     # 字符全在集合 → 全剥光

>>> 'a***b'.strip('*')
'a***b'                # 两端都不是 *,完全不剥

>>> 'login()'.strip('()')
'login'                # 右端 ) → 剥;倒数第二 ( → 剥;再左是 n → 停
                       # 凑巧对了!但 'login(a, b)'.strip('()') 立刻翻车
```

### split(sep)[0] 一刀切语义

```python
>>> 'login()'.split('(')[0]
'login'

>>> 'login(a, b)'.split('(')[0]
'login'                # 第一个 ( 一刀切,后面全扔

>>> 'login(a: str) -> Token'.split('(')[0]
'login'                # 同上

>>> 'no_parens'.split('(')[0]
'no_parens'            # 没 sep,整段当第一段返回
```

### removesuffix / removeprefix 必须赋值

```python
>>> s = "app.auth.__init__"
>>> s.removesuffix(".__init__")     # 返回 "app.auth"
'app.auth'
>>> s                                # ⚠ 原变量没动!
'app.auth.__init__'

>>> s = s.removesuffix(".__init__")  # 必须赋值
>>> s
'app.auth'
```

### find_references 里 P0 bug 修复

```python
# ❌ Bug
if module.endswith(".__init__"):
    module.removesuffix(".__init__")     # 返回值丢了

# ✅ 修复
if module.endswith(".__init__"):
    module = module.removesuffix(".__init__")
#   ^^^^^^^^^^ 加赋值
```

## 坑 / Why

### Why strip 在 `'login()'` 凑巧对了

`'login()'.strip('()')` 内部 trace:
1. 右端最后字符 `)` ∈ `{'(', ')'}` → 剥
2. 倒数第二字符 `(` ∈ `{'(', ')'}` → 剥
3. 再往左 `n` ∉ `{'(', ')'}` → 停止
4. 左端首字符 `l` ∉ `{'(', ')'}` → 停止
→ 结果 `'login'` ✅

**只要 LLM 传入不是"光秃秃的 `xxx()`"形态**(99% 真实场景 LLM 会传 `login(a, b)` 或 `def login(...)` 这种带签名的),**strip 立刻翻车**。

### Why Python 字符串不可变

设计哲学:
- **字符串作为 dict key / set 元素**需要 hashable → 必须不可变
- **多线程安全**:不可变对象天然 thread-safe
- **interning 优化**:CPython 把短字符串 intern 到常量池,前提是不可变

代价就是所有"改字符串"操作都返回新对象,**必须赋值才生效**。

### Why list/str 混淆容易出 bug

```python
# 看起来对称,实际语义完全不同
lst.append(x)       # in-place,改 lst
s.replace(a, b)     # 返回新 str,s 不动
```

**心智模型**:
- 看到 **可变容器**(list / dict / set)→ 方法多 in-place
- 看到 **不可变值类型**(str / tuple / int / float)→ 方法都返回新对象

### Why find_references P0 bug 隐蔽

- `module.removesuffix(".__init__")` 看起来"我在改 module" → 直觉错误
- runtime 不报错(方法调用语法正确)
- Pyright 不警告(类型对得上)
- **只有跑专门触发 `__init__` 路径的 fixture 才暴露**
- 真实项目 demo 触发不到(top-imported 不会是 `__init__.py`)

## 关联

- [[find-references-init-normalization-bug]] — P0 bug 的完整修复
- [[find-definition-two-phase-design]] — normalize_symbol 用 split 而不是 strip
