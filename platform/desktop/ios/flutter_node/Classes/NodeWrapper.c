// NodeWrapper.c —— iOS 端 Node 启动垫片（补齐 NodeMobile 缺失的 camelCase API）
//
// ============================================================================
// 背景：为什么必须有这个文件
// ============================================================================
//
// NodeMobile.framework（Janea Systems 的 nodejs-mobile，com.janeasystems.NodeMobile）
// 解析其 Mach-O 导出符号表（51893 个 N_EXT|N_SECT 符号）后确认：
// 它**只**导出一个启动入口，且是 C 名字：
//
//     _node_start        @ 0x4000        （extern "C"，无参数名信息）
//
// 而 `node.h`（随 framework 分发）里声明的是 C++ 版本：
//
//     namespace node {
//       NODE_EXTERN int Start(int argc, char* argv[]);
//       /**! CNode Patch Start **/
//       NODE_EXTERN int Start(int argc, char* argv[],
//                             std::function<void(node::Environment*)> initNode);
//       /**! CNode Patch End **/
//     }
//
// NodeMobile 里**不存在**下列符号（已逐个查表确认）：
//     nodeStart / nodeStartThread / nodeStop / getEnvironmentEventLoop
//
// 而 xuelongqy/flutter_node 的 Dart 层（lib/bindings/node.dart）恰恰按 camelCase 查找：
//     nodeStart / nodeStartThread / nodeStop
// 并且它是用 `DynamicLibrary.process()` 一类「进程全局符号」方式查找的
// （iOS 端 AOT 快照里**没有**任何 "NodeMobile" / "flutter_node" 路径字符串，
//   证明 Dart 侧不按路径 dlopen，而是按符号名走全局表）。
//
// 所以：**必须有人把 camelCase 的三个符号补上**。原版就是这么做的 ——
// flutter_node.framework 的导出表里能直接看到：
//     _nodeStart        @ 0x400c
//     _nodeStartThread  @ 0x40ec
//     _nodeStop         @ 0x4264
// 并且它内部用 `dlsym(RTLD_DEFAULT, "node_start")` 动态解析 NodeMobile 的符号。
//
// ============================================================================
// 调用约定：从原版 flutter_node.framework 反汇编逐条还原（arm64 / AAPCS64）
// ============================================================================
//
// 【_getNodeStart @ 0x408c】—— 带静态缓存的 dlsym 包装
//     0x4098  ldr  x0, [x19, #0xb90]      ; 静态缓存槽
//     0x40a0  cbnz x0, #0x40e0            ; 命中则直接返回
//     0x40a4  adrp x1, #0x7000; add x1, x1, #0x6c8   ; x1 = "node_start"
//     0x40ac  mov  x0, #-2                ; x0 = RTLD_DEFAULT (-2)
//     0x40b0  bl   #0x65d0                ; dlsym(RTLD_DEFAULT, "node_start")
//     0x40b4  str  x0, [x19, #0xb90]      ; 写回缓存
//     0x40b8  cbz  x0, #0x40d0            ; NULL → 打印 ERROR
//     → 即 `static void* h = dlsym(RTLD_DEFAULT, "node_start");`
//
// 【nodeStart(argc=x0, argv=x1, cb=x2) @ 0x400c】
//     0x4020  mov  x21, x2                ; cb
//     0x4024  mov  x19, x1                ; argv
//     0x4028  mov  x20, x0                ; argc
//     0x4038  bl   printf("[NodeWrapper] nodeStart called, argc=%d\n", argc)
//     0x403c  cbz  x21, #0x4048           ; cb == NULL 就跳过
//     0x4040  mov  x0, #0                 ; x0 = NULL
//     0x4044  blr  x21                    ; cb(NULL)
//     0x4048  bl   #0x408c                ; fn = _getNodeStart()
//     0x404c  cbz  x0, #0x4074            ; 解析失败 → 返回 -1
//     0x405c  str  w9, [x21, #0xb80]      ; running = 1
//     0x4060  mov  x0, x20                ; x0 = argc
//     0x4064  mov  x1, x19                ; x1 = argv
//     0x4068  blr  x8                     ; ★ node_start(argc, argv) —— 只有 2 个参数
//     0x406c  str  wzr, [x21, #0xb80]     ; running = 0
//     0x4074  mov  w0, #-1                ; 解析失败分支返回 -1
//     → ★★ 关键：`node_start` 只吃 **(argc, argv)** 两个参数；
//        第 3 个 cb **不进** node_start（CNode 补丁的 std::function 形参在这版
//        NodeMobile 里已退化为不带回调的 2 参形式）。多传参数在 AAPCS64 下无害，
//        但按 2 参调用才是与原版逐字节一致的行为。
//
// 【nodeStartThread(argc=x0, argv=x1, cb=x2) @ 0x40ec】
//     0x4104  mov  x19, x2                ; cb
//     0x4108  mov  x20, x1                ; argv
//     0x410c  mov  x21, x0                ; argc
//     0x411c  bl   printf("[NodeWrapper] nodeStartThread called, argc=%d\n", argc)
//     0x4120  ldr  w8, [x8, #0xb80]       ; w8 = running
//     0x412c  ldr  x9, [x23, #0xb88]      ; x9 = thread
//     0x4130  cmp  w8, #0
//     0x4134  ccmp x9, #0, #0, eq         ; if (running && thread != NULL)
//     0x4138  b.eq #0x414c                ;   → 创建；否则打印 already running 返回 -1
//     0x414c  mov  w0, #0x18              ; malloc(24)
//     0x4150  bl   #0x65f4
//     0x415c  str  w21, [x0]              ; ctx->argc  (offset 0, 4 字节)
//     0x4160  stp  x20, x19, [x0, #8]     ; ctx->argv = x20 (offset 8)
//                                          ; ctx->cb   = x19 (offset 16)
//     0x4164  adrp x0, #0x11000; add x0, x0, #0xb88   ; &thread
//     0x416c  adrp x2, #0x4000; add x2, x2, #0x1c4    ; x2 = 线程入口 0x41c4
//     0x4174  mov  x1, #0                 ; x1 = NULL (pthread_attr)
//     0x4178  mov  x3, x22                ; x3 = ctx
//     0x417c  bl   #0x66c0                ; pthread_create(&thread, NULL, entry, ctx)
//     0x4180  cbz  w0, #0x41a8            ; 0 = 成功
//     0x4184  mov  x0, x22; bl free       ; 失败释放 ctx
//     0x418c  mov  w0, #-1
//     0x41a8  ldr  x0, [x23, #0xb88]; bl pthread_detach
//     0x41b0  printf("[NodeWrapper] Thread started, argc=%d\n", argc)
//     0x41bc  mov  w0, #0                 ; return 0
//
// 【线程入口 @ 0x41c4】
//     0x41d8  mov  x19, x0                ; ctx
//     0x41dc  ldr  w8, [x0]               ; argc
//     0x41e4  bl   printf("[NodeWrapper] Thread started, argc=%d\n", argc)
//     0x41f0  ldr  x8, [x19, #0x10]       ; cb
//     0x41f4  cbz  x8, #0x4200
//     0x41f8  mov  x0, #0; blr x8         ; cb(NULL)
//     0x4208  str  w8, [x21, #0xb80]      ; running = 1
//     0x420c  bl   #0x408c                ; fn = _getNodeStart()
//     0x4210  cbz  x0, #0x422c
//     0x4218  ldr  w0, [x19]              ; argc
//     0x421c  ldr  x1, [x19, #8]          ; argv
//     0x4220  blr  x8                     ; ★ node_start(argc, argv)
//
// 【nodeStop @ 0x4264】
//     0x426c  bl   printf("[NodeWrapper] nodeStop called\n")
//     0x427c  str  wzr, [x8, #0xb80]      ; running = 0
//     0x4284  str  xzr, [x8, #0xb88]      ; thread  = NULL
//     0x4288  mov  w0, #0                 ; return 0
//     → 只重置标志位，**不做**真实停止（NodeMobile 没有 node_stop 导出）。
//        与安卓侧注释「内嵌 Node 刻意不停止（进程级单例）」结论一致。
//
// ============================================================================

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

