package ops

import (
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
)

// panelBind is the panel toggle (Brian's call 2026-10-04): CTRL+SHIFT+B,
// because the old Super-based bind is Omarchy's stock Browser bind.
const panelBind = "CTRL + SHIFT + B"

func TestHyprlandBindsPanelToggleToCtrlShiftB(t *testing.T) {
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatal(err)
	}
	want := `local BACKSTORY_BIND = "` + panelBind + `"`
	if !strings.Contains(string(raw), want) {
		t.Errorf("hyprland/backstory.lua lacks %s", want)
	}
}

// TestHyprlandBindCommandDoesNotStartWithABracket: Hyprland's exec reads a
// leading [ ] as window rules (`exec [workspace 2] app`), so a bind command
// that opens with a shell test `[ ... ]` runs nothing (seen 2026-10-31 on
// Hyprland 0.56: the key did nothing while the same command after a prefix
// worked). The bind's shell test is written `test ...` instead.
func TestHyprlandBindCommandDoesNotStartWithABracket(t *testing.T) {
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatalf("read backstory.lua: %v", err)
	}
	m := regexp.MustCompile(`hl\.dsp\.exec_cmd\("\s*(.)`).FindAllStringSubmatch(string(raw), -1)
	if len(m) == 0 {
		t.Fatal("no hl.dsp.exec_cmd(\"...\") in hyprland/backstory.lua")
	}
	for _, c := range m {
		if c[1] == "[" {
			t.Errorf("an exec_cmd command starts with [, which Hyprland reads as window rules: %q", c[0])
		}
	}
}

// No tracked file but the CHANGELOG (history) may still pair the old Omarchy
// Browser bind with Backstory. The pattern is assembled so this file does not
// match itself.
func TestNoTrackedFileStillNamesOldBind(t *testing.T) {
	old := regexp.MustCompile(`(?i)super\s*\+\s*shift\s*\+\s*b\b`)
	out, err := gitLsFilesAtRoot()
	if err != nil {
		t.Fatalf("git ls-files: %v", err)
	}
	scanned := 0
	for _, rel := range strings.Split(strings.TrimRight(string(out), "\x00"), "\x00") {
		if rel == "CHANGELOG.md" || rel == "" {
			continue
		}
		b, err := os.ReadFile("../" + rel) //nolint:gosec // tracked path in this repo
		if err != nil {
			continue // deleted in the working tree, or a directory entry
		}
		scanned++
		if loc := old.FindIndex(b); loc != nil {
			t.Errorf("%s still names the old bind %q", rel, b[loc[0]:loc[1]])
		}
	}
	if scanned < 10 {
		t.Fatalf("scanned only %d tracked files; the guard is not reading the repo", scanned)
	}
}

// gitLsFilesAtRoot lists tracked files relative to the repo root (the test
// runs in ops/, so --full-name plus a "../" prefix addresses them correctly).
func gitLsFilesAtRoot() ([]byte, error) {
	cmd := exec.Command("git", "ls-files", "-z", "--full-name", "--", "..")
	return cmd.Output()
}

// TestHyprlandWindowruleMatchesPanelClass pins tasks 93f7c6fd/2606210b: the
// shipped Lua windowrule floats and sizes the window, matching class
// org.quickshell AND the exact title Panel.qml's windowTitle sets.
func TestHyprlandWindowruleMatchesPanelClass(t *testing.T) {
	qml, err := os.ReadFile("../panel/Panel.qml")
	if err != nil {
		t.Fatalf("read Panel.qml: %v", err)
	}
	m := regexp.MustCompile(`readonly property string windowTitle: "([^"]+)"`).FindSubmatch(qml)
	if m == nil {
		t.Fatal("Panel.qml declares no windowTitle")
	}
	title := string(m[1])

	if _, err := os.Stat("hyprland/backstory.conf"); err == nil {
		t.Error("backstory.conf must not exist (Omarchy uses Lua config)")
	}
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatalf("read backstory.lua: %v", err)
	}
	lua := string(raw)

	if !regexp.MustCompile(`title\s*=\s*"\^\(` + regexp.QuoteMeta(title) + `\)\$"`).MatchString(lua) {
		t.Errorf("lua title pattern does not match Panel.qml windowTitle %q", title)
	}
	if !regexp.MustCompile(`class\s*=\s*"\^\(org\\\\\.quickshell\)\$"`).MatchString(lua) {
		t.Error("lua must match class ^(org\\\\.quickshell)$")
	}
	main := mainWindowRule(t)
	if !regexp.MustCompile(`float\s*=\s*true`).MatchString(main) {
		t.Error("the window's rule must set float = true")
	}
	if !regexp.MustCompile(`size\s*=\s*\{\s*\d+\s*,\s*\d+\s*\}`).MatchString(main) {
		t.Error("the window's rule must set a size")
	}
	if !regexp.MustCompile(`o\.window\(|hl\.window_rule\(`).MatchString(lua) {
		t.Error("lua must call o.window or hl.window_rule")
	}
	// Task ddbbe8b7: helpers is not a resolvable module on Omarchy (it defines
	// the global `o`), so a require( call makes hyprland.lua error. Comments
	// are stripped so the install note may mention require.
	code := regexp.MustCompile(`(?m)--.*$`).ReplaceAllString(lua, "")
	if regexp.MustCompile(`\brequire\s*[("']`).MatchString(code) {
		t.Error("lua must not call require( — use the global o")
	}
}

