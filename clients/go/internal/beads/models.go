package beads

import "time"

type ServerInfo struct {
	Name         string     `json:"name"`
	Version      string     `json:"version"`
	BoardCount   int        `json:"boardCount"`
	UpdatedAt    time.Time  `json:"updatedAt"`
	AuthRequired bool       `json:"authRequired"`
	Capabilities []string   `json:"capabilities"`
	LLMStatus    *LLMStatus `json:"llmStatus,omitempty"`
}

type LLMStatus struct {
	IsAvailable bool      `json:"isAvailable"`
	Provider    string    `json:"provider"`
	Model       *string   `json:"model,omitempty"`
	Message     string    `json:"message"`
	UpdatedAt   time.Time `json:"updatedAt"`
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
	ID                 string     `json:"id"`
	BeadsID            *string    `json:"beadsID,omitempty"`
	IssueType          *string    `json:"issueType,omitempty"`
	Status             *string    `json:"status,omitempty"`
	ParentBeadsID      *string    `json:"parentBeadsID,omitempty"`
	ChildBeadsIDs      []string   `json:"childBeadsIDs,omitempty"`
	DependencyBeadsIDs []string   `json:"dependencyBeadsIDs,omitempty"`
	DependentBeadsIDs  []string   `json:"dependentBeadsIDs,omitempty"`
	DependencyCount    int        `json:"dependencyCount"`
	DependentCount     int        `json:"dependentCount"`
	Title              string     `json:"title"`
	Summary            string     `json:"summary"`
	SourceType         string     `json:"sourceType"`
	SourceURL          *string    `json:"sourceURL,omitempty"`
	BranchName         *string    `json:"branchName,omitempty"`
	IssueNumber        *int       `json:"issueNumber,omitempty"`
	PullRequestNumber  *int       `json:"pullRequestNumber,omitempty"`
	Labels             []string   `json:"labels"`
	Priority           string     `json:"priority"`
	IsBlocked          bool       `json:"isBlocked"`
	IsStale            bool       `json:"isStale"`
	Notes              string     `json:"notes"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
	ArchivedAt         *time.Time `json:"archivedAt,omitempty"`
}

type BeadDraft struct {
	Title              string   `json:"title"`
	BeadsID            *string  `json:"beadsID,omitempty"`
	IssueType          *string  `json:"issueType,omitempty"`
	Status             *string  `json:"status,omitempty"`
	ParentBeadsID      *string  `json:"parentBeadsID,omitempty"`
	ChildBeadsIDs      []string `json:"childBeadsIDs"`
	DependencyBeadsIDs []string `json:"dependencyBeadsIDs"`
	DependentBeadsIDs  []string `json:"dependentBeadsIDs"`
	DependencyCount    int      `json:"dependencyCount"`
	DependentCount     int      `json:"dependentCount"`
	Summary            string   `json:"summary"`
	SourceType         string   `json:"sourceType"`
	SourceURL          *string  `json:"sourceURL,omitempty"`
	BranchName         string   `json:"branchName"`
	IssueNumber        *int     `json:"issueNumber,omitempty"`
	PullRequestNumber  *int     `json:"pullRequestNumber,omitempty"`
	LabelsText         string   `json:"labelsText"`
	Priority           string   `json:"priority"`
	IsBlocked          bool     `json:"isBlocked"`
	IsStale            bool     `json:"isStale"`
	Notes              string   `json:"notes"`
}

type BeadFieldSuggestionRequest struct {
	BoardID       *string   `json:"boardID,omitempty"`
	EditingBeadID *string   `json:"editingBeadID,omitempty"`
	Draft         BeadDraft `json:"draft"`
}

type BeadFieldSuggestionResponse struct {
	Message     string                `json:"message"`
	Suggestions []BeadFieldSuggestion `json:"suggestions"`
	GeneratedAt time.Time             `json:"generatedAt"`
}

type BeadFieldSuggestion struct {
	Field     string `json:"field"`
	Value     string `json:"value"`
	Rationale string `json:"rationale"`
}

type BeadPlanReviewRequest struct {
	BoardID *string `json:"boardID,omitempty"`
	BeadID  string  `json:"beadID"`
	Scope   string  `json:"scope"`
}

type BeadPlanReviewResponse struct {
	Message     string                  `json:"message"`
	Findings    []BeadPlanReviewFinding `json:"findings"`
	Changes     []BeadPlanReviewChange  `json:"changes"`
	GeneratedAt time.Time               `json:"generatedAt"`
}

type BeadPlanReviewFinding struct {
	Severity string `json:"severity"`
	Category string `json:"category"`
	Title    string `json:"title"`
	Detail   string `json:"detail"`
}

type BeadPlanReviewChange struct {
	Kind          string   `json:"kind"`
	TargetBeadsID *string  `json:"targetBeadsID,omitempty"`
	Field         *string  `json:"field,omitempty"`
	Value         *string  `json:"value,omitempty"`
	Title         *string  `json:"title,omitempty"`
	Summary       *string  `json:"summary,omitempty"`
	Notes         *string  `json:"notes,omitempty"`
	Labels        []string `json:"labels,omitempty"`
	Priority      *string  `json:"priority,omitempty"`
	IssueType     *string  `json:"issueType,omitempty"`
	Rationale     string   `json:"rationale"`
}