// ---------------------------------------------------------------------------
// NodeMobile 的真实导出：extern "C" int node_start(int argc, char** argv)
// 注意**只有两个参数** —— 见上方 0x4068 / 0x4220 的反汇编。
// ---------------------------------------------------------------------------
typedef int (*node_start_fn)(int argc, char** argv);

/// initNode 回调：CNode 补丁的 `std::function<void(node::Environment*)>` 的 C 化形态。
/// 原版把它当成「一个只吃 env 指针的函数指针」直接 `blr` 调用（见 0x41f8）。
typedef void (*init_node_fn)(void* env);

/// 线程上下文布局，必须与 0x415c/0x4160 一致：
///   offset 0  : int    argc   （4 字节，`str w21,[x0]`）
///   offset 8  : char** argv   （`stp x20, x19, [x0,#8]` 的第一个）
///   offset 16 : void*  cb     （同上 stp 的第二个）
/// 总大小 0x18 = 24 字节（`mov w0,#0x18; malloc`）。
typedef struct {
  int argc;
  char** argv;
  void* cb;
} node_thread_ctx;

static int g_running = 0;
static pthread_t g_thread;
static int g_thread_valid = 0;
static void* g_node_start = NULL;

// ---------------------------------------------------------------------------
// _getNodeStart —— 对应原版 0x408c：dlsym(RTLD_DEFAULT, "node_start") + 静态缓存
// ---------------------------------------------------------------------------
static node_start_fn get_node_start(void) {
  if (g_node_start == NULL) {
    g_node_start = dlsym(RTLD_DEFAULT, "node_start");
    if (g_node_start != NULL) {
      puts("[NodeWrapper] Found node_start via RTLD_DEFAULT");
    } else {
      puts("[NodeWrapper] ERROR: Could not find node_start symbol");
    }
  }
  return (node_start_fn)g_node_start;
}

