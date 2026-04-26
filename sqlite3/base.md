sqlite3 的命令主要分为两类：一类是以点 (`.`) 开头的**点命令**，用于管理数据库环境；另一类是以分号 (`;`) 结尾的**标准 SQL 语句**，用于操作数据。这里为你整理了最常用的一些命令。

### 🗄️ 常用“点命令”

- **`.help`**：显示所有可用的点命令列表及简要说明，是最重要的命令。
- **`.databases`**：列出所有已连接的数据库名称及其文件路径。
- **`.tables ?PATTERN?`**：列出当前数据库中的所有表。可选的 `?PATTERN?` 参数用于过滤表名，例如 `.tables %user%` 会显示所有包含 "user" 的表。
- **`.schema ?TABLE?`**：显示创建数据库表或指定表的 `CREATE` SQL 语句，常用于查看表结构。
- **`.quit` 或 `.exit`**：退出 `sqlite3` 命令行工具。

**导入与导出**

- **`.dump ?TABLE?`**：将数据库或指定表的结构和数据导出为 SQL 文本格式。
- **`.output FILENAME`**：将后续所有命令的输出重定向到指定文件。
- **`.import FILE TABLE`**：将 CSV 或其他分隔符格式文件的数据导入到指定的数据库表中。
- **`.read FILENAME`**：执行指定文件中包含的 SQL 语句。
- **`.backup ?DB? FILE`**：在线备份整个数据库（默认为 "main"）到指定文件，比 `.dump` 更快。

**环境设置与调试**

- **`.show`**：显示当前所有环境变量的设置，如输出模式、分隔符等。
- **`.mode MODE`**：设置查询结果的输出格式，常用模式有 `csv`, `column`, `list`, `insert`, `html` 等。
- **`.headers ON|OFF`**：设置是否在查询结果中显示列标题。配合 `.mode column` 使用效果更佳。
- **`.width NUM NUM ...`**：当 `.mode` 设置为 `column` 时，可用此命令手动设置各列的显示宽度。
- **`.timer ON|OFF`**：开启或关闭 SQL 语句执行时间的统计，常用于性能调试。

### 📝 标准 SQL 语句

- **`CREATE TABLE ...`**：创建新表，需指定列名、数据类型及约束。
- **`INSERT INTO ... VALUES ...`**：向表中插入新记录。
- **`SELECT ... FROM ...`**：查询数据。
- **`UPDATE ... SET ... WHERE ...`**：更新符合条件的记录。
- **`DELETE FROM ... WHERE ...`**：删除符合条件的记录。
- **`ALTER TABLE ... ADD COLUMN ...`**：向已存在的表中添加新列。
- **`DROP TABLE ...`**：删除整个表及其所有数据。
- **`CREATE INDEX ... ON ...`**：创建索引以提高查询效率。
- **`BEGIN TRANSACTION ... COMMIT / ROLLBACK`**：手动控制事务，确保数据一致性。

### 📝 格式化查询输出

对于日常使用，建议开启以下设置以获得更清晰的查询结果，提升可读性。

```sql
sqlite> .mode column
sqlite> .headers on
sqlite> .timer on
```

### 💎 总结

总而言之，掌握 `sqlite3` 命令行工具的关键在于：

- **求助**：随时用 `.help`。
- **管理**：用 `.tables`, `.schema` 查看结构。
- **设置**：用 `.mode column`, `.headers on` 让输出更清晰。
- **操作数据**：用标准的 SQL 语句。
