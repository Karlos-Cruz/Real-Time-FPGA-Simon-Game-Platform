import React, { useEffect, useMemo, useRef, useState } from "react";

const PAD_CONFIG = [
  { id: "U", label: "Up", keyHint: "W / ↑", name: "Yellow", color: "#facc15" },
  { id: "L", label: "Left", keyHint: "A / ←", name: "Red", color: "#ef4444" },
  { id: "R", label: "Right", keyHint: "D / →", name: "Green", color: "#22c55e" },
  { id: "D", label: "Down", keyHint: "S / ↓", name: "Blue", color: "#3b82f6" },
];

const DEFAULT_STATE = {
  connected: false,
  mode: "demo",
  turn: "idle",
  activePad: null,
  score: 0,
  highScore: 0,
  round: 0,
  lastInput: "-",
  sequencePreview: [],
  statusText: "Waiting for bridge connection",
  flashColon: true,
  playerName: "Yaime Morales Hernandez",
  partnerName: "Karlos Cruz Bonano",
  projectLabel: "Design Challenge : The Game of Simon",
  boardLabel: "Live from Basys3",
  newHighScoreActive: false,
};

function padFromKey(key) {
  const k = key.toLowerCase();
  if (k === "w" || key === "ArrowUp") return "U";
  if (k === "a" || key === "ArrowLeft") return "L";
  if (k === "d" || key === "ArrowRight") return "R";
  if (k === "s" || key === "ArrowDown") return "D";
  if (k === "c") return "C";
  return null;
}

function formatTwo(n) {
  return String(n).padStart(2, "0");
}

