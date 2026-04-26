好的，已将原文末尾关于“如何才算精通 Python”的讨论部分单独提取如下，内容未作任何删减，仅调整了格式以保持清晰。

---

### 补充说明：怎样才算精通 Python？

**Level 1：了解基本语法**  
这是最容易的一级，掌握了Python的基本语法，可以通过Python代码实现常用的需求，不管代码质量怎么样。这部分内容，可以参考：The Python Tutorial。

**Level 2：熟练使用常用的库**

- 熟悉常用 standard library 的使用，包括但不限于 copy / json / itertools / collections / hashlib / os / sys 等，这部分内容，可以参考：The Python Standard Library。
- 熟悉常用的第三方库，这就根据每个人不同的用法而有所不同了，但是一定要掌握你所常用的那个领域里的第三方库。

**Level 3：Pythonic**  
这一级别比上一级别稍难，但是还是可以轻松达到。所谓Pythonic，就是相比其它语言，Python可以通过更加优雅的实现方式（不管是语法糖还是什么），比如（包括但不限于）with、for-else、try-else、yield等。

另外你还需要掌握这些所谓魔法的实现原理，了解Python在语法层面的一些协议，可以自己实现语法糖。如with的实现方式（上下文管理器）等。

达到这一级，你的代码可以看起来很漂亮了。这部分内容，可以参考：The Python Language Reference、Python HOWTOs。

**Level 4：高级玩法**  
掌握Python的内存机制、GIL限制等，知道如何改变Python的行为，可以轻松写出高效的优质的Python代码，能够轻松分辨不同Python代码的效率并知道如何优化。

**Level 5：看透本质**  
阅读Python的C实现，掌握Python中各种对象的本质，掌握是如何通过C实现面向对象的行为，对于常见的数据结构，掌握其实现细节。到这一步，需要将Python源码学习至少一遍，并对关键部分有较深层次的理解。

**Level 6：手到拈来，一切皆空**  
不可说，不必说～

---

**精通是个伪命题**

怎样才算精通Python，这是一个非常有趣的问题。

很少有人会说自己精通Python，因为，这年头敢说精通的人都会被人摁在地上摩擦。其次，我们真的不应该纠结于编程语言，而应该专注于领域知识。比如，你可以说你精通数据库，精通分布式，精通机器学习，那都算你厉害。但是，你说你精通Python，这一点都不酷，在业界的认可度也不高。

再者，Python使用范围如此广泛，一个人精力有限，不可能精通所有的领域。就拿Python官网的Python应用领域来说，Python有以下几个方面的应用：

- Web Programming: Django, Pyramid, Bottle, Tornado, Flask, web2py
- GUI Development: wxPython, tkInter, PyGtk, PyGObject, PyQt
- Scientific and Numeric: SciPy, Pandas, IPython
- Software Development: Buildbot, Trac, Roundup
- System Administration: Ansible, Salt, OpenStack

如果有人声称精通上面所有领域，那么，请收下我的膝盖，并且，请收我为徒。

既然精通Python是不可能也是没有意义的事情，那么，为什么各个招聘要求里面，都要求精通Python呢？我觉得这都是被逼的。为什么这么说呢，且听我慢慢说来。

**为什么招聘要求精通Python**

绝大部分人对Python的认识都有偏差，认为Python比较简单。相对于C、C++和Java来说，Python是比较容易学习一些，所以，才会有这么多只是简单地了解了一点语法，就声称自己会Python的工程师。

打个比方，如果一个工程师，要去面试一个C++的岗位，他至少会找一本C++的书认真学习，然后再去应聘。Python则不然，很多同学只花了一点点时间，了解一下Python的语法，就说自己熟悉Python。这也导致Python的面试官相对于其他方向的面试官，更加容易遇到不合格的求职者，浪费了大家的时间。Python面试官为了不给自己找麻烦，只能提高要求，要求求职者精通Python。

**怎样才算精通Python**

既然精通Python本身是一件不可能的事情，而面试官又要求精通Python，作为求职者，应该达到怎样的水平，才敢去应聘呢？我的观点是，要求精通Python的岗位都是全职的Python开发，Python是他们的主要使用语言，要想和他们成为同事，你至少需要：

1. 能够写出Pythonic的代码
2. 对Python的一些高级特性比较熟悉
3. 对Python的优缺点比较了解

这样说可能比较抽象，不太好理解。我们来看几个例子，如果能够充分理解这里的每一个例子，那么，你完全能够顺利通过“精通Python”的岗位面试。

---

### 敢来挑战吗

**1. 上下文管理器**

大家在编程的时候，经常会遇到这样的场景：先执行一些准备操作，然后执行自己的业务逻辑，等业务逻辑完成以后，再执行一些清理操作。

比如，打开文件，处理文件内容，最后关闭文件。又如，当多线程程序需要访问临界资源的时候，线程首先需要获取互斥锁，当执行完成并准备退出临界区的时候，需要释放互斥锁。对于这些情况，Python中提供了上下文管理器（Context Manager）的概念，可以通过上下文管理器来控制代码块执行前的准备动作以及执行后的收尾动作。

