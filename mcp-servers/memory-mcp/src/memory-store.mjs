import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs';

// DB 경로: MEMORY_DB_PATH 환경변수 > 레포 data/ 디렉토리 > 홈 폴백
function resolveDbPath() {
  if (process.env.MEMORY_DB_PATH) return process.env.MEMORY_DB_PATH;

  // __dirname 대신 import.meta.url 기반으로 레포 루트 찾기
  const srcDir = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Z]:)/, '$1'));
  const repoRoot = path.resolve(srcDir, '..', '..', '..'); // memory-mcp/src → mcp-servers → repo root
  const dataDir = path.join(repoRoot, 'data');

  if (fs.existsSync(dataDir)) return path.join(dataDir, 'memory.db');

  const homeDir = process.env.HOME || process.env.USERPROFILE;
  return path.join(homeDir, '.agent-memory.db');
}

class MemoryStore {
  constructor() {
    const dbPath = resolveDbPath();
    this.db = new Database(dbPath);
    this._init();
  }

  _init() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS memories (
        id          TEXT    PRIMARY KEY,
        type        TEXT    NOT NULL DEFAULT 'general',
        content     TEXT    NOT NULL,
        tags        TEXT    NOT NULL DEFAULT '[]',
        source      TEXT    NOT NULL DEFAULT '',
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      );

      CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
        id        UNINDEXED,
        content,
        tags,
        content = 'memories',
        content_rowid = 'rowid'
      );

      CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
        INSERT INTO memories_fts(rowid, id, content, tags)
        VALUES (new.rowid, new.id, new.content, new.tags);
      END;

      CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
        INSERT INTO memories_fts(memories_fts, rowid, id, content, tags)
        VALUES ('delete', old.rowid, old.id, old.content, old.tags);
      END;

      CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
        INSERT INTO memories_fts(memories_fts, rowid, id, content, tags)
        VALUES ('delete', old.rowid, old.id, old.content, old.tags);
        INSERT INTO memories_fts(rowid, id, content, tags)
        VALUES (new.rowid, new.id, new.content, new.tags);
      END;
    `);
  }

  store({ content, type = 'general', tags = [], source = '' }) {
    const id = randomUUID();
    const now = Date.now();
    const tagsJson = JSON.stringify(tags);

    this.db
      .prepare(
        `INSERT INTO memories (id, type, content, tags, source, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .run(id, type, content, tagsJson, source, now, now);

    return { id, type, content, tags, source, created_at: now };
  }

  recall({ query, type, limit = 10 }) {
    // FTS5 MATCH 쿼리 — 특수문자 이스케이프
    const ftsQuery = query
      .replace(/['"*^()]/g, ' ')
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .map((w) => `"${w}"`)
      .join(' OR ');

    if (!ftsQuery) return [];

    const typeClause = type ? `AND m.type = '${type.replace(/'/g, "''")}'` : '';

    const rows = this.db
      .prepare(
        `SELECT m.id, m.type, m.content, m.tags, m.source, m.created_at,
                rank AS score
         FROM memories_fts
         JOIN memories m ON memories_fts.id = m.id
         WHERE memories_fts MATCH ?
         ${typeClause}
         ORDER BY rank
         LIMIT ?`
      )
      .all(ftsQuery, limit);

    return rows.map((r) => ({ ...r, tags: JSON.parse(r.tags) }));
  }

  list({ type, limit = 20, source } = {}) {
    let query = 'SELECT id, type, content, tags, source, created_at FROM memories WHERE 1=1';
    const params = [];

    if (type) {
      query += ' AND type = ?';
      params.push(type);
    }
    if (source) {
      query += ' AND source = ?';
      params.push(source);
    }

    query += ' ORDER BY created_at DESC LIMIT ?';
    params.push(limit);

    const rows = this.db.prepare(query).all(...params);
    return rows.map((r) => ({ ...r, tags: JSON.parse(r.tags) }));
  }

  delete({ id }) {
    const info = this.db.prepare('DELETE FROM memories WHERE id = ?').run(id);
    if (info.changes === 0) throw new Error(`Memory not found: ${id}`);
    return { deleted: id };
  }

  update({ id, content, tags }) {
    const existing = this.db.prepare('SELECT * FROM memories WHERE id = ?').get(id);
    if (!existing) throw new Error(`Memory not found: ${id}`);

    const newContent = content ?? existing.content;
    const newTags = tags !== undefined ? JSON.stringify(tags) : existing.tags;
    const now = Date.now();

    this.db
      .prepare('UPDATE memories SET content = ?, tags = ?, updated_at = ? WHERE id = ?')
      .run(newContent, newTags, now, id);

    return {
      id,
      type: existing.type,
      content: newContent,
      tags: JSON.parse(newTags),
      source: existing.source,
      updated_at: now
    };
  }

  stats() {
    const total = this.db.prepare('SELECT COUNT(*) as n FROM memories').get().n;
    const byType = this.db
      .prepare("SELECT type, COUNT(*) as n FROM memories GROUP BY type ORDER BY n DESC")
      .all();
    return { total, by_type: byType };
  }
}

// 싱글턴 — MCP 서버 프로세스 내에서 단일 DB 연결 유지
let _store;
export function getMemoryStore() {
  if (!_store) _store = new MemoryStore();
  return _store;
}
