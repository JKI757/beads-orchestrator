package beads

import (
	"crypto/rand"
	"fmt"
	"strings"
	"time"
)

func FindBoard(boards []Board, key string) (int, error) {
	needle := strings.ToLower(strings.TrimSpace(key))
	if needle == "" {
		return -1, fmt.Errorf("board is required")
	}

	for i, board := range boards {
		if strings.ToLower(board.ID) == needle || strings.ToLower(board.Name) == needle {
			return i, nil
		}
	}
	for i, board := range boards {
		if strings.Contains(strings.ToLower(board.Name), needle) {
			return i, nil
		}
	}
	return -1, fmt.Errorf("board %q not found", key)
}

func FindColumn(columns []Column, key string) (int, error) {
	needle := strings.ToLower(strings.TrimSpace(key))
	if needle == "" {
		return -1, fmt.Errorf("column is required")
	}

	for i, column := range columns {
		if strings.ToLower(column.ID) == needle || strings.ToLower(column.Name) == needle {
			return i, nil
		}
	}
	for i, column := range columns {
		if strings.Contains(strings.ToLower(column.Name), needle) {
			return i, nil
		}
	}
	return -1, fmt.Errorf("column %q not found", key)
}

func AddBead(boards []Board, boardKey, columnKey string, bead Bead) ([]Board, Bead, error) {
	boardIndex, err := FindBoard(boards, boardKey)
	if err != nil {
		return boards, Bead{}, err
	}

	columnIndex, err := FindColumn(boards[boardIndex].Columns, columnKey)
	if err != nil {
		return boards, Bead{}, err
	}

	now := time.Now().UTC()
	if bead.ID == "" {
		bead.ID = NewUUID()
	}
	if bead.SourceType == "" {
		bead.SourceType = "manual"
	}
	if bead.Priority == "" {
		bead.Priority = "normal"
	}
	if bead.Labels == nil {
		bead.Labels = []string{}
	}
	bead.CreatedAt = now
	bead.UpdatedAt = now

	boards[boardIndex].Columns[columnIndex].Beads = append([]Bead{bead}, boards[boardIndex].Columns[columnIndex].Beads...)
	boards[boardIndex].UpdatedAt = now
	return boards, bead, nil
}

func MoveBead(boards []Board, boardKey, beadKey, targetColumnKey string) ([]Board, Bead, error) {
	boardIndex, err := FindBoard(boards, boardKey)
	if err != nil {
		return boards, Bead{}, err
	}

	targetColumnIndex, err := FindColumn(boards[boardIndex].Columns, targetColumnKey)
	if err != nil {
		return boards, Bead{}, err
	}

	sourceColumnIndex, sourceBeadIndex, bead, err := findBead(boards[boardIndex], beadKey)
	if err != nil {
		return boards, Bead{}, err
	}

	now := time.Now().UTC()
	sourceBeads := boards[boardIndex].Columns[sourceColumnIndex].Beads
	boards[boardIndex].Columns[sourceColumnIndex].Beads = append(sourceBeads[:sourceBeadIndex], sourceBeads[sourceBeadIndex+1:]...)
	bead.UpdatedAt = now
	boards[boardIndex].Columns[targetColumnIndex].Beads = append([]Bead{bead}, boards[boardIndex].Columns[targetColumnIndex].Beads...)
	boards[boardIndex].UpdatedAt = now
	return boards, bead, nil
}

func ArchiveBead(boards []Board, boardKey, beadKey string) ([]Board, Bead, error) {
	boardIndex, err := FindBoard(boards, boardKey)
	if err != nil {
		return boards, Bead{}, err
	}

	columnIndex, beadIndex, bead, err := findBead(boards[boardIndex], beadKey)
	if err != nil {
		return boards, Bead{}, err
	}

	now := time.Now().UTC()
	bead.UpdatedAt = now
	bead.ArchivedAt = &now
	boards[boardIndex].Columns[columnIndex].Beads[beadIndex] = bead
	boards[boardIndex].UpdatedAt = now
	return boards, bead, nil
}

func findBead(board Board, key string) (int, int, Bead, error) {
	needle := strings.ToLower(strings.TrimSpace(key))
	if needle == "" {
		return -1, -1, Bead{}, fmt.Errorf("bead is required")
	}

	for columnIndex, column := range board.Columns {
		for beadIndex, bead := range column.Beads {
			if strings.ToLower(bead.ID) == needle || strings.ToLower(bead.Title) == needle {
				return columnIndex, beadIndex, bead, nil
			}
		}
	}

	for columnIndex, column := range board.Columns {
		for beadIndex, bead := range column.Beads {
			if strings.Contains(strings.ToLower(bead.Title), needle) {
				return columnIndex, beadIndex, bead, nil
			}
		}
	}

	return -1, -1, Bead{}, fmt.Errorf("bead %q not found", key)
}

func NewUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}

	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
