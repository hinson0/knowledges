看到了问题根源。这是 Python 相对导入的经典陷阱。

★ Insight ─────────────────────────────────────

Python 有两种运行模式：作为脚本(**name** == "**main**",**package** 为 None 或空)和作为模块(python -m,**package** 自动设置为所属包名)
相对导入 from .db import aengine 里的 . 必须通过 **package** 属性解析,脚本模式下 **package** 是空的,所以 Python 不知道 . 指向哪里,直接抛 ImportError
判断依据:如果文件里用了 from .xxx 这种带点的导入,就不能直接 python xxx.py 启动
─────────────────────────────────────────────────
