// clean-client prepares the distroless Mattermost client tree. The clean mode
// removes upstream web assets before the pinned YourOwn.Chat client is copied;
// the finalize mode repairs the only runtime-writable part after that copy.
package main

import (
	"fmt"
	"os"
	"path/filepath"
)

const clientRoot = "/mattermost/client"

const mattermostRuntimeID = 2000

func main() {
	if len(os.Args) != 3 || os.Args[1] != clientRoot {
		fatalf("expected %q followed by clean or finalize", clientRoot)
	}

	info, err := os.Lstat(clientRoot)
	if err != nil {
		fatalf("inspect client root: %v", err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		fatalf("client root is not a real directory")
	}

	switch os.Args[2] {
	case "clean":
		entries, err := os.ReadDir(clientRoot)
		if err != nil {
			fatalf("read client root: %v", err)
		}
		for _, entry := range entries {
			if err := os.RemoveAll(filepath.Join(clientRoot, entry.Name())); err != nil {
				fatalf("remove %q: %v", entry.Name(), err)
			}
		}
	case "finalize":
	default:
		fatalf("unknown operation %q", os.Args[2])
	}

	pluginRoot := filepath.Join(clientRoot, "plugins")
	if err := os.MkdirAll(pluginRoot, 0o755); err != nil {
		fatalf("create plugin webapp root: %v", err)
	}
	if err := os.Chmod(pluginRoot, 0o755); err != nil {
		fatalf("set plugin webapp root mode: %v", err)
	}
	if err := os.Chown(pluginRoot, mattermostRuntimeID, mattermostRuntimeID); err != nil {
		fatalf("set plugin webapp root ownership: %v", err)
	}

	// The helper is build-time-only and must not survive in the final image.
	if err := os.Remove(os.Args[0]); err != nil {
		fatalf("remove cleanup helper: %v", err)
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "clean-client: "+format+"\n", args...)
	os.Exit(1)
}
