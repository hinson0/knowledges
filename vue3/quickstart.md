# Vue 3 速通笔记

> 写给从其它技术栈过来、想快速上手 Vue 3 + `<script setup>` + TypeScript 的人。
> 锚点引用了 `~/xiaoshuo` 项目里的真实文件,可对照看。

## 1. `.vue` 文件 = SFC(Single File Component)

一个组件 = 一个 `.vue` 文件,内含三块:

```vue
<script setup lang="ts">
// 逻辑(状态、props、方法)
</script>

<template>
  <!-- 模板(HTML) -->
</template>

<style scoped>
/* 样式(scoped 只作用本组件) */
</style>
```

- `<style>` 可省;`<template>` 可省(纯渲染函数,极少);`<script>` 一般都有。
- `scoped` 让 CSS 只影响当前组件,不污染全局——用 `[data-v-xxxx]` attribute 选择器实现。

**关键魔法 `<script setup>`**:文件顶层声明的 `const`/`function` **自动暴露给 template**,不用 `return { ... }`。这是 Vue 3 最重要的甜点语法。

## 2. 响应式三件套

```ts
import { ref, reactive, computed } from 'vue'

const count = ref(0)               // 任意值用 ref
count.value++                       // 脚本里访问要 .value

const user = reactive({ name: '阿松', age: 18 })  // 对象用 reactive,无 .value
user.age++

const double = computed(() => count.value * 2)    // 派生值,自动跟踪依赖
```

### `.value` 黄金规则

| 场景 | 写法 |
|---|---|
| `<script>` 里读/写 ref | `count.value` |
| `<template>` 里用 ref | `count`(自动 unwrap) |

**实操选择**:95% 用 `ref`,统一好记。`reactive` 解构后会丢响应式,容易踩坑。

## 3. 模板语法速查

| 写法 | 作用 | 例子 |
|---|---|---|
| `{{ x }}` | 文本插值 | `<h1>{{ title }}</h1>` |
| `:prop="x"` | 绑定 attribute(`v-bind` 简写) | `<img :src="url">` |
| `@event="fn"` | 监听事件(`v-on` 简写) | `<button @click="add">` |
| `v-if` / `v-else-if` / `v-else` | 条件渲染(真删 DOM) | `<div v-if="loaded">` |
| `v-show` | 条件渲染(只切 `display`) | `<div v-show="open">` |
| `v-for` | 列表渲染,**必须配 `:key`** | `<li v-for="b in books" :key="b.id">` |
| `v-model` | 双向绑定(input/select 等) | `<input v-model="keyword">` |
| `v-html` | 渲染 HTML 字符串(慎用) | `<div v-html="raw">` |

## 4. Props / Emits(组件通信)

```vue
<script setup lang="ts">
// 父传子
const props = defineProps<{
  title: string
  cover?: string         // 可选
}>()

// 子向父发事件
const emit = defineEmits<{
  (e: 'submit', value: string): void
  (e: 'close'): void
}>()

function onClick() {
  emit('submit', '阿松')
}
</script>
```

父组件用法:

```vue
<BookCover :title="b.title" :cover="b.cover" @submit="handleSubmit" />
```

`v-model` 本质是 `:modelValue` + `@update:modelValue`,自定义组件支持 v-model 时用这两个名字即可。

## 5. 生命周期与副作用

```ts
import { onMounted, onUnmounted, watch, watchEffect } from 'vue'

onMounted(() => { /* DOM 挂载完成 */ })
onUnmounted(() => { /* 清理定时器/事件监听 */ })

// 显式监听某个值
watch(count, (newVal, oldVal) => { ... })

// 自动收集依赖,任何用到的响应式变量变了就重跑
watchEffect(() => {
  console.log('count 现在是', count.value)
})
```

## 6. `.vue` vs `.ts` 决策表

**一句话:有 UI 用 `.vue`,纯逻辑用 `.ts`。**

| 文件类型 | 用什么 | 例子(`~/xiaoshuo`) |
|---|---|---|
| 页面 | `.vue` | `views/reader/Reader.vue` |
| 跨页复用组件 | `.vue` | `components/BookCover.vue` |
| 复用逻辑(composable) | `.ts` | `views/reader/usePager.ts` |
| Pinia store | `.ts` | `stores/reader.ts` |
| 路由配置 | `.ts` | `router/index.ts` |
| API 请求 | `.ts` | `api/book.ts` |
| 类型定义 | `.ts` | `types/book.ts` |
| 全局样式/token | `.css` | `styles/tokens.css` |

