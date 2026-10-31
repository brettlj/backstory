// TestWorkflows guards .github/workflows/*.yml (task ce739911): every action
// is pinned to a full commit SHA, release.yml builds with the PKGBUILD's
// flags, runs only on v* tags, creates a draft, and only its release job
// holds write permissions. The YAML is checked as text (no YAML dependency);
// each rule is a function over file content so mutated copies can be tested.
package ops

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

var (
	usesLine   = regexp.MustCompile(`^\s*-?\s*uses:\s*(\S+)`)
	usesPinned = regexp.MustCompile(`^[^@\s]+@[0-9a-f]{40}$`)
	writePerm  = regexp.MustCompile(`^\s*(contents|id-token|attestations|security-events):\s*write\s*$`)
	indentOf   = func(s string) int { return len(s) - len(strings.TrimLeft(s, " ")) }
)

func readRepoFile(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", rel)) //nolint:gosec // fixed repo-relative path
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func unpinnedUses(text string) []string {
	var bad []string
	for _, l := range strings.Split(text, "\n") {
		if m := usesLine.FindStringSubmatch(l); m != nil && !usesPinned.MatchString(m[1]) {
			bad = append(bad, m[1])
		}
	}
	return bad
}

// buildFlags extracts the flag set shared by the PKGBUILD and release.yml,
// normalising the version token (v$pkgver vs ${TAG}).
func buildFlags(text string) []string {
	var out []string
	for _, re := range []string{
		`CGO_ENABLED=0`,
		`go build( -trimpath)?`,
		`-ldflags "-s -w -X github\.com/RidgetopAi/backstory/internal/version\.Version=`,
		`\./cmd/backstory`,
	} {
		out = append(out, regexp.MustCompile(re).FindString(text))
	}
	return out
}

// releaseProblems returns every violated release.yml rule.
func releaseProblems(release, pkgbuild string) []string {
	var p []string
	want, got := buildFlags(pkgbuild), buildFlags(release)
	for i := range want {
		if want[i] == "" {
			p = append(p, "PKGBUILD missing build flag pattern "+string(rune('0'+i)))
		} else if got[i] != want[i] {
			p = append(p, "release.yml build flag drift: want "+want[i]+" got "+got[i])
		}
	}
	if !regexp.MustCompile(`(?m)^on:\n  push:\n    tags:\n      - 'v\*'\n(\S|$)`).MatchString(release) {
		p = append(p, "release.yml must trigger only on push of v* tags")
	}
	if !regexp.MustCompile(`gh release create\b[^\n]*--draft`).MatchString(release) {
		p = append(p, "gh release create must use --draft")
	}
	if !strings.Contains(release, "actions/attest-build-provenance@") {
		p = append(p, "release.yml must use actions/attest-build-provenance")
	}
	return p
}

// writeScopes reports, per write permission line, the top-level job (or
// "<workflow>") that holds it.
func writeScopes(text string) []string {
	var scopes []string
	inJobs, job := false, ""
	for _, l := range strings.Split(text, "\n") {
		if strings.TrimSpace(l) == "" || strings.HasPrefix(strings.TrimSpace(l), "#") {
			continue
		}
		ind := indentOf(l)
		if ind == 0 {
			inJobs = strings.HasPrefix(l, "jobs:")
			job = ""
		} else if inJobs && ind == 2 && strings.HasSuffix(strings.TrimSpace(l), ":") {
			job = strings.TrimSuffix(strings.TrimSpace(l), ":")
		}
		if writePerm.MatchString(l) {
			if job == "" {
				job = "<workflow>"
			}
			scopes = append(scopes, job)
		}
	}
	return scopes
}

func TestWorkflowsPinnedToSHA(t *testing.T) {
	files, _ := filepath.Glob("../.github/workflows/*.yml")
	if len(files) == 0 {
		t.Fatal("no workflows found")
	}
	for _, f := range files {
		b, _ := os.ReadFile(f) //nolint:gosec // glob of tracked workflow files
		if bad := unpinnedUses(string(b)); len(bad) > 0 {
			t.Errorf("%s: uses: not pinned to a 40-hex SHA: %v", f, bad)
		}
	}
}

func TestReleaseWorkflowRules(t *testing.T) {
	for _, p := range releaseProblems(readRepoFile(t, ".github/workflows/release.yml"), readRepoFile(t, "ops/aur/PKGBUILD")) {
		t.Error(p)
	}
}

func TestWorkflowWritePermissionsOnlyReleaseAndScorecardJobs(t *testing.T) {
	files, _ := filepath.Glob("../.github/workflows/*.yml")
	for _, f := range files {
		b, _ := os.ReadFile(f) //nolint:gosec // glob of tracked workflow files
		for _, s := range writeScopes(string(b)) {
			base := filepath.Base(f)
			if !(base == "release.yml" && s == "release") && !(base == "scorecard.yml" && s == "analysis") {
				t.Errorf("%s: write permission held by %q; only release.yml's release job and scorecard.yml's analysis job may", f, s)
			}
		}
	}
	rel := readRepoFile(t, ".github/workflows/release.yml")
	if n := len(writeScopes(rel)); n != 3 {
		t.Errorf("release job must hold exactly contents/id-token/attestations write, found %d", n)
	}
	if !regexp.MustCompile(`(?m)^permissions:\n  contents: read\n`).MatchString(rel) {
		t.Error("release.yml default permissions must be contents: read")
	}
}

// scorecardProblems returns every violated scorecard.yml rule (task b85b5883).
func scorecardProblems(text string) []string {
	var p []string
	if !regexp.MustCompile(`(?m)^permissions: read-all\n`).MatchString(text) {
		p = append(p, "scorecard.yml default permissions must be read-all")
	}
	if got := writeScopes(text); len(got) != 2 || got[0] != "analysis" || got[1] != "analysis" {
		p = append(p, "scorecard.yml: only the analysis job may hold write permissions, exactly security-events and id-token")
	}
	for _, perm := range []string{"security-events", "id-token"} {
		if !regexp.MustCompile(`(?m)^      ` + perm + `: write\n`).MatchString(text) {
			p = append(p, "scorecard.yml job must hold "+perm+": write")
		}
	}
	if strings.Contains(text, "write-all") {
		p = append(p, "scorecard.yml must not use write-all")
	}
	if !regexp.MustCompile(`(?m)^on:\n  push:\n    branches:\n      - main\n  schedule:\n    - cron: '[^']+'\n  branch_protection_rule:\n(\S|$)`).MatchString(text) {
		p = append(p, "scorecard.yml must trigger on push to main, schedule, and branch_protection_rule only")
	}
	if !regexp.MustCompile(`uses: ossf/scorecard-action@[0-9a-f]{40}`).MatchString(text) {
		p = append(p, "scorecard.yml must run ossf/scorecard-action pinned to a SHA")
	}
	if !regexp.MustCompile(`publish_results: true`).MatchString(text) {
		p = append(p, "scorecard.yml must set publish_results: true")
	}
	if !regexp.MustCompile(`uses: github/codeql-action/upload-sarif@[0-9a-f]{40}`).MatchString(text) {
		p = append(p, "scorecard.yml must upload SARIF")
	}
	return p
}

func TestScorecardWorkflowRules(t *testing.T) {
	for _, p := range scorecardProblems(readRepoFile(t, ".github/workflows/scorecard.yml")) {
		t.Error(p)
	}
}

func TestCIVulncheckJob(t *testing.T) {
	ci := readRepoFile(t, ".github/workflows/ci.yml")
	if !regexp.MustCompile(`(?m)^  vulncheck:\n(?:    .*\n|\n)*?    permissions:\n      contents: read\n(?:    .*\n|\n)*?      - run: make vulncheck\n`).MatchString(ci) {
		t.Error("ci.yml needs a vulncheck job with contents: read running make vulncheck")
	}
	mk := readRepoFile(t, "Makefile")
	if regexp.MustCompile(`(?m)^check:.*vulncheck`).MatchString(mk) {
		t.Error("vulncheck must not be part of make check")
	}
	if !strings.Contains(mk, "GOVULNCHECK_VERSION ?= v1.9.0") {
		t.Error("govulncheck must be pinned to v1.9.0")
	}
}

// TestScorecardRulesDetectMutations proves the scorecard rules bite.
func TestScorecardRulesDetectMutations(t *testing.T) {
	sc := readRepoFile(t, ".github/workflows/scorecard.yml")
	if len(scorecardProblems(sc)) != 0 || len(unpinnedUses(sc)) != 0 {
		t.Fatal("control must be clean")
	}
	tagged := regexp.MustCompile(`scorecard-action@[0-9a-f]{40}`).ReplaceAllString(sc, "scorecard-action@v2.5.0")
	if len(unpinnedUses(tagged)) == 0 || len(scorecardProblems(tagged)) == 0 {
		t.Error("tag-pinned scorecard-action not detected")
	}
	for name, m := range map[string]string{
		"write-all":      strings.Replace(sc, "permissions: read-all", "permissions: write-all", 1),
		"extra write":    strings.Replace(sc, "      id-token: write\n", "      id-token: write\n      contents: write\n", 1),
		"no publish":     strings.Replace(sc, "publish_results: true", "publish_results: false", 1),
		"any branch":     strings.Replace(sc, "    branches:\n      - main\n", "", 1),
		"workflow-level": strings.Replace(sc, "permissions: read-all", "permissions:\n  security-events: write", 1),
	} {
		if len(scorecardProblems(m)) == 0 {
			t.Errorf("mutation %q not detected", name)
		}
	}
}

// TestWorkflowRulesDetectMutations proves the rules bite: each mutation of
// the real release.yml must be reported.
func TestWorkflowRulesDetectMutations(t *testing.T) {
	rel, pkg := readRepoFile(t, ".github/workflows/release.yml"), readRepoFile(t, "ops/aur/PKGBUILD")
	if len(releaseProblems(rel, pkg)) != 0 || len(unpinnedUses(rel)) != 0 {
		t.Fatal("control must be clean")
	}
	sha := regexp.MustCompile(`attest-build-provenance@[0-9a-f]{40}`)
	if len(unpinnedUses(sha.ReplaceAllString(rel, "attest-build-provenance@v4"))) == 0 {
		t.Error("tag-pinned uses not detected")
	}
	if len(releaseProblems(strings.Replace(rel, "--draft ", "", 1), pkg)) == 0 {
		t.Error("removed --draft not detected")
	}
	if len(releaseProblems(strings.Replace(rel, "-trimpath", "", 1), pkg)) == 0 {
		t.Error("dropped -trimpath not detected")
	}
	if len(releaseProblems(strings.Replace(rel, "- 'v*'", "- '*'", 1), pkg)) == 0 {
		t.Error("widened tag trigger not detected")
	}
	ci := readRepoFile(t, ".github/workflows/ci.yml")
	if len(writeScopes(strings.Replace(ci, "contents: read", "contents: write", 1))) == 0 {
		t.Error("write permission in ci not detected")
	}
}
