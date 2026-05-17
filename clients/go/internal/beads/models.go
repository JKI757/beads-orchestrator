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
	IsAvailable             bool      `json:"isAvailable"`
	Provider                string    `json:"provider"`
	Model                   *string   `json:"model,omitempty"`
	Message                 string    `json:"message"`
	LastLatencyMilliseconds *int      `json:"lastLatencyMilliseconds,omitempty"`
	LastFailureMessage      *string   `json:"lastFailureMessage,omitempty"`
	UpdatedAt               time.Time `json:"updatedAt"`
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

type BeadStatusReportRequest struct {
	BoardID *string `json:"boardID,omitempty"`
	BeadID  *string `json:"beadID,omitempty"`
	Scope   string  `json:"scope"`
}

type BeadStatusReportResponse struct {
	Title       string                    `json:"title"`
	Summary     string                    `json:"summary"`
	Sections    []BeadStatusReportSection `json:"sections"`
	GeneratedAt time.Time                 `json:"generatedAt"`
}

type BeadStatusReportSection struct {
	Title string   `json:"title"`
	Items []string `json:"items"`
}

type AIPMAutomationSettings struct {
	IsEnabled                 bool   `json:"isEnabled"`
	Cadence                   string `json:"cadence"`
	AutonomyLevel             string `json:"autonomyLevel"`
	ReviewsBacklog            bool   `json:"reviewsBacklog"`
	GeneratesReports          bool   `json:"generatesReports"`
	MaximumProposals          int    `json:"maximumProposals"`
	SendsNotifications        bool   `json:"sendsNotifications"`
	NotifiesHighRiskProposals bool   `json:"notifiesHighRiskProposals"`
	NotifiesRunFailures       bool   `json:"notifiesRunFailures"`
}

type AIPMState struct {
	Settings           AIPMAutomationSettings   `json:"settings"`
	LastRunAt          *time.Time               `json:"lastRunAt,omitempty"`
	LastRunSummary     *string                  `json:"lastRunSummary,omitempty"`
	LastRunError       *string                  `json:"lastRunError,omitempty"`
	NextRunAt          *time.Time               `json:"nextRunAt,omitempty"`
	LatestIntelligence *AIPMProjectIntelligence `json:"latestIntelligence,omitempty"`
	Proposals          []AIPMDecisionProposal   `json:"proposals"`
	Reports            []AIPMReportSnapshot     `json:"reports"`
	AuditEvents        []AIPMAuditEvent         `json:"auditEvents"`
	UpdatedAt          time.Time                `json:"updatedAt"`
}

type AIPMDecisionProposal struct {
	ID        string                 `json:"id"`
	Title     string                 `json:"title"`
	Summary   string                 `json:"summary"`
	Category  string                 `json:"category"`
	Risk      string                 `json:"risk"`
	Rationale string                 `json:"rationale"`
	Changes   []BeadPlanReviewChange `json:"changes"`
	Status    string                 `json:"status"`
	CreatedAt time.Time              `json:"createdAt"`
}

type AIPMReportSnapshot struct {
	ID          string                    `json:"id"`
	Title       string                    `json:"title"`
	Summary     string                    `json:"summary"`
	Sections    []BeadStatusReportSection `json:"sections"`
	GeneratedAt time.Time                 `json:"generatedAt"`
}

type AIPMAuditEvent struct {
	ID            string                `json:"id"`
	Kind          string                `json:"kind"`
	Actor         string                `json:"actor"`
	Summary       string                `json:"summary"`
	ProposalID    *string               `json:"proposalID,omitempty"`
	ProposalTitle *string               `json:"proposalTitle,omitempty"`
	Change        *BeadPlanReviewChange `json:"change,omitempty"`
	ResultStatus  *string               `json:"resultStatus,omitempty"`
	ResultMessage *string               `json:"resultMessage,omitempty"`
	CreatedAt     time.Time             `json:"createdAt"`
}

type AIPMProjectIntelligence struct {
	BoardID          string              `json:"boardID"`
	BoardName        string              `json:"boardName"`
	TotalActiveBeads int                 `json:"totalActiveBeads"`
	BlockedBeads     int                 `json:"blockedBeads"`
	StaleBeads       int                 `json:"staleBeads"`
	UrgentBeads      int                 `json:"urgentBeads"`
	OrphanedChildren int                 `json:"orphanedChildren"`
	DependencyIssues int                 `json:"dependencyIssues"`
	Signals          []AIPMProjectSignal `json:"signals"`
	GeneratedAt      time.Time           `json:"generatedAt"`
}

type AIPMProjectSignal struct {
	ID       string   `json:"id"`
	Severity string   `json:"severity"`
	Category string   `json:"category"`
	Title    string   `json:"title"`
	Detail   string   `json:"detail"`
	BeadIDs  []string `json:"beadIDs"`
}

type AIPMRunRequest struct {
	BoardID *string `json:"boardID,omitempty"`
}
