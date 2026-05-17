package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/JKI757/beads-orchestrator/clients/go/internal/beads"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	root := flag.NewFlagSet("beadsctl", flag.ExitOnError)
	serverURL := root.String("server", os.Getenv("BEADS_SERVER_URL"), "Beads-Orchestrator server URL")
	token := root.String("token", os.Getenv("BEADS_TOKEN"), "pairing bearer token")
	root.Usage = usage
	if err := root.Parse(args); err != nil {
		return err
	}

	if root.NArg() == 0 {
		usage()
		return nil
	}

	command := root.Arg(0)
	commandArgs := root.Args()[1:]

	client, err := beads.NewClient(*serverURL, *token)
	if err != nil && command != "help" {
		return err
	}

	ctx := context.Background()
	switch command {
	case "help":
		usage()
	case "health":
		info, err := client.Health(ctx)
		if err != nil {
			return err
		}
		printJSON(info)
	case "verify":
		info, err := client.Verify(ctx)
		if err != nil {
			return err
		}
		printJSON(info)
	case "boards":
		boards, err := client.Boards(ctx)
		if err != nil {
			return err
		}
		printBoards(boards)
	case "beads":
		return listBeads(ctx, client, commandArgs)
	case "pull":
		return pullBoards(ctx, client, commandArgs)
	case "push":
		return pushBoards(ctx, client, commandArgs)
	case "create-bead":
		return createBead(ctx, client, commandArgs)
	case "move-bead":
		return moveBead(ctx, client, commandArgs)
	case "archive-bead":
		return archiveBead(ctx, client, commandArgs)
	default:
		return fmt.Errorf("unknown command %q", command)
	}

	return nil
}

func listBeads(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("beads", flag.ExitOnError)
	boardKey := fs.String("board", "", "board name or ID")
	if err := fs.Parse(args); err != nil {
		return err
	}

	boards, err := client.Boards(ctx)
	if err != nil {
		return err
	}
	boardIndex, err := beads.FindBoard(boards, *boardKey)
	if err != nil {
		return err
	}

	board := boards[boardIndex]
	for _, column := range board.Columns {
		fmt.Printf("\n%s\n", column.Name)
		for _, bead := range column.Beads {
			if bead.ArchivedAt != nil {
				continue
			}
			fmt.Printf("  %s  [%s]  %s\n", bead.ID, bead.Priority, bead.Title)
			if bead.Summary != "" {
				fmt.Printf("      %s\n", bead.Summary)
			}
		}
	}
	return nil
}

func pullBoards(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("pull", flag.ExitOnError)
	outputPath := fs.String("out", "boards.json", "output JSON path")
	if err := fs.Parse(args); err != nil {
		return err
	}

	boards, err := client.Boards(ctx)
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(boards, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(*outputPath, append(data, '\n'), 0o644); err != nil {
		return err
	}
	fmt.Printf("wrote %d boards to %s\n", len(boards), *outputPath)
	return nil
}

func pushBoards(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("push", flag.ExitOnError)
	inputPath := fs.String("in", "boards.json", "input JSON path")
	if err := fs.Parse(args); err != nil {
		return err
	}

	data, err := os.ReadFile(*inputPath)
	if err != nil {
		return err
	}
	var boards []beads.Board
	if err := json.Unmarshal(data, &boards); err != nil {
		return err
	}
	if err := client.ReplaceBoards(ctx, boards); err != nil {
		return err
	}
	fmt.Printf("pushed %d boards from %s\n", len(boards), *inputPath)
	return nil
}

func createBead(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("create-bead", flag.ExitOnError)
	boardKey := fs.String("board", "", "board name or ID")
	columnKey := fs.String("column", "Backlog", "target column name or ID")
	title := fs.String("title", "", "bead title")
	summary := fs.String("summary", "", "bead summary")
	notes := fs.String("notes", "", "bead notes")
	priority := fs.String("priority", "normal", "low, normal, high, or urgent")
	labels := fs.String("labels", "", "comma-separated labels")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*title) == "" {
		return fmt.Errorf("title is required")
	}

	boards, err := client.Boards(ctx)
	if err != nil {
		return err
	}
	updatedBoards, bead, err := beads.AddBead(boards, *boardKey, *columnKey, beads.Bead{
		Title:      strings.TrimSpace(*title),
		Summary:    strings.TrimSpace(*summary),
		SourceType: "manual",
		Labels:     splitCSV(*labels),
		Priority:   strings.TrimSpace(*priority),
		Notes:      strings.TrimSpace(*notes),
	})
	if err != nil {
		return err
	}
	if err := client.ReplaceBoards(ctx, updatedBoards); err != nil {
		return err
	}
	fmt.Printf("created bead %s\n", bead.ID)
	return nil
}