// TestHyprlandWindowruleHidesThePopOutUntilPlaced: a pop-out opens the window
// under Panel.qml's windowTitle plus "-popout", which the rule floats and
// draws with no decorations, blur or animation, so nothing shows until the
// window sits where the popup's card is (seen 2026-10-31: without it, the
// border and glow showed for two frames at the window's usual place).
func TestHyprlandWindowruleHidesThePopOutUntilPlaced(t *testing.T) {
	qml, err := os.ReadFile("../panel/Panel.qml")
	if err != nil {
		t.Fatalf("read Panel.qml: %v", err)
	}
	m := regexp.MustCompile(`readonly property string windowTitle: "([^"]+)"`).FindSubmatch(qml)
	if m == nil {
		t.Fatal("Panel.qml declares no windowTitle")
	}
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatalf("read backstory.lua: %v", err)
	}
	code := regexp.MustCompile(`(?m)--.*$`).ReplaceAllString(string(raw), "")
	rule := regexp.MustCompile(`(?s)o\.window\(\{[^}]*title\s*=\s*"\^\(` + regexp.QuoteMeta(string(m[1])+"-popout") + `\)\$"\s*\},\s*\{([^}]*)\}\)`).FindStringSubmatch(code)
	if rule == nil {
		t.Fatalf("no rule for the pop-out title %q", string(m[1])+"-popout")
	}
	for _, want := range []string{`float\s*=\s*true`, `no_anim\s*=\s*true`, `decorate\s*=\s*false`, `no_blur\s*=\s*true`} {
		if !regexp.MustCompile(want).MatchString(rule[1]) {
			t.Errorf("the pop-out rule lacks %s:\n%s", want, rule[1])
		}
	}
}

// TestHyprlandWindowruleOpensWithoutAnimation: Hyprland does not animate the
// panel window, as it does not animate Omarchy's own panels
// (default/hypr/apps/omarchy-shell.lua sets no_anim for them). Those panels
// fade their card in themselves in QML, and so does Panel.qml
// (tst_panel_window.qml test_card_fades_in_on_every_open). Hyprland's window
// animation took about 300 ms to settle.
func TestHyprlandWindowruleOpensWithoutAnimation(t *testing.T) {
	if !regexp.MustCompile(`no_anim\s*=\s*true`).MatchString(mainWindowRule(t)) {
		t.Error("the window's rule must set no_anim = true")
	}
}

// mainWindowRule is the body of the window's own rule, o.window(BACKSTORY,
// {...}), comments stripped: the pop-out rule sets some of the same effects,
// so a check of the whole file would pass with them gone from this one.
func mainWindowRule(t *testing.T) string {
	t.Helper()
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatalf("read backstory.lua: %v", err)
	}
	code := regexp.MustCompile(`(?m)--.*$`).ReplaceAllString(string(raw), "")
	m := regexp.MustCompile(`(?s)o\.window\(BACKSTORY,\s*\{(.*?)\n\}\)`).FindStringSubmatch(code)
	if m == nil {
		t.Fatal("no o.window(BACKSTORY, {...}) rule in hyprland/backstory.lua")
	}
	return m[1]
}

// TestHyprlandWindowruleKeepsTheThemesShadow: the window is styled as any
// other window, so it keeps the theme's shadow (Norrsken's focus "glow").
// It once dropped it because, with no_anim, closing left the glow on screen
// as a ghost outline; on Hyprland 0.56 closing leaves none (seen 2026-10-31).
func TestHyprlandWindowruleKeepsTheThemesShadow(t *testing.T) {
	raw, err := os.ReadFile("hyprland/backstory.lua")
	if err != nil {
		t.Fatalf("read backstory.lua: %v", err)
	}
	code := regexp.MustCompile(`(?m)--.*$`).ReplaceAllString(string(raw), "")
	if regexp.MustCompile(`no_shadow\s*=`).MatchString(code) {
		t.Error("lua window rule must not set no_shadow: the window takes the theme's shadow")
	}
}
