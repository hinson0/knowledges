好的，根据你之前的提问，我把 **GitLab 相关的核心知识点** 整理成了一份简明汇总，方便你随时查阅。

---

## 一、GitLab 界面语言设置（中文）

### ✅ 新版本（GitLab 15.0+）

- **个人设置**：右上角头像 → `Preferences` → `Localization` → `Language` → 选择 `Chinese, Simplified - 简体中文` → 保存。
- **全局设置（管理员）**：编辑 `/etc/gitlab/gitlab.rb`，添加 `gitlab_rails['locale'] = 'zh_CN'`，然后 `sudo gitlab-ctl reconfigure`。

### ❌ 旧版本（<15.0）

- **没有内置中文**，Preferences 菜单中找不到 Localization 选项。
- **解决方法**：升级 GitLab 到 15.0+，或手动安装第三方汉化补丁（不推荐），或换用极狐GitLab（原生中文）。

---

## 二、两步验证（2FA）与 Personal Access Token

### 🔐 2FA 开启后，网页登录需要密码 + 动态验证码

- 动态验证码通过手机 App 生成（如 Microsoft Authenticator、Google Authenticator 等）。

### 🔑 命令行操作（git clone / push 等）不能用密码 + 验证码

- **必须使用 Personal Access Token（个人访问令牌）代替密码**。

#### 生成 Token 的步骤

1. GitLab → 右上角头像 → `Settings` → `Access Tokens`。
2. 输入名称、过期时间。
3. 勾选需要的权限（例如 `read_repository` 用于克隆，`write_repository` 用于推送）。
4. 点击 `Create personal access token`，**立即复制并保存**（关闭页面后不再显示）。

#### 使用 Token 的方式

- **命令行克隆**：`git clone https://用户名:Token@gitlab.example.com/组/项目.git`
- **或正常克隆后，在 Password 提示处粘贴 Token**（不是登录密码）

---

## 三、项目权限与克隆判断

### 🔍 如何知道是否有克隆权限？

| 方法           | 操作                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------ |
| **看界面**     | 项目首页右上角是否有 **“Clone”** 按钮（蓝色，可点击）                                                        |
| **看成员角色** | 左侧菜单 → `Members` → 找到自己，角色为 **Reporter / Developer / Maintainer / Owner** 都能克隆（Guest 不能） |
| **直接尝试**   | `git clone <项目URL>`，成功则有权限，失败会报错（如 403 或 Authentication failed）                           |

### 📌 角色与权限速查

- **Guest**：只能看 Issue、Wiki，不能克隆代码
- **Reporter**：可克隆、看 Issue/Merge Request
- **Developer**：可克隆、推送、创建分支等
- **Maintainer / Owner**：完全管理权限

---

## 四、常见 GitLab + Git 命令行认证问题

### ❌ 错误示例

```
remote: HTTP Basic: Access denied. The provided password or token is incorrect or your account has 2FA enabled...
```

**原因**：账户开启了 2FA，但用了登录密码而不是 Personal Access Token。

**解决**：使用 `Personal Access Token` 作为密码。

### 💡 让 Git 记住 Token（避免每次都输入）

```bash
git config --global credential.helper store
```

下次输入用户名和 Token 后，会自动保存在 `~/.git-credentials`。

---

## 五、GitLab 界面常用术语（中英对照）

| 英文                      | 中文      |
| ------------------------- | --------- |
| Projects                  | 项目      |
| Groups                    | 群组      |
| Issues                    | 问题/工单 |
| Merge requests            | 合并请求  |
| To-Do List                | 待办事项  |
| Milestones                | 里程碑    |
| Snippets                  | 代码片段  |
| Activity                  | 活动      |
| Members                   | 成员      |
| Settings                  | 设置      |
| Preferences               | 偏好设置  |
| Access Tokens             | 访问令牌  |
| Two-Factor Authentication | 两步验证  |

---

## 六、小技巧

- **快速跳转**：按 `/` 聚焦搜索框，按 `?` 查看所有快捷键。
- **查看项目 ID**：项目首页右侧通常有显示（如 `项目ID: 14`）。
- **WSL 与 Windows 共用 Git 凭据**：不推荐，因为 WSL 内的 Git 配置与 Windows 独立，建议分别在两个环境配置。

---

如果你还需要补充某个具体方面（比如 CI/CD、Webhook、分支保护规则等），可以告诉我，我继续帮你整理。
