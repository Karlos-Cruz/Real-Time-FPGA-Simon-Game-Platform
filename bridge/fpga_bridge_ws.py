import asyncio
import json
import threading
import serial
import websockets

SERIAL_PORT = "COM7"
BAUD_RATE = 115200
SER_TIMEOUT = 0.1

START_BYTE = 0xAA
END_BYTE = 0x55
PAYLOAD_LEN = 7

clients = set()

latest_state = {
    "type": "state",
    "turn": "idle",
    "score": 0,
    "highScore": 0,
    "round": 0,
    "lastInput": "-",
    "statusText": "Waiting for FPGA data",
    "flashColon": False,
    "sequencePreview": [],
    "newHighScoreActive": False,
}

loop_ref = None
serial_ref = None
last_sent_pad = "-"


def send_pad_to_serial(pad: str, is_down: bool):
    global serial_ref

    if serial_ref is None:
        return

    if not is_down:
        return

    mapping = {
        "L": b"L",
        "R": b"R",
        "U": b"U",
        "D": b"D",
        "C": b"C",
    }

    if pad in mapping:
        try:
            serial_ref.write(mapping[pad])
            print(f"[SERIAL TX] sent {pad}")
        except Exception as e:
            print("[SERIAL WRITE ERROR]", e)


def decode_state(code: int) -> str:
    return {
        0: "idle",      # ST_ON
        1: "showing",   # ST_PLAY show mode
        2: "player",    # ST_PLAY player mode
        3: "gameover",  # ST_LOSE
        4: "clear",
        5: "timeout",
        6: "sleep",
        7: "init",
    }.get(code, "idle")


def decode_last_btn(code: int) -> str:
    return {
        0: "-",
        1: "L",   # btnL = red
        2: "R",   # btnR = green
        3: "U",   # btnU = yellow
        4: "D",   # btnD = blue
        5: "C",   # start
        6: "CLR",
    }.get(code, "-")


def build_status_text(turn: str) -> str:
    return {
        "idle": "Waiting to start",
        "showing": "Showing pattern",
        "player": "Player turn",
        "gameover": "Wrong input / lose",
        "clear": "Clearing game",
        "timeout": "Watchdog timeout",
        "sleep": "Sleep mode",
        "init": "Initializing",
    }.get(turn, "Unknown state")


def read_exact(ser: serial.Serial, n: int) -> bytes:
    data = b""
    while len(data) < n:
        chunk = ser.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


async def broadcast(message: dict):
    if not clients:
        return

    dead = []
    text = json.dumps(message)

    for ws in clients:
        try:
            await ws.send(text)
        except Exception:
            dead.append(ws)

    for ws in dead:
        clients.discard(ws)


def serial_loop():
    global latest_state, serial_ref, loop_ref, last_sent_pad

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=SER_TIMEOUT)
        serial_ref = ser
        print(f"[OK] Serial abierto en {SERIAL_PORT} @ {BAUD_RATE}")
    except Exception as e:
        print(f"[ERROR] No pude abrir serial: {e}")
        return

    while True:
        try:
            b = ser.read(1)
            if not b:
                continue

            if b[0] != START_BYTE:
                continue

            payload = read_exact(ser, PAYLOAD_LEN)
            tail = read_exact(ser, 1)

            if len(payload) != PAYLOAD_LEN or len(tail) != 1:
                continue

            if tail[0] != END_BYTE:
                continue

            state_code = payload[0] & 0x07
            score = payload[1]
            high_score = payload[2]
            last_btn_code = payload[3] & 0x07
            flash = (payload[4] & 0x01) == 1
            led_hi = payload[5]
            led_lo = payload[6]

            led_mask = f"{led_hi:08b}{led_lo:08b}"
            turn = decode_state(state_code)
            last_input = decode_last_btn(last_btn_code)
            status_text = build_status_text(turn)

            latest_state = {
                "type": "state",
                "turn": turn,
                "score": score,
                "highScore": high_score,
                "round": score,
                "lastInput": last_input,
                "statusText": f"{status_text} | LEDs {led_mask}",
                "flashColon": flash,
                "sequencePreview": [],
                "newHighScoreActive": score > high_score,
            }

            # Manda el estado general al website
            if loop_ref is not None:
                asyncio.run_coroutine_threadsafe(
                    broadcast(latest_state),
                    loop_ref
                )

            # Manda evento de botón cuando cambia el último botón tocado en FPGA
            if last_input in ["L", "R", "U", "D"] and last_input != last_sent_pad:
                if loop_ref is not None:
                    asyncio.run_coroutine_threadsafe(
                        broadcast({
                            "type": "pad_down",
                            "pad": last_input
                        }),
                        loop_ref
                    )
                last_sent_pad = last_input


            if last_input not in ["L", "R", "U", "D"]:
                last_sent_pad = "-"

            print("[FPGA RX]", latest_state)

        except Exception as e:
            print(f"[ERROR] Serial loop: {e}")


async def handler(websocket):
    global latest_state
    clients.add(websocket)
    print("[WS] Cliente conectado")

    try:
        await websocket.send(json.dumps(latest_state))

        async for message in websocket:
            try:
                data = json.loads(message)
            except Exception:
                continue

            msg_type = data.get("type")
            pad = data.get("pad")

            if msg_type == "pad_down" and pad:
                print(f"[WEB] pad_down {pad}")
                send_pad_to_serial(pad, True)

            elif msg_type == "pad_up" and pad:
                print(f"[WEB] pad_up {pad}")

    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        clients.discard(websocket)
        print("[WS] Cliente desconectado")


async def main():
    global loop_ref
    loop_ref = asyncio.get_running_loop()

    t = threading.Thread(target=serial_loop, daemon=True)
    t.start()

    print("[OK] WebSocket server en ws://localhost:8765")
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())