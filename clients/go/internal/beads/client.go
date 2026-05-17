package beads

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Client struct {
	baseURL    *url.URL
	token      string
	httpClient *http.Client
}

func NewClient(serverURL, token string) (*Client, error) {
	trimmedURL := strings.TrimSpace(serverURL)
	if trimmedURL == "" {
		return nil, fmt.Errorf("server URL is required")
	}

	parsed, err := url.Parse(trimmedURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return nil, fmt.Errorf("server URL must include scheme and host, for example http://beads-mac.local:8787")
	}

	return &Client{
		baseURL: parsed,
		token:   strings.TrimSpace(token),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}, nil
}

func (c *Client) Health(ctx context.Context) (ServerInfo, error) {
	var info ServerInfo
	err := c.get(ctx, "health", false, &info)
	return info, err
}

func (c *Client) Verify(ctx context.Context) (ServerInfo, error) {
	var info ServerInfo
	err := c.get(ctx, "auth/verify", true, &info)
	return info, err
}

func (c *Client) Boards(ctx context.Context) ([]Board, error) {
	var boards []Board
	err := c.get(ctx, "boards", true, &boards)
	return boards, err
}

func (c *Client) LLMStatus(ctx context.Context) (LLMStatus, error) {
	var status LLMStatus
	err := c.get(ctx, "llm/status", true, &status)
	return status, err
}

func (c *Client) SuggestBeadFields(ctx context.Context, request BeadFieldSuggestionRequest) (BeadFieldSuggestionResponse, error) {
	var response BeadFieldSuggestionResponse
	err := c.post(ctx, "ai/bead-suggestions", request, true, &response)
	return response, err
}

func (c *Client) ReviewPlan(ctx context.Context, request BeadPlanReviewRequest) (BeadPlanReviewResponse, error) {
	var response BeadPlanReviewResponse
	err := c.post(ctx, "ai/plan-review", request, true, &response)
	return response, err
}

func (c *Client) StatusReport(ctx context.Context, request BeadStatusReportRequest) (BeadStatusReportResponse, error) {
	var response BeadStatusReportResponse
	err := c.post(ctx, "ai/status-report", request, true, &response)
	return response, err
}

func (c *Client) AIPMState(ctx context.Context) (AIPMState, error) {
	var state AIPMState
	err := c.get(ctx, "ai/pm/state", true, &state)
	return state, err
}

func (c *Client) UpdateAIPMSettings(ctx context.Context, settings AIPMAutomationSettings) (AIPMState, error) {
	var state AIPMState
	err := c.put(ctx, "ai/pm/settings", settings, true, &state)
	return state, err
}

func (c *Client) RunAIPM(ctx context.Context, request AIPMRunRequest) (AIPMState, error) {
	var state AIPMState
	err := c.post(ctx, "ai/pm/run", request, true, &state)
	return state, err
}

func (c *Client) ReplaceBoards(ctx context.Context, boards []Board) error {
	body, err := json.MarshalIndent(boards, "", "  ")
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, c.endpoint("boards"), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	c.authorize(req)
	return c.do(req, nil)
}

func (c *Client) get(ctx context.Context, path string, requiresAuth bool, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.endpoint(path), nil)
	if err != nil {
		return err
	}
	if requiresAuth {
		c.authorize(req)
	}
	return c.do(req, target)
}

func (c *Client) post(ctx context.Context, path string, body any, requiresAuth bool, target any) error {
	payload, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint(path), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if requiresAuth {
		c.authorize(req)
	}
	return c.do(req, target)
}

func (c *Client) put(ctx context.Context, path string, body any, requiresAuth bool, target any) error {
	payload, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, c.endpoint(path), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if requiresAuth {
		c.authorize(req)
	}
	return c.do(req, target)
}

func (c *Client) endpoint(path string) string {
	endpoint := *c.baseURL
	endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/" + strings.TrimLeft(path, "/")
	return endpoint.String()
}

func (c *Client) authorize(req *http.Request) {
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
}

func (c *Client) do(req *http.Request, target any) error {
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		message := strings.TrimSpace(string(body))
		if message == "" {
			message = resp.Status
		}
		return fmt.Errorf("server returned %s: %s", resp.Status, message)
	}

	if target == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(target)
}
