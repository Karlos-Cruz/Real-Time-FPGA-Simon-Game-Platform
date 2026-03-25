# Real-Time FPGA Simon Game Platform

VHDL • Python • WebSockets • React/Vite • UART Communication

A full-stack hardware/software system implementing the classic Simon game on a Xilinx Basys3 FPGA, with real-time bidirectional communication to a web dashboard.

---

## Overview

This project integrates FPGA hardware, a Python communication bridge, and a web-based dashboard to create a fully interactive real-time system.

The FPGA handles all game logic, while the web interface allows visualization and remote control of the game through a WebSocket connection.

---

## System Architecture

![System Architecture](docs/architecture.png)

The system is composed of three main layers:

### FPGA (Basys3)

* Implements the Simon game using VHDL
* Handles:

  * Button inputs
  * Game logic (FSM)
  * LED patterns
  * 7-segment display

### Python Bridge

* Connects FPGA ↔ Web
* Converts:

  * UART serial data → WebSocket messages
  * Web inputs → UART signals

### Web Dashboard (React + Vite)

* Displays game state in real time
* Sends inputs back to FPGA
* Provides interactive UI controls

---

## Data Flow

FPGA → Web:

1. Game state generated on FPGA
2. Sent via UART
3. Decoded by Python bridge
4. Broadcast via WebSocket
5. Rendered on dashboard

Web → FPGA:

1. User input (keyboard/UI)
2. Sent via WebSocket
3. Translated by bridge
4. Sent via UART
5. Processed by FPGA

This enables full bidirectional real-time communication 

---

## FPGA Modules

The FPGA design is composed of:

* `board_io` → Top-level module (connects all components)
* `clean_signals` → Debounces button inputs
* `simon_fsm` → Main game logic (FSM-based)
* `sevenseg_mux4` → Controls 7-segment display
* `uart_rx` → Receives serial data
* `uart_tx` → Transmits serial data

The system processes user inputs, executes game logic, and updates outputs (LEDs and display) 

---

## Game Logic

The Simon game is implemented using a finite state machine with the following states:

* Idle
* Show Sequence
* Player Input
* Check Input
* Game Over

The FPGA maintains:

* Score
* High score
* Current round
* LED sequence

---

## Project Structure

```text
fpga-simon-dashboard/
│
├── fpga/
│   ├── src/
│   └── constraints/
│
├── bridge/
│
├── website/
│
└── docs/
```

---

## Getting Started

### 1. Program the FPGA

1. Open Vivado
2. Run synthesis and implementation
3. Generate bitstream
4. Program the Basys3

---

### 2. Run Python Bridge

```bash
cd bridge
pip install -r requirements.txt
python fpga_bridge_ws.py
```

Make sure to configure the correct COM port (e.g., COM7) 

---

### 3. Run Web Dashboard

```bash
cd website
npm install
npm run dev
```

Open:
http://localhost:5173

---

## Controls

| Key   | Action     |
| ----- | ---------- |
| W / ↑ | Up         |
| A / ← | Left       |
| S / ↓ | Down       |
| D / → | Right      |
| C     | Start Game |

---

## Technologies

* VHDL (FPGA Design)
* Xilinx Vivado
* Python (asyncio, websockets, pyserial)
* React + Vite
* UART Communication
* WebSockets

---

## Key Highlights

* Full-stack hardware and software integration
* Real-time FPGA ↔ Web communication
* Custom UART protocol
* FSM-based embedded system design

---

## Demo

Add screenshots or a short demo video here.

---

## License

MIT License

---

## Authors

* Yaime Morales Hernandez
* Karlos Cruz Bonano

---
