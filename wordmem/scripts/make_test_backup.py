#!/usr/bin/env python3
"""
生成词记 App 测试数据包（可直接导入的备份 zip）。

数据包内容：
- 近义词组（26 组，测试近义词检测 + 选择题）
- 多状态（new/learning/review）测试复习流程
- 多日期分布（测试自选复习 + 统计折线图）
- 标签（考研/CET-4/CET-6/雅思/托福/GRE）
- 复习记录（测试学习趋势 + 连续学习天数）
"""
import json
import sqlite3
import hashlib
import zipfile
from datetime import datetime, timedelta, timezone

OUTPUT_ZIP = r"C:/Users/Administrator/WorkBuddy/2026-08-12-22-28-38/词记测试数据包-100词.zip"

FSRS_PARAMS = ("0.4072,1.1829,3.1262,15.4722,7.2102,"
               "0.5316,1.0651,0.0234,1.616,0.1544,"
               "1.0824,1.9813,0.0953,0.2975,2.2042,"
               "0.2407,2.9466,0.5034,0.6567")


def now_utc():
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt):
    return dt.replace(microsecond=0).isoformat()


def days_ago(n, hour=10):
    d = now_utc() - timedelta(days=n)
    return d.replace(hour=hour, minute=0, second=0)


# 测试单词：word, custom_def, tags, card_state, created_days_ago, due_offset_minutes, reps, stability, note
# due_offset_minutes 为相对 now 的偏移（负=已到期，正=未来）
WORDS = [
    # ---- 近义词组 1: 高兴 ----
    ("happy", "adj. 高兴的；快乐的；幸福的", "CET-4", "review", 20, -1440, 5, 18.0, "常用形容词"),
    ("glad", "adj. 高兴的；乐意的", "CET-4", "review", 18, -1440, 4, 12.0, ""),
    ("joyful", "adj. 快乐的；喜悦的", "雅思", "learning", 2, -60, 1, 3.0, ""),
    ("cheerful", "adj. 高兴的；愉快的", "CET-6", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 2: 大 ----
    ("big", "adj. 大的；重要的", "CET-4", "review", 15, -2880, 4, 16.0, ""),
    ("large", "adj. 大的；大量的", "CET-4", "review", 12, -1440, 3, 9.0, ""),
    ("huge", "adj. 巨大的；庞大的", "CET-6", "learning", 1, -30, 1, 2.5, ""),
    ("enormous", "adj. 巨大的；极大的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 3: 美丽 ----
    ("beautiful", "adj. 美丽的；漂亮的", "CET-4", "review", 25, -4320, 6, 25.0, ""),
    ("pretty", "adj. 漂亮的；好看的", "CET-4", "review", 22, -2880, 4, 11.0, ""),
    ("lovely", "adj. 可爱的；美丽的", "CET-6", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 4: 快 ----
    ("fast", "adj. 快的；迅速的", "CET-4", "review", 10, -1440, 3, 8.0, ""),
    ("quick", "adj. 快的；敏捷的", "CET-4", "learning", 1, -20, 1, 2.0, ""),
    ("rapid", "adj. 迅速的；快速的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 5: 开始 ----
    ("begin", "v. 开始；着手", "CET-4", "review", 8, -1440, 3, 7.0, ""),
    ("start", "v. 开始；出发", "CET-4", "learning", 1, -15, 1, 1.8, ""),
    ("commence", "v. 开始；着手进行", "GRE", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 6: 聪明 ----
    ("smart", "adj. 聪明的；机灵的", "CET-4", "review", 6, -720, 3, 6.0, ""),
    ("clever", "adj. 聪明的；机敏的", "CET-4", "learning", 1, -10, 1, 1.5, ""),
    ("intelligent", "adj. 聪明的；智慧的", "CET-6", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 7: 重要 ----
    ("important", "adj. 重要的；重大的", "CET-4", "review", 5, -720, 3, 5.0, ""),
    ("significant", "adj. 重要的；有意义的", "考研", "learning", 1, -5, 1, 1.2, ""),
    ("crucial", "adj. 关键的；重要的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 8: 强 ----
    ("strong", "adj. 强壮的；有力的", "CET-4", "review", 4, -720, 2, 4.0, ""),
    ("powerful", "adj. 强大的；有力的", "CET-6", "learning", 1, -3, 1, 1.0, ""),
    ("sturdy", "adj. 强健的；结实的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 9: 疲劳 ----
    ("tired", "adj. 疲劳的；累的", "CET-4", "review", 3, -360, 2, 3.5, ""),
    ("exhausted", "adj. 筋疲力尽的", "CET-6", "learning", 1, -1, 1, 0.8, ""),
    ("weary", "adj. 疲倦的；厌倦的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 10: 悲伤 ----
    ("sad", "adj. 悲伤的；难过的", "CET-4", "review", 2, -240, 2, 2.8, ""),
    ("unhappy", "adj. 不快乐的；不幸福的", "CET-6", "learning", 1, -1, 1, 0.6, ""),
    ("sorrowful", "adj. 悲伤的；悲哀的", "GRE", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 11: 小 ----
    ("small", "adj. 小的；微小的", "CET-4", "review", 20, -1440, 5, 18.0, ""),
    ("little", "adj. 小的；少的", "CET-4", "learning", 2, -30, 1, 2.5, ""),
    ("tiny", "adj. 极小的；微小的", "CET-6", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 12: 好 ----
    ("good", "adj. 好的；优秀的", "CET-4", "review", 21, -2880, 6, 22.0, ""),
    ("excellent", "adj. 优秀的；杰出的", "考研", "review", 15, -1440, 4, 14.0, ""),
    ("great", "adj. 伟大的；极好的", "CET-4", "learning", 1, -45, 1, 2.8, ""),
    ("wonderful", "adj. 极好的；精彩的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 13: 坏 ----
    ("bad", "adj. 坏的；差的", "CET-4", "review", 18, -1440, 4, 13.0, ""),
    ("terrible", "adj. 可怕的；糟糕的", "CET-6", "learning", 1, -20, 1, 2.0, ""),
    ("awful", "adj. 糟糕的；可怕的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 14: 勇敢 ----
    ("brave", "adj. 勇敢的", "CET-4", "review", 10, -720, 3, 7.0, ""),
    ("courageous", "adj. 勇敢的；有胆量的", "考研", "learning", 1, -10, 1, 1.5, ""),
    ("bold", "adj. 大胆的；勇敢的", "CET-6", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 15: 害怕 ----
    ("afraid", "adj. 害怕的；担心的", "CET-4", "review", 9, -720, 3, 6.5, ""),
    ("scared", "adj. 害怕的；恐惧的", "CET-6", "learning", 1, -8, 1, 1.4, ""),
    ("frightened", "adj. 受惊的；害怕的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 16: 生气 ----
    ("angry", "adj. 生气的；愤怒的", "CET-4", "review", 8, -360, 3, 6.0, ""),
    ("mad", "adj. 发疯的；狂怒的", "CET-6", "learning", 1, -6, 1, 1.2, ""),
    ("furious", "adj. 狂怒的；激烈的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 17: 安静 ----
    ("quiet", "adj. 安静的；平静的", "CET-4", "review", 7, -360, 2, 5.0, ""),
    ("silent", "adj. 沉默的；寂静的", "CET-6", "learning", 1, -4, 1, 1.0, ""),
    ("calm", "adj. 平静的；镇定的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 18: 困难 ----
    ("difficult", "adj. 困难的；难懂的", "CET-4", "review", 16, -1440, 4, 15.0, ""),
    ("hard", "adj. 困难的；坚硬的", "CET-4", "review", 12, -720, 3, 9.0, ""),
    ("tough", "adj. 艰难的；坚韧的", "CET-6", "learning", 1, -12, 1, 1.6, ""),
    ("challenging", "adj. 有挑战性的；困难的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 19: 容易 ----
    ("easy", "adj. 容易的；简单的", "CET-4", "review", 14, -1440, 4, 12.0, ""),
    ("simple", "adj. 简单的；朴素的", "CET-4", "review", 11, -720, 3, 8.5, ""),
    ("effortless", "adj. 不费力的；轻松的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 20: 有趣 ----
    ("interesting", "adj. 有趣的；有意思的", "CET-4", "review", 13, -1440, 4, 11.0, ""),
    ("fascinating", "adj. 迷人的；极有趣的", "考研", "learning", 1, -15, 1, 1.7, ""),
    ("intriguing", "adj. 有趣的；引人入胜的", "GRE", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 21: 无聊 ----
    ("boring", "adj. 无聊的；乏味的", "CET-4", "review", 6, -360, 2, 4.5, ""),
    ("dull", "adj. 枯燥的；迟钝的", "CET-6", "learning", 1, -3, 1, 0.9, ""),
    ("tedious", "adj. 冗长乏味的", "考研", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 22: 奇怪 ----
    ("strange", "adj. 奇怪的；陌生的", "CET-4", "review", 5, -360, 2, 4.0, ""),
    ("odd", "adj. 奇怪的；奇数的", "CET-6", "learning", 1, -2, 1, 0.7, ""),
    ("weird", "adj. 怪异的；离奇的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 23: 著名 ----
    ("famous", "adj. 著名的；出名的", "CET-4", "review", 17, -1440, 4, 14.5, ""),
    ("renowned", "adj. 著名的；有声望的", "考研", "learning", 1, -18, 1, 1.9, ""),
    ("celebrated", "adj. 著名的；有名望的", "GRE", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 24: 富有 ----
    ("rich", "adj. 富有的；丰富的", "CET-4", "review", 15, -720, 3, 10.5, ""),
    ("wealthy", "adj. 富有的；富裕的", "考研", "learning", 1, -14, 1, 1.8, ""),
    ("affluent", "adj. 富裕的；富足的", "GRE", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 25: 干净 ----
    ("clean", "adj. 干净的；清洁的", "CET-4", "review", 12, -720, 3, 9.5, ""),
    ("tidy", "adj. 整洁的；整齐的", "CET-6", "learning", 1, -9, 1, 1.3, ""),
    ("neat", "adj. 整洁的；利索的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 近义词组 26: 寒冷 ----
    ("cold", "adj. 寒冷的；冷的", "CET-4", "review", 11, -720, 3, 8.8, ""),
    ("chilly", "adj. 寒冷的；阴冷的", "CET-6", "learning", 1, -5, 1, 1.1, ""),
    ("freezing", "adj. 极冷的；冰冻的", "雅思", "new", 0, 0, 0, 0, ""),
    # ---- 其他单词（非近义词，作干扰项 + 测试其他功能）----
    ("computer", "n. 计算机；电脑", "CET-4", "review", 7, -1440, 3, 7.0, ""),
    ("telephone", "n. 电话；电话机", "CET-4", "new", 0, 0, 0, 0, ""),
    ("library", "n. 图书馆；藏书", "CET-4", "review", 9, -1440, 3, 6.5, ""),
    ("music", "n. 音乐；乐曲", "CET-4", "new", 0, 0, 0, 0, ""),
    ("science", "n. 科学；学科", "CET-4", "review", 11, -1440, 3, 8.5, ""),
    ("history", "n. 历史；历史学", "CET-4", "new", 0, 0, 0, 0, ""),
    ("abandon", "v. 放弃；抛弃；离弃", "考研,CET-6", "review", 14, -2880, 4, 13.0, "易混淆词"),
    ("abstract", "adj. 抽象的；n. 摘要", "CET-6,考研", "learning", 1, -20, 1, 2.2, ""),
    ("academic", "adj. 学术的；学院的", "考研,雅思", "review", 16, -2880, 4, 15.0, ""),
    ("economy", "n. 经济；节约", "CET-4,考研", "new", 0, 0, 0, 0, ""),
    ("environment", "n. 环境；外界", "CET-4,考研", "review", 13, -1440, 3, 10.0, ""),
    ("technology", "n. 技术；科技", "CET-4,雅思", "new", 0, 0, 0, 0, ""),
    ("government", "n. 政府；政体", "考研,托福", "review", 19, -2880, 5, 16.5, ""),
    ("education", "n. 教育；培养", "考研", "learning", 1, -22, 1, 2.3, ""),
    ("culture", "n. 文化；文明", "CET-4,托福", "review", 13, -1440, 3, 9.0, ""),
    ("society", "n. 社会；社团", "考研", "new", 0, 0, 0, 0, ""),
    ("language", "n. 语言；语言文字", "CET-4", "review", 10, -720, 3, 7.5, ""),
    ("knowledge", "n. 知识；学问", "雅思", "new", 0, 0, 0, 0, ""),
]


def build_db():
    conn = sqlite3.connect(":memory:")
    c = conn.cursor()

    # ---- 表结构（与 app_database.dart 保持一致）----
    c.executescript("""
    CREATE TABLE user_words (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      word            TEXT NOT NULL,
      sense_id        INTEGER DEFAULT 0,
      custom_def      TEXT,
      note            TEXT DEFAULT '',
      tags            TEXT DEFAULT '',
      is_favorite     INTEGER NOT NULL DEFAULT 0,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      card_state      TEXT NOT NULL DEFAULT 'new',
      stability       REAL DEFAULT 0,
      difficulty      REAL DEFAULT 0,
      reps            INTEGER NOT NULL DEFAULT 0,
      lapses          INTEGER NOT NULL DEFAULT 0,
      due             TEXT NOT NULL,
      last_review     TEXT,
      elapsed_days    REAL DEFAULT 0,
      scheduled_days  REAL DEFAULT 0
    );
    CREATE TABLE review_logs (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      user_word_id    INTEGER NOT NULL,
      rating          INTEGER NOT NULL,
      state           TEXT NOT NULL,
      elapsed_days    REAL,
      scheduled_days  REAL,
      reviewed_at     TEXT NOT NULL
    );
    CREATE TABLE fsrs_params (
      id                INTEGER PRIMARY KEY DEFAULT 1,
      parameters        TEXT NOT NULL,
      desired_retention REAL NOT NULL DEFAULT 0.9,
      optimized_at      TEXT,
      review_count      INTEGER DEFAULT 0,
      is_active         INTEGER NOT NULL DEFAULT 0,
      updated_at        TEXT NOT NULL
    );
    CREATE TABLE app_settings (
      key             TEXT PRIMARY KEY,
      value           TEXT NOT NULL,
      updated_at      TEXT NOT NULL
    );
    CREATE INDEX idx_uw_due ON user_words(due);
    CREATE INDEX idx_uw_state ON user_words(card_state);
    CREATE INDEX idx_uw_created ON user_words(created_at);
    CREATE INDEX idx_uw_fav ON user_words(is_favorite);
    CREATE INDEX idx_uw_tags ON user_words(tags);
    CREATE INDEX idx_rl_word ON review_logs(user_word_id);
    CREATE INDEX idx_rl_time ON review_logs(reviewed_at);
    """)

    # FTS5 外部内容表 + 触发器（与 app 一致）
    c.executescript("""
    CREATE VIRTUAL TABLE user_words_fts USING fts5(
      word, custom_def, note, tags,
      content='user_words', content_rowid='id',
      tokenize='unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER user_words_ai AFTER INSERT ON user_words BEGIN
      INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
      VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
    END;
    CREATE TRIGGER user_words_ad AFTER DELETE ON user_words BEGIN
      INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
      VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
    END;
    CREATE TRIGGER user_words_au AFTER UPDATE ON user_words BEGIN
      INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
      VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
      INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
      VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
    END;
    """)

    # ---- fsrs_params 默认数据 ----
    c.execute(
        "INSERT INTO fsrs_params (id, parameters, desired_retention, is_active, updated_at) "
        "VALUES (1, ?, 0.9, 0, ?)",
        (FSRS_PARAMS, iso(now_utc())),
    )

    # ---- 插入单词 ----
    now = now_utc()
    word_ids = {}
    review_logs = []

    for (word, custom_def, tags, state, created_days, due_min, reps,
         stability, note) in WORDS:
        created = days_ago(created_days)
        due = now + timedelta(minutes=due_min)
        updated = created
        difficulty = 5.0 if reps > 0 else 0.0
        last_review = iso(now - timedelta(days=1)) if reps > 0 else None
        is_fav = 1 if word in ("abandon", "important", "beautiful") else 0

        c.execute(
            """INSERT INTO user_words
               (word, sense_id, custom_def, note, tags, is_favorite,
                created_at, updated_at, card_state, stability, difficulty,
                reps, lapses, due, last_review, elapsed_days, scheduled_days)
               VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)""",
            (word, custom_def, note, tags, is_fav,
             iso(created), iso(updated), state, stability, difficulty,
             reps, iso(due), last_review, 0.0, stability),
        )
        wid = c.execute("SELECT last_insert_rowid()").fetchone()[0]
        word_ids[word] = wid

        # 为有复习次数的词生成复习记录
        for i in range(min(reps, 4)):
            reviewed_at = now - timedelta(days=created_days + i * 2, hours=1)
            rating = 4 if i == 0 else 3  # 第一次 easy，后续 good
            prev_state = "new" if i == 0 else ("learning" if i == 1 else "review")
            review_logs.append((wid, rating, prev_state, 0.0, stability, iso(reviewed_at)))

    # ---- 插入复习记录 ----
    c.executemany(
        """INSERT INTO review_logs
           (user_word_id, rating, state, elapsed_days, scheduled_days, reviewed_at)
           VALUES (?, ?, ?, ?, ?, ?)""",
        review_logs,
    )

    conn.commit()

    # 导出数据库文件
    db_bytes = b"".join(conn.iterdump()).encode("utf-8")  # 占位，实际用文件方式
    conn.close()

    return word_ids, review_logs


def write_db_file(path):
    """用文件方式重建数据库（iterdump 不可靠，直接重新建）"""
    conn = sqlite3.connect(path)
    c = conn.cursor()
    _create_and_fill(conn, c)
    conn.commit()
    conn.close()


def _create_and_fill(conn, c):
    c.executescript("""
    CREATE TABLE user_words (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      word            TEXT NOT NULL,
      sense_id        INTEGER DEFAULT 0,
      custom_def      TEXT,
      note            TEXT DEFAULT '',
      tags            TEXT DEFAULT '',
      is_favorite     INTEGER NOT NULL DEFAULT 0,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      card_state      TEXT NOT NULL DEFAULT 'new',
      stability       REAL DEFAULT 0,
      difficulty      REAL DEFAULT 0,
      reps            INTEGER NOT NULL DEFAULT 0,
      lapses          INTEGER NOT NULL DEFAULT 0,
      due             TEXT NOT NULL,
      last_review     TEXT,
      elapsed_days    REAL DEFAULT 0,
      scheduled_days  REAL DEFAULT 0
    );
    CREATE TABLE review_logs (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      user_word_id    INTEGER NOT NULL,
      rating          INTEGER NOT NULL,
      state           TEXT NOT NULL,
      elapsed_days    REAL,
      scheduled_days  REAL,
      reviewed_at     TEXT NOT NULL
    );
    CREATE TABLE fsrs_params (
      id                INTEGER PRIMARY KEY DEFAULT 1,
      parameters        TEXT NOT NULL,
      desired_retention REAL NOT NULL DEFAULT 0.9,
      optimized_at      TEXT,
      review_count      INTEGER DEFAULT 0,
      is_active         INTEGER NOT NULL DEFAULT 0,
      updated_at        TEXT NOT NULL
    );
    CREATE TABLE app_settings (
      key             TEXT PRIMARY KEY,
      value           TEXT NOT NULL,
      updated_at      TEXT NOT NULL
    );
    CREATE INDEX idx_uw_due ON user_words(due);
    CREATE INDEX idx_uw_state ON user_words(card_state);
    CREATE INDEX idx_uw_created ON user_words(created_at);
    CREATE INDEX idx_uw_fav ON user_words(is_favorite);
    CREATE INDEX idx_uw_tags ON user_words(tags);
    CREATE INDEX idx_rl_word ON review_logs(user_word_id);
    CREATE INDEX idx_rl_time ON review_logs(reviewed_at);
    CREATE VIRTUAL TABLE user_words_fts USING fts5(
      word, custom_def, note, tags,
      content='user_words', content_rowid='id',
      tokenize='unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER user_words_ai AFTER INSERT ON user_words BEGIN
      INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
      VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
    END;
    CREATE TRIGGER user_words_ad AFTER DELETE ON user_words BEGIN
      INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
      VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
    END;
    CREATE TRIGGER user_words_au AFTER UPDATE ON user_words BEGIN
      INSERT INTO user_words_fts(user_words_fts, rowid, word, custom_def, note, tags)
      VALUES ('delete', old.id, old.word, old.custom_def, old.note, old.tags);
      INSERT INTO user_words_fts(rowid, word, custom_def, note, tags)
      VALUES (new.id, new.word, new.custom_def, new.note, new.tags);
    END;
    """)

    c.execute(
        "INSERT INTO fsrs_params (id, parameters, desired_retention, is_active, updated_at) "
        "VALUES (1, ?, 0.9, 0, ?)",
        (FSRS_PARAMS, iso(now_utc())),
    )

    now = now_utc()
    review_logs = []

    for (word, custom_def, tags, state, created_days, due_min, reps,
         stability, note) in WORDS:
        created = days_ago(created_days)
        due = now + timedelta(minutes=due_min)
        updated = created
        difficulty = 5.0 if reps > 0 else 0.0
        last_review = iso(now - timedelta(days=1)) if reps > 0 else None
        is_fav = 1 if word in ("abandon", "important", "beautiful") else 0

        c.execute(
            """INSERT INTO user_words
               (word, sense_id, custom_def, note, tags, is_favorite,
                created_at, updated_at, card_state, stability, difficulty,
                reps, lapses, due, last_review, elapsed_days, scheduled_days)
               VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)""",
            (word, custom_def, note, tags, is_fav,
             iso(created), iso(updated), state, stability, difficulty,
             reps, iso(due), last_review, 0.0, stability),
        )
        wid = c.execute("SELECT last_insert_rowid()").fetchone()[0]

        for i in range(min(reps, 4)):
            reviewed_at = now - timedelta(days=created_days + i * 2, hours=1)
            rating = 4 if i == 0 else 3
            prev_state = "new" if i == 0 else ("learning" if i == 1 else "review")
            review_logs.append((wid, rating, prev_state, 0.0, stability, iso(reviewed_at)))

    c.executemany(
        """INSERT INTO review_logs
           (user_word_id, rating, state, elapsed_days, scheduled_days, reviewed_at)
           VALUES (?, ?, ?, ?, ?, ?)""",
        review_logs,
    )


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    import os
    import tempfile

    tmpdir = tempfile.mkdtemp()
    db_path = os.path.join(tmpdir, "vocabulary.db")
    write_db_file(db_path)

    # fsrs_params.json
    fsrs_json = json.dumps({
        "id": 1,
        "parameters": FSRS_PARAMS,
        "desired_retention": 0.9,
        "optimized_at": None,
        "review_count": 0,
        "is_active": 0,
        "updated_at": iso(now_utc()),
    }, ensure_ascii=False)
    fsrs_path = os.path.join(tmpdir, "fsrs_params.json")
    with open(fsrs_path, "w", encoding="utf-8") as f:
        f.write(fsrs_json)

    # 统计
    conn = sqlite3.connect(db_path)
    word_count = conn.execute("SELECT COUNT(*) FROM user_words").fetchone()[0]
    review_count = conn.execute("SELECT COUNT(*) FROM review_logs").fetchone()[0]
    state_counts = dict(conn.execute(
        "SELECT card_state, COUNT(*) FROM user_words GROUP BY card_state").fetchall())
    tag_counts = dict(conn.execute(
        "SELECT tags, COUNT(*) FROM user_words WHERE tags != '' GROUP BY tags").fetchall())
    conn.close()

    db_size = os.path.getsize(db_path)
    fsrs_size = os.path.getsize(fsrs_path)

    manifest = {
        "version": "1.0",
        "app_version": "1.0.5",
        "dict_version": "ecdict_mini_v2",
        "dict_word_count": 14945,
        "backup_time": iso(now_utc()),
        "user_word_count": word_count,
        "review_log_count": review_count,
        "streak_days": 0,
        "files": {
            "vocabulary.db": {
                "sha256": sha256_file(db_path),
                "size": db_size,
            },
            "fsrs_params.json": {
                "sha256": sha256_file(fsrs_path),
                "size": fsrs_size,
            },
        },
    }
    manifest_path = os.path.join(tmpdir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False)

    # 打包 zip
    with zipfile.ZipFile(OUTPUT_ZIP, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(manifest_path, "manifest.json")
        zf.write(db_path, "vocabulary.db")
        zf.write(fsrs_path, "fsrs_params.json")

    print(f"测试数据包已生成: {OUTPUT_ZIP}")
    print(f"  单词数: {word_count}")
    print(f"  复习记录数: {review_count}")
    print(f"  状态分布: {state_counts}")
    print(f"  数据库大小: {db_size} 字节")
    print(f"  sha256: {manifest['files']['vocabulary.db']['sha256']}")


if __name__ == "__main__":
    main()
