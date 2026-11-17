# Pink Hanoi — SWI-Prolog Tower of Hanoi

A browser-based Tower of Hanoi game with single-player and local pass-the-mouse multiplayer. Prolog owns the puzzle state and validates every move; the browser only renders server responses and manages the display timer.

## 🎮 Play the Game

**[Click here to play Pink Hanoi](https://tower-of-hanoi-2e5e.onrender.com)**

## Requirements

- SWI-Prolog **9.0 or newer** (uses the built-in HTTP, JSON, UUID, and list libraries).
- A modern desktop or mobile browser.
- No npm, build step, or third-party Prolog packages.

## Run

From this project directory:

```bash
swipl server.pl
```

The server starts on **http://localhost:8080**. Open that URL in your browser.

Alternatively, start the SWI-Prolog console with `swipl`, then load and start manually:

```prolog
?- [server].
?- start.
```

Stop the server with **Ctrl+C** in the terminal running SWI-Prolog.

## Project layout

```text
pink_hanoi/
├── server.pl          HTTP server, JSON endpoints, session state
├── hanoi.pl            Hanoi initialization, rules, move application, stars
├── players.pl          Multiplayer ranking and winner predicates
├── public/
│   ├── index.html      Page structure
│   ├── style.css       Baby-pink responsive styling and animations
│   └── script.js       Mouse interaction, rendering, timer, API client
├── tests/
│   └── test_hanoi.pl   Prolog rule tests
└── README.md
```

## API overview

- `POST /api/new` — create a single or multiplayer game.
- `GET /api/state?id=GAME_ID` — retrieve the public current state.
- `POST /api/move` — request a move (`id`, `from`, `to`).
- `POST /api/undo` — single-player undo only.
- `POST /api/restart` — single-player restart only.
- `POST /api/finish` — submit a completed turn's elapsed seconds.
- `POST /api/ready` — begin the next multiplayer player's turn.
- `GET /api/results?id=GAME_ID` — final multiplayer ranking (hidden until all players finish).

Every move is validated by Prolog. Invalid moves do not increment the move count. Multiplayer undo and restart are rejected server-side as well as omitted from the interface.

## Tests

Run the included Prolog unit tests:

```bash
swipl -q -g run_tests -t halt tests/test_hanoi.pl
```

The tests cover par values, legal/illegal moves, move application, and star thresholds.

## Notes

- Difficulty: Easy = 3 disks (par 7), Hard = 4 disks (par 15), Difficult = 5 disks (par 31).
- Multiplayer results are returned only after all players complete their turn.
- Ranking tie-breaks are applied by Prolog. All players with identical primary and tie-break scores are announced as winners.
- The browser timer is display-side timing; the submitted duration is stored by Prolog at turn completion.
