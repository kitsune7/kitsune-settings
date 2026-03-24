package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

const numWorkers = 10

type repoResult struct {
	name          string
	hasChanges    bool
	currentBranch string
	defaultBranch string
	offDefault    bool
	err           error
}

func discoverRepos(gitDir string) []string {
	entries, err := os.ReadDir(gitDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", gitDir, err)
		os.Exit(1)
	}

	var repos []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		repoPath := filepath.Join(gitDir, entry.Name())
		gitPath := filepath.Join(repoPath, ".git")
		if info, err := os.Stat(gitPath); err == nil && info.IsDir() {
			repos = append(repos, repoPath)
		}
	}
	return repos
}

func gitOutput(repoDir string, args ...string) (string, error) {
	fullArgs := append([]string{"-C", repoDir}, args...)
	cmd := exec.Command("git", fullArgs...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func getDefaultBranch(repoDir string) string {
	ref, err := gitOutput(repoDir, "symbolic-ref", "refs/remotes/origin/HEAD")
	if err == nil && ref != "" {
		return filepath.Base(ref)
	}

	for _, candidate := range []string{"main", "master", "develop"} {
		cmd := exec.Command("git", "-C", repoDir, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+candidate)
		if cmd.Run() == nil {
			return candidate
		}
	}

	return ""
}

func checkRepo(repoPath string) repoResult {
	name := filepath.Base(repoPath)
	result := repoResult{name: name}

	changes, err := gitOutput(repoPath, "status", "--porcelain")
	if err != nil {
		result.err = fmt.Errorf("git status failed: %w", err)
		return result
	}
	result.hasChanges = changes != ""

	currentBranch, err := gitOutput(repoPath, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		result.err = fmt.Errorf("git rev-parse failed: %w", err)
		return result
	}
	result.currentBranch = currentBranch

	defaultBranch := getDefaultBranch(repoPath)
	result.defaultBranch = defaultBranch

	if defaultBranch != "" && currentBranch != defaultBranch {
		result.offDefault = true
	}

	return result
}

func progressBar(done, total, width int) string {
	if total == 0 {
		return ""
	}
	filled := width * done / total
	if filled > width {
		filled = width
	}

	return strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
}

func getTermWidth() int {
	out, err := exec.Command("stty", "size").Output()
	if err != nil {
		return 80
	}
	parts := strings.Fields(strings.TrimSpace(string(out)))
	if len(parts) >= 2 {
		if w, err := strconv.Atoi(parts[1]); err == nil && w > 0 {
			return w
		}
	}
	return 80
}

func main() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	gitDir := filepath.Join(homeDir, "Git")

	repos := discoverRepos(gitDir)
	total := len(repos)

	if total == 0 {
		return
	}

	// Detect TTY by checking if stderr is connected to a terminal
	stderrStat, _ := os.Stderr.Stat()
	tty := (stderrStat.Mode() & os.ModeCharDevice) != 0
	termWidth := 80
	if tty {
		termWidth = getTermWidth()
	}

	jobs := make(chan string, total)
	results := make(chan repoResult, total)

	var wg sync.WaitGroup
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for repoPath := range jobs {
				results <- checkRepo(repoPath)
			}
		}()
	}

	for _, repo := range repos {
		jobs <- repo
	}
	close(jobs)

	go func() {
		wg.Wait()
		close(results)
	}()

	var collected []repoResult
	var completed atomic.Int32

	if tty {
		barWidth := termWidth - 20
		if barWidth < 10 {
			barWidth = 10
		}
		if barWidth > 50 {
			barWidth = 50
		}

		for result := range results {
			collected = append(collected, result)
			done := int(completed.Add(1))
			bar := progressBar(done, total, barWidth)
			line := fmt.Sprintf("\r  %s %d/%d", bar, done, total)
			if len(line) < termWidth {
				line += strings.Repeat(" ", termWidth-len(line))
			}
			fmt.Fprint(os.Stderr, line)
		}
		fmt.Fprintf(os.Stderr, "\r%s\r", strings.Repeat(" ", termWidth))
	} else {
		for result := range results {
			collected = append(collected, result)
		}
	}

	sort.Slice(collected, func(i, j int) bool {
		return collected[i].name < collected[j].name
	})

	first := true
	for _, r := range collected {
		if r.err != nil {
			if !first {
				fmt.Println()
			}
			first = false
			fmt.Println(r.name)
			fmt.Printf("  Error: %v\n", r.err)
			continue
		}

		if !r.hasChanges && !r.offDefault {
			continue
		}

		if !first {
			fmt.Println()
		}
		first = false

		fmt.Println(r.name)
		if r.hasChanges {
			fmt.Println("  Local changes")
		}
		if r.offDefault {
			fmt.Printf("  On branch: %s (default: %s)\n", r.currentBranch, r.defaultBranch)
		}
	}
}