我们以处理文件为例来看一下在其他语言中，是如何处理这种情况的。

Java风格/C++风格的Python代码：

```python
myfile = open(r'C:\misc\data.txt')
try:
    for line in myfile:
        # ...use line here...
finally:
    myfile.close()
```

Pythonic的代码：

```python
with open(r'C:\misc\data.txt') as myfile:
    for line in myfile:
        # ...use line here...
```

我们这个问题讨论的是精通Python，显然，仅仅是知道上下文管理器是不够的，你还需要知道：

1. 上下文管理器的其他使用场景（如数据库cursor，锁）
   - 上下文管理器管理锁
   - 上下文管理器管理数据库cursor
   - 上下文管理器控制运算精度

2. 上下文管理器可以同时管理多个资源

假设你需要读取一个文件的内容，经过处理以后，写入到另外一个文件中。你能写出Pythonic的代码，所以你使用了上下文管理器，满意地写出了下面这样的代码：

```python
with open('data.txt') as source:
    with open('target.txt', 'w') as target:
        target.write(source.read())
```

你已经做得很好了，但是，你时刻要记住，你是精通Python的人啊！精通Python的人应该知道，上面这段代码还可以这么写：

```python
with open('data.txt') as source, open('target.txt', 'w') as target:
    target.write(source.read())
```

3. 在自己的代码中，实现上下文管理协议

你知道上下文管理器的语法简洁优美，写出来的代码不但短小，而且可读性强。所以，作为精通Python的人，你应该能够轻易地实现上下文管理协议。在Python中，我们就是要自己实现下面两个协议：

- `__enter__(self)`：定义上下文管理器在with语句创建的代码块开始时应执行的操作。注意，`__enter__`的返回值会绑定到with语句的目标（即as后面的名称）。
- `__exit__(self, exception_type, exception_value, traceback)`：定义上下文管理器在其代码块执行完成后（或终止后）应执行的操作。它可以用于处理异常、执行清理工作，或执行代码块结束后总是需要立即执行的操作。如果代码块成功执行，`exception_type`、`exception_value`和`traceback`将为None。否则，你可以选择处理异常或让用户处理它；如果你想处理异常，请确保`__exit__`最后返回True。如果你不想让上下文管理器处理异常，只需让它发生即可。

**2. 装饰器**

由于我们这个问题的题目是精通Python，所以，我假设大家已经知道装饰器是什么，并且能够写简单的装饰器。那么，你是否知道，写装饰器也有一些注意事项呢。

我们来看一个例子：

```python
def is_admin(f):
    def wrapper(*args, **kwargs):
        if kwargs.get("username") != 'admin':
            raise Exception("This user is not allowed to get food")
        return f(*args, **kwargs)
    return wrapper

@is_admin
def barfoo(username='someone'):
    """Do crazy stuff"""
    pass

print(barfoo.__doc__)
print(barfoo.__name__)
```

输出：

```
None
wrapper
```

我们用装饰器装饰完函数以后，无法正确地获取到原函数的函数名称和帮助信息，为了获取这些信息，我们需要使用`@functools.wraps`。如下所示：

```python
import functools

def is_admin(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if kwargs.get("username") != 'admin':
            raise Exception("This user is not allowed to get food")
        return f(*args, **kwargs)
    return wrapper
```

再比如，我们要获取被装饰的函数的参数，以进行判断，如下所示：

```python
import functools

def check_is_admin(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if kwargs.get('username') != 'admin':
            raise Exception("This user is not allowed to get food")
        return f(*args, **kwargs)
    return wrapper

@check_is_admin
def get_food(username, food='chocolate'):
    return "{} get food: {1}".format(username, food)

print(get_food('admin'))
```

这段代码看起来没有任何问题，但是，执行将会出错，因为，username是一个位置参数，而不是一个关键字参数，我们在装饰器里面，通过`kwargs.get('username')`是获取不到username这个变量的。为了保证灵活性，我们可以通过`inspect`来修改装饰器的代码，如下所示：

```python
import inspect
import functools

def check_is_admin(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        func_args = inspect.getcallargs(f, *args, **kwargs)
        print(func_args)
        if func_args.get('username') != 'admin':
            raise Exception("This user is not allowed to get food")
        return f(*args, **kwargs)
    return wrapper
```

装饰器还有很多知识，比如装饰器怎么装饰一个类，装饰器的使用场景，装饰器有哪些缺点，这些，你们都知道吗？

**3. 全局变量**

关于Python的全局变量，我们先从一个问题开始：Python有没有全局变量？可能你看到这个问题的时候就蒙圈了，没关系，我来解释一下。

从Python自己的角度来说，Python是有全局变量的，所以，Python为我们提供了`global`关键字，我们能够在函数里面修改全局变量。但是，从C/C++/Java程序员的角度来说，Python是没有全局变量的。因为，Python的全局变量并不是程序级别的（即全局唯一），而是模块级别的。模块就是一个Python文件，是一个独立的、顶层的命名空间。模块内定义的变量，都属于该命名空间下，Python并没有真正的全局变量，变量必然属于某一个模块。

