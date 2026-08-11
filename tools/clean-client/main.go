// clean-client removes the upstream web assets from the distroless Mattermost
// runtime before the pinned YourOwn.Chat client is copied into the image.
package main

import (
	"fmt"
	"os"
	"path/filepath"
)

const clientRoot = "/mattermost/client"

func main() {
	if len(os.Args) != 2 || os.Args[1] != clientRoot {
		fatalf("expected exactly %q", clientRoot)
	}

	info, err := os.Lstat(clientRoot)
	if err != nil {
		fatalf("inspect client root: %v", err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		fatalf("client root is not a real directory")
	}

	entries, err := os.ReadDir(clientRoot)
	if err != nil {
		fatalf("read client root: %v", err)
	}
	for _, entry := range entries {
		if err := os.RemoveAll(filepath.Join(clientRoot, entry.Name())); err != nil {
			fatalf("remove %q: %v", entry.Name(), err)
		}
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
