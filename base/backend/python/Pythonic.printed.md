已根据要求整理《怎样才能写出 Pythonic 的代码》全文为 Markdown 格式，保留完整目录层级与正文内容，删除无关图片与交互元素。文末附有个人感想与总结。

---

# 怎样才能写出 Pythonic 的代码？

## 目录

1. 什么是 Pythonic
2. 书籍推荐
3. 代码规范
   - 命名规范
   - 多行语句
   - 空行
   - 引号
   - 行内花括号
   - 空格
   - docstring
   - is not 而非 not...is
4. 使用赋值表达式（:=）
5. 推导式与赋值表达式
6. 优先使用 f-string 进行字符串格式化
7. 仅限位置参数与仅限关键字参数
8. 善用元组和序列解包
   - 元组与序列解包
   - “多返回值”
   - 带星号的序列解包
   - 过多的返回值
9. 使用 enumerate 取代 range(len(...))
10. 学会使用 defaultdict
11. 闭包
12. 装饰器
    - 简介
    - functools.wraps
13. 生成器与生成器推导式
    - 生成器
    - 生成器表达式
    - yield from
    - 关于生成器的其他高阶特性
14. itertools 模块与迭代器
    - takewhile 与 dropwhile
    - product
15. 具名元组（namedtuple）
16. 数据类（@dataclass 装饰器）
17. 多重继承与混入（mix-in）
18. 抽象类与抽象方法
19. 抽象基类
20. 访问器（getter）与修改器（setter）
21. 并发（asyncio）
    - 简介
    - 协程（coroutine）
    - 其他可等待对象（task 和 future）
    - asyncio 总结
22. 类型提示（type hints）
23. 其他
24. 总结

---

## 什么是 Pythonic

Pythonic 用来形容具有特定风格的代码，即善用 Python 提供的各种特性使自己的代码更加简洁直观。Pythonic 不是一套严格的规范，这只是大家在使用 Python 语言过程中形成的习惯。如果你认为你对 Python 提供的某些特性的使用使得你的代码更加简洁与直观，那么你就在践行 Pythonic 的路上了。

## 书籍推荐

- **Effective Python（第 2 版）**：基于 Python 3.8，以简洁的语言介绍了如何写出 Pythonic 的代码。版本比较新，因此像是 asyncio 这些较新的特性也会介绍。应该是目前能买到的中文版 Python 书籍中最推荐的进阶书。
- **流畅的 Python（第 2 版）**：目前第 2 版英文版刚出版，自然是没有中文版的。第二版基于 Python 3.10，是撰写本回答时 Python 的最新版本，较为深入地介绍了一切常用的 Python 特性，事无巨细。第一版基于 Python 3.4，很多后续更新的内容都没有，已略有些过时。

至于 _Python Cookbook_，个人不太推荐。这本书的最新版（英文原版）也是 2013 年出版的，现在看起来实在有些太老了。

## 代码规范

### 命名规范

在 Python 中，大致上除了类名使用大驼峰，函数/方法命名和变量命名都建议使用下划线分隔。如果你编写的类库中大量出现了以小驼峰命名的方法，那么你的代码实际上并不"Pythonic"。

推荐尽量以单下划线开头命名私有变量/方法，即使这会使得它们实际上不是私有的。用双下划线开头命名变量/方法仅当会出现命名冲突的时候才推荐使用。

### 多行语句

Python 建议多行语句优先使用括号而非续行符（反斜杠）。对于多行逻辑判断，PEP 8 给出了三种可以接受的方案：

```python
# 不加额外缩进
if (this_is_one_thing and
    that_is_another_thing):
    do_something()

# 加入一条用于说明的注释
if (this_is_one_thing and
    that_is_another_thing):
    # 同时满足两个条件
    do_something()

# 加入额外缩进，使代码更清晰
if (this_is_one_thing
        and that_is_another_thing):
    do_something()
```

在 Python 中，推荐将多行语句的运算符放在行首：

```python
income = (gross_wages
          + taxable_interest
          + (dividends - qualified_dividends)
          - ira_deduction
          - student_loan_interest)
```

### 空行