我们来看一个例子，就能够充分理解上面的概念。三种不同的修改全局变量的方法：

```python
import sys
import test

a = 1

def func1():
    global a
    a += 1

def func2():
    test.a += 1

def func3():
    module = sys.modules['test']
    module.a += 1

func1()
func2()
func3()
```

这段代码虽然看起来都是在对全局变量操作，其实，还涉及到命名空间和模块的工作原理，如果不能很清楚的知道发生了什么，可能需要补充一下自己的知识了。

**4. 时间复杂度**

我们都知道，在Python里面list是异构元素的集合，并且能够动态增长或收缩，可以通过索引和切片访问。那么，又有多少人知道，list是一个数组而不是一个链表。

关于数组和链表的知识，我想大家都知道了，这里就不再赘述。如果我们在写代码的过程中，对于自己最常用的数据结构，连它的时间复杂度都不知道，我们又怎么能够写出高效的代码呢。写不出高效的代码，那我们又怎么能够声称自己精通这门编程语言呢。

既然list是一个数组，那么，我们要使用链表的时候，应该使用什么数据结构呢？在写Python代码的时候，如果你需要一个链表，你应该使用标准库collections中的deque，deque是双向链表。标准库里面有一个queue，看起来和deque有点像，它们是什么关系？这个问题留着读者自己回答。

我们再来看一个很实际的例子：有两个目录，每个目录都有大量文件，求两个目录中都有的文件，此时，用Set比List快很多。因为，Set的底层实现是一个hash表，判断一个元素是否存在于某个集合中，List的时间复杂度为O(n)，Set的时间复杂度为O(1)，所以这里应该使用Set。我们应该非常清楚Python中各个常用数据结构的时间复杂度，并在实际写代码的过程中，充分利用不同数据结构的优势。

**5. Python中的else**

最后我们来看一个对Python语言优缺点理解的例子，即Python中增加的两个else。相对于C++语言或者Java语言，Python语法中多了两个else。

一个在while循环或for循环中：

```python
while True:
    ...
else:
    ...
```

另一个在try...except语句中：

```python
try:
    ...
except:
    ...
else:
    ...
finally:
    ...
```

那么，哪一个是最好的设计，哪一个是不好的设计呢？要回答这个问题，我们先来看一下在大家固有的观念中，else语句起到什么作用。在所有语言中，else都是和if语句一起出现的：

```
if <condition>
    statement1
else
    statement2
```

翻译成自然语言就是，如果条件满足，则执行语句1，否则，执行语句2。注意我们前面的用语，是“否则”，也就是说，else语句在我们固有的观念中，起到的作用是“否则”，是在不满足条件的情况下才执行的。

我们来看Python中，while循环后面的else语句。这个else语句是在while语句正常结束的时候执行的。所以，按照语意来说，while循环的else起到的作用是“and”。也就是说，在Python中，while循环末尾的else换做and才是更加合适的。

你可能觉得我有点钻牛角尖，那好，我再强调一遍，while循环中的else语句是在循环正常结束的时候执行的，那么请问：

1. 如果while循环里面遇到了break语句，else语句会执行吗
2. 如果while循环最后，遇到了continue语句，else语句还会执行吗
3. 如果while循环内部出现异常，else语句还会执行吗

这里的几个问题，大多数人都不能够很快的正确回答出来。而我们的代码是写给人看的，不应该将大多数人排除在能够读懂这段代码之外。所以我认为，Python语言中循环语句末尾的else语句是一个糟糕的设计。

现在，我们再来看try...except语句中的else，这个else设计得特别好，其他语言也应该吸取这个设计。这个设计的语义是，执行try里面的语句，这里面的语句可能会出现异常，如果出现了异常，就执行except里面的语句，如果没有出现异常，就执行else里面的语句，最后，无论是否出现异常，都要执行finally语句。这个设计好就好在，else的语句完全和我们的直观感受是一样的，是在没有出现异常的情况下执行。并且，有else比没有else好，有了else以后，正确地将程序员认为可能出现异常的代码和不可能出现异常的代码分开，这样，更加清楚的表明了是哪一条语句可能会出现异常，更多的暴露了程序员的意图，使得代码维护和修改更加容易。

---

**结论**：这篇回答很长，但是，我相信对很多人都会有帮助。这里想说的是，Python是一门编程语言，使用范围非常广泛，大家不要去追求精通Python程序语言自身，而应该将精力放在自己需要解决的实际问题上。其次，绝大多数人对Python的认识都存在误区，认为Python很简单，只是简单地了解一下就开始写Python代码，写出了一堆很不好维护的代码，我希望这一部分人看到我的回答以后，能够回去重新学习Python。最后，对于一些同学的疑虑——招聘职位要求精通Python，我的回答是，他们并不奢望招到一个精通Python的人，他们只是想招到一个合格的工程师，而大部分的Python工程师，都，不，合，格！
