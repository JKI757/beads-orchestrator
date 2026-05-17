package beads

import "time"

type ServerInfo struct {
	Name         string    `json:"name"`
	Version      string    `json:"version"`
	BoardCount   int       `json:"boardCount"`
	UpdatedAt    time.Time `json:"updatedAt"`
	AuthRequired bool      `json:"authRequired"`
	Capabilities []string  `json:"capabilities"`
}

type Board struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	RepositoryName string     `json:"repositoryName"`
	RepositoryPath *string    `json:"repositoryPath,omitempty"`
	Columns        []Column   `json:"columns"`
	UpdatedAt      time.Time  `json:"updatedAt"`
	ArchivedAt     *time.Time `json:"archivedAt,omitempty"`
}

type Column struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Beads []Bead `json:"beads"`
}

type Bead struct {
	ID                string     `json:"id"`
	Title             string     `json:"title"`
	Summary           string     `json:"summary"`
	SourceType        string     `json:"sourceType"`
	SourceURL         *string    `json:"sourceURL,omitempty"`
	BranchName        *string    `json:"branchName,omitempty"`
	IssueNumber       *int       `json:"issueNumber,omitempty"`
	PullRequestNumber *int       `json:"pullRequestNumber,omitempty"`
	Labels            []string   `json:"labels"`
	Priority          string     `json:"priority"`
	IsBlocked         bool       `json:"isBlocked"`
	IsStale           bool       `json:"isStale"`
	Notes             string     `json:"notes"`
	CreatedAt         time.Time  `json:"createdAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`
	ArchivedAt        *time.Time `json:"archivedAt,omitempty"`
}