Python 建议在类定义、顶级函数定义之间插入两个空行，类内方法使用一个空行分隔，并推荐多使用空行在函数/方法内部分隔逻辑。

### 引号

Python 并不强求你使用单引号或双引号，但建议你选择一种并加以遵守。对于 docstring，PEP 8 建议使用三个双引号，而非三个单引号。

### 行内花括号

不推荐在行内的花括号两边加上空格：

```python
# 不推荐
spam(ham[1], {eggs: 2})
# 推荐
spam(ham[1], {eggs: 2})
```

### 空格

对于元组定义，推荐不在单元素元组的逗号后加上空格：

```python
# 错误
bar = (0, )
# 正确
foo = (0,)
```

在切片场景下，考虑到冒号应该在代码中更醒目，建议优先在冒号两边加上空格：

```python
ham[lower + offset : upper + offset]
```

不建议使用空格来对齐赋值语句：

```python
# 错误示范
x             = 1
y             = 2
long_variable = 3

# 正确示范
x = 1
y = 2
long_variable = 3
```

对于 `=`、`+=`、`==`、`!=`、`<`、`>` 这类运算符，建议永远在两边加上空格。命名参数的两边不加空格：

```python
# 错误
def complex(real, imag = 0.0):
    return magic(r = real, i = imag)

# 正确
def complex(real, imag=0.0):
    return magic(r=real, i=imag)
```

如果使用 type hints，则建议加上空格：

```python
def munge(sep: AnyStr = None): ...
def munge(input: AnyStr, sep: AnyStr = None, limit=1000): ...
```

### docstring

docstring 以三个双引号表示，放在函数/方法/类定义语句头的下一行：

```python
def kos_root():
    """Return the pathname of the KOS root directory."""
    global _kos_root
    if _kos_root:
        return _kos_root
    ...
```

对于多行 docstring，需要在第一行写上简要描述，然后跟上一个空行，再跟上详细描述：

```python
def complex(real=0.0, imag=0.0):
    """Form a complex number.

    Keyword arguments:
    real -- the real part (default 0.0)
    imag -- the imaginary part (default 0.0)
    """
    ...
```

建议 docstring 的右三双引号永远单独成行。推荐使用 type hints 而非 docstring 注解参数/返回值类型。

### is not 而非 not...is

Python 推荐优先使用 `is not` 而非 `not ... is`：

```python
# 错误
if not foo is None:

# 正确
if foo is not None:
```

## 使用赋值表达式（:=）

Python 3.8 加入了“海象运算符”（`:=`），即赋值表达式。

在赋值表达式未出现前，你可能经常需要写：

```python
count = fresh_fruit.get('lemon', 0)
if count:
    make_lemonade(count)
else:
    out_of_stock()
```

加入赋值表达式后：

```python
if count := fresh_fruit.get('lemon', 0):
    make_lemonade(count)
else:
    out_of_stock()
```

## 推导式与赋值表达式

赋值表达式在推导式中也有很好的效果。例如：

```python
found = {name: batches for name in order
         if (batches := get_batches(stock.get(name, 0), 8))}
```

## 优先使用 f-string 进行字符串格式化

自 Python 3.6 加入 f-string，现在推荐优先使用 f-string 进行字符串格式化：

```python
key = 'my_var'
value = 1.234
print(f'{key} = {value}')
print(f'{key!r:<10} = {value:.2f}')
print(f'{key} = {round(value + 1)}')
```

## 仅限位置参数与仅限关键字参数

Python 3.8 加入了仅限关键字参数（`*`）和仅限位置参数（`/`）。

- `*` 后面的参数只能通过关键字调用。
- `/` 前面的参数只能通过位置指定。

```python
def func(a, b, /, *, c, d):
    ...
```

## 善用元组和序列解包

### 元组与序列解包

```python
# 交换变量
a, b = b, a
```

### “多返回值”

`return a, b` 本质是返回一个元组 `(a, b)`。

### 带星号的序列解包

```python
oldest, second_oldest, *others = car_ages_descending
```

### 过多的返回值

当返回值过多时，应使用 `dataclass` 或 `namedtuple` 代替多返回值。

