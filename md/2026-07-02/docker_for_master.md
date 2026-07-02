# docker学习

## 如何在docker中临时起一个现成的image 去为master分支fixbug用???

- 先确定image的名字,比如叫cms-center-image
- 然后执行

```bash

docker run -it \
  --name cms-center-master-container \
  -p 8001:8000 \
  -v $(pwd):/var/cms-center \
  -w /var/cms-center \
  cms-center-image:latest \
  bash
```

这其中:

- docker run -it 是指用交互式的方式
- --name cms-center-master-container 当前的container名字
- -p 8001:8000 宿主机到docker的映射,即将宿主的8001映射到容器:cms-center-master-container的8000
- -v $(pwd):/var/cms-center 表示将当前的目录 以`volume`卷的方式挂在到 docker目录的/var/cms-center(bind mount)
- -w /var/cms-center 表示 当前的cms-center作为工作目录,即进去的目录就是这个
- cms-center-image:latest 表示使用的镜像
- bash 进入容器的 bash shell(尽量使用bash,这个sh选项是精简版本,会很恶心的.什么都没有基本的shell都不提示,纯搞手敲)

## --build的含义

- docker compose up -d 一般不加--build
- 只要这些情况下加:
  - Dockerfile改了
  - docker-compose.yml文件改了

- 改业务代码不需要加--build 因为会自己通过bind mount过去
