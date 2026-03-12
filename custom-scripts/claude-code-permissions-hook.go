package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/BurntSushi/toml"
)

type config struct {
	Allow []rule `toml:"allow"`
	Deny  []rule `toml:"deny"`
}

type rule struct {
	Name                         string `toml:"name"`
	Tool                         string `toml:"tool"`
	CommandRegex                 string `toml:"command_regex"`
	CommandExcludeRegex          string `toml:"command_exclude_regex"`
	FilePathRegex                string `toml:"file_path_regex"`
	FilePathExcludeRegex         string `toml:"file_path_exclude_regex"`
	WorkingDirectoryRegex        string `toml:"working_directory_regex"`
	WorkingDirectoryExcludeRegex string `toml:"working_directory_exclude_regex"`
	SubagentType                 string `toml:"subagent_type"`
	ToolInputRegex               string `toml:"tool_input_regex"`
	ToolInputExcludeRegex        string `toml:"tool_input_exclude_regex"`
	Reason                       string `toml:"reason"`
}

type compiledRule struct {
	name                 string
	tool                 string
	commandRegex         *regexp.Regexp
	commandExcludeRegex  *regexp.Regexp
	filePathRegex        *regexp.Regexp
	filePathExcludeRegex *regexp.Regexp
	workingDirRegex      *regexp.Regexp
	workingDirExclude    *regexp.Regexp
	subagentType         string
	toolInputRegex       *regexp.Regexp
	toolInputExclude     *regexp.Regexp
	reason               string
}

type hookInput struct {
	ToolName  string         `json:"tool_name"`
	ToolInput map[string]any `json:"tool_input"`
}

type requestContext struct {
	Tool             string
	Command          string
	WorkingDirectory string
	SubagentType     string
	FilePaths        []string
	ToolInputJSON    string
}

type hookOutput struct {
	HookSpecificOutput permissionOutput `json:"hookSpecificOutput"`
}

type permissionOutput struct {
	HookEventName            string `json:"hookEventName"`
	PermissionDecision       string `json:"permissionDecision"`
	PermissionDecisionReason string `json:"permissionDecisionReason,omitempty"`
}

func main() {
	command, configPath, err := parseArgs(os.Args[1:])
	if err != nil {
		fatal(err)
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		fatal(err)
	}

	switch command {
	case "validate":
		fmt.Println("Config OK")
		return
	case "run":
		if err := run(cfg); err != nil {
			var denyErr denyDecisionError
			if errors.As(err, &denyErr) {
				writeDecision("deny", denyErr.Reason)
				os.Exit(2)
			}

			fatal(err)
		}
	default:
		fatal(fmt.Errorf("unknown command %q", command))
	}
}

func parseArgs(args []string) (string, string, error) {
	command := "run"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command = args[0]
		args = args[1:]
	}

	fs := flag.NewFlagSet(command, flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	configFlag := fs.String("config", "", "Path to permissions.toml")
	if err := fs.Parse(args); err != nil {
		return "", "", err
	}

	if fs.NArg() > 0 {
		return "", "", fmt.Errorf("unexpected arguments: %s", strings.Join(fs.Args(), " "))
	}

	configPath := *configFlag
	if configPath == "" {
		configPath = resolveDefaultConfigPath()
	}

	return command, configPath, nil
}

func resolveDefaultConfigPath() string {
	if configPath := os.Getenv("CLAUDE_PERMISSIONS_CONFIG"); configPath != "" {
		return configPath
	}

	if settingsDir := os.Getenv("SETTINGS_DIR"); settingsDir != "" {
		return filepath.Join(settingsDir, "settings", "claude", "permissions.toml")
	}

	homeDir, err := os.UserHomeDir()
	if err == nil && homeDir != "" {
		return filepath.Join(homeDir, "Git", "kitsune-settings", "settings", "claude", "permissions.toml")
	}

	return "settings/claude/permissions.toml"
}

func loadConfig(configPath string) (*compiledConfig, error) {
	var rawConfig config
	if _, err := toml.DecodeFile(configPath, &rawConfig); err != nil {
		return nil, fmt.Errorf("load config %q: %w", configPath, err)
	}

	allowRules, err := compileRules("allow", rawConfig.Allow)
	if err != nil {
		return nil, err
	}

	denyRules, err := compileRules("deny", rawConfig.Deny)
	if err != nil {
		return nil, err
	}

	return &compiledConfig{
		allowRules: allowRules,
		denyRules:  denyRules,
	}, nil
}

