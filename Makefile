# Makefile — Distributed Execution System
#
# Usage:
#   make          → build everything (server + node)
#   make server   → build only the server  (Machine A)
#   make node     → build only the node    (Machine B)
#   make clean    → remove compiled binaries

CC      = gcc
CFLAGS  = -Wall -Wextra -O2 -g
LDFLAGS = -lpthread

.PHONY: all server node clean

all: server node

server: server.c common.c common.h
	$(CC) $(CFLAGS) server.c common.c -o server $(LDFLAGS)
	@echo "✓ Built: server"

node: node.c common.c common.h
	$(CC) $(CFLAGS) node.c common.c -o node $(LDFLAGS)
	@echo "✓ Built: node"

clean:
	rm -f server node
	@echo "✓ Cleaned."
