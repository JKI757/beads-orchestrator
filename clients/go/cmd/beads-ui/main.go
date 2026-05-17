package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
	"github.com/JKI757/beads-orchestrator/clients/go/internal/beads"
)

type uiState struct {
	window        fyne.Window
	client        *beads.Client
	boards        []beads.Board
	selectedBoard int
	boardList     *widget.List
	content       *fyne.Container
	status        *widget.Label
	serverEntry   *widget.Entry
	tokenEntry    *widget.Entry
}

func main() {
	a := app.NewWithID("com.beadsorchestrator.go")
	w := a.NewWindow("Beads-Orchestrator")
	w.Resize(fyne.NewSize(1100, 720))

	state := &uiState{
		window:        w,
		selectedBoard: -1,
		status:        widget.NewLabel("Enter a Mac server URL and pairing token."),
		content:       container.NewMax(),
	}

	state.serverEntry = widget.NewEntry()
	state.serverEntry.SetPlaceHolder("http://beads-mac.local:8787")
	state.serverEntry.SetText(os.Getenv("BEADS_SERVER_URL"))
	state.tokenEntry = widget.NewPasswordEntry()
	state.tokenEntry.SetPlaceHolder("Pairing token")
	state.tokenEntry.SetText(os.Getenv("BEADS_TOKEN"))

	connectButton := widget.NewButton("Connect", func() {
		state.connect()
	})
	refreshButton := widget.NewButton("Refresh", func() {
		state.refresh()
	})
	newBeadButton := widget.NewButton("New Bead", func() {
		state.showNewBeadDialog()
	})

	state.boardList = widget.NewList(
		func() int { return len(state.activeBoards()) },
		func() fyne.CanvasObject { return widget.NewLabel("Board") },
		func(id widget.ListItemID, object fyne.CanvasObject) {
			object.(*widget.Label).SetText(state.activeBoards()[id].Name)
		},
	)
	state.boardList.OnSelected = func(id widget.ListItemID) {
		state.selectedBoard = id
		state.renderBoard()
	}

	top := container.NewBorder(
		nil,
		nil,
		widget.NewLabel("Server"),
		container.NewHBox(connectButton, refreshButton, newBeadButton),
		container.NewGridWithColumns(2, state.serverEntry, state.tokenEntry),
	)
	left := container.NewBorder(widget.NewLabel("Boards"), nil, nil, nil, state.boardList)
	main := container.NewBorder(top, state.status, left, nil, state.content)
	w.SetContent(main)

	if state.serverEntry.Text != "" && state.tokenEntry.Text != "" {
		state.connect()
	}

	w.ShowAndRun()
}

func (s *uiState) connect() {
	client, err := beads.NewClient(s.serverEntry.Text, s.tokenEntry.Text)
	if err != nil {
		s.showError(err)
		return
	}
	s.client = client
	info, err := client.Verify(context.Background())
	if err != nil {
		s.showError(err)
		return
	}
	s.status.SetText(fmt.Sprintf("Connected to %s; %d boards", info.Name, info.BoardCount))
	s.refresh()
}

func (s *uiState) refresh() {
	if s.client == nil {
		s.connect()
		return
	}

	boards, err := s.client.Boards(context.Background())
	if err != nil {
		s.showError(err)
		return
	}
	s.boards = boards
	if s.selectedBoard < 0 && len(s.activeBoards()) > 0 {
		s.selectedBoard = 0
	}
	if s.selectedBoard >= len(s.activeBoards()) {
		s.selectedBoard = len(s.activeBoards()) - 1
	}
	s.boardList.Refresh()
	if s.selectedBoard >= 0 {
		s.boardList.Select(s.selectedBoard)
	}
	s.renderBoard()
	s.status.SetText(fmt.Sprintf("Loaded %d boards from Mac", len(s.activeBoards())))
}

