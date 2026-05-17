BIN_DIR := bin
CLI := $(BIN_DIR)/beadsctl
UI := $(BIN_DIR)/beads-ui

.PHONY: all cli ui test fmt tidy clean cross

all: cli ui

cli:
	go build -o $(CLI) ./cmd/beadsctl

ui:
	go build -o $(UI) ./cmd/beads-ui

test:
	go test ./...

fmt:
	gofmt -w ./cmd ./internal

tidy:
	go mod tidy

cross:
	mkdir -p $(BIN_DIR)
	GOOS=darwin GOARCH=arm64 go build -o $(BIN_DIR)/beadsctl-darwin-arm64 ./cmd/beadsctl
	GOOS=darwin GOARCH=amd64 go build -o $(BIN_DIR)/beadsctl-darwin-amd64 ./cmd/beadsctl
	GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/beadsctl-linux-amd64 ./cmd/beadsctl
	GOOS=windows GOARCH=amd64 go build -o $(BIN_DIR)/beadsctl-windows-amd64.exe ./cmd/beadsctl

clean:
	rm -rf $(BIN_DIR)