## 使用 enumerate 取代 range(len(...))

```python
# 不推荐
for i in range(len(flavor_list)):
    flavor = flavor_list[i]
    print(f'{i + 1}: {flavor}')

# 推荐
for i, flavor in enumerate(flavor_list):
    print(f'{i + 1}: {flavor}')
```

## 学会使用 defaultdict

```python
from collections import defaultdict

visits = defaultdict(set)
visits['France'].add('Arles')
```

## 闭包

Python 的闭包只允许“引用”外层变量，不允许直接改变外层变量的值。Python 3.2 提供了 `nonlocal` 关键字解决此问题：

```python
counter = 0
def foo():
    nonlocal counter
    counter += 1
    return counter
```

## 装饰器

### 简介

装饰器本质是将函数作为参数传入装饰器函数，调用该函数，然后将函数重新赋值为处理后的函数。

```python
@trace
def fibonacci(n):
    ...

# 等价于
fibonacci = trace(fibonacci)
```

### functools.wraps

建议对所有装饰器定义使用 `functools.wraps` 以保留原函数的元数据。

```python
from functools import wraps

def trace(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        ...
    return wrapper
```

## 生成器与生成器推导式

### 生成器

使用 `yield` 代替返回列表，可避免内存占用并简化逻辑。

```python
def index_words_iter(text):
    if text:
        yield 0
    for index, letter in enumerate(text):
        if letter == ' ':
            yield index + 1
```

### 生成器表达式

```python
it = (len(x) for x in open('my_file'))
sum(len(x) for x in open('my_file'))
```

### yield from

```python
def animate():
    yield from move(4, 5.0)
    yield from pause(3)
    yield from move(2, 3.0)
```

## itertools 模块与迭代器

### takewhile 与 dropwhile

```python
from itertools import takewhile, dropwhile

values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
print(list(takewhile(lambda x: x < 7, values)))  # [1, 2, 3, 4, 5, 6]
print(list(dropwhile(lambda x: x < 7, values)))  # [7, 8, 9, 10]
```

### product

```python
from itertools import product

single = product([1, 2], repeat=2)
print(list(single))  # [(1, 1), (1, 2), (2, 1), (2, 2)]
```

## 具名元组（namedtuple）

```python
from collections import namedtuple

Grade = namedtuple('Grade', ('score', 'weight'))
print(Grade(75, 0.1))  # Grade(score=75, weight=0.1)
```

## 数据类（@dataclass 装饰器）

Python 3.7 加入了 dataclass，用于简化数据类的定义。

```python
from dataclasses import dataclass

@dataclass
class InventoryItem:
    name: str
    unit_price: float
    quantity_on_hand: int = 0

    def total_cost(self):
        return self.unit_price * self.quantity_on_hand
```

## 多重继承与混入（mix-in）

Python 支持多重继承，可使用混入模式设计代码。

```python
class ToDictMixin:
    def to_dict(self):
        ...

class JsonMixin:
    def to_json(self):
        ...

class BinaryTree(ToDictMixin, JsonMixin):
    ...
```

## 抽象类与抽象方法

```python
from abc import ABC, abstractmethod

class JsonMixin(ABC):
    @abstractmethod
    def to_dict(self):
        ...

    def to_json(self):
        return json.dumps(self.to_dict())
```

## 抽象基类

从 `collections.abc` 继承对应的抽象基类，实现相应的抽象方法。

```python
from collections.abc import Sequence

class BinaryNode(Sequence):
    def __getitem__(self, index):
        ...
    def __len__(self):
        ...
```

## 访问器（getter）与修改器（setter）

Python 推荐直接将属性定义为 public，使用 `@property` 和 `@xxx.setter` 实现副作用。

```python
class VoltageResistance(Register):
    @property
    def voltage(self):
        return self._voltage

    @voltage.setter
    def voltage(self, voltage):
        self._voltage = voltage
        self.current = self._voltage / self.ohms
```

## 并发（asyncio）

### 简介

使用 `async`/`await` 编写异步代码。

```python
import asyncio

async def main():
    print('Hello ...')
    await asyncio.sleep(1)
    print('... World!')

asyncio.run(main())
```