type compiledConfig struct {
	allowRules []compiledRule
	denyRules  []compiledRule
}

func compileRules(ruleSetName string, rules []rule) ([]compiledRule, error) {
	compiledRules := make([]compiledRule, 0, len(rules))
	for index, item := range rules {
		compiled, err := compileRule(item)
		if err != nil {
			return nil, fmt.Errorf("%s[%d]: %w", ruleSetName, index, err)
		}

		compiledRules = append(compiledRules, compiled)
	}

	return compiledRules, nil
}

func compileRule(item rule) (compiledRule, error) {
	commandRegex, err := compileOptionalRegex(item.CommandRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("command_regex: %w", err)
	}

	commandExcludeRegex, err := compileOptionalRegex(item.CommandExcludeRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("command_exclude_regex: %w", err)
	}

	filePathRegex, err := compileOptionalRegex(item.FilePathRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("file_path_regex: %w", err)
	}

	filePathExcludeRegex, err := compileOptionalRegex(item.FilePathExcludeRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("file_path_exclude_regex: %w", err)
	}

	workingDirRegex, err := compileOptionalRegex(item.WorkingDirectoryRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("working_directory_regex: %w", err)
	}

	workingDirExclude, err := compileOptionalRegex(item.WorkingDirectoryExcludeRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("working_directory_exclude_regex: %w", err)
	}

	toolInputRegex, err := compileOptionalRegex(item.ToolInputRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("tool_input_regex: %w", err)
	}

	toolInputExclude, err := compileOptionalRegex(item.ToolInputExcludeRegex)
	if err != nil {
		return compiledRule{}, fmt.Errorf("tool_input_exclude_regex: %w", err)
	}

	return compiledRule{
		name:                 item.Name,
		tool:                 item.Tool,
		commandRegex:         commandRegex,
		commandExcludeRegex:  commandExcludeRegex,
		filePathRegex:        filePathRegex,
		filePathExcludeRegex: filePathExcludeRegex,
		workingDirRegex:      workingDirRegex,
		workingDirExclude:    workingDirExclude,
		subagentType:         item.SubagentType,
		toolInputRegex:       toolInputRegex,
		toolInputExclude:     toolInputExclude,
		reason:               item.Reason,
	}, nil
}

func compileOptionalRegex(pattern string) (*regexp.Regexp, error) {
	if pattern == "" {
		return nil, nil
	}

	return regexp.Compile(pattern)
}

func run(cfg *compiledConfig) error {
	inputBytes, err := io.ReadAll(os.Stdin)
	if err != nil {
		return fmt.Errorf("read hook input: %w", err)
	}

	var input hookInput
	if err := json.Unmarshal(inputBytes, &input); err != nil {
		return fmt.Errorf("decode hook input: %w", err)
	}

	ctx, err := buildRequestContext(input)
	if err != nil {
		return err
	}

	if matchedRule, matched := findMatch(cfg.denyRules, ctx); matched {
		return denyDecisionError{Reason: decisionReason("deny", matchedRule)}
	}

	if matchedRule, matched := findMatch(cfg.allowRules, ctx); matched {
		writeDecision("allow", decisionReason("allow", matchedRule))
	}

	return nil
}

func buildRequestContext(input hookInput) (requestContext, error) {
	if input.ToolName == "" {
		return requestContext{}, errors.New("hook input did not include tool_name")
	}

	if input.ToolInput == nil {
		input.ToolInput = map[string]any{}
	}

	toolInputJSON, err := marshalToolInput(input.ToolInput)
	if err != nil {
		return requestContext{}, fmt.Errorf("encode tool_input for matching: %w", err)
	}

	return requestContext{
		Tool:             input.ToolName,
		Command:          stringField(input.ToolInput, "command"),
		WorkingDirectory: stringField(input.ToolInput, "working_directory"),
		SubagentType:     stringField(input.ToolInput, "subagent_type"),
		FilePaths:        collectPaths(input.ToolInput),
		ToolInputJSON:    toolInputJSON,
	}, nil
}