**判断口诀**:"我这文件里要写 `<template>` 吗?" 要 → `.vue`,不要 → `.ts`。

## 7. Composable —— Vue 3 的灵魂

**Composable** 是以 `use` 开头的 `.ts` 函数,内部可以用 `ref`/`computed`/`onMounted` 等所有响应式 API,但**不渲染 DOM**。组件调用它得到响应式状态和方法。

```ts
// usePager.ts
export function usePager(mode: 'cover' | 'sim' | 'scroll') {
  const currentPage = ref(0)
  const totalPages = ref(0)
  function next() { currentPage.value++ }
  function prev() { currentPage.value-- }
  return { currentPage, totalPages, next, prev }
}
```

```vue
<!-- Reader.vue -->
<script setup lang="ts">
import { usePager } from './usePager'
const { currentPage, next, prev } = usePager('cover')
</script>
```

它是 Vue 3 取代 Vue 2 mixin/HOC 的官方方案。

## 8. Pinia(状态管理)

跟 composable 同形:`defineStore` 包一层而已。

```ts
// stores/user.ts
import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useUserStore = defineStore('user', () => {
  const token = ref<string>(localStorage.getItem('token') || '')

  function setToken(t: string) {
    token.value = t
    localStorage.setItem('token', t)
  }
  function logout() {
    token.value = ''
    localStorage.removeItem('token')
  }

  return { token, setToken, logout }
})
```

组件里用:

```vue
<script setup lang="ts">
import { useUserStore } from '@/stores/user'
const userStore = useUserStore()
console.log(userStore.token)        // 直接读
userStore.setToken('xxx')           // 调 action
</script>
```

**为什么 store 是 `.ts` 不是 `.vue`?** 因为 store 跟 UI 解耦,任何组件、任何代码都能用,所以放纯 `.ts`。**".vue 是消费者,.ts 是供应者"** 这个心智模型能帮你做架构决定。

## 9. 调用链心智模型

```
Reader.vue (页面 / 消费者)
  ├─ 调 usePager.ts        ← composable,提供翻页响应式状态
  ├─ 调 useReaderStore()   ← Pinia store,字号/主题等全局配置
  ├─ 调 useProgressStore() ← Pinia store,持久化阅读进度
  └─ 渲染 <BookCover />    ← 子组件,更小颗粒 UI
```

`.vue` 在底层消费;`.ts`(composable + store)在中层供应数据/逻辑;子 `.vue` 提供原子 UI。

## 10. 5 个上手动作

1. 打开真实组件(如 `views/reader/Reader.vue`),看 `<script setup>` 里 import 了什么、`ref` 定义了什么、template 里怎么用。
2. 看 `stores/reader.ts`,认 `defineStore('xxx', () => { ... return { ... } })` 套路。
3. 改一个 `ref` 的初值,刷新页面看 DOM 变化——直观感受响应式。
4. 加个 `<button @click="...">`,点一下让 `count.value++`,看 UI 自动更新。
5. 写一个 `computed`,基于现有 `ref` 派生一个值,在 template 用 `{{ }}` 显示出来。

## 11. 心智清单

- ✅ 顶层 `<script setup>` + `<template>` + `<style scoped>`
- ✅ `ref()` 用得最多,记住 `.value`(脚本里有,模板里无)
- ✅ Props 用 `defineProps<{...}>()`,Emits 用 `defineEmits<{...}>()`
- ✅ 跨组件共享状态 → Pinia store(`.ts`)
- ✅ 跨组件共享逻辑 → composable `useXxx.ts`(`.ts`)
- ✅ 副作用 → `onMounted` / `onUnmounted` / `watch` / `watchEffect`
- ❌ 别在 `<script setup>` 顶层之外定义状态希望模板看到——必须顶层
- ❌ 别 `const { age } = reactive({age:1})` 然后改 `age`——解构丢响应式
- ❌ 别忘了 `v-for` 的 `:key`,否则列表更新会出灵异 bug

## 12. 进阶关键词(以后再深入)

- `provide` / `inject` —— 跨多层组件传值,替代深层 props 透传
- `<Suspense>` —— 异步组件占位
- `<Teleport>` —— 把 DOM 渲染到 body 等任意地方,做浮层/Modal 必备
- `defineExpose` —— `<script setup>` 默认对外不暴露任何东西,要让父组件 ref 拿到子组件方法时用它
- `shallowRef` / `shallowReactive` —— 只跟踪顶层,优化大对象
- `effectScope` —— 收集多个副作用,统一销毁
