# docker-compose environment:列表式 vs 映射式(不可混用)

## Trigger Question
> (按建议改 app.environment 后)`docker compose config` 报错:
> `services.app.environment.[0]: unexpected type map[string]interface {}`

## Key Takeaways
- `environment:` 有两种合法写法,**不能混用**:
  - 列表式(sequence):`- KEY=value`(等号,无冒号)
  - 映射式(mapping):`KEY: value`(冒号,无 `-`)
- `- DB_HOST: mysql` 是「列表里塞了个映射」,YAML 解析成 `[{DB_HOST: mysql}]`,而 Compose 列表项只接受字符串 → 报 `unexpected type map[string]interface {}`。
- 映射式下裸写数字端口会被 YAML 当**整数**,部分 Compose 版本报 "should be a string";端口建议加引号 `"3306"`。列表式 `- DB_PORT=3306` 则不用引号(等号右边天然是字符串)。

## Schema / Field Table
| 写法 | 形式 | 例子 |
|------|------|------|
| 列表 | `- KEY=value` | `- DB_HOST=mysql` |
| 映射 | `KEY: value` | `DB_HOST: mysql` |

## Code Example
```yaml
# ✅ 映射式(推荐)
environment:
  DB_HOST: mysql
  DB_PORT: "3306"

# ✅ 列表式
environment:
  - DB_HOST=mysql
  - DB_PORT=3306

# ❌ 混用 → unexpected type map
environment:
  - DB_HOST: mysql
```

## Pitfall / Why
- 改完先 `docker compose config` 静态校验,可在不启动容器的情况下立刻暴露这类语法错。见 [[docker-compose-exec-run-config]]。

## Related
- [[docker-compose-exec-run-config]]
- [[docker-compose-host-vs-container-db-address]]
