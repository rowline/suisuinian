#!/usr/bin/env node
/**
 * suisuinian-brain-proxy.js
 *
 * Endpoints:
 *   POST /transcribe  { "filePath": "..." }
 *   POST /summarize   { "transcript": "...", "audioPath": "..." }
 *   POST /chat        { "message": "...", "context": "...", "sessionId": "..." }
 *   GET  /health
 *
 * Persistence: transcripts and summaries are cached as sidecar files.
 */

const http = require('http');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');

const PORT = 19001;
const OPENCLAW_BIN = '/opt/homebrew/bin/openclaw';
const PYTHON3_BIN = '/usr/bin/python3';
const WHISPER_MODEL = 'mlx-community/whisper-large-v3-turbo';
const ENV_BASE = {
  ...process.env,
  PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${process.env.PATH || ''}`
};

const KNOWLEDGE_DIR = path.join(__dirname, 'suisuinian-knowledge');
const TRANSCRIPTS_DIR = '/tmp/suisuinian-recordings'; // Simulator shared path

if (!fs.existsSync(KNOWLEDGE_DIR)) {
  fs.mkdirSync(KNOWLEDGE_DIR, { recursive: true });
}

function syncTranscriptsToKnowledge() {
  if (!fs.existsSync(TRANSCRIPTS_DIR)) return;
  console.log(`🔄 Syncing existing transcripts from ${TRANSCRIPTS_DIR}...`);
  try {
    const files = fs.readdirSync(TRANSCRIPTS_DIR);
    let count = 0;
    for (const file of files) {
      if (file.endsWith('.transcript')) {
        const dest = path.join(KNOWLEDGE_DIR, file.replace('.transcript', '.txt'));
        if (!fs.existsSync(dest)) {
          const content = fs.readFileSync(path.join(TRANSCRIPTS_DIR, file), 'utf8');
          // Try to extract raw text if it's JSON
          try {
            const json = JSON.parse(content);
            fs.writeFileSync(dest, json.transcript || content, 'utf8');
          } catch {
            fs.writeFileSync(dest, content, 'utf8');
          }
          count++;
        }
      }
    }
    if (count > 0) console.log(`✅ Synced ${count} transcripts to knowledge base.`);
  } catch (e) {
    console.error('❌ Sync failed:', e.message);
  }
}
syncTranscriptsToKnowledge();

// ── Helpers ──────────────────────────────────────────────────────────────────
function sidecarPath(audioPath, ext) {
  return audioPath.replace(/\.[^.]+$/, '') + ext;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', () => { try { resolve(JSON.parse(body)); } catch { reject(new Error('Invalid JSON')); } });
  });
}

function send(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

const HF_TOKEN = process.env.HF_TOKEN || ''; // Use process environment variable

function transcribeAudio(filePath) {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(__dirname, 'transcribe_and_diarize.py');
    execFile(PYTHON3_BIN, [scriptPath, filePath, HF_TOKEN],
      { env: ENV_BASE, timeout: 600000 },
      (err, stdout, stderr) => {
        if (err && (!stdout || !stdout.trim())) {
          return reject(new Error(stderr || err.message));
        }

        try {
          // The python script outputs JSON, but torchaudio might output warnings to stdout.
          // Find the last line that looks like a JSON object.
          const lines = stdout.split('\n').map(l => l.trim()).filter(l => l.startsWith('{') && l.endsWith('}'));
          const jsonStr = lines.length > 0 ? lines[lines.length - 1] : "{}";

          const res = JSON.parse(jsonStr);
          if (res.error) {
            return reject(new Error(res.error));
          }
          // Resolve with the JSON object for the transcriber
          resolve(res);
        } catch (e) {
          console.error("Failed to parse python output:", stdout.slice(-500));
          return reject(new Error("Failed to receive valid JSON from Python script"));
        }
      }
    );
  });
}

// ── OpenClaw agent call ───────────────────────────────────────────────────────
function openclawChat(message, sessionId, systemPrompt = '') {
  return new Promise((resolve, reject) => {
    // Explicitly scope OpenClaw to ONLY the knowledge directory
    const finalMessage = systemPrompt ? `${systemPrompt}\n\n${message}` : message;

    const args = ['agent', '--agent', 'main', '--message', finalMessage, '--json'];
    if (sessionId) args.push('--session-id', sessionId);

    execFile(OPENCLAW_BIN, args,
      { env: ENV_BASE, timeout: 120000, cwd: KNOWLEDGE_DIR },
      (err, stdout, stderr) => {
        if (err) { reject(new Error(stderr || err.message)); return; }
        try {
          const result = JSON.parse(stdout);
          const text = result?.result?.payloads?.[0]?.text ?? '';
          const sid = result?.result?.meta?.agentMeta?.sessionId ?? sessionId ?? '';
          resolve({ text: text || '(no reply)', sessionId: sid });
        } catch {
          reject(new Error('Parse error: ' + stdout.slice(0, 200)));
        }
      }
    );
  });
}

// ── Server ────────────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  if (req.method === 'GET' && req.url === '/health') {
    return send(res, 200, { status: 'ok' });
  }

  try {
    // ── POST /transcribe ──────────────────────────────────────────────────
    if (req.method === 'POST' && req.url === '/transcribe') {
      const { filePath, force } = await readBody(req);
      if (!filePath) return send(res, 400, { error: 'Missing filePath' });
      if (!fs.existsSync(filePath)) return send(res, 404, { error: `File not found: ${filePath}` });

      // Return cached transcript if it exists and force is not true
      const cachePath = sidecarPath(filePath, '.transcript');
      if (!force && fs.existsSync(cachePath)) {
        const cached = fs.readFileSync(cachePath, 'utf8').trim();
        if (cached) {
          try {
            const parsed = JSON.parse(cached);
            console.log(`📂 Loaded cached transcript (${parsed.transcript?.length || 0} chars)`);
            return send(res, 200, { ...parsed, cached: true });
          } catch (e) {
            // Fallback for legacy raw text caches
            console.log(`📂 Loaded legacy cached transcript (${cached.length} chars)`);
            return send(res, 200, { transcript: cached, cached: true });
          }
        }
      }

      console.log(`🎙️  Transcribing & Diarizing: ${path.basename(filePath)} (${(fs.statSync(filePath).size / 1e6).toFixed(1)} MB)`);
      const resultObj = await transcribeAudio(filePath); // now returns an object {transcript, speaker_segments}

      fs.writeFileSync(cachePath, JSON.stringify(resultObj), 'utf8');   // 💾 cache it as JSON

      // Also save a plain text copy to the restricted knowledge folder for OpenClaw to read
      if (resultObj.transcript) {
        const knowFilename = path.basename(filePath).replace(/\.[^.]+$/, '.txt');
        fs.writeFileSync(path.join(KNOWLEDGE_DIR, knowFilename), resultObj.transcript, 'utf8');
      }

      console.log(`✅ Transcript ready (${resultObj.transcript?.length || 0} chars) — saved to cache & knowledge dir`);

      return send(res, 200, { ...resultObj, cached: false });
    }

    // ── POST /summarize ───────────────────────────────────────────────────
    if (req.method === 'POST' && req.url === '/summarize') {
      const { transcript, audioPath } = await readBody(req);
      if (!transcript?.trim()) return send(res, 400, { error: 'Missing transcript' });

      // Return cached summary if exists
      let cachePath = null;
      if (audioPath) {
        if (audioPath.startsWith('/Users/rollin/Library/Developer/CoreSimulator')) {
          cachePath = sidecarPath(audioPath, '.summary');
        } else {
          const base = path.basename(audioPath);
          cachePath = path.join('/tmp', 'suisuinian-recordings', base.replace(/\.[^.]+$/, '.summary'));
        }

        if (fs.existsSync(cachePath)) {
          const cached = fs.readFileSync(cachePath, 'utf8').trim();
          if (cached) {
            console.log(`📂 Loaded cached summary (${cached.length} chars)`);
            return send(res, 200, { summary: cached, cached: true });
          }
        }
      }

      const prompt = `你是一个语音备忘录整理助手。请将以下转录内容整理成简洁的要点总结（中文）。

格式要求（严格遵守）：
- 用 **粗体冒号** 作为各小节标题，例如：**主要议题：**
- 用短横线列表 "- " 列出每个要点
- 不要使用 # 号标题，不要使用表格

转录内容：
${transcript.trim()}`;

      // Create a unique session ID so OpenClaw doesn't remember previous summaries
      // and refuse to summarize again ("I already summarized this").
      const sid = 'summary_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);

      console.log(`📝 Summarizing ${transcript.length} chars via OpenClaw (session: ${sid})...`);
      const { text: summary, sessionId: finalSid } = await openclawChat(prompt, sid);
      console.log(`✅ Summary ready (${summary.length} chars)`);

      // Cache summary alongside audio file
      if (cachePath) {
        fs.writeFileSync(cachePath, summary, 'utf8');
      }
      return send(res, 200, { summary, sessionId: finalSid, cached: false });
    }

    // ── POST /daily_summarize ─────────────────────────────────────────────
    if (req.method === 'POST' && req.url === '/daily_summarize') {
      const { transcripts, dateString } = await readBody(req);
      if (!Array.isArray(transcripts) || transcripts.length === 0) {
        return send(res, 400, { error: 'Missing or empty transcripts array' });
      }

      const combinedText = transcripts.join('\n\n---\n\n');
      const prompt = `你是一个个人知识库的日报整理助手。以下是我在 ${dateString || '今天'} 录制的多个语音备忘录和会议记录片段。
请根据这些内容，以我的口吻，整理出一份简明扼要的“今日日报”。

格式要求（严格遵守）：
- **核心事项**：说明今天推进或讨论了哪些最重要的事。
- **关键细节**：列举重要的决定、数据、或待办事项。
- 采用短横线列表 "- " 列出每个要点。
- 语言精练，直接说事，不要说“好的，我为您整理”，直接输出正文。不要使用 # 号标记。

【今日全部语音记录内容】：
${combinedText.trim()}`;

      const sid = 'daily_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
      console.log(`📝 Generating Daily Report for ${transcripts.length} files (${combinedText.length} chars) via OpenClaw (session: ${sid})...`);
      const { text: summary, sessionId: finalSid } = await openclawChat(prompt, sid);
      console.log(`✅ Daily Report ready (${summary.length} chars)`);

      return send(res, 200, { summary, sessionId: finalSid });
    }

    // ── POST /chat ────────────────────────────────────────────────────────
    if (req.method === 'POST' && req.url === '/chat') {
      const { message, sessionId, useGlobalScope } = await readBody(req);
      if (!message?.trim()) return send(res, 400, { error: 'Missing message' });

      // We no longer rely on iOS sending us the massive context text.
      // We explicitly instruct OpenClaw to ONLY use its working directory for facts.
      let sysPrompt = '';
      if (!sessionId && useGlobalScope) {
        sysPrompt = `[SYSTEM: YOU ARE A PRIVATE KNOWLEDGE ASSISTANT. YOUR KNOWLEDGE SOURCE IS LIMITED TO THE TXT FILES IN THE CURRENT DIRECTORY (KNOWLEDGE BASE). YOU ARE FORBIDDEN FROM SEARCHING THE MAC SYSTEM, THE INTERNET, OR ANY OTHER DIRECTORIES. IF INFORMATION IS NOT IN THE LOCAL FILES, SAY YOU DON'T KNOW. DO NOT USE EXTERNAL TOOLS.]\n\n[系统提示：你是一个私有知识库助手。你只能查阅当前目录下的文本文件（这是用户的录音记录）。严禁使用任何搜索工具去查看电脑上的其他文件夹或互联网。如果在此目录的文件中找不到答案，请直接告知你不知道，不要胡乱猜测。]`;
      }

      console.log(`💬 Chat: "${message.slice(0, 60)}..." (session: ${sessionId || 'new'})`);
      const reply = await openclawChat(message.trim(), sessionId, sysPrompt);
      console.log(`✅ Reply (${reply.text.length} chars), session: ${reply.sessionId}`);
      return send(res, 200, reply);
    }

    send(res, 404, { error: 'Unknown endpoint' });
  } catch (e) {
    console.error('❌', e.message);
    send(res, 500, { error: e.message });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n🦞 suisuinian-brain  →  http://localhost:${PORT}`);
  console.log(`   POST /transcribe { filePath }        ← mlx-whisper (cached)`);
  console.log(`   POST /summarize  { transcript, audioPath } ← OpenClaw (cached)`);
  console.log(`   POST /chat       { message, context, sessionId }`);
  console.log(`   GET  /health\n`);
});
