可以改，分两种：

**临时本次启动生效**

```bash
codex --sandbox workspace-write --ask-for-approval never
```

如果你还希望命令能联网：

```bash
codex --sandbox workspace-write --ask-for-approval never \
  -c sandbox_workspace_write.network_access=true
```

**永久默认生效**

改你的用户配置：

```bash
~/.codex/config.toml
```

加入或修改：

```toml
approval_policy = "never"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = true
```

含义是：

- `approval_policy = "never"`：不再弹审批确认。
- `sandbox_mode = "workspace-write"`：仍限制在当前 workspace 里读写，风险相对可控。
- `network_access = true`：允许 shell 命令联网。只在你信任项目时开。

如果你想完全不受 sandbox 限制，可以用：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

但这个等价于非常高信任模式，我不建议作为全局默认；更适合容器、虚拟机、临时隔离目录里用。

另外，很多弹窗其实可以在审批时选择“记住/持久允许这个命令前缀”。比如你经常运行 `git commit`、`npm test`，批准一次 prefix rule 后，以后同类命令就不会每次点。这个比全局 `danger-full-access` 更稳。
