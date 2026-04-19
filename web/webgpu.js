const COMMAND_STRIDE = 48;

const CommandTag = {
  clear: 0,
  rect: 1,
  strokeRect: 2,
  text: 3,
  clipPush: 4,
  clipPop: 5,
  polyline: 6,
};

const decoder = new TextDecoder();

function colorFromPacked(value) {
  const r = value & 0xff;
  const g = (value >>> 8) & 0xff;
  const b = (value >>> 16) & 0xff;
  const a = ((value >>> 24) & 0xff) / 255;
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

function readCommand(view, offset) {
  return {
    tag: view.getUint32(offset + 0, true),
    flags: view.getUint32(offset + 4, true),
    color: view.getUint32(offset + 8, true),
    data0: view.getUint32(offset + 12, true),
    x: view.getFloat32(offset + 16, true),
    y: view.getFloat32(offset + 20, true),
    w: view.getFloat32(offset + 24, true),
    h: view.getFloat32(offset + 28, true),
    p0: view.getFloat32(offset + 32, true),
    p1: view.getFloat32(offset + 36, true),
    p2: view.getFloat32(offset + 40, true),
    p3: view.getFloat32(offset + 44, true),
  };
}

export function createRenderer(canvas) {
  const ctx = canvas.getContext("2d");
  let cssWidth = 0;
  let cssHeight = 0;
  let dpr = Math.max(1, window.devicePixelRatio || 1);

  function resize() {
    dpr = Math.max(1, window.devicePixelRatio || 1);
    const parent = canvas.parentElement;
    cssWidth = Math.max(320, Math.floor(parent.clientWidth));
    cssHeight = Math.max(360, Math.floor(parent.clientHeight));
    canvas.width = Math.floor(cssWidth * dpr);
    canvas.height = Math.floor(cssHeight * dpr);
    canvas.style.width = `${cssWidth}px`;
    canvas.style.height = `${cssHeight}px`;
    return { width: cssWidth, height: cssHeight };
  }

  function render(frame) {
    if (!frame.memory || frame.commandsLen <= 0) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      return;
    }

    const commandView = new DataView(frame.memory.buffer, frame.commandsPtr, frame.commandsLen * COMMAND_STRIDE);
    const textBytes = new Uint8Array(frame.memory.buffer, frame.textPtr, frame.textLen);
    const pointValues = new Float32Array(frame.memory.buffer, frame.pointsPtr, frame.pointsLen * 2);

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssWidth, cssHeight);
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    ctx.save();
    let saveDepth = 1;

    for (let index = 0; index < frame.commandsLen; index += 1) {
      const command = readCommand(commandView, index * COMMAND_STRIDE);

      switch (command.tag) {
        case CommandTag.clear: {
          ctx.fillStyle = colorFromPacked(command.color);
          ctx.fillRect(command.x, command.y, command.w, command.h);
          break;
        }
        case CommandTag.rect: {
          ctx.fillStyle = colorFromPacked(command.color);
          ctx.fillRect(command.x, command.y, command.w, command.h);
          break;
        }
        case CommandTag.strokeRect: {
          ctx.strokeStyle = colorFromPacked(command.color);
          ctx.lineWidth = Math.max(1, command.p0 || 1);
          ctx.strokeRect(command.x, command.y, command.w, command.h);
          break;
        }
        case CommandTag.text: {
          const text = decoder.decode(textBytes.subarray(command.data0, command.data0 + command.flags));
          ctx.fillStyle = colorFromPacked(command.color);
          ctx.font = `${command.p0 || 14}px "Avenir Next", "Helvetica Neue", sans-serif`;
          ctx.textBaseline = "top";
          ctx.fillText(text, command.x, command.y);
          break;
        }
        case CommandTag.clipPush: {
          ctx.save();
          saveDepth += 1;
          ctx.beginPath();
          ctx.rect(command.x, command.y, command.w, command.h);
          ctx.clip();
          break;
        }
        case CommandTag.clipPop: {
          if (saveDepth > 1) {
            ctx.restore();
            saveDepth -= 1;
          }
          break;
        }
        case CommandTag.polyline: {
          if (!command.flags) break;
          ctx.strokeStyle = colorFromPacked(command.color);
          ctx.lineWidth = Math.max(1, command.p0 || 1.5);
          ctx.beginPath();

          for (let pointIndex = 0; pointIndex < command.flags; pointIndex += 1) {
            const offset = (command.data0 + pointIndex) * 2;
            const x = pointValues[offset];
            const y = pointValues[offset + 1];
            if (pointIndex === 0) {
              ctx.moveTo(x, y);
            } else {
              ctx.lineTo(x, y);
            }
          }

          ctx.stroke();
          break;
        }
        default:
          break;
      }
    }

    while (saveDepth > 0) {
      ctx.restore();
      saveDepth -= 1;
    }
  }

  return {
    resize,
    render,
  };
}
