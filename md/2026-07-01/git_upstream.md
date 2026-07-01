你现在的问题大概率是：**本地分支的 upstream 还指向 `origin/master`**，所以 `git push` 默认还往 master 推。

先检查：

```bash
git branch --show-current
git branch -vv
```

如果你当前在本地分支，比如：

```bash
feature/demo
```

直接这样推：

```bash
git push -u origin HEAD
```

这句最推荐记：

```bash
git push -u origin HEAD
```

意思是：**把当前本地分支推到远端，并创建同名远端分支，同时绑定 upstream。**

等价于：

```bash
git push -u origin feature/demo
```

---

如果你已经发现本地分支错误绑定到了 `origin/master`，先解绑：

```bash
git branch --unset-upstream
```

然后重新绑定到同名远端分支：

```bash
git push -u origin HEAD
```

再检查：

```bash
git branch -vv
```

你应该看到类似：

```bash
* feature/demo abc1234 [origin/feature/demo] xxx
```

而不是：

```bash
* feature/demo abc1234 [origin/master] xxx
```

---

以后新建本地分支后，第一次推远端就用：

```bash
git push -u origin HEAD
```

之后再 `git push`，就会默认推到对应的远端同名分支。

---

如果你已经把代码误推到了远端 `master`，不要马上 `force push`。先看：

```bash
git log --oneline --decorate --graph -10
```

如果只是本地分支绑定错了，按上面修即可。

如果**远端 master 已经被污染**，更安全的处理方式是：

```bash
git checkout master
git pull origin master
git revert <误推的commit>
git push origin master
```

除非你非常确定没人拉过 master，否则不要轻易：

```bash
git push --force
```

更安全的强推也应该是：

```bash
git push --force-with-lease
```
