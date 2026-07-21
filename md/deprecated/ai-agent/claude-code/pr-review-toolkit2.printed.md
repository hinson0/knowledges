description: "使用专业智能体进行全面的 PR 审查"
argument-hint: "[审查维度]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Task"]

# 全面 PR 审查

使用多个专业智能体进行全面的拉取请求审查，每个智能体聚焦代码质量的不同方面。

**审查维度（可选）：** "$ARGUMENTS"

## 审查工作流：

1.  **确定审查范围**
    - 检查 git 状态以识别已更改的文件
    - 解析参数以查看用户是否请求了特定的审查维度
    - 默认：运行所有适用的审查

2.  **可用审查维度：**
    - **comments** - 分析代码注释的准确性和可维护性
    - **tests** - 审查测试覆盖的质量和完整性
    - **errors** - 检查错误处理中的静默失败
    - **types** - 分析类型设计和不变性（如果添加了新类型）
    - **code** - 针对项目指南进行通用代码审查
    - **simplify** - 简化代码以提高清晰度和可维护性
    - **all** - 运行所有适用的审查（默认）

3.  **识别已更改的文件**
    - 运行 `git diff --name-only` 查看修改过的文件
    - 检查 PR 是否已存在：`gh pr view`
    - 识别文件类型以及适用的审查

4.  **确定适用的审查**
    基于更改：
    - **始终适用**：code-reviewer（通用质量）
    - **如果测试文件更改**：pr-test-analyzer
    - **如果添加了注释/文档**：comment-analyzer
    - **如果错误处理更改**：silent-failure-hunter
    - **如果添加/修改了类型**：type-design-analyzer
    - **在通过审查之后**：code-simplifier（优化和精炼）

5.  **启动审查智能体**
    **顺序方式**（一次一个）：
    - 更易于理解和采取行动
    - 每个报告在下个开始前完成
    - 适合交互式审查
      **并行方式**（用户可请求）：
    - 同时启动所有智能体
    - 全面的审查更快
    - 结果一起返回

6.  **汇总结果**
    在智能体完成后，总结：
    - **严重问题**（合并前必须修复）
    - **重要问题**（应该修复）
    - **建议**（有更好）
    - **正面观察**（做得好的地方）

7.  **提供行动计划**
    组织调查结果：

    ```markdown
    # PR 审查摘要

    ## 严重问题（发现 X 个）

    - [agent-name]: 问题描述 [文件:行号]

    ## 重要问题（发现 X 个）

    - [agent-name]: 问题描述 [文件:行号]

    ## 建议（发现 X 个）

    - [agent-name]: 建议内容 [文件:行号]

    ## 优点

    - 此 PR 中做得好的地方

    ## 推荐行动

    1. 首先修复严重问题
    2. 处理重要问题
    3. 考虑建议
    4. 修复后重新运行审查
    ```

## 使用示例：

**完整审查（默认）：**

```
/pr-review-toolkit:review-pr
```

**特定维度：**

```
/pr-review-toolkit:review-pr tests errors # 仅审查测试覆盖和错误处理
/pr-review-toolkit:review-pr comments    # 仅审查代码注释
/pr-review-toolkit:review-pr simplify    # 在通过审查后简化代码
```

**并行审查：**

```
/pr-review-toolkit:review-pr all parallel # 并行启动所有智能体
```

## 智能体描述：

**comment-analyzer**：

- 验证注释相对于代码的准确性
- 识别注释腐化
- 检查文档完整性

**pr-test-analyzer**：

- 审查行为测试覆盖率
- 识别关键缺口
- 评估测试质量

**silent-failure-hunter**：

- 发现静默失败
- 审查 catch 块
- 检查错误日志记录

**type-design-analyzer**：

- 分析类型封装性
- 审查不变性表达
- 评定类型设计质量

**code-reviewer**：

- 检查 CLAUDE.md 合规性
- 检测 bug 和问题
- 审查通用代码质量

**code-simplifier**：

- 简化复杂代码
- 提高清晰度和可读性
- 应用项目标准
- 保留原有功能

## 提示：

- **尽早运行**：在审查前，在本地运行 /pr-review-toolkit:review-pr 以提前发现问题
- **有针对性地使用**：仅请求你需要的维度（例如，仅运行 /pr-review-toolkit:review-pr tests）
- **首先修复严重问题**：在解决严重问题之前，不要合并
- **考虑上下文**：某些问题可能是误报，需要人工判断
- **并行审查**：对于大型 PR，使用 `parallel` 参数可以更快获得结果
- **重新运行**：修复问题后，重新运行审查以验证是否已解决