func (s *uiState) renderBoard() {
	activeBoards := s.activeBoards()
	if s.selectedBoard < 0 || s.selectedBoard >= len(activeBoards) {
		s.content.Objects = []fyne.CanvasObject{
			container.NewCenter(widget.NewLabel("No board selected.")),
		}
		s.content.Refresh()
		return
	}

	board := activeBoards[s.selectedBoard]
	header := widget.NewRichTextFromMarkdown(fmt.Sprintf("## %s\n%s", board.Name, board.RepositoryName))
	columns := container.NewHBox()
	for _, column := range board.Columns {
		columnBox := container.NewVBox()
		count := 0
		for _, bead := range column.Beads {
			if bead.ArchivedAt != nil {
				continue
			}
			count++
			beadCopy := bead
			columnCopy := column
			card := widget.NewCard(
				bead.Title,
				strings.Join(bead.Labels, ", "),
				container.NewVBox(
					widget.NewLabel(bead.Summary),
					container.NewHBox(
						widget.NewButton("Details", func() {
							s.showBeadDetails(columnCopy.Name, beadCopy)
						}),
						widget.NewButton("Move", func() {
							s.showMoveDialog(board.ID, beadCopy)
						}),
						widget.NewButton("Archive", func() {
							s.archiveBead(board.ID, beadCopy.ID)
						}),
					),
				),
			)
			columnBox.Add(card)
		}
		columnTitle := widget.NewLabelWithStyle(fmt.Sprintf("%s (%d)", column.Name, count), fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
		columns.Add(container.NewVBox(columnTitle, container.NewVScroll(columnBox)))
	}

	s.content.Objects = []fyne.CanvasObject{
		container.NewBorder(header, nil, nil, nil, container.NewHScroll(columns)),
	}
	s.content.Refresh()
}

func (s *uiState) showNewBeadDialog() {
	activeBoards := s.activeBoards()
	if s.selectedBoard < 0 || s.selectedBoard >= len(activeBoards) {
		s.showError(fmt.Errorf("select a board first"))
		return
	}

	board := activeBoards[s.selectedBoard]
	title := widget.NewEntry()
	summary := widget.NewMultiLineEntry()
	labels := widget.NewEntry()
	priority := widget.NewSelect([]string{"low", "normal", "high", "urgent"}, nil)
	priority.SetSelected("normal")
	columnNames := make([]string, 0, len(board.Columns))
	for _, column := range board.Columns {
		columnNames = append(columnNames, column.Name)
	}
	columnSelect := widget.NewSelect(columnNames, nil)
	if len(columnNames) > 0 {
		columnSelect.SetSelected(columnNames[0])
	}

	form := widget.NewForm(
		widget.NewFormItem("Title", title),
		widget.NewFormItem("Summary", summary),
		widget.NewFormItem("Labels", labels),
		widget.NewFormItem("Priority", priority),
		widget.NewFormItem("Column", columnSelect),
	)
	dialog.NewCustomConfirm("New Bead", "Create", "Cancel", form, func(confirm bool) {
		if !confirm {
			return
		}
		if strings.TrimSpace(title.Text) == "" {
			s.showError(fmt.Errorf("title is required"))
			return
		}
		updatedBoards, _, err := beads.AddBead(s.boards, board.ID, columnSelect.Selected, beads.Bead{
			Title:      strings.TrimSpace(title.Text),
			Summary:    strings.TrimSpace(summary.Text),
			SourceType: "manual",
			Labels:     splitCSV(labels.Text),
			Priority:   priority.Selected,
		})
		if err != nil {
			s.showError(err)
			return
		}
		s.saveBoards(updatedBoards)
	}, s.window).Show()
}

func (s *uiState) showMoveDialog(boardID string, bead beads.Bead) {
	boardIndex, err := beads.FindBoard(s.boards, boardID)
	if err != nil {
		s.showError(err)
		return
	}
	columnNames := make([]string, 0, len(s.boards[boardIndex].Columns))
	for _, column := range s.boards[boardIndex].Columns {
		columnNames = append(columnNames, column.Name)
	}
	columnSelect := widget.NewSelect(columnNames, nil)
	if len(columnNames) > 0 {
		columnSelect.SetSelected(columnNames[0])
	}
	dialog.NewCustomConfirm("Move Bead", "Move", "Cancel", columnSelect, func(confirm bool) {
		if !confirm {
			return
		}
		updatedBoards, _, err := beads.MoveBead(s.boards, boardID, bead.ID, columnSelect.Selected)
		if err != nil {
			s.showError(err)
			return
		}
		s.saveBoards(updatedBoards)
	}, s.window).Show()
}

func (s *uiState) archiveBead(boardID, beadID string) {
	updatedBoards, bead, err := beads.ArchiveBead(s.boards, boardID, beadID)
	if err != nil {
		s.showError(err)
		return
	}
	s.saveBoards(updatedBoards)
	s.status.SetText("Archived " + bead.Title)
}

func (s *uiState) showBeadDetails(columnName string, bead beads.Bead) {
	body := widget.NewLabel(fmt.Sprintf("Column: %s\nPriority: %s\n\n%s\n\n%s", columnName, bead.Priority, bead.Summary, bead.Notes))
	body.Wrapping = fyne.TextWrapWord
	dialog.ShowCustom(bead.Title, "Close", container.NewScroll(body), s.window)
}

func (s *uiState) saveBoards(updatedBoards []beads.Board) {
	if s.client == nil {
		s.showError(fmt.Errorf("connect to a server first"))
		return
	}
	if err := s.client.ReplaceBoards(context.Background(), updatedBoards); err != nil {
		s.showError(err)
		return
	}
	s.boards = updatedBoards
	s.boardList.Refresh()
	s.renderBoard()
	s.status.SetText("Saved to Mac server")
}

func (s *uiState) activeBoards() []beads.Board {
	active := make([]beads.Board, 0, len(s.boards))
	for _, board := range s.boards {
		if board.ArchivedAt == nil {
			active = append(active, board)
		}
	}
	return active
}

func (s *uiState) showError(err error) {
	s.status.SetText(err.Error())
	dialog.ShowError(err, s.window)
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
