# ProcHive

A distributed binary execution system written in C. ProcHive separates the concerns of **compilation** and **execution** across machines — a coordinator server compiles C source files locally and dispatches the resulting ELF binaries to remote worker nodes over a custom TCP wire protocol.

---

## How It Works

```
Machine A (server)                        Machine B (node)
──────────────────                        ────────────────
1. User picks a .c file                   Listens on a TCP port
2. Compiles it via gcc → ELF binary       Handles MSG_QUERY_LOAD
3. Queries all nodes for load             Handles MSG_RUN_BINARY
4. Selects least-loaded node (or manual)  Forks binary, captures stdout+stderr
5. Sends binary over TCP                  Returns output to server
6. Prints the output
```

The node never compiles anything. It only receives a pre-compiled binary, executes it, and streams the output back. Multiple jobs can run concurrently on a node — each connection is handled in its own thread.

---

## Architecture

### Coordinator (server.c — Machine A)

- Maintains a registry of worker nodes (IP + port)
- Compiles `.c` files locally using `gcc` via `fork()` + `execlp()`
- Polls all registered nodes for their current active-job count (`MSG_QUERY_LOAD`)
- Dispatches the compiled binary to the chosen node (`MSG_RUN_BINARY`)
- Supports manual node selection or automatic least-loaded dispatch

### Worker Node (node.c — Machine B)

- Runs a persistent TCP listener
- Spawns a new `pthread` per incoming connection — fully concurrent
- Tracks active jobs with a mutex-protected counter (`g_active_jobs`)
- On `MSG_RUN_BINARY`: writes the binary to a temp file, `chmod 0700`, forks it, captures `stdout` + `stderr`, and sends the output back

### Wire Protocol (common.c / common.h)

All communication uses a simple binary protocol over TCP:

| Primitive | Format |
|-----------|--------|
| `send_u32` / `recv_u32` | 4-byte unsigned int in network byte order |
| `send_string` / `recv_string` | 4-byte length prefix + raw bytes |

Two message types:

| Tag | Value | Direction | Meaning |
|-----|-------|-----------|---------|
| `MSG_QUERY_LOAD` | `1` | server → node | Ask node for active job count |
| `MSG_RUN_BINARY` | `2` | server → node | Send compiled binary for execution |

---

## Project Structure

```
ProcHive/
├── server.c      # Coordinator — compiles, queries load, dispatches binary
├── node.c        # Worker — receives binary, executes, returns output
├── client.c      # Legacy standalone client (earlier design iteration)
├── common.c      # Wire protocol implementation
├── common.h      # Shared constants, message types, function declarations
├── sample.c      # Example C program to dispatch
└── Makefile      # Build targets: server, node, clean
```

---

## Build

> Requires GCC and POSIX-compliant Linux. Tested on Ubuntu/Debian.

```bash
# Build both binaries
make

# Build individually
make server
make node
make clean
```

Compiler flags: `-Wall -Wextra -O2 -g -lpthread`

---

## Usage

### 1. Start the worker node (Machine B)

```bash
./node 9010
```

The node will listen on port `9010` and wait for jobs from the server.
You can run multiple nodes on different ports on the same or different machines.

### 2. Start the server (Machine A)

```bash
./server
```

On startup, register one or more worker nodes by entering their IP and port. Type `done` when finished.

### 3. Server commands

| Command | Description |
|---------|-------------|
| `run`   | Pick a `.c` file from the current directory, compile it, and dispatch to a node |
| `nodes` | List all registered nodes and their current active-job load |
| `add`   | Register an additional node at runtime |
| `quit`  | Exit the server |

### Example session

```
> run

C files in current directory:
  [1] sample.c

Pick a file (1-1): 1
[server] Compiling sample.c locally...
[server] Compilation successful.
[server] Binary size: 16312 bytes

  Idx  IP Address           Port     Active Jobs
  ───  ──────────────────   ────────  ──────────
  [1]  127.0.0.1            9010      0

Select target node:
  [0]  Auto — send to least-loaded node (Node 1, load=0)
  [1]  127.0.0.1:9010  (load: 0)
Choice [0 = auto]: 0

╔══════════════════════════════════════════╗
║   OUTPUT from 127.0.0.1:9010             ║
╚══════════════════════════════════════════╝
Hello from server side execution
══════════════════════════════════════════
```

---

## Default Ports

| Component | Default Port |
|-----------|:---:|
| Node listener | `9010` |

Ports can be overridden at startup.

---

## Key Design Decisions

- **Compile on the coordinator, run on the node.** This cleanly separates the environment that has the source and toolchain (Machine A) from the execution environment (Machine B).
- **Thread-per-connection on the node.** Each incoming request gets its own `pthread`, allowing concurrent job execution. Load is tracked atomically with a mutex.
- **Short-lived connections.** Every message exchange (load query or binary dispatch) opens a fresh TCP connection and closes it when done. No persistent session state.
- **Binary-level dispatch.** The binary is read entirely into memory on the server side, transmitted as a length-prefixed byte stream, written to a temp file on the node, and executed directly.

---

## Limitations

- Linux only (uses `fork`, `execl`, `mkstemp`, POSIX threads, POSIX sockets)
- No execution timeout on the node — a runaway program blocks that thread indefinitely
- No authentication or access control between server and node
- GCC must be installed on Machine A (the coordinator)

---

## License

MIT