function parseBridgeMessage(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function getPadColor(padId) {
  if (padId === "C") return "#cbd5e1";
  const pad = PAD_CONFIG.find((item) => item.id === padId);
  return pad ? pad.color : "#334155";
}

function padFromLedPattern(ledValue) {
  if (ledValue == null) return null;

  let normalized = "";

  if (Array.isArray(ledValue)) {
    normalized = ledValue.join("");
  } else if (typeof ledValue === "number") {
    normalized = ledValue.toString(2).padStart(16, "0");
  } else {
    const raw = String(ledValue).trim();

    if (/^0x[0-9a-f]+$/i.test(raw)) {
      normalized = parseInt(raw, 16).toString(2).padStart(16, "0");
    } else if (/^[01\s]+$/.test(raw)) {
      normalized = raw.replace(/\s/g, "");
    } else if (/^\d+$/.test(raw)) {
      normalized = Number(raw).toString(2).padStart(16, "0");
    } else {
      normalized = raw.replace(/\s/g, "");
    }
  }

  if (normalized === "1111000000000000") return "L";
  if (normalized === "0000111100000000") return "R";
  if (normalized === "0000000011110000") return "U";
  if (normalized === "0000000000001111") return "D";

  return null;
}

function extractLedPatternFromMessage(message) {
  const directPattern =
    message?.led ??
    message?.leds ??
    message?.ledState ??
    message?.led_pattern;

  if (directPattern != null) {
    return directPattern;
  }

  const statusText = message?.statusText;
  if (typeof statusText === "string") {
    const match = statusText.match(/LEDs\s+([01]{16})/i);
    if (match) {
      return match[1];
    }
  }

  return null;
}

export default function SimonFPGADashboard() {
  const [game, setGame] = useState(DEFAULT_STATE);
  const [pressedKeys, setPressedKeys] = useState([]);
  const [socketUrl, setSocketUrl] = useState("ws://localhost:8765");
  const [bridgeState, setBridgeState] = useState("disconnected");
  const socketRef = useRef(null);
  const activePadTimeoutRef = useRef(null);

  useEffect(() => {
    const handleKeyDown = (e) => {
      const pad = padFromKey(e.key);
      if (!pad) return;
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)) {
        e.preventDefault();
      }
      setPressedKeys((prev) => (prev.includes(pad) ? prev : [...prev, pad]));
      pulsePad(pad, "web");
    };

    const handleKeyUp = (e) => {
      const pad = padFromKey(e.key);
      if (!pad) return;
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)) {
        e.preventDefault();
      }
      setPressedKeys((prev) => prev.filter((p) => p !== pad));
      sendBridgeMessage({ type: "pad_up", source: "web", pad });
    };

    window.addEventListener("keydown", handleKeyDown, { passive: false });
    window.addEventListener("keyup", handleKeyUp, { passive: false });

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("keyup", handleKeyUp);
      if (activePadTimeoutRef.current) {
        clearTimeout(activePadTimeoutRef.current);
      }
      if (socketRef.current) {
        socketRef.current.close();
      }
    };
  }, []);

  const roundProgress = useMemo(() => {
    const target = Math.max(game.highScore || 1, 1);
    const value = Math.min(100, (game.score / target) * 100);
    return Number.isFinite(value) ? value : 0;
  }, [game.score, game.highScore]);

  function sendBridgeMessage(payload) {
    if (!socketRef.current || socketRef.current.readyState !== WebSocket.OPEN) return;
    socketRef.current.send(JSON.stringify(payload));
  }

  function connectBridge() {
    try {
      if (socketRef.current && socketRef.current.readyState === WebSocket.OPEN) {
        socketRef.current.close();
      }

      const socket = new WebSocket(socketUrl);
      socketRef.current = socket;
      setBridgeState("connecting");

      socket.onopen = () => {
        setBridgeState("connected");
        setGame((prev) => ({
          ...prev,
          connected: true,
          mode: "live",
          statusText: "Bridge connected: FPGA ↔ Web live sync active",
        }));
      };

      socket.onmessage = (event) => {
        const message = parseBridgeMessage(event.data);
        if (!message) return;

        const ledPattern = extractLedPatternFromMessage(message);

        if (ledPattern != null) {
          const ledPad = padFromLedPattern(ledPattern);
          if (ledPad) {
            pulsePad(ledPad, "fpga");
          }
        }

        if (message.type === "pad_down" && message.pad) {
          pulsePad(message.pad, "fpga");
          return;
        }

        if (message.type === "pad_up" && message.pad) {
          setGame((prev) => ({
            ...prev,
            activePad: prev.activePad === message.pad ? null : prev.activePad,
          }));
          return;
        }

        if (message.type === "state") {
          const stateLedPattern = extractLedPatternFromMessage(message);
          const stateLedPad = padFromLedPattern(stateLedPattern);

          if (stateLedPad) {
            pulsePad(stateLedPad, "fpga");
          }

          setGame((prev) => ({
            ...prev,
            connected: true,
            mode: "live",
            turn: message.turn ?? prev.turn,
            score: message.score ?? prev.score,
            highScore: message.highScore ?? prev.highScore,
            round: message.round ?? prev.round,
            lastInput: stateLedPad ?? message.lastInput ?? prev.lastInput,
            statusText: message.statusText ?? prev.statusText,
            flashColon: message.flashColon ?? prev.flashColon,
            sequencePreview: Array.isArray(message.sequencePreview) ? message.sequencePreview : prev.sequencePreview,
            newHighScoreActive: message.newHighScoreActive ?? prev.newHighScoreActive,
          }));
        }
      };

      socket.onclose = () => {
        setBridgeState("disconnected");
        setGame((prev) => ({
          ...prev,
          connected: false,
          statusText: "Bridge disconnected",
        }));
      };

      socket.onerror = () => {
        setBridgeState("error");
        setGame((prev) => ({
          ...prev,
          connected: false,
          statusText: "Could not connect to bridge",
        }));
      };
    } catch (error) {
      setBridgeState("error");
      setGame((prev) => ({
        ...prev,
        connected: false,
        statusText: "Bridge connection failed",
      }));
    }
  }

  function disconnectBridge() {
    if (socketRef.current) {
      socketRef.current.close();
      socketRef.current = null;
    }
  }

  function pulsePad(pad, source) {
    if (activePadTimeoutRef.current) {
      clearTimeout(activePadTimeoutRef.current);
    }

    setGame((prev) => ({
      ...prev,
      activePad: pad,
      lastInput: pad,
      statusText: source === "fpga" ? `FPGA pressed ${pad}` : `Web pressed ${pad}`,
    }));

    if (source === "web") {
      sendBridgeMessage({ type: "pad_down", source: "web", pad });
    }

    activePadTimeoutRef.current = setTimeout(() => {
      setGame((prev) => ({
        ...prev,
        activePad: prev.activePad === pad ? null : prev.activePad,
      }));
    }, 320);
  }

  function resetDashboard() {
    disconnectBridge();
    setGame(DEFAULT_STATE);
    setPressedKeys([]);
    setBridgeState("disconnected");
  }

  const bridgeBadge =
    bridgeState === "connected"
      ? "Bridge Online"
      : bridgeState === "connecting"
        ? "Connecting..."
        : bridgeState === "error"
          ? "Bridge Error"
          : "Bridge Offline";

  return (
    <div style={styles.page}>
      <div style={styles.container}>
        <div style={styles.headerCard}>
          <div style={styles.headerTop}>
            <div>
              <div style={styles.title}>Simon FPGA Dashboard</div>
              <div style={styles.subtitle}>Simple React version for VS Code + Vite</div>
            </div>
            <div style={styles.badgeRow}>
              <div style={styles.badge}>{game.boardLabel}</div>
              <div style={styles.badge}>{bridgeBadge}</div>
            </div>
          </div>

          <div style={styles.mainGrid}>
            <div>
              <div style={styles.crossWrap}>
                {PAD_CONFIG.map((pad) => {
                  const isActive = game.activePad === pad.id || pressedKeys.includes(pad.id);
                  const positionStyle =
                    pad.id === "U"
                      ? styles.padUp
                      : pad.id === "L"
                        ? styles.padLeft
                        : pad.id === "R"
                          ? styles.padRight
                          : styles.padDown;

                  return (
                    <button
                      key={pad.id}
                      type="button"
                      onMouseDown={() => pulsePad(pad.id, "web")}
                      onMouseUp={() => sendBridgeMessage({ type: "pad_up", source: "web", pad: pad.id })}
                      style={{
                        ...styles.crossPadButton,
                        ...positionStyle,
                        background: pad.color,
                        boxShadow: isActive ? `0 0 24px ${pad.color}` : "none",
                        transform: isActive ? "scale(1.05)" : "scale(1)",
                        color: "white",
                      }}
                    >
                      <div style={styles.crossPadName}>{pad.name}</div>
                      <div style={styles.crossPadLabel}>{pad.label}</div>
                      <div style={styles.crossPadHint}>{pad.keyHint}</div>
                    </button>
                  );
                })}

                <button
                  type="button"
                  onMouseDown={() => pulsePad("C", "web")}
                  onMouseUp={() => sendBridgeMessage({ type: "pad_up", source: "web", pad: "C" })}
                  style={{
                    ...styles.crossCenterButton,
                    boxShadow:
                      game.activePad === "C" || pressedKeys.includes("C")
                        ? "0 0 24px rgba(226,232,240,0.6)"
                        : "none",
                    transform:
                      game.activePad === "C" || pressedKeys.includes("C")
                        ? "scale(1.05)"
                        : "scale(1)",
                  }}
                >
                  <div style={styles.centerButtonText}>C</div>
                  <div style={styles.centerButtonSubtext}>Start</div>
                  <div style={styles.centerButtonHint}>C key</div>
                </button>
              </div>
            </div>

            <div style={styles.sideColumn}>
              <div style={styles.panel}>
                <div style={styles.scoreHeaderRow}>
                  <div style={styles.scoreHeaderLabel}>High Score</div>
                  <div style={styles.scoreHeaderLabel}>Score</div>
                </div>

                <div style={styles.scoreLine}>
                  <span>{formatTwo(game.highScore)}</span>
                  <span style={{ opacity: game.flashColon ? 1 : 0.35 }}>:</span>
                  <span>{formatTwo(game.score)}</span>
                </div>

                <div style={styles.progressOuter}>
                  <div style={{ ...styles.progressInner, width: `${roundProgress}%` }} />
                </div>

                <div style={styles.infoGrid}>
                  <div style={styles.infoBox}>
                    <div style={styles.infoLabel}>Round</div>
                    <div style={styles.infoValue}>{formatTwo(game.round)}</div>
                  </div>
                  <div style={styles.infoBox}>
                    <div style={styles.infoLabel}>Last Correct Input</div>
                    <div style={{ ...styles.infoValue, color: getPadColor(game.lastInput) }}>
                      {game.lastInput}
                    </div>
                  </div>
                </div>

                <div style={styles.statusText}>{game.statusText}</div>
              </div>

              <div style={styles.panel}>
                <div style={styles.sectionTitle}>FPGA ↔ Web Controls</div>
                <label style={styles.inputLabel}>Bridge WebSocket URL</label>
                <input
                  value={socketUrl}
                  onChange={(e) => setSocketUrl(e.target.value)}
                  style={styles.input}
                  placeholder="ws://localhost:8765"
                />

                <div style={styles.buttonRow}>
                  <button type="button" onClick={connectBridge} style={styles.actionButton}>
                    Connect Bridge
                  </button>
                  <button type="button" onClick={disconnectBridge} style={styles.actionButtonSecondary}>
                    Disconnect
                  </button>
                  <button type="button" onClick={resetDashboard} style={styles.actionButtonSecondary}>
                    Reset
                  </button>
                </div>

                <div style={styles.helpBox}>
                  Web → FPGA: clicking pads or pressing W A S D / arrows sends pad events through the bridge.
                  <br />
                  FPGA → Web: button messages received from the bridge light up the same pads here.
                </div>
              </div>

              <div style={styles.panel}>
                <div style={styles.sectionTitle}>Documentation</div>
                <div style={styles.docIntroTitle}>Below is the link for the documentation</div>
                <div style={styles.docDescription}>
                  This project uses an FPGA board and a Python bridge to connect the hardware with the web
                  dashboard. The Simon game logic runs through the FPGA system, so the board, bridge, and
                  required code setup must be properly connected for the project to work as intended.
                </div>
                <div style={styles.sequenceRow}>
                  <a
                    href="https://docs.google.com/document/d/17Q0fylPOYC4pDjJ5tgcIqmgbqemaZofmXpz45iJbUSM/edit?usp=sharing"
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{ color: "#22d3ee", fontWeight: "600" }}
                  >
                    Open Project Documentation
                  </a>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div style={styles.footerGrid}>
          <div style={styles.footerCard}>
            <div style={styles.footerTitle}>2026 HDL & FPGAs Bootcamp</div>
            <div>{game.projectLabel}</div>
            <div>University of Puerto Rico Mayaguez Campus</div>
          </div>
          <div style={styles.footerCard}>
            <div style={styles.studentName}>Yaime Morales Hernandez</div>
            <div style={styles.studentSubtitle}>Undergraduate Student in Computer Engineering</div>
            <a
              href="https://www.linkedin.com/in/yaimemoraleshernandez/"
              target="_blank"
              rel="noopener noreferrer"
              style={styles.link}
            >
              LinkedIn Profile
            </a>
          </div>
          <div style={styles.footerCard}>
            <div style={styles.studentName}>Karlos Cruz Bonano</div>
            <div style={styles.studentSubtitle}>Undergraduate Student in Electrical Engineering</div>
            <a
              href="https://www.linkedin.com/in/karlos-cruz-bonano-b7210a276/"
              target="_blank"
              rel="noopener noreferrer"
              style={styles.link}
            >
              LinkedIn Profile
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}

