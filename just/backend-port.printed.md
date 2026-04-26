方案 A（推荐）：固定后端端口 8000，不让它漂移
端口是契约，就像 Postgres 5432。8000 被占说明你已经有一个后端在跑，多半是忘了关。改 start-be：检测到占用时列出占用进程 + 提示用户处理，而不是换端口。

优点：彻底消除这类 bug，环境稳定。
代价：失去"一键再起一个"的便利。

方案 B：共享 runtime port 文件 + 启动前注入
start-be 启动时把实际端口写到 .claude/.dev-port
start-fe 启动前先读这个文件，sed 写入 .env 的 EXPO_PUBLIC_API_URL，启动完再恢复（类似你现在对 app.json 做的 trap cleanup）
优点：保留端口漂移能力。
代价：要求 be 先于 fe 启动；.env 被 worktree 软链到 main，所有 worktree 会互相干扰。