// ---------------------------------------------------------------------------
// nodeStart —— 阻塞式启动（在调用者线程上跑完整个事件循环）
// ---------------------------------------------------------------------------
int nodeStart(int argc, char** argv, void* cb) {
  printf("[NodeWrapper] nodeStart called, argc=%d\n", argc);

  if (cb != NULL) {
    ((init_node_fn)cb)(NULL);
  }

  node_start_fn fn = get_node_start();
  if (fn == NULL) {
    return -1;
  }

  g_running = 1;
  int rc = fn(argc, argv);
  g_running = 0;
  return rc;
}

// ---------------------------------------------------------------------------
// 线程入口 —— 对应原版 0x41c4
// ---------------------------------------------------------------------------
static void* node_thread_entry(void* arg) {
  node_thread_ctx* ctx = (node_thread_ctx*)arg;
  int argc = ctx->argc;
  char** argv = ctx->argv;
  void* cb = ctx->cb;

  printf("[NodeWrapper] Thread started, argc=%d\n", argc);

  if (cb != NULL) {
    ((init_node_fn)cb)(NULL);
  }

  g_running = 1;

  node_start_fn fn = get_node_start();
  if (fn != NULL) {
    fn(argc, argv);
  }

  g_running = 0;
  free(ctx);
  return NULL;
}

// ---------------------------------------------------------------------------
// nodeStartThread —— 起独立线程跑 node_start，立即返回
//   返回 0 成功 / -1 失败（已有实例或内存、线程创建失败）
// ---------------------------------------------------------------------------
int nodeStartThread(int argc, char** argv, void* cb) {
  printf("[NodeWrapper] nodeStartThread called, argc=%d\n", argc);

  if (g_running || g_thread_valid) {
    puts("[NodeWrapper] Node.js is already running");
    return -1;
  }

  node_thread_ctx* ctx = (node_thread_ctx*)malloc(sizeof(node_thread_ctx));
  if (ctx == NULL) {
    return -1;
  }
  ctx->argc = argc;
  ctx->argv = argv;
  ctx->cb = cb;

  if (pthread_create(&g_thread, NULL, node_thread_entry, ctx) != 0) {
    free(ctx);
    return -1;
  }
  g_thread_valid = 1;
  pthread_detach(g_thread);
  return 0;
}

// ---------------------------------------------------------------------------
// nodeStop —— 只重置标志（NodeMobile 无 node_stop 导出，无法真实停止）
// ---------------------------------------------------------------------------
int nodeStop(void) {
  puts("[NodeWrapper] nodeStop called");
  g_running = 0;
  g_thread_valid = 0;
  return 0;
}