const styles = {
  page: {
    minHeight: "100vh",
    width: "100%",
    background: "linear-gradient(135deg, #020617, #0f172a, #111827)",
    color: "white",
    padding: "24px",
    fontFamily: "Arial, sans-serif",
    boxSizing: "border-box",
  },
  container: {
    width: "100%",
    maxWidth: "100%",
    margin: "0 auto",
  },
  headerCard: {
    background: "rgba(255,255,255,0.05)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: "24px",
    padding: "24px",
    marginBottom: "24px",
  },
  headerTop: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "flex-start",
    gap: "16px",
    flexWrap: "wrap",
    marginBottom: "24px",
  },
  title: {
    fontSize: "36px",
    fontWeight: "700",
    marginBottom: "6px",
    color: "#a5f3fc",
  },
  subtitle: {
    color: "#cbd5e1",
    fontSize: "14px",
  },
  badgeRow: {
    display: "flex",
    gap: "10px",
    flexWrap: "wrap",
  },
  badge: {
    padding: "10px 14px",
    borderRadius: "999px",
    background: "rgba(255,255,255,0.08)",
    border: "1px solid rgba(255,255,255,0.12)",
    fontSize: "14px",
  },
  mainGrid: {
    display: "grid",
    gridTemplateColumns: "1.1fr 0.9fr",
    gap: "24px",
    width: "100%",
  },
  padGrid: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: "16px",
  },
  padButton: {
    height: "180px",
    borderRadius: "24px",
    border: "2px solid rgba(255,255,255,0.3)",
    padding: "20px",
    cursor: "pointer",
    transition: "all 0.15s ease",
    textAlign: "left",
    fontWeight: "700",
  },
  crossWrap: {
    position: "relative",
    width: "520px",
    height: "520px",
    margin: "0 auto",
  },
  crossPadButton: {
    position: "absolute",
    width: "150px",
    height: "150px",
    borderRadius: "24px",
    border: "2px solid rgba(255,255,255,0.3)",
    padding: "14px",
    cursor: "pointer",
    transition: "all 0.15s ease",
    fontWeight: "700",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    textAlign: "center",
  },
  padUp: {
    top: "0px",
    left: "185px",
  },
  padLeft: {
    top: "185px",
    left: "0px",
  },
  padRight: {
    top: "185px",
    right: "0px",
  },
  padDown: {
    bottom: "0px",
    left: "185px",
  },
  crossCenterButton: {
    position: "absolute",
    top: "185px",
    left: "185px",
    width: "150px",
    height: "150px",
    borderRadius: "24px",
    border: "2px solid rgba(255,255,255,0.3)",
    background: "#94a3b8",
    color: "#0f172a",
    cursor: "pointer",
    transition: "all 0.15s ease",
    fontWeight: "700",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    textAlign: "center",
    padding: "14px",
  },
  centerButtonWrap: {
    display: "flex",
    justifyContent: "center",
    marginTop: "16px",
  },
  centerButton: {
    width: "220px",
    height: "110px",
    borderRadius: "24px",
    border: "2px solid rgba(255,255,255,0.3)",
    background: "#94a3b8",
    color: "#0f172a",
    cursor: "pointer",
    transition: "all 0.15s ease",
    fontWeight: "700",
  },
  centerButtonText: {
    fontSize: "32px",
    fontWeight: "800",
    marginBottom: "6px",
  },
  centerButtonSubtext: {
    fontSize: "16px",
    marginBottom: "6px",
  },
  centerButtonHint: {
    fontSize: "14px",
    opacity: 0.85,
  },
  padName: {
    fontSize: "28px",
    marginBottom: "8px",
  },
  padLabel: {
    fontSize: "16px",
    opacity: 0.9,
    marginBottom: "8px",
  },
  padHint: {
    fontSize: "14px",
    opacity: 0.85,
  },
  crossPadName: {
    fontSize: "18px",
    fontWeight: "800",
    marginBottom: "4px",
  },
  crossPadLabel: {
    fontSize: "13px",
    opacity: 0.95,
    marginBottom: "4px",
  },
  crossPadHint: {
    fontSize: "12px",
    opacity: 0.85,
  },
  sideColumn: {
    display: "flex",
    flexDirection: "column",
    gap: "16px",
  },
  panel: {
    background: "rgba(255,255,255,0.05)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: "20px",
    padding: "20px",
  },
  scoreHeaderRow: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: "8px",
    padding: "0 6px",
  },
  scoreHeaderLabel: {
    color: "#94a3b8",
    fontSize: "13px",
    fontWeight: "700",
    textTransform: "uppercase",
    letterSpacing: "0.5px",
  },
  scoreLine: {
    fontSize: "54px",
    fontWeight: "800",
    letterSpacing: "4px",
    marginBottom: "14px",
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    gap: "12px",
  },
  progressOuter: {
    width: "100%",
    height: "12px",
    borderRadius: "999px",
    background: "rgba(255,255,255,0.1)",
    overflow: "hidden",
    marginBottom: "18px",
  },
  progressInner: {
    height: "100%",
    background: "linear-gradient(90deg, #06b6d4, #22c55e)",
    borderRadius: "999px",
  },
  infoGrid: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: "12px",
    marginBottom: "14px",
  },
  infoBox: {
    background: "rgba(0,0,0,0.2)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: "16px",
    padding: "14px",
  },
  infoLabel: {
    color: "#94a3b8",
    fontSize: "13px",
    marginBottom: "6px",
  },
  infoValue: {
    fontSize: "28px",
    fontWeight: "700",
    color: "white",
  },
  statusText: {
    color: "#cbd5e1",
    fontSize: "14px",
    lineHeight: 1.5,
  },
  sectionTitle: {
    fontSize: "18px",
    fontWeight: "700",
    marginBottom: "12px",
  },
  inputLabel: {
    display: "block",
    fontSize: "12px",
    color: "#94a3b8",
    marginBottom: "8px",
  },
  input: {
    width: "100%",
    padding: "12px 14px",
    borderRadius: "12px",
    background: "rgba(0,0,0,0.2)",
    border: "1px solid rgba(255,255,255,0.15)",
    color: "white",
    outline: "none",
    boxSizing: "border-box",
    marginBottom: "14px",
  },
  buttonRow: {
    display: "flex",
    gap: "10px",
    flexWrap: "wrap",
    marginBottom: "12px",
  },
  actionButton: {
    padding: "12px 16px",
    borderRadius: "12px",
    border: "none",
    background: "#0891b2",
    color: "white",
    fontWeight: "700",
    cursor: "pointer",
  },
  actionButtonSecondary: {
    padding: "12px 16px",
    borderRadius: "12px",
    border: "1px solid rgba(255,255,255,0.15)",
    background: "rgba(255,255,255,0.05)",
    color: "white",
    fontWeight: "700",
    cursor: "pointer",
  },
  helpBox: {
    background: "rgba(0,0,0,0.2)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: "16px",
    padding: "14px",
    color: "#cbd5e1",
    fontSize: "13px",
    lineHeight: 1.6,
  },
  sequenceRow: {
    display: "flex",
    gap: "10px",
    flexWrap: "wrap",
  },
  footerGrid: {
    display: "grid",
    gridTemplateColumns: "repeat(3, 1fr)",
    gap: "16px",
    width: "100%",
  },
  footerCard: {
    background: "rgba(255,255,255,0.05)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: "20px",
    padding: "20px",
    color: "#cbd5e1",
  },
  footerTitle: {
    color: "white",
    fontWeight: "700",
    marginBottom: "8px",
  },
  studentName: {
    color: "white",
    fontWeight: "700",
    marginBottom: "6px",
  },
  studentSubtitle: {
    marginBottom: "8px",
  },
  link: {
    color: "#22d3ee",
    fontWeight: "600",
    textDecoration: "none",
  },
  docIntroTitle: {
    color: "white",
    fontWeight: "700",
    marginBottom: "8px",
  },
  docDescription: {
    color: "#cbd5e1",
    fontSize: "13px",
    lineHeight: 1.6,
    marginBottom: "14px",
  },
};