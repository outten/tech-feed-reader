/* Daily Sudoku — grid interaction, timer, autosave
 * Idempotent via data-sudoku-wired sentinel (Turbo 8 safe).
 */
(function () {
  'use strict';

  function init() {
    const board = document.getElementById('sudoku-board');
    if (!board || board.dataset.sudokuWired) return;
    board.dataset.sudokuWired = '1';

    // ── state ──────────────────────────────────────────────────────────────
    const puzzleId  = board.dataset.puzzleId;
    const clues     = board.dataset.clues;          // 81-char string, '0'=blank
    const solution  = board.dataset.solution;
    let   cells     = board.dataset.board.split(''); // mutable current state
    let   notes     = JSON.parse(board.dataset.notes || '{}');
    let   elapsed   = parseInt(board.dataset.elapsed, 10) || 0;
    let   solved    = board.dataset.solved === 'true';
    let   notesMode = false;
    let   selected  = null;  // currently focused cell index (0-80)
    let   timerHandle;

    // ── build grid ─────────────────────────────────────────────────────────
    for (let i = 0; i < 81; i++) {
      const cell = document.createElement('div');
      cell.className = 'sudoku-cell';
      cell.dataset.idx = i;
      cell.setAttribute('role', 'gridcell');

      const isClue = clues[i] !== '0';
      if (isClue) {
        cell.classList.add('sudoku-clue');
        cell.textContent = clues[i];
        cell.setAttribute('aria-label', `Given: ${clues[i]}`);
      } else {
        cell.setAttribute('tabindex', '0');
        renderCell(cell, i);
      }

      // thick borders for box edges
      const r = Math.floor(i / 9), c = i % 9;
      if (r % 3 === 0) cell.classList.add('box-top');
      if (c % 3 === 0) cell.classList.add('box-left');
      if (r === 8)     cell.classList.add('box-bottom');
      if (c === 8)     cell.classList.add('box-right');

      cell.addEventListener('click',  () => selectCell(i));
      cell.addEventListener('focus',  () => selectCell(i));
      cell.addEventListener('keydown', onCellKey);
      board.appendChild(cell);
    }

    // ── numpad ─────────────────────────────────────────────────────────────
    document.querySelectorAll('.sudoku-numpad-btn').forEach(btn => {
      btn.addEventListener('click', () => enterDigit(parseInt(btn.dataset.digit, 10)));
    });

    // ── control buttons ────────────────────────────────────────────────────
    const notesToggle = document.getElementById('sudoku-notes-toggle');
    if (notesToggle) {
      notesToggle.addEventListener('click', () => {
        notesMode = !notesMode;
        notesToggle.classList.toggle('active', notesMode);
        notesToggle.setAttribute('aria-pressed', notesMode);
      });
    }

    const checkBtn = document.getElementById('sudoku-check');
    if (checkBtn) checkBtn.addEventListener('click', checkBoard);

    const resetBtn = document.getElementById('sudoku-reset');
    if (resetBtn) resetBtn.addEventListener('click', resetBoard);

    // ── timer ──────────────────────────────────────────────────────────────
    updateTimerDisplay();
    if (!solved) {
      timerHandle = setInterval(() => {
        elapsed++;
        updateTimerDisplay();
      }, 1000);
    }

    // ── autosave ───────────────────────────────────────────────────────────
    let savePending = false;
    function scheduleSave(force) {
      if (force) { doSave(); return; }
      if (!savePending) {
        savePending = true;
        setTimeout(() => { doSave(); savePending = false; }, 3000);
      }
    }

    function doSave(completedFlag) {
      fetch(`/games/sudoku/${puzzleId}/state`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          board:        cells.join(''),
          notes:        notes,
          elapsed_secs: elapsed,
          completed:    !!completedFlag
        })
      }).catch(() => {});
    }

    // ── helpers ────────────────────────────────────────────────────────────
    function cellEl(idx) {
      return board.querySelector(`.sudoku-cell[data-idx="${idx}"]`);
    }

    function renderCell(el, idx) {
      if (!el) el = cellEl(idx);
      if (!el || el.classList.contains('sudoku-clue')) return;

      el.innerHTML = '';
      const val = cells[idx];

      if (val !== '0') {
        el.textContent = val;
        el.removeAttribute('aria-label');
        if (solution[idx] !== val) {
          el.classList.add('sudoku-error');
        } else {
          el.classList.remove('sudoku-error');
        }
      } else {
        const cellNotes = notes[String(idx)];
        if (cellNotes && cellNotes.length) {
          const noteGrid = document.createElement('div');
          noteGrid.className = 'sudoku-notes-grid';
          for (let d = 1; d <= 9; d++) {
            const span = document.createElement('span');
            span.textContent = cellNotes.includes(d) ? d : '';
            noteGrid.appendChild(span);
          }
          el.appendChild(noteGrid);
          el.setAttribute('aria-label', `Notes: ${cellNotes.join(',')}`);
        } else {
          el.setAttribute('aria-label', 'Empty');
        }
      }
    }

    function selectCell(idx) {
      if (selected !== null) {
        const prev = cellEl(selected);
        if (prev) prev.classList.remove('selected');
        // clear row/col/box highlights
        board.querySelectorAll('.sudoku-highlight').forEach(el => el.classList.remove('sudoku-highlight'));
        board.querySelectorAll('.sudoku-same-digit').forEach(el => el.classList.remove('sudoku-same-digit'));
      }
      selected = idx;
      const el = cellEl(idx);
      if (!el) return;
      el.classList.add('selected');

      const r = Math.floor(idx / 9), c = idx % 9;
      const br = Math.floor(r / 3) * 3, bc = Math.floor(c / 3) * 3;
      const digit = cells[idx];

      for (let i = 0; i < 81; i++) {
        const ir = Math.floor(i / 9), ic = i % 9;
        const sameHouse = ir === r || ic === c || (Math.floor(ir / 3) * 3 === br && Math.floor(ic / 3) * 3 === bc);
        const ce = cellEl(i);
        if (!ce) continue;
        if (i !== idx && sameHouse) ce.classList.add('sudoku-highlight');
        if (digit !== '0' && cells[i] === digit) ce.classList.add('sudoku-same-digit');
      }
    }

    function enterDigit(digit) {
      if (solved) return;
      if (selected === null) return;
      if (clues[selected] !== '0') return;

      if (notesMode && digit !== 0) {
        const key = String(selected);
        const cur = notes[key] || [];
        notes[key] = cur.includes(digit)
          ? cur.filter(d => d !== digit)
          : [...cur, digit].sort();
        cells[selected] = '0';
      } else {
        cells[selected] = String(digit);
        delete notes[String(selected)];
      }

      renderCell(null, selected);
      selectCell(selected);
      scheduleSave();

      if (isSolved()) onSolved();
    }

    function onCellKey(e) {
      const idx = parseInt(e.currentTarget.dataset.idx, 10);
      if (isNaN(idx)) return;

      if (e.key >= '1' && e.key <= '9') {
        selectCell(idx);
        enterDigit(parseInt(e.key, 10));
        e.preventDefault();
      } else if (e.key === '0' || e.key === 'Backspace' || e.key === 'Delete') {
        selectCell(idx);
        enterDigit(0);
        e.preventDefault();
      } else if (e.key === 'n' || e.key === 'N') {
        notesMode = !notesMode;
        if (notesToggle) {
          notesToggle.classList.toggle('active', notesMode);
          notesToggle.setAttribute('aria-pressed', notesMode);
        }
      } else {
        const moves = { ArrowUp: -9, ArrowDown: 9, ArrowLeft: -1, ArrowRight: 1 };
        if (moves[e.key] !== undefined) {
          const next = idx + moves[e.key];
          if (next >= 0 && next < 81) {
            selectCell(next);
            const nextEl = cellEl(next);
            if (nextEl) nextEl.focus();
          }
          e.preventDefault();
        }
      }
    }

    function isSolved() {
      return cells.join('') === solution;
    }

    function onSolved() {
      solved = true;
      clearInterval(timerHandle);
      doSave(true);
      board.classList.add('sudoku-complete');
      showMessage('🎉 Solved! Time: ' + formatElapsed(elapsed), 'success');
      const badge = document.querySelector('.sudoku-solved-badge');
      if (!badge) {
        const b = document.createElement('span');
        b.className = 'badge sudoku-solved-badge';
        b.textContent = '✓ Solved';
        const hdr = document.querySelector('.sudoku-header-right');
        if (hdr) hdr.appendChild(b);
      }
    }

    function checkBoard() {
      let errors = 0;
      for (let i = 0; i < 81; i++) {
        if (cells[i] !== '0' && cells[i] !== solution[i]) errors++;
      }
      if (errors === 0 && cells.join('').indexOf('0') === -1) {
        onSolved();
      } else if (errors > 0) {
        showMessage(`${errors} error${errors > 1 ? 's' : ''} found — incorrect cells are highlighted in red.`, 'error');
      } else {
        showMessage('Looking good so far — no errors.', 'info');
      }
    }

    function resetBoard() {
      if (!confirm('Reset the puzzle? Your progress will be lost.')) return;
      cells = clues.split('');
      notes = {};
      board.querySelectorAll('.sudoku-cell:not(.sudoku-clue)').forEach(el => {
        const i = parseInt(el.dataset.idx, 10);
        renderCell(el, i);
        el.classList.remove('sudoku-error');
      });
      doSave();
      showMessage('', '');
    }

    function updateTimerDisplay() {
      const el = document.getElementById('sudoku-timer');
      if (el) el.textContent = formatElapsed(elapsed);
    }

    function formatElapsed(s) {
      const m = Math.floor(s / 60), sec = s % 60;
      const h = Math.floor(m / 60), min = m % 60;
      return h > 0
        ? `${h}:${String(min).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
        : `${min}:${String(sec).padStart(2, '0')}`;
    }

    function showMessage(text, type) {
      const el = document.getElementById('sudoku-message');
      if (!el) return;
      el.textContent = text;
      el.className = `sudoku-message sudoku-message-${type}`;
    }
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