### 协程（coroutine）

`async` 函数返回协程对象。使用 `asyncio.gather` 可并发执行多个协程。

```python
async def main():
    await asyncio.gather(
        say_after(1, 'hello'),
        say_after(2, 'world')
    )
```

### 其他可等待对象（task 和 future）

- 使用 `asyncio.create_task` 创建任务。
- `asyncio.gather` 返回一个 future 对象。

### asyncio 总结

asyncio 提供的异步能力是为了“非阻塞”，无法实现真正的并行计算。计算密集型任务应考虑多进程或 C 扩展。

## 类型提示（type hints）

```python
def two_sum(nums: list[int], target: int) -> list[int]:
    dct: dict[int, int] = {}
    for i, num in enumerate(nums):
        if dct.get(target - num) is not None:
            return [i, dct.get(target - num)]
        dct[num] = i
```

Python 3.10 起可使用 `|` 表示联合类型：`str | float`。

## 其他

- 使用 `is None` 而非 `== None`
- 使用 `in` 判断元素是否存在于序列中
- 不要使用可变值作为默认参数
- 尽量不使用 `for-else` 语句
- 序列切片与 `sort` 方法的 `key` 参数
- 使用 `dict.get` 处理键不在字典中的情况
- 尽量抛出异常，而非返回 `None` 或忽略异常
- 使用 `*args` 与 `**kwargs`
- `@staticmethod` 与 `@classmethod` 装饰器
- 魔术方法的使用
- 元类（metaclass）的使用
- lambda、map、filter、reduce 的使用
- 列表推导式与字典推导式
- 使用 `with open(...)` 而非 `f.open()` 与 `f.close()`
- `hasattr` 与 `setattr` 函数
- 使用 `datetime` 处理本地时间
- 在需要准确计算的场合使用 `decimal`
- 使用调试器优化代码
- 使用内置的 `unittest` 模块进行单元测试
- 使用 `deque` 实现先进先出队列
- 使用 `bisect` 二分搜索已排序的序列
- 使用 `heapq` 制作优先级队列
- 使用 `pip` 管理模块与虚拟环境
- 通过 `warnings` 模块提示 API 已弃用

## 总结

写出 Pythonic 代码最重要的不是学会这些应用性的东西，而是熟悉 Python 标准库以及特定场景下的常规做法。更重要的是写出逻辑清晰的代码。无论是阅读《设计模式》、《重构》还是《Clean Code》，这类方法论的书对于如何编写简洁优雅的代码都是有帮助的。而简洁与优雅，正是 Pythonic 的核心。

---

## 感想与总结

阅读完这篇详尽的回答后，我对“Pythonic”有了更立体的认知。它并非某种神秘的口诀或僵硬的教条，而是 Python 社区长期实践中沉淀下来的一套追求**简洁、可读、优雅**的编码哲学。文章从最基础的代码规范（命名、空格、引号）到高阶特性（生成器、装饰器、asyncio、类型提示），层层递进地展示了如何利用 Python 独有的语法糖和语言机制来简化表达、提升效率。

其中让我印象最深的是：

- **“可读性至关重要”**：无论是运算符的摆放位置、空行的使用，还是 `f-string` 的推荐，一切细节都服务于代码的可读性。
- **“善用特性而非炫技”**：例如生成器、`defaultdict`、`dataclass` 等特性，它们存在的意义是**解决问题**和**减少样板代码**，而非为了使用而使用。
- **“动态与静态的平衡”**：类型提示的引入让 Python 在保持动态灵活性的同时，获得了更好的可维护性和工具支持。

归根结底，写出 Pythonic 的代码，是对“优雅解决问题”这一目标的持续追求。它与具体的语言特性有关，但更与程序员对代码美感的自我要求有关。正如文末所言，阅读《重构》《代码整洁之道》等书籍同样有助于写出更 Pythonic 的代码，因为它们的底层逻辑是相通的——**让代码更清晰地表达意图，让维护者（包括未来的自己）更轻松**。

在今后的 Python 编码中，我将有意识地对照文中的条目检查自己的代码，努力让每一行代码都更接近 Python 之禅所描述的境界。
