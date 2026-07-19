"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const home = os.homedir();
const username = (process.env.SBYG_SERV00_USER || os.userInfo().username).toLowerCase();
const configuredPort = Number.parseInt(process.env.SBYG_APP_PORT || "3000", 10);
const listenPort = Number.isInteger(configuredPort) && configuredPort >= 0 && configuredPort <= 65535
  ? configuredPort
  : 3000;
const workdir = path.join(home, "domains", `${username}.serv00.net`, "logs");
const keepScript = path.join(home, "serv00keep.sh");
const portScript = path.join(home, "webport.sh");
const tokenFile = path.join(workdir, "UUID.txt");
const listFile = path.join(workdir, "list.txt");
const activeTasks = new Set();

function readAccessToken() {
  try {
    const token = fs.readFileSync(tokenFile, "utf8").trim();
    return token.length >= 8 && token.length <= 128 ? token : "";
  } catch {
    return "";
  }
}

function tokenMatches(candidate) {
  const expected = readAccessToken();
  if (!expected || !candidate) return false;
  const actualBuffer = Buffer.from(candidate);
  const expectedBuffer = Buffer.from(expected);
  return actualBuffer.length === expectedBuffer.length &&
    crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}

function writeResponse(res, status, body, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Cache-Control": "no-store",
    "Content-Type": contentType,
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  });
  res.end(body);
}

function startTask(name, script) {
  if (activeTasks.has(name)) return false;
  activeTasks.add(name);
  const child = spawn("bash", [script], {
    cwd: home,
    detached: true,
    stdio: "ignore",
  });
  child.once("error", (error) => {
    console.error(`${name} 启动失败:`, error.message);
    activeTasks.delete(name);
  });
  child.once("exit", () => activeTasks.delete(name));
  child.unref();
  return true;
}

function parseRoute(req) {
  try {
    return new URL(req.url, "http://127.0.0.1").pathname
      .split("/")
      .filter(Boolean)
      .map(decodeURIComponent);
  } catch {
    return [];
  }
}

const server = http.createServer((req, res) => {
  if (req.method !== "GET") {
    writeResponse(res, 405, "仅支持 GET 请求\n");
    return;
  }

  const route = parseRoute(req);
  if (route.length !== 2 || !tokenMatches(route[1])) {
    writeResponse(res, 404, "未找到资源\n");
    return;
  }

  switch (route[0]) {
    case "up":
    case "re": {
      const started = startTask("keep", keepScript);
      writeResponse(res, 202, started ? "网页保活启动（任务已提交）\n" : "网页保活已在运行\n");
      break;
    }
    case "rp": {
      const started = startTask("ports", portScript);
      writeResponse(res, 202, started ? "端口重置任务已提交\n" : "端口重置任务已在运行\n");
      break;
    }
    case "jc": {
      const status = {
        keep_running: activeTasks.has("keep"),
        port_reset_running: activeTasks.has("ports"),
        config_present: fs.existsSync(path.join(workdir, "config.json")),
        subscription_present: fs.existsSync(listFile),
      };
      writeResponse(res, 200, `${JSON.stringify(status)}\n`, "application/json; charset=utf-8");
      break;
    }
    case "list":
      try {
        writeResponse(res, 200, fs.readFileSync(listFile, "utf8"));
      } catch {
        writeResponse(res, 404, "订阅尚未生成\n");
      }
      break;
    default:
      writeResponse(res, 404, "未找到资源\n");
  }
});

if (process.env.SBYG_DISABLE_AUTO_KEEP !== "1") {
  setInterval(() => startTask("keep", keepScript), (2 * 60 + 15) * 60 * 1000).unref();
}
server.listen(listenPort, "127.0.0.1", () => {
  console.log(`Serv00 保活服务仅监听 127.0.0.1:${server.address().port}`);
  if (process.env.SBYG_DISABLE_AUTO_KEEP !== "1") startTask("keep", keepScript);
});