func moveBead(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("move-bead", flag.ExitOnError)
	boardKey := fs.String("board", "", "board name or ID")
	beadKey := fs.String("bead", "", "bead title or ID")
	columnKey := fs.String("column", "", "target column name or ID")
	if err := fs.Parse(args); err != nil {
		return err
	}

	boards, err := client.Boards(ctx)
	if err != nil {
		return err
	}
	updatedBoards, bead, err := beads.MoveBead(boards, *boardKey, *beadKey, *columnKey)
	if err != nil {
		return err
	}
	if err := client.ReplaceBoards(ctx, updatedBoards); err != nil {
		return err
	}
	fmt.Printf("moved bead %s\n", bead.ID)
	return nil
}

func archiveBead(ctx context.Context, client *beads.Client, args []string) error {
	fs := flag.NewFlagSet("archive-bead", flag.ExitOnError)
	boardKey := fs.String("board", "", "board name or ID")
	beadKey := fs.String("bead", "", "bead title or ID")
	if err := fs.Parse(args); err != nil {
		return err
	}

	boards, err := client.Boards(ctx)
	if err != nil {
		return err
	}
	updatedBoards, bead, err := beads.ArchiveBead(boards, *boardKey, *beadKey)
	if err != nil {
		return err
	}
	if err := client.ReplaceBoards(ctx, updatedBoards); err != nil {
		return err
	}
	fmt.Printf("archived bead %s\n", bead.ID)
	return nil
}

func printBoards(boards []beads.Board) {
	for _, board := range boards {
		if board.ArchivedAt != nil {
			continue
		}
		count := 0
		for _, column := range board.Columns {
			for _, bead := range column.Beads {
				if bead.ArchivedAt == nil {
					count++
				}
			}
		}
		fmt.Printf("%s  %s  %d active beads\n", board.ID, board.Name, count)
	}
}

func printJSON(value any) {
	data, _ := json.MarshalIndent(value, "", "  ")
	fmt.Println(string(data))
}

func splitCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return []string{}
	}

	parts := strings.Split(value, ",")
	labels := make([]string, 0, len(parts))
	for _, part := range parts {
		label := strings.TrimSpace(part)
		if label != "" {
			labels = append(labels, label)
		}
	}
	return labels
}

func usage() {
	fmt.Fprintf(os.Stderr, `beadsctl manages a Beads-Orchestrator Mac server.

Usage:
  beadsctl --server http://mac.local:8787 --token TOKEN <command> [flags]

Environment:
  BEADS_SERVER_URL   default server URL
  BEADS_TOKEN        default pairing token

Commands:
  health                     Show unauthenticated server health
  verify                     Verify pairing token
  boards                     List boards
  beads --board NAME         List active beads for a board
  pull --out boards.json     Save board snapshot to JSON
  push --in boards.json      Replace server snapshot from JSON
  create-bead --board NAME --column Backlog --title TITLE [--summary TEXT] [--labels a,b]
  move-bead --board NAME --bead TITLE_OR_ID --column Ready
  archive-bead --board NAME --bead TITLE_OR_ID

`)
}