func marshalToolInput(toolInput map[string]any) (string, error) {
	encoded, err := json.Marshal(toolInput)
	if err != nil {
		return "", err
	}

	return string(encoded), nil
}

func stringField(values map[string]any, fieldName string) string {
	rawValue, ok := values[fieldName]
	if !ok {
		return ""
	}

	stringValue, ok := rawValue.(string)
	if !ok {
		return ""
	}

	return stringValue
}

func collectPaths(values map[string]any) []string {
	collected := []string{}
	appendUniquePaths(&collected, values, "")
	return collected
}

func appendUniquePaths(collected *[]string, value any, fieldName string) {
	switch typedValue := value.(type) {
	case map[string]any:
		for key, nestedValue := range typedValue {
			appendUniquePaths(collected, nestedValue, key)
		}
	case []any:
		if isPathListField(fieldName) {
			for _, item := range typedValue {
				stringValue, ok := item.(string)
				if ok && stringValue != "" {
					appendIfMissing(collected, stringValue)
				}
			}
			return
		}

		for _, item := range typedValue {
			appendUniquePaths(collected, item, fieldName)
		}
	case string:
		if isPathField(fieldName) && typedValue != "" {
			appendIfMissing(collected, typedValue)
		}
	}
}

func appendIfMissing(paths *[]string, value string) {
	for _, existing := range *paths {
		if existing == value {
			return
		}
	}

	*paths = append(*paths, value)
}

func isPathField(fieldName string) bool {
	switch fieldName {
	case "path", "file_path", "target_directory", "target_notebook", "downloadPath":
		return true
	default:
		return false
	}
}

func isPathListField(fieldName string) bool {
	switch fieldName {
	case "paths", "reference_image_paths", "attachments":
		return true
	default:
		return false
	}
}

func findMatch(rules []compiledRule, ctx requestContext) (compiledRule, bool) {
	for _, rule := range rules {
		if rule.matches(ctx) {
			return rule, true
		}
	}

	return compiledRule{}, false
}

func (rule compiledRule) matches(ctx requestContext) bool {
	if rule.tool != "" && rule.tool != ctx.Tool {
		return false
	}

	if rule.subagentType != "" && rule.subagentType != ctx.SubagentType {
		return false
	}

	if !matchesString(rule.commandRegex, rule.commandExcludeRegex, ctx.Command) {
		return false
	}

	if !matchesString(rule.workingDirRegex, rule.workingDirExclude, ctx.WorkingDirectory) {
		return false
	}

	if !matchesPaths(rule.filePathRegex, rule.filePathExcludeRegex, ctx.FilePaths) {
		return false
	}

	if !matchesString(rule.toolInputRegex, rule.toolInputExclude, ctx.ToolInputJSON) {
		return false
	}

	return true
}

func matchesString(includeRegex *regexp.Regexp, excludeRegex *regexp.Regexp, value string) bool {
	if excludeRegex != nil && excludeRegex.MatchString(value) {
		return false
	}

	if includeRegex == nil {
		return true
	}

	return includeRegex.MatchString(value)
}

func matchesPaths(includeRegex *regexp.Regexp, excludeRegex *regexp.Regexp, values []string) bool {
	if excludeRegex != nil {
		for _, value := range values {
			if excludeRegex.MatchString(value) {
				return false
			}
		}
	}

	if includeRegex == nil {
		return true
	}

	for _, value := range values {
		if includeRegex.MatchString(value) {
			return true
		}
	}

	return false
}

func decisionReason(decision string, rule compiledRule) string {
	if rule.reason != "" {
		return rule.reason
	}

	ruleLabel := rule.name
	if ruleLabel == "" {
		ruleLabel = "unnamed rule"
	}

	if decision == "allow" {
		return fmt.Sprintf("Allowed by %s.", ruleLabel)
	}

	return fmt.Sprintf("Blocked by %s.", ruleLabel)
}

func writeDecision(decision string, reason string) {
	output := hookOutput{
		HookSpecificOutput: permissionOutput{
			HookEventName:            "PreToolUse",
			PermissionDecision:       decision,
			PermissionDecisionReason: reason,
		},
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(output); err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

type denyDecisionError struct {
	Reason string
}

func (err denyDecisionError) Error() string {
	return err.Reason
}
