DROP DATABASE IF EXISTS fydp;
CREATE DATABASE fydp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE fydp;

CREATE TABLE schema_version (
    installed_rank INT           NOT NULL AUTO_INCREMENT,
    version        VARCHAR(50)   NOT NULL COMMENT 'e.g. 1.0, 2.0, 5.0',
    description    VARCHAR(500)  NOT NULL,
    script         VARCHAR(300)  NOT NULL COMMENT 'Filename of migration script',
    checksum       INT           NULL     COMMENT 'CRC32 of script content — set by migration runner',
    installed_by   VARCHAR(100)  NOT NULL DEFAULT 'DBA',
    installed_on   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    execution_time INT           NOT NULL DEFAULT 0 COMMENT 'ms',
    success        TINYINT(1)    NOT NULL DEFAULT 1,
    PRIMARY KEY (installed_rank),
    UNIQUE KEY uq_sv_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0 FIX 7] Flyway-compatible migration history — append-only';

INSERT INTO schema_version (version, description, script) VALUES
  ('1.0', 'Initial schema',                                        'V1__initial_schema.sql'),
  ('2.0', 'JSON to bridge tables; domain VARCHAR to FK',           'V2__bridge_tables_domain_fk.sql'),
  ('3.0', 'Section/trimester FKs; CGPA CHECK',                    'V3__section_trimester_fk.sql'),
  ('3.1', 'Messaging module',                                      'V3_1__messaging.sql'),
  ('4.0', 'Production hardening; uploaded_files; session mgmt',   'V4__production_hardening.sql'),
  ('5.0', 'Full-production perfect; all 7 critical fixes applied', 'V5__full_production_perfect.sql');

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1 — DATABASE CREATION (done above)
-- ─────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2 — TABLE DEFINITIONS
-- Table order strictly respects FK dependencies — zero forward references.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Reference / lookup tables ────────────────────────────────────────────────

CREATE TABLE departments (
    department_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    department_name VARCHAR(150)  NOT NULL COMMENT 'Full official name',
    short_code      VARCHAR(20)   NOT NULL COMMENT 'e.g. CSE, EEE, BBA',
    faculty         VARCHAR(150)  NULL     COMMENT 'Parent faculty name',
    is_active       TINYINT(1)    NOT NULL DEFAULT 1,
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (department_id),
    UNIQUE KEY uq_dept_name (department_name),
    UNIQUE KEY uq_dept_code (short_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Reference table — replaces raw VARCHAR department in users';

CREATE TABLE sections (
    section_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    section_code  VARCHAR(20)   NOT NULL COMMENT 'e.g. CSE-A, EEE-B',
    department_id INT UNSIGNED  NOT NULL,
    is_active     TINYINT(1)    NOT NULL DEFAULT 1,
    created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (section_id),
    UNIQUE KEY uq_section_code (section_code),
    CONSTRAINT fk_sec_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Reference table — replaces raw section_code VARCHAR';

CREATE TABLE trimesters (
    trimester_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    trimester_name VARCHAR(30)   NOT NULL COMMENT 'e.g. Spring 2026',
    start_date     DATE          NOT NULL,
    end_date       DATE          NOT NULL,
    is_active      TINYINT(1)    NOT NULL DEFAULT 1,
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (trimester_id),
    UNIQUE KEY uq_trim_name (trimester_name),
    CONSTRAINT chk_trim_dates CHECK (end_date > start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Reference table — replaces raw target_trimester VARCHAR';

CREATE TABLE skills (
    skill_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    skill_name     VARCHAR(100)  NOT NULL,
    skill_category VARCHAR(100)  NULL COMMENT 'e.g. Programming, AI/ML, DevOps',
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (skill_id),
    UNIQUE KEY uq_skill_name (skill_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master skill catalogue — shared across all modules';

CREATE TABLE project_domains (
    domain_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    domain_name VARCHAR(100)  NOT NULL,
    description TEXT          NULL,
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (domain_id),
    UNIQUE KEY uq_domain_name (domain_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master domain catalogue — shared across FYDP and Pre-FYDP modules';

CREATE TABLE fydp_stages (
    stage_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    stage_name  ENUM('FYDP-1','FYDP-2','FYDP-3') NOT NULL,
    stage_order TINYINT       NOT NULL COMMENT 'Ordering: 1, 2, 3',
    description TEXT          NULL,
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (stage_id),
    UNIQUE KEY uq_stage_name  (stage_name),
    UNIQUE KEY uq_stage_order (stage_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FYDP lifecycle stages — stage_order enforces forward-only promotion';

CREATE TABLE evaluation_weight_config (
    config_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    stage_id        INT UNSIGNED  NOT NULL,
    evaluation_type VARCHAR(100)  NOT NULL COMMENT 'e.g. MIDTERM, FINAL, PRESENTATION',
    weight_pct      DECIMAL(5,2)  NOT NULL COMMENT 'e.g. 40.00 means 40% of stage grade',
    effective_from  DATE          NOT NULL DEFAULT (CURRENT_DATE),
    is_active       TINYINT(1)    NOT NULL DEFAULT 1,
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (config_id),
    UNIQUE KEY uq_ewc_stage_type (stage_id, evaluation_type),
    CONSTRAINT chk_ewc_weight CHECK (weight_pct BETWEEN 0.00 AND 100.00),
    CONSTRAINT fk_ewc_stage FOREIGN KEY (stage_id) REFERENCES fydp_stages(stage_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0 FIX 5] Per-stage evaluation weights — configurable without schema changes';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 1: USER MANAGEMENT
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TABLE users (
    user_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    university_id    VARCHAR(20)   NOT NULL,
    full_name        VARCHAR(120)  NOT NULL,
    email            VARCHAR(150)  NOT NULL,
    password_hash    VARCHAR(255)  NOT NULL
                     COMMENT '[v4.0] bcrypt cost≥12 or Argon2id — NEVER SHA2/MD5/plain',
    role             ENUM('STUDENT','SUPERVISOR','COURSE_TEACHER',
                          'ADMIN','PRE_FYDP_STUDENT') NOT NULL DEFAULT 'STUDENT',
    department_id    INT UNSIGNED  NOT NULL,
    batch            VARCHAR(20)   NULL     COMMENT '[v8.0] e.g. B.Sc 57 — moved from user_profiles for login compatibility',
    phone            VARCHAR(20)   NULL,
    profile_photo    VARCHAR(500)  NULL
                     COMMENT 'External URL or internal path; system uploads → uploaded_files',
    account_status   ENUM('ACTIVE','SUSPENDED','DEACTIVATED') NOT NULL DEFAULT 'ACTIVE',
    is_active        TINYINT(1)    NOT NULL DEFAULT 1,
    deleted_at       DATETIME      NULL,
    last_changed_by  INT UNSIGNED  NULL
                     COMMENT '[v5.0 FIX 1] Written by procs only — read by audit trigger',
    created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email         (email),
    UNIQUE KEY uq_users_university_id (university_id),
    CONSTRAINT chk_users_soft_delete
        CHECK (
            (is_active = 1 AND deleted_at IS NULL)
            OR
            (is_active = 0 AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT fk_users_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] soft-delete CHECK constraint; [v5.0] last_changed_by for pool-safe audit';

CREATE TABLE uploaded_files (
    file_id         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    uploader_id     INT UNSIGNED     NOT NULL COMMENT 'FK → users',
    file_path       VARCHAR(500)     NOT NULL COMMENT 'Relative server path',
    original_name   VARCHAR(255)     NOT NULL COMMENT 'Original filename from client',
    mime_type       VARCHAR(100)     NOT NULL COMMENT 'e.g. application/pdf, image/png',
    file_size_bytes BIGINT UNSIGNED  NOT NULL,
    entity_type     ENUM('REPORT','TASK','TASK_SUBMISSION','GROUP_CHAT',
                         'DIRECT_MESSAGE','PROFILE','OTHER')
                                     NOT NULL DEFAULT 'OTHER',
    is_active       TINYINT(1)       NOT NULL DEFAULT 1,
    uploaded_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (file_id),
    CONSTRAINT fk_uf_uploader
        FOREIGN KEY (uploader_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] Central file registry — single source of truth for all uploads';

CREATE TABLE user_sessions (
    session_id    VARCHAR(128)  NOT NULL COMMENT 'UUID v4 — generated by application',
    user_id       INT UNSIGNED  NOT NULL,
    refresh_token VARCHAR(512)  NOT NULL COMMENT 'bcrypt-hashed refresh token',
    ip_address    VARCHAR(45)   NULL     COMMENT 'IPv4 or IPv6',
    user_agent    VARCHAR(500)  NULL,
    expires_at    DATETIME      NOT NULL,
    revoked_at    DATETIME      NULL     COMMENT 'NULL=valid; set on logout/revocation',
    created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (session_id),
    CONSTRAINT fk_us_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] JWT refresh token store with revocation support';

CREATE TABLE login_attempts (
    attempt_id   BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    email        VARCHAR(150)     NOT NULL COMMENT 'Attempted email — may not exist in users',
    ip_address   VARCHAR(45)      NOT NULL,
    was_success  TINYINT(1)       NOT NULL DEFAULT 0,
    attempted_at TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (attempt_id, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0 FIX 4] Range-partitioned by month; auto-provisioned; rate-limit log'
  PARTITION BY RANGE (UNIX_TIMESTAMP(attempted_at)) (
    PARTITION p_2026_01 VALUES LESS THAN (1769904000),
    PARTITION p_2026_02 VALUES LESS THAN (1772323200),
    PARTITION p_2026_03 VALUES LESS THAN (1775001600),
    PARTITION p_2026_04 VALUES LESS THAN (1777593600),
    PARTITION p_2026_05 VALUES LESS THAN (1780272000),
    PARTITION p_2026_06 VALUES LESS THAN (1782864000),
    PARTITION p_2026_07 VALUES LESS THAN (1785542400),
    PARTITION p_2026_08 VALUES LESS THAN (1788220800),
    PARTITION p_2026_09 VALUES LESS THAN (1790812800),
    PARTITION p_2026_10 VALUES LESS THAN (1793491200),
    PARTITION p_2026_11 VALUES LESS THAN (1796083200),
    PARTITION p_2026_12 VALUES LESS THAN (1798761600),
    PARTITION p_future   VALUES LESS THAN MAXVALUE
  );

CREATE TABLE password_reset_tokens (
    token_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_id    INT UNSIGNED  NOT NULL,
    token_hash VARCHAR(64)   NOT NULL COMMENT 'SHA2-256 of raw token',
    expires_at DATETIME      NOT NULL,
    used_at    DATETIME      NULL,
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (token_id),
    UNIQUE KEY uq_prt_token_hash (token_hash),
    CONSTRAINT fk_prt_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] Single-use password reset tokens — hashed and expiring';

CREATE TABLE user_status_log (
    log_id     BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_id    INT UNSIGNED     NOT NULL,
    old_status ENUM('ACTIVE','SUSPENDED','DEACTIVATED') NULL,
    new_status ENUM('ACTIVE','SUSPENDED','DEACTIVATED') NOT NULL,
    changed_by INT UNSIGNED     NULL COMMENT '[v5.0] From NEW.last_changed_by — pool-safe',
    reason     TEXT             NULL,
    changed_at DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id),
    CONSTRAINT fk_usl_user
        FOREIGN KEY (user_id)    REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_usl_changed_by
        FOREIGN KEY (changed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0] Immutable status history — changed_by from NEW.last_changed_by';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 2: FYDP-TRACK MATCHMAKING
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE matchmaking_team_invitations (
    invitation_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    sender_student_id   INT UNSIGNED  NOT NULL,
    receiver_student_id INT UNSIGNED  NOT NULL,
    invitation_message  TEXT          NULL,
    invitation_status   ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    responded_at        DATETIME      NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (invitation_id),
    CONSTRAINT fk_inv_sender
        FOREIGN KEY (sender_student_id)   REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_inv_receiver
        FOREIGN KEY (receiver_student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Team invitations — self-invite & duplicate-PENDING enforced by trigger';

CREATE TABLE notifications (
    notification_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_id               INT UNSIGNED  NOT NULL,
    notification_type     ENUM('INVITATION_RECEIVED','INVITATION_ACCEPTED',
                               'INVITATION_REJECTED','REPORT_APPROVED',
                               'REPORT_REJECTED','ESCALATION_COMPLETE',
                               'STAGE_PROMOTED','SYSTEM_ALERT',
                               'NEW_GROUP_MESSAGE','NEW_DIRECT_MESSAGE',
                               'TASK_ASSIGNED','TASK_REVIEWED',
                               'PASSWORD_RESET_REQUESTED') NOT NULL,
    title                 VARCHAR(255)  NULL,
    message               TEXT          NOT NULL,
    reference_entity_id   INT UNSIGNED  NULL,
    reference_entity_type ENUM('matchmaking_team_invitations','project_groups',
                               'course_teacher_inbox','weekly_progress_reports',
                               'pre_fydp_join_requests','group_chat_messages',
                               'direct_messages','group_tasks') NULL,
    is_read               TINYINT(1)    NOT NULL DEFAULT 0,
    created_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id),
    CONSTRAINT fk_notif_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] TASK_ASSIGNED, TASK_REVIEWED, PASSWORD_RESET_REQUESTED added';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 3: FYDP GROUP MANAGEMENT & ESCALATION ENGINE
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE announcements (
    announcement_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    author_id       INT UNSIGNED  NOT NULL,
    title           VARCHAR(255)  NOT NULL,
    content         TEXT          NOT NULL,
    target_role     ENUM('ALL','STUDENT','SUPERVISOR','COURSE_TEACHER','ADMIN','PRE_FYDP_STUDENT')
                                  NOT NULL DEFAULT 'ALL'
                                  COMMENT '[v6.0 FIX] ENUM replaces VARCHAR for 3NF domain constraint',
    section_id      INT UNSIGNED  NULL,
    is_active       TINYINT(1)    NOT NULL DEFAULT 1,
    deleted_at      DATETIME      NULL,
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (announcement_id),
    CONSTRAINT chk_ann_soft_delete
        CHECK (
            (is_active = 1 AND deleted_at IS NULL)
            OR
            (is_active = 0 AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT fk_ann_author
        FOREIGN KEY (author_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ann_section
        FOREIGN KEY (section_id) REFERENCES sections(section_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_ann_author (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] soft-delete CHECK constraint; [v4.0] section_id FK';

CREATE TABLE project_groups (
    group_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_code        VARCHAR(30)   NOT NULL,
    project_title     VARCHAR(300)  NOT NULL,
    project_domain_id INT UNSIGNED  NOT NULL,
    supervisor_id     INT UNSIGNED  NOT NULL,
    current_stage_id  INT UNSIGNED  NOT NULL,
    section_id        INT UNSIGNED  NOT NULL,
    project_status    ENUM('ACTIVE','COMPLETED','DROPPED','ON_HOLD') NOT NULL DEFAULT 'ACTIVE',
    is_active         TINYINT(1)    NOT NULL DEFAULT 1,
    deleted_at        DATETIME      NULL,
    last_changed_by   INT UNSIGNED  NULL
                      COMMENT '[v5.0 FIX 1] Pool-safe audit attribution',
    created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    UNIQUE KEY uq_group_code (group_code),
    CONSTRAINT chk_pg_soft_delete
        CHECK (
            (is_active = 1 AND deleted_at IS NULL)
            OR
            (is_active = 0 AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT fk_pg_domain
        FOREIGN KEY (project_domain_id) REFERENCES project_domains(domain_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pg_supervisor
        FOREIGN KEY (supervisor_id)     REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pg_stage
        FOREIGN KEY (current_stage_id)  REFERENCES fydp_stages(stage_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pg_section
        FOREIGN KEY (section_id)        REFERENCES sections(section_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] soft-delete CHECK constraint; [v5.0] last_changed_by for pool-safe audit';

CREATE TABLE group_evaluations (
    evaluation_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id           INT UNSIGNED  NOT NULL,
    teacher_id         INT UNSIGNED  NOT NULL,
    evaluation_type    VARCHAR(100)  NOT NULL COMMENT 'e.g. MIDTERM | FINAL | PRESENTATION',
    score              DECIMAL(5,2)  NOT NULL,
    weight_pct         DECIMAL(5,2)  NOT NULL DEFAULT 0.00
                       COMMENT '[v5.0] Copied from evaluation_weight_config at insert time',
    weighted_score     DECIMAL(7,4)  GENERATED ALWAYS AS (score * weight_pct / 100) STORED
                       COMMENT '[v5.0] score × weight_pct / 100 — stored generated column',
    feedback           TEXT          NULL,
    evaluated_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (evaluation_id),
    UNIQUE KEY uk_eval_group_type (group_id, evaluation_type),
    CONSTRAINT chk_eval_score  CHECK (score      BETWEEN 0.00 AND 100.00),
    CONSTRAINT chk_eval_weight CHECK (weight_pct BETWEEN 0.00 AND 100.00),
    CONSTRAINT fk_eval_group
        FOREIGN KEY (group_id)   REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_eval_teacher
        FOREIGN KEY (teacher_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_eval_group (group_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0 FIX 5] Weighted score (generated), grade band computed in view';

CREATE TABLE group_members (
    group_member_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id        INT UNSIGNED  NOT NULL,
    student_id      INT UNSIGNED  NOT NULL,
    member_role     ENUM('TEAM_LEAD','DEVELOPER','DESIGNER',
                         'RESEARCHER','TESTER','DATA_ENGINEER') NOT NULL DEFAULT 'DEVELOPER',
    joined_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_member_id),
    UNIQUE KEY uq_gm_group_student (group_id, student_id),
    CONSTRAINT fk_gm_group
        FOREIGN KEY (group_id)   REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gm_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: FYDP group ↔ student membership with role assignment';

CREATE TABLE course_teacher_sections (
    mapping_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    course_teacher_id INT UNSIGNED  NOT NULL,
    section_id        INT UNSIGNED  NOT NULL,
    assigned_stage_id INT UNSIGNED  NOT NULL,
    created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (mapping_id),
    UNIQUE KEY uq_cts (course_teacher_id, section_id, assigned_stage_id),
    CONSTRAINT fk_cts_teacher
        FOREIGN KEY (course_teacher_id) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_cts_section
        FOREIGN KEY (section_id)        REFERENCES sections(section_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cts_stage
        FOREIGN KEY (assigned_stage_id) REFERENCES fydp_stages(stage_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Maps course teachers to sections and FYDP stages';

CREATE TABLE weekly_progress_reports (
    report_id            INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    group_id             INT UNSIGNED      NOT NULL,
    student_id           INT UNSIGNED      NOT NULL,
    week_no              TINYINT UNSIGNED  NOT NULL,
    report_title         VARCHAR(300)      NOT NULL,
    report_content       LONGTEXT          NOT NULL,
    report_file_id       INT UNSIGNED      NULL,
    submitted_at         DATETIME          NULL,
    supervisor_status    ENUM('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
    supervisor_feedback  TEXT              NULL,
    supervisor_signed_at DATETIME          NULL,
    last_changed_by      INT UNSIGNED      NULL
                         COMMENT '[v5.0 FIX 1] Pool-safe audit attribution',
    is_active            TINYINT(1)        NOT NULL DEFAULT 1,
    deleted_at           DATETIME          NULL,
    created_at           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (report_id),
    UNIQUE KEY uq_report_weekly (group_id, student_id, week_no),
    CONSTRAINT chk_week_range CHECK (week_no BETWEEN 1 AND 52),
    CONSTRAINT chk_wpr_soft_delete
        CHECK (
            (is_active = 1 AND deleted_at IS NULL)
            OR
            (is_active = 0 AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT fk_wpr_group
        FOREIGN KEY (group_id)       REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_wpr_student
        FOREIGN KEY (student_id)     REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_wpr_file
        FOREIGN KEY (report_file_id) REFERENCES uploaded_files(file_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] soft-delete CHECK constraint; [v5.0] last_changed_by for pool-safe audit';

CREATE TABLE course_teacher_inbox (
    inbox_id          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    group_id          INT UNSIGNED      NOT NULL,
    week_no           TINYINT UNSIGNED  NOT NULL,
    escalated_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    escalation_status ENUM('IN_PROGRESS','PENDING_REVIEW','REVIEWED','FLAGGED')
                                        NOT NULL DEFAULT 'IN_PROGRESS',
    reviewed_at       DATETIME          NULL,
    reviewed_by       INT UNSIGNED      NULL,
    notes             TEXT              NULL,
    PRIMARY KEY (inbox_id),
    UNIQUE KEY uq_inbox_group_week (group_id, week_no),
    CONSTRAINT fk_inbox_group
        FOREIGN KEY (group_id)    REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_inbox_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v7.0] 3NF fix — derived counts removed; computed in views; reviewed_by role-guarded by trigger';

CREATE TABLE topic_change_history (
    history_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id          INT UNSIGNED  NOT NULL,
    old_domain_id     INT UNSIGNED  NULL,
    new_domain_id     INT UNSIGNED  NULL,
    old_project_title VARCHAR(300)  NULL,
    new_project_title VARCHAR(300)  NULL,
    changed_by_admin  INT UNSIGNED  NOT NULL,
    change_reason     TEXT          NOT NULL,
    changed_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    CONSTRAINT fk_tch_group
        FOREIGN KEY (group_id)         REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_tch_old_domain
        FOREIGN KEY (old_domain_id)    REFERENCES project_domains(domain_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tch_new_domain
        FOREIGN KEY (new_domain_id)    REFERENCES project_domains(domain_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tch_admin
        FOREIGN KEY (changed_by_admin) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit: title/domain changes — append-only';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 4: IMPORT PIPELINE & ENTERPRISE AUDIT
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE import_error_logs (
    error_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    error_row     INT           NOT NULL,
    error_message VARCHAR(500)  NOT NULL,
    raw_data      TEXT          NULL,
    logged_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (error_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Row-level error log for bulk UCAM CSV import failures';

CREATE TABLE ucam_import_staging (
    staging_id                   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    raw_student_university_id    VARCHAR(50)   NULL,
    raw_group_code               VARCHAR(50)   NULL,
    raw_supervisor_university_id VARCHAR(50)   NULL,
    raw_stage_name               VARCHAR(50)   NULL,
    raw_project_title            VARCHAR(300)  NULL,
    raw_domain_name              VARCHAR(100)  NULL,
    import_batch_id              VARCHAR(50)   NULL,
    imported_at                  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (staging_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Staging table — intentionally FK-free (raw CSV data)';

CREATE TABLE audit_log (
    audit_id   BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    table_name VARCHAR(100)     NOT NULL,
    operation  ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id  INT UNSIGNED     NOT NULL,
    changed_by INT UNSIGNED     NULL COMMENT '[v5.0] From NEW.last_changed_by — pool-safe',
    old_data   JSON             NULL,
    new_data   JSON             NULL,
    changed_at TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id, changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v5.0 FIX 1+4] Pool-safe audit; range-partitioned by month'
  PARTITION BY RANGE (UNIX_TIMESTAMP(changed_at)) (
    PARTITION p_2026_01 VALUES LESS THAN (1769904000),
    PARTITION p_2026_02 VALUES LESS THAN (1772323200),
    PARTITION p_2026_03 VALUES LESS THAN (1775001600),
    PARTITION p_2026_04 VALUES LESS THAN (1777593600),
    PARTITION p_2026_05 VALUES LESS THAN (1780272000),
    PARTITION p_2026_06 VALUES LESS THAN (1782864000),
    PARTITION p_2026_07 VALUES LESS THAN (1785542400),
    PARTITION p_2026_08 VALUES LESS THAN (1788220800),
    PARTITION p_2026_09 VALUES LESS THAN (1790812800),
    PARTITION p_2026_10 VALUES LESS THAN (1793491200),
    PARTITION p_2026_11 VALUES LESS THAN (1796083200),
    PARTITION p_2026_12 VALUES LESS THAN (1798761600),
    PARTITION p_future   VALUES LESS THAN MAXVALUE
  );

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 5: PRE-FYDP TEAM BUILDING PLATFORM
-- ══════════════════════════════════════════════════════════════════════════════

-- [v6.0] user_profiles: merged student_profiles + pre_fydp_profiles
CREATE TABLE user_profiles (
    profile_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_id             INT UNSIGNED  NOT NULL,
    profile_type        ENUM('FYDP', 'PRE_FYDP') NOT NULL
                        COMMENT 'FYDP = active FYDP student; PRE_FYDP = pre-FYDP student',
    batch               VARCHAR(20)   NULL     COMMENT 'e.g. B.Sc 57, B.Sc 59',
    bio                 TEXT          NULL,
    cgpa                DECIMAL(4,2)  NULL,
    github_url          VARCHAR(500)  NULL,
    linkedin_url        VARCHAR(500)  NULL,
    portfolio_url       VARCHAR(500)  NULL,
    preferred_role      VARCHAR(60)   NULL
                        COMMENT 'FYDP roles: TEAM_LEAD/DEVELOPER/DESIGNER/RESEARCHER/TESTER/DATA_ENGINEER; PRE_FYDP roles: FULL_STACK_DEVELOPER/FRONTEND_DEVELOPER/BACKEND_DEVELOPER/ML_ENGINEER/DATA_SCIENTIST/SECURITY_ANALYST/EMBEDDED_DEVELOPER/UI_UX_DESIGNER/DEVOPS_ENGINEER/OTHER',
    trimester_id        INT UNSIGNED  NULL,
    availability_status ENUM('LOOKING', 'IN_TEAM', 'NOT_AVAILABLE') NOT NULL DEFAULT 'LOOKING',
    profile_strength    TINYINT UNSIGNED NULL DEFAULT NULL
                        COMMENT 'NULL for FYDP students; 0-100 for PRE_FYDP students',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (profile_id),
    UNIQUE KEY uq_up_user_id (user_id),
    CONSTRAINT chk_up_cgpa         CHECK (cgpa IS NULL OR cgpa BETWEEN 0.00 AND 4.00),
    CONSTRAINT chk_up_profile_str  CHECK (profile_strength IS NULL OR profile_strength <= 100),
    CONSTRAINT chk_up_preferred_role CHECK (
        preferred_role IS NULL
        OR preferred_role IN (
            'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER',
            'FULL_STACK_DEVELOPER','FRONTEND_DEVELOPER','BACKEND_DEVELOPER',
            'ML_ENGINEER','DATA_SCIENTIST','SECURITY_ANALYST',
            'EMBEDDED_DEVELOPER','UI_UX_DESIGNER','DEVOPS_ENGINEER','OTHER'
        )
    ),
    CONSTRAINT fk_up_user
        FOREIGN KEY (user_id)      REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_up_trimester
        FOREIGN KEY (trimester_id) REFERENCES trimesters(trimester_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v7.0] preferred_role CHECK constraint; [v6.0] merged student_profiles + pre_fydp_profiles';

-- [v6.0] user_skills: merged student_skills + pre_fydp_student_skills
CREATE TABLE user_skills (
    user_id           INT UNSIGNED  NOT NULL,
    skill_id          INT UNSIGNED  NOT NULL,
    proficiency_level ENUM('BEGINNER','INTERMEDIATE','ADVANCED','EXPERT') NOT NULL DEFAULT 'BEGINNER',
    years_experience  DECIMAL(4,1)  NULL DEFAULT 0.0
                      COMMENT 'NULL acceptable for Pre-FYDP students who have not entered this',
    created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, skill_id),
    CONSTRAINT fk_uskills_user  FOREIGN KEY (user_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_us_skill FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] Merged student_skills + pre_fydp_student_skills — unified skill registry';

-- [v6.0] user_domain_interests: merged student_domain_interests + pre_fydp_student_domain_interests
CREATE TABLE user_domain_interests (
    user_id        INT UNSIGNED  NOT NULL,
    domain_id      INT UNSIGNED  NOT NULL,
    interest_level ENUM('LOW','MEDIUM','HIGH') NOT NULL DEFAULT 'MEDIUM',
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, domain_id),
    CONSTRAINT fk_udi_user   FOREIGN KEY (user_id)   REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_udi_domain FOREIGN KEY (domain_id) REFERENCES project_domains(domain_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] Merged student_domain_interests + pre_fydp_student_domain_interests';

CREATE TABLE pre_fydp_groups (
    group_id     INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    group_name   VARCHAR(200)      NOT NULL,
    domain_id    INT UNSIGNED      NOT NULL,
    description  TEXT              NULL,
    max_members  TINYINT UNSIGNED  NOT NULL DEFAULT 5,
    github_url   VARCHAR(500)      NULL,
    created_by   INT UNSIGNED      NOT NULL,
    group_status ENUM('OPEN','FULL','CLOSED') NOT NULL DEFAULT 'OPEN',
    is_active    TINYINT(1)        NOT NULL DEFAULT 1,
    deleted_at   DATETIME          NULL,
    created_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    CONSTRAINT chk_pfg_max_members CHECK (max_members > 0),
    CONSTRAINT chk_pfg_soft_delete
        CHECK (
            (is_active = 1 AND deleted_at IS NULL)
            OR
            (is_active = 0 AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT fk_pfg_creator FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_pfg_domain  FOREIGN KEY (domain_id)  REFERENCES project_domains(domain_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v6.0] soft-delete CHECK constraint; [v4.0] CHECK(max_members>0)';

CREATE TABLE pre_fydp_group_required_skills (
    group_id   INT UNSIGNED  NOT NULL,
    skill_id   INT UNSIGNED  NOT NULL,
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id, skill_id),
    CONSTRAINT fk_pfgrs_group FOREIGN KEY (group_id) REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfgrs_skill FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Pre-FYDP group ↔ required skill (1NF fix)';

CREATE TABLE pre_fydp_group_members (
    member_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id    INT UNSIGNED  NOT NULL,
    user_id     INT UNSIGNED  NOT NULL,
    member_role ENUM('Lead','Frontend','Backend','ML Engineer',
                     'DevOps','Security','Tester','Data Engineer','Other') NULL,
    joined_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),
    UNIQUE KEY uq_pfgm (group_id, user_id),
    CONSTRAINT fk_pfgm_group FOREIGN KEY (group_id) REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfgm_user  FOREIGN KEY (user_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] Bridge: Pre-FYDP group ↔ student — availability auto-updated by trigger';

CREATE TABLE pre_fydp_join_requests (
    request_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id       INT UNSIGNED  NOT NULL,
    sender_id      INT UNSIGNED  NOT NULL,
    request_type   ENUM('JOIN_REQUEST','INVITATION') NOT NULL DEFAULT 'JOIN_REQUEST',
    message        TEXT          NULL,
    request_status ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    responded_at   DATETIME      NULL,
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (request_id),
    CONSTRAINT fk_pfjr_group  FOREIGN KEY (group_id)  REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfjr_sender FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] Duplicate-PENDING prevention enforced by trigger';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 6: MESSAGING, COMMUNICATION & TASK MANAGEMENT
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE group_tasks (
    task_id       INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    group_id      INT UNSIGNED      NOT NULL,
    supervisor_id INT UNSIGNED      NOT NULL,
    week_no       TINYINT UNSIGNED  NOT NULL,
    title         VARCHAR(255)      NOT NULL,
    description   TEXT              NULL,
    task_file_id  INT UNSIGNED      NULL,
    due_date      DATE              NULL,
    created_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_id),
    CONSTRAINT fk_gtask_group      FOREIGN KEY (group_id)     REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gtask_supervisor FOREIGN KEY (supervisor_id) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gtask_file       FOREIGN KEY (task_file_id)  REFERENCES uploaded_files(file_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_gtask_group (group_id),
    INDEX idx_gtask_week  (group_id, week_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] task_file_id FK → uploaded_files';

CREATE TABLE group_task_submissions (
    submission_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    task_id            INT UNSIGNED  NOT NULL,
    student_id         INT UNSIGNED  NOT NULL,
    status             ENUM('SUBMITTED','ACKNOWLEDGED','NEEDS_REVISION')
                                     NOT NULL DEFAULT 'SUBMITTED',
    student_note       TEXT          NULL,
    attachment_file_id INT UNSIGNED  NULL,
    submitted_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at        DATETIME      NULL,
    reviewed_by        INT UNSIGNED  NULL,
    PRIMARY KEY (submission_id),
    UNIQUE KEY uq_gts_task_student (task_id, student_id),
    CONSTRAINT fk_gts_task
        FOREIGN KEY (task_id)            REFERENCES group_tasks(task_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_gts_student
        FOREIGN KEY (student_id)         REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_gts_attachment
        FOREIGN KEY (attachment_file_id) REFERENCES uploaded_files(file_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_gts_reviewer
        FOREIGN KEY (reviewed_by)        REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0 NEW] Per-student task completion with supervisor review lifecycle';

CREATE TABLE group_chat_messages (
    message_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    group_id           INT UNSIGNED  NOT NULL,
    sender_id          INT UNSIGNED  NOT NULL,
    message_text       TEXT          NULL,
    attachment_file_id INT UNSIGNED  NULL,
    attachment_path    VARCHAR(500)  NULL     COMMENT '[v8.0] Legacy direct path for chat attachments',
    attachment_name    VARCHAR(255)  NULL     COMMENT '[v8.0] Original filename for chat attachments',
    chat_type          ENUM('STUDENT_ONLY','WITH_SUPERVISOR','WITH_TEACHER')
                                     NOT NULL DEFAULT 'STUDENT_ONLY',
    created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id),
    CONSTRAINT fk_gcm_group
        FOREIGN KEY (group_id)           REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gcm_sender
        FOREIGN KEY (sender_id)          REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gcm_attachment
        FOREIGN KEY (attachment_file_id) REFERENCES uploaded_files(file_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] attachment_file_id FK → uploaded_files; [v8.0] attachment_path/name legacy columns';

CREATE TABLE direct_messages (
    message_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    sender_id          INT UNSIGNED  NOT NULL,
    receiver_id        INT UNSIGNED  NOT NULL,
    message_text       TEXT          NULL,
    attachment_file_id INT UNSIGNED  NULL,
    attachment_path    VARCHAR(500)  NULL     COMMENT '[v8.0] Legacy direct path for DM attachments',
    attachment_name    VARCHAR(255)  NULL     COMMENT '[v8.0] Original filename for DM attachments',
    is_read            TINYINT(1)    NOT NULL DEFAULT 0,
    created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id),
    CONSTRAINT fk_dm_sender
        FOREIGN KEY (sender_id)          REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_dm_receiver
        FOREIGN KEY (receiver_id)        REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_dm_attachment
        FOREIGN KEY (attachment_file_id) REFERENCES uploaded_files(file_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v4.0] attachment_file_id FK → uploaded_files; [v8.0] attachment_path/name legacy columns';


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — HIGH-PERFORMANCE INDEXING STRATEGY
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX idx_dept_active           ON departments(is_active);
CREATE INDEX idx_sec_dept              ON sections(department_id);
CREATE INDEX idx_sec_active            ON sections(is_active);
CREATE INDEX idx_trim_active           ON trimesters(is_active);
CREATE INDEX idx_users_role            ON users(role);
CREATE INDEX idx_users_dept            ON users(department_id);
CREATE INDEX idx_users_acct_status     ON users(account_status);
CREATE INDEX idx_users_is_active       ON users(is_active);
CREATE INDEX idx_users_deleted_at      ON users(deleted_at);

CREATE INDEX idx_uf_uploader           ON uploaded_files(uploader_id);
CREATE INDEX idx_uf_entity_type        ON uploaded_files(entity_type);
CREATE INDEX idx_uf_uploaded_at        ON uploaded_files(uploaded_at);

CREATE INDEX idx_us_user               ON user_sessions(user_id);
CREATE INDEX idx_us_expires            ON user_sessions(expires_at);
CREATE INDEX idx_us_active_lookup      ON user_sessions(user_id, revoked_at, expires_at);

CREATE INDEX idx_la_email              ON login_attempts(email);
CREATE INDEX idx_la_ip                 ON login_attempts(ip_address);

CREATE INDEX idx_prt_user              ON password_reset_tokens(user_id);
CREATE INDEX idx_prt_expires           ON password_reset_tokens(expires_at);
CREATE INDEX idx_usl_user              ON user_status_log(user_id);
CREATE INDEX idx_usl_changed_at        ON user_status_log(changed_at);

-- [v6.0] Indexes on unified user_profiles (replaces idx_sp_* and idx_pfp_*)
CREATE INDEX idx_up_availability       ON user_profiles(availability_status);
CREATE INDEX idx_up_trimester          ON user_profiles(trimester_id);
CREATE INDEX idx_up_profile_type       ON user_profiles(profile_type);

-- [v6.0] Indexes on unified user_skills (replaces idx_ss_skill_id and idx_pfss_skill_id)
CREATE INDEX idx_us_skill_id           ON user_skills(skill_id);

-- [v6.0] Indexes on unified user_domain_interests (replaces idx_sdi_domain_id and idx_pfsdi_domain_id)
CREATE INDEX idx_udi_domain_id         ON user_domain_interests(domain_id);

CREATE INDEX idx_inv_receiver          ON matchmaking_team_invitations(receiver_student_id);
CREATE INDEX idx_inv_sender            ON matchmaking_team_invitations(sender_student_id);
CREATE INDEX idx_inv_status            ON matchmaking_team_invitations(invitation_status);
CREATE INDEX idx_notif_user_unread     ON notifications(user_id, is_read);
CREATE INDEX idx_notif_type            ON notifications(notification_type);
CREATE INDEX idx_ann_section           ON announcements(section_id);
CREATE INDEX idx_ann_active            ON announcements(is_active);
CREATE INDEX idx_ann_deleted           ON announcements(deleted_at);

CREATE INDEX idx_pg_supervisor         ON project_groups(supervisor_id);
CREATE INDEX idx_pg_stage              ON project_groups(current_stage_id);
CREATE INDEX idx_pg_section            ON project_groups(section_id);
CREATE INDEX idx_pg_domain             ON project_groups(project_domain_id);
CREATE INDEX idx_pg_status             ON project_groups(project_status);
CREATE INDEX idx_pg_deleted            ON project_groups(deleted_at);
CREATE FULLTEXT INDEX ft_project_title ON project_groups(project_title);

CREATE INDEX idx_ge_teacher            ON group_evaluations(teacher_id);
CREATE INDEX idx_gm_student            ON group_members(student_id);
CREATE INDEX idx_cts_stage             ON course_teacher_sections(assigned_stage_id);
CREATE INDEX idx_cts_section           ON course_teacher_sections(section_id);

CREATE INDEX idx_wpr_supervisor_status ON weekly_progress_reports(supervisor_status);
CREATE INDEX idx_wpr_week_no           ON weekly_progress_reports(week_no);
CREATE INDEX idx_wpr_group             ON weekly_progress_reports(group_id);
CREATE INDEX idx_wpr_student           ON weekly_progress_reports(student_id);
CREATE INDEX idx_wpr_escalation        ON weekly_progress_reports(group_id, week_no, supervisor_status);
CREATE INDEX idx_wpr_ct_dashboard      ON weekly_progress_reports(group_id, supervisor_status, week_no);
CREATE INDEX idx_wpr_deleted           ON weekly_progress_reports(deleted_at);

CREATE INDEX idx_inbox_status          ON course_teacher_inbox(escalation_status);
CREATE INDEX idx_inbox_group           ON course_teacher_inbox(group_id);
CREATE INDEX idx_tch_group             ON topic_change_history(group_id);
CREATE INDEX idx_tch_changed_at        ON topic_change_history(changed_at);

CREATE INDEX idx_audit_table           ON audit_log(table_name, operation);
CREATE INDEX idx_audit_user            ON audit_log(changed_by);

CREATE INDEX idx_pfg_domain            ON pre_fydp_groups(domain_id);
CREATE INDEX idx_pfg_creator           ON pre_fydp_groups(created_by);
CREATE INDEX idx_pfg_status            ON pre_fydp_groups(group_status);
CREATE INDEX idx_pfg_deleted           ON pre_fydp_groups(deleted_at);
CREATE FULLTEXT INDEX ft_pfg_name_desc ON pre_fydp_groups(group_name, description);

CREATE INDEX idx_pfgrs_skill           ON pre_fydp_group_required_skills(skill_id);
CREATE INDEX idx_pfjr_sender           ON pre_fydp_join_requests(sender_id);
CREATE INDEX idx_pfjr_status           ON pre_fydp_join_requests(request_status);
CREATE INDEX idx_gtask_file            ON group_tasks(task_file_id);
CREATE INDEX idx_gts_student           ON group_task_submissions(student_id);
CREATE INDEX idx_gts_status            ON group_task_submissions(status);
CREATE INDEX idx_gts_reviewed_by       ON group_task_submissions(reviewed_by);
CREATE INDEX idx_gcm_group_type        ON group_chat_messages(group_id, chat_type);
CREATE INDEX idx_gcm_group_created     ON group_chat_messages(group_id, created_at);
CREATE INDEX idx_gcm_sender            ON group_chat_messages(sender_id);
CREATE INDEX idx_gcm_attachment        ON group_chat_messages(attachment_file_id);
CREATE INDEX idx_dm_receiver_read      ON direct_messages(receiver_id, is_read);
CREATE INDEX idx_dm_sender             ON direct_messages(sender_id);
CREATE INDEX idx_dm_conversation       ON direct_messages(sender_id, receiver_id, created_at);
CREATE INDEX idx_dm_attachment         ON direct_messages(attachment_file_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 — SAMPLE DATA
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 4.1 DEPARTMENTS ──────────────────────────────────────────────────────────
INSERT INTO departments (department_name, short_code, faculty) VALUES
  ('Administration',                        'ADMIN', 'Central Administration'),
  ('Computer Science and Engineering',      'CSE',   'Faculty of Science and Engineering'),
  ('Electrical and Electronic Engineering', 'EEE',   'Faculty of Science and Engineering'),
  ('Business Administration',               'BBA',   'Faculty of Business and Economics'),
  ('Civil Engineering',                     'CE',    'Faculty of Science and Engineering');

-- ── 4.2 SECTIONS ─────────────────────────────────────────────────────────────
INSERT INTO sections (section_code, department_id) VALUES
  ('CSE-A', (SELECT department_id FROM departments WHERE short_code='CSE')),
  ('CSE-B', (SELECT department_id FROM departments WHERE short_code='CSE')),
  ('CSE-C', (SELECT department_id FROM departments WHERE short_code='CSE')),
  ('CSE-D', (SELECT department_id FROM departments WHERE short_code='CSE')),
  ('EEE-A', (SELECT department_id FROM departments WHERE short_code='EEE'));

-- ── 4.3 TRIMESTERS ───────────────────────────────────────────────────────────
INSERT INTO trimesters (trimester_name, start_date, end_date) VALUES
  ('Spring 2025', '2025-01-10', '2025-05-15'),
  ('Summer 2025', '2025-06-01', '2025-08-31'),
  ('Fall 2025',   '2025-09-10', '2025-12-31'),
  ('Spring 2026', '2026-01-10', '2026-05-15');

-- ── 4.4 SKILLS ───────────────────────────────────────────────────────────────
INSERT INTO skills (skill_name, skill_category) VALUES
  ('Python','Programming'),('Java','Programming'),('C++','Programming'),
  ('JavaScript','Programming'),('Spring Boot','Backend'),('Node.js','Backend'),
  ('Backend Development','Backend'),('React','Frontend'),('Vue.js','Frontend'),
  ('CSS','Frontend'),('Frontend Development','Frontend'),('Figma','Design'),
  ('UI/UX Design','Design'),('MySQL','Database'),('PostgreSQL','Database'),
  ('MongoDB','Database'),('Machine Learning','AI/ML'),('Deep Learning','AI/ML'),
  ('NLP','AI/ML'),('TensorFlow','AI/ML'),('PyTorch','AI/ML'),('OpenCV','AI/ML'),
  ('Data Science','Analytics'),('D3.js','Analytics'),('Cybersecurity','Security'),
  ('Kali Linux','Security'),('Wireshark','Security'),('Networking','Networking'),
  ('IoT','Hardware'),('Arduino','Hardware'),('Raspberry Pi','Hardware'),
  ('MQTT','Hardware'),('Docker','DevOps'),('AWS','Cloud'),('Flutter','Mobile'),
  ('React Native','Mobile'),('Blockchain','Emerging Tech');

-- ── 4.5 PROJECT DOMAINS ──────────────────────────────────────────────────────
INSERT INTO project_domains (domain_name, description) VALUES
  ('Artificial Intelligence','AI and intelligent systems'),
  ('NLP','Natural Language Processing applications'),
  ('FinTech','Financial technology and digital payments'),
  ('Health Informatics','Healthcare data management and analytics'),
  ('IoT','Internet of Things and embedded systems'),
  ('Cybersecurity','Network and application security'),
  ('Data Analytics','Big data and business intelligence'),
  ('Mobile Application','Cross-platform mobile app development'),
  ('Machine Learning','ML model development and deployment'),
  ('Software Engineering','Large-scale software systems'),
  ('Cloud Computing','Cloud-native and containerized applications'),
  ('Embedded Systems','Low-level hardware and firmware development');

-- ── 4.6 FYDP STAGES ──────────────────────────────────────────────────────────
INSERT INTO fydp_stages (stage_name, stage_order, description) VALUES
  ('FYDP-1', 1, 'Proposal, literature review, and initial planning'),
  ('FYDP-2', 2, 'Implementation, development, and testing'),
  ('FYDP-3', 3, 'Final presentation, thesis submission, and viva');

-- ── 4.6b EVALUATION WEIGHTS  [v5.0 FIX 5] ───────────────────────────────────
INSERT INTO evaluation_weight_config (stage_id, evaluation_type, weight_pct) VALUES
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1'),'MIDTERM',      40.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1'),'FINAL',        60.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-2'),'MIDTERM',      30.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-2'),'PRESENTATION', 30.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-2'),'FINAL',        40.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-3'),'PRESENTATION', 40.00),
  ((SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-3'),'FINAL',        60.00);

-- ── 4.7 USERS ────────────────────────────────────────────────────────────────
SET @d_admin = (SELECT department_id FROM departments WHERE short_code='ADMIN');
SET @d_cse   = (SELECT department_id FROM departments WHERE short_code='CSE');
SET @d_eee   = (SELECT department_id FROM departments WHERE short_code='EEE');

INSERT INTO users
  (university_id, full_name, email, password_hash, role, department_id, phone, account_status)
VALUES
  ('ADMIN001','Dr. Rafiqul Islam',  'admin@uiu.ac.bd',
   SHA2('admin123', 256),'ADMIN',            @d_admin,'01711000001','ACTIVE'),
  ('SUP001',  'Dr. Tanvir Ahmed',   'tanvir@uiu.ac.bd',
   SHA2('sup123', 256), 'SUPERVISOR',       @d_cse,  '01711000002','ACTIVE'),
  ('SUP002',  'Dr. Nadia Rahman',   'nadia@uiu.ac.bd',
   SHA2('sup123', 256), 'SUPERVISOR',       @d_cse,  '01711000003','ACTIVE'),
  ('SUP003',  'Dr. Karim Hossain',  'karim@uiu.ac.bd',
   SHA2('sup123', 256), 'SUPERVISOR',       @d_eee,  '01711000004','ACTIVE'),
  ('CT001',   'Mr. Shafiq Alam',    'shafiq@uiu.ac.bd',
   SHA2('ct123', 256),  'COURSE_TEACHER',   @d_cse,  '01711000005','ACTIVE'),
  ('CT002',   'Ms. Farhana Begum',  'farhana@uiu.ac.bd',
   SHA2('ct123', 256),  'COURSE_TEACHER',   @d_cse,  '01711000006','ACTIVE'),
  ('STU001',  'Arif Hasan',         'arif@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000001','ACTIVE'),
  ('STU002',  'Bristy Akter',       'bristy@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000002','ACTIVE'),
  ('STU003',  'Cyrus Khan',         'cyrus@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000003','ACTIVE'),
  ('STU004',  'Dina Sultana',       'dina@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000004','ACTIVE'),
  ('STU005',  'Emon Chowdhury',     'emon@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000005','ACTIVE'),
  ('STU006',  'Farhan Islam',       'farhan@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000006','ACTIVE'),
  ('STU007',  'Gita Roy',           'gita@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000007','ACTIVE'),
  ('STU008',  'Hasan Ali',          'hasan@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000008','ACTIVE'),
  ('STU009',  'Israt Jahan',        'israt@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000009','ACTIVE'),
  ('STU010',  'Jahir Uddin',        'jahir@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000010','ACTIVE'),
  ('STU011',  'Kamrul Bashar',      'kamrul@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000011','ACTIVE'),
  ('STU012',  'Lima Khanam',        'lima@student.uiu.ac.bd',
   SHA2('stu123', 256), 'STUDENT',          @d_cse,  '01811000012','ACTIVE'),
  ('PFYDP001','Suvrojit Bose',      'suvrojit@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_cse,  '01911000001','ACTIVE'),
  ('PFYDP002','Zainab Ali',         'zainab@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_cse,  '01911000002','ACTIVE'),
  ('PFYDP003','Hamza Iqbal',        'hamza@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_cse,  '01911000003','ACTIVE'),
  ('PFYDP004','Nusrat Jahan',       'nusrat@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_cse,  '01911000004','ACTIVE'),
  ('PFYDP005','Rafiq Ahmed',        'rafiq@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_cse,  '01911000005','ACTIVE'),
  ('PFYDP006','Samira Begum',       'samira@student.uiu.ac.bd',
   SHA2('pre123', 256),  'PRE_FYDP_STUDENT', @d_eee,  '01911000006','ACTIVE');

-- ── 4.8 USER PROFILES [v6.0] — merged FYDP student profiles ─────────────────
SET @trim_sp25 = (SELECT trimester_id FROM trimesters WHERE trimester_name='Spring 2025');

INSERT INTO user_profiles
  (user_id, profile_type, batch, cgpa, bio, github_url, linkedin_url,
   preferred_role, trimester_id, availability_status, profile_strength)
SELECT
  u.user_id,
  'FYDP',
  'B.Sc 57',
  ROUND(2.80 + (RAND() * 1.20), 2),
  'Passionate CSE student with interest in AI and software development.',
  CONCAT('https://github.com/', LOWER(REPLACE(u.full_name,' ','_'))),
  CONCAT('https://linkedin.com/in/', LOWER(REPLACE(u.full_name,' ','-'))),
  ELT(FLOOR(1+RAND()*6),'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER'),
  @trim_sp25,
  'LOOKING',
  NULL
FROM users u WHERE u.role = 'STUDENT';

-- ── 4.9 USER SKILLS [v6.0] — all users (FYDP + Pre-FYDP) ───────────────────
INSERT INTO user_skills (user_id, skill_id, proficiency_level, years_experience) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT skill_id FROM skills WHERE skill_name='Python'),           'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT skill_id FROM skills WHERE skill_name='Machine Learning'), 'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT skill_id FROM skills WHERE skill_name='React'),            'ADVANCED',     1.5),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT skill_id FROM skills WHERE skill_name='Node.js'),          'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT skill_id FROM skills WHERE skill_name='NLP'),              'EXPERT',       2.5),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT skill_id FROM skills WHERE skill_name='Deep Learning'),    'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT skill_id FROM skills WHERE skill_name='MySQL'),            'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT skill_id FROM skills WHERE skill_name='Data Science'),     'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU005'),(SELECT skill_id FROM skills WHERE skill_name='Cybersecurity'),    'ADVANCED',     1.5),
  ((SELECT user_id FROM users WHERE university_id='STU006'),(SELECT skill_id FROM skills WHERE skill_name='IoT'),              'INTERMEDIATE', 1.0),
  -- Pre-FYDP students (years_experience = NULL)
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='Python'),         'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='React'),          'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='Node.js'),        'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='MySQL'),          'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow'),     'BEGINNER',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='React'),          'EXPERT',       NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='Vue.js'),         'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='Figma'),          'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='UI/UX Design'),   'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='CSS'),            'EXPERT',       NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Java'),           'EXPERT',       NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Spring Boot'),    'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Docker'),         'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='AWS'),            'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='PostgreSQL'),     'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='Python'),         'EXPERT',       NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow'),     'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='PyTorch'),        'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='NLP'),            'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='OpenCV'),         'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Python'),         'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Kali Linux'),     'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Wireshark'),      'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Networking'),     'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='C++'),            'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Arduino'),        'EXPERT',       NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Raspberry Pi'),   'ADVANCED',     NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='MQTT'),           'INTERMEDIATE', NULL),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Python'),         'INTERMEDIATE', NULL);

-- ── 4.10 USER DOMAIN INTERESTS [v6.0] — all users (FYDP + Pre-FYDP) ─────────
INSERT INTO user_domain_interests (user_id, domain_id, interest_level) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT domain_id FROM project_domains WHERE domain_name='NLP'),                    'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT domain_id FROM project_domains WHERE domain_name='Mobile Application'),     'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT domain_id FROM project_domains WHERE domain_name='NLP'),                    'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT domain_id FROM project_domains WHERE domain_name='Data Analytics'),         'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU005'),(SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),          'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU006'),(SELECT domain_id FROM project_domains WHERE domain_name='IoT'),                    'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT domain_id FROM project_domains WHERE domain_name='Machine Learning'),       'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT domain_id FROM project_domains WHERE domain_name='Software Engineering'),   'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT domain_id FROM project_domains WHERE domain_name='Software Engineering'),   'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT domain_id FROM project_domains WHERE domain_name='Mobile Application'),     'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT domain_id FROM project_domains WHERE domain_name='Software Engineering'),   'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT domain_id FROM project_domains WHERE domain_name='Cloud Computing'),        'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT domain_id FROM project_domains WHERE domain_name='NLP'),                    'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT domain_id FROM project_domains WHERE domain_name='Data Analytics'),         'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),          'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT domain_id FROM project_domains WHERE domain_name='IoT'),                    'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT domain_id FROM project_domains WHERE domain_name='IoT'),                    'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT domain_id FROM project_domains WHERE domain_name='Embedded Systems'),       'HIGH');

-- ── 4.11 COURSE TEACHER SECTIONS ─────────────────────────────────────────────
INSERT INTO course_teacher_sections (course_teacher_id, section_id, assigned_stage_id) VALUES
  ((SELECT user_id FROM users WHERE university_id='CT001'),
   (SELECT section_id FROM sections WHERE section_code='CSE-A'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1')),
  ((SELECT user_id FROM users WHERE university_id='CT001'),
   (SELECT section_id FROM sections WHERE section_code='CSE-B'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1')),
  ((SELECT user_id FROM users WHERE university_id='CT002'),
   (SELECT section_id FROM sections WHERE section_code='CSE-A'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-2')),
  ((SELECT user_id FROM users WHERE university_id='CT002'),
   (SELECT section_id FROM sections WHERE section_code='CSE-C'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-2'));

-- ── 4.12 PROJECT GROUPS ──────────────────────────────────────────────────────
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
VALUES
  ('UIU-G001','BanglaBot: Conversational AI for Bangla Language',
   (SELECT domain_id FROM project_domains WHERE domain_name='NLP'),
   (SELECT user_id FROM users WHERE university_id='SUP001'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code='CSE-A')),
  ('UIU-G002','SecureNet: AI-Powered Intrusion Detection System',
   (SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),
   (SELECT user_id FROM users WHERE university_id='SUP001'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code='CSE-B')),
  ('UIU-G003','HealthSync: Smart Patient Monitoring via IoT',
   (SELECT domain_id FROM project_domains WHERE domain_name='Health Informatics'),
   (SELECT user_id FROM users WHERE university_id='SUP003'),
   (SELECT stage_id FROM fydp_stages WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code='CSE-A'));

-- ── 4.13 GROUP MEMBERS ───────────────────────────────────────────────────────
INSERT INTO group_members (group_id, student_id, member_role) VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),(SELECT user_id FROM users WHERE university_id='STU001'),'TEAM_LEAD'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),(SELECT user_id FROM users WHERE university_id='STU002'),'DEVELOPER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),(SELECT user_id FROM users WHERE university_id='STU003'),'RESEARCHER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),(SELECT user_id FROM users WHERE university_id='STU004'),'DATA_ENGINEER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),(SELECT user_id FROM users WHERE university_id='STU005'),'TEAM_LEAD'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),(SELECT user_id FROM users WHERE university_id='STU006'),'DEVELOPER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),(SELECT user_id FROM users WHERE university_id='STU007'),'RESEARCHER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),(SELECT user_id FROM users WHERE university_id='STU008'),'DEVELOPER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G003'),(SELECT user_id FROM users WHERE university_id='STU009'),'TEAM_LEAD'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G003'),(SELECT user_id FROM users WHERE university_id='STU010'),'DEVELOPER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G003'),(SELECT user_id FROM users WHERE university_id='STU011'),'RESEARCHER'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G003'),(SELECT user_id FROM users WHERE university_id='STU012'),'DATA_ENGINEER');

-- ── 4.14 MATCHMAKING INVITATIONS ─────────────────────────────────────────────
INSERT INTO matchmaking_team_invitations
  (sender_student_id, receiver_student_id, invitation_message) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),
   (SELECT user_id FROM users WHERE university_id='STU002'),
   'Hey Bristy! I am working on an NLP project. Want to team up?'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),
   (SELECT user_id FROM users WHERE university_id='STU004'),
   'Hi Dina! Your DB skills would complement my NLP work perfectly.'),
  ((SELECT user_id FROM users WHERE university_id='STU005'),
   (SELECT user_id FROM users WHERE university_id='STU006'),
   'Farhan, interested in a security-focused FYDP?'),
  ((SELECT user_id FROM users WHERE university_id='STU007'),
   (SELECT user_id FROM users WHERE university_id='STU008'),
   'Let us collaborate on an AI project this trimester!');

UPDATE matchmaking_team_invitations
   SET invitation_status='ACCEPTED', responded_at=NOW()
 WHERE sender_student_id   = (SELECT user_id FROM users WHERE university_id='STU001')
   AND receiver_student_id = (SELECT user_id FROM users WHERE university_id='STU002');

UPDATE matchmaking_team_invitations
   SET invitation_status='ACCEPTED', responded_at=NOW()
 WHERE sender_student_id   = (SELECT user_id FROM users WHERE university_id='STU003')
   AND receiver_student_id = (SELECT user_id FROM users WHERE university_id='STU004');

-- ── 4.15 NOTIFICATIONS ───────────────────────────────────────────────────────
INSERT INTO notifications
  (user_id, notification_type, message, reference_entity_id, reference_entity_type, is_read) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU005'),
   'INVITATION_RECEIVED','Emon Chowdhury has invited you to join a security FYDP project.',
   3,'matchmaking_team_invitations',0),
  ((SELECT user_id FROM users WHERE university_id='STU007'),
   'INVITATION_RECEIVED','Gita Roy has invited you to join an AI FYDP project.',
   4,'matchmaking_team_invitations',0);

-- ── 4.16 WEEKLY PROGRESS REPORTS ─────────────────────────────────────────────
INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content, submitted_at, supervisor_status)
VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU001'),
   1,'Week 1 - Literature Survey',
   'Completed initial literature review on Bangla NLP transformer models.',NOW(),'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU002'),
   1,'Week 1 - Frontend Planning',
   'Designed UI wireframes and component hierarchy for the chatbot interface.',NOW(),'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU003'),
   1,'Week 1 - Dataset Collection',
   'Identified 3 publicly available Bangla text datasets for model training.',NOW(),'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU004'),
   1,'Week 1 - DB Schema Draft',
   'Drafted initial normalized database schema for conversation storage.',NOW(),'PENDING');

-- ── 4.17 PRE-FYDP USER PROFILES [v6.0] ───────────────────────────────────────
SET @trim_sp26 = (SELECT trimester_id FROM trimesters WHERE trimester_name='Spring 2026');

INSERT INTO user_profiles
  (user_id, profile_type, batch, bio, cgpa, preferred_role, github_url, linkedin_url,
   trimester_id, availability_status, profile_strength)
VALUES
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),
   'PRE_FYDP','B.Sc 59','Full-stack developer passionate about AI and ML.',3.65,
   'FULL_STACK_DEVELOPER','https://github.com/suvrojit','https://linkedin.com/in/suvrojit-bose',
   @trim_sp26,'LOOKING',71),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),
   'PRE_FYDP','B.Sc 59','Frontend specialist with strong design skills.',3.52,
   'FRONTEND_DEVELOPER','https://github.com/zainabali','https://linkedin.com/in/zainab-ali',
   @trim_sp26,'IN_TEAM',85),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),
   'PRE_FYDP','B.Sc 59','Backend developer with cloud and DevOps experience.',3.78,
   'BACKEND_DEVELOPER','https://github.com/hamzaiqbal','https://linkedin.com/in/hamza-iqbal',
   @trim_sp26,'IN_TEAM',90),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),
   'PRE_FYDP','B.Sc 59','ML researcher interested in NLP and computer vision.',3.88,
   'ML_ENGINEER','https://github.com/nusratjahan',NULL,
   @trim_sp26,'LOOKING',60),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),
   'PRE_FYDP','B.Sc 59','Cybersecurity enthusiast with CTF competition experience.',3.45,
   'SECURITY_ANALYST',NULL,NULL,
   @trim_sp26,'LOOKING',40),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),
   'PRE_FYDP','B.Sc 58','IoT and embedded systems developer with hardware experience.',3.30,
   'EMBEDDED_DEVELOPER',NULL,NULL,
   @trim_sp26,'LOOKING',35);

-- ── 4.20 PRE-FYDP GROUPS ─────────────────────────────────────────────────────
INSERT INTO pre_fydp_groups
  (group_name, domain_id, description, max_members, github_url, created_by, group_status)
VALUES
  ('NeuralVerse',
   (SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),
   'AI-powered virtual study assistant using GPT models and RAG pipeline.',5,
   'https://github.com/neuralverse',
   (SELECT user_id FROM users WHERE university_id='PFYDP002'),'OPEN'),
  ('CyberShield',
   (SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),
   'AI-driven intrusion detection system for university networks.',5,NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP005'),'OPEN'),
  ('MediCare AI',
   (SELECT domain_id FROM project_domains WHERE domain_name='Machine Learning'),
   'Predictive diagnostics using federated learning for health data privacy.',4,NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP004'),'OPEN'),
  ('CloudForge',
   (SELECT domain_id FROM project_domains WHERE domain_name='Cloud Computing'),
   'Containerized micro-services platform for student startups.',5,
   'https://github.com/cloudforge',
   (SELECT user_id FROM users WHERE university_id='PFYDP003'),'OPEN'),
  ('DataPulse',
   (SELECT domain_id FROM project_domains WHERE domain_name='Data Analytics'),
   'Real-time analytics dashboard for e-commerce platforms.',4,NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP006'),'OPEN'),
  ('SmartCampus',
   (SELECT domain_id FROM project_domains WHERE domain_name='IoT'),
   'IoT-based smart campus management system with environmental sensors.',5,NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP006'),'FULL');

INSERT INTO pre_fydp_group_required_skills (group_id, skill_id) VALUES
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT skill_id FROM skills WHERE skill_name='Python')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT skill_id FROM skills WHERE skill_name='React')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT skill_id FROM skills WHERE skill_name='NLP')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),(SELECT skill_id FROM skills WHERE skill_name='Python')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),(SELECT skill_id FROM skills WHERE skill_name='MySQL')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),(SELECT skill_id FROM skills WHERE skill_name='Backend Development')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),(SELECT skill_id FROM skills WHERE skill_name='Networking')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT skill_id FROM skills WHERE skill_name='Python')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT skill_id FROM skills WHERE skill_name='Frontend Development')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT skill_id FROM skills WHERE skill_name='Backend Development')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT skill_id FROM skills WHERE skill_name='Node.js')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT skill_id FROM skills WHERE skill_name='MySQL')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT skill_id FROM skills WHERE skill_name='Docker')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),  (SELECT skill_id FROM skills WHERE skill_name='Python')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),  (SELECT skill_id FROM skills WHERE skill_name='React')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),  (SELECT skill_id FROM skills WHERE skill_name='MongoDB')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),  (SELECT skill_id FROM skills WHERE skill_name='D3.js')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='C++')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='Arduino')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='React')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='MQTT'));

INSERT INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP002'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Backend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'ML Engineer'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT user_id FROM users WHERE university_id='PFYDP003'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT user_id FROM users WHERE university_id='PFYDP002'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'), (SELECT user_id FROM users WHERE university_id='PFYDP005'),'Security'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP006'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Backend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP002'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP003'),'DevOps'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'Tester');

INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message, request_status) VALUES
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),
   (SELECT user_id FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST','I have experience with Python and networking. Would love to join!','PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),
   (SELECT user_id FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST','Interested in data analytics dashboards!','PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),
   (SELECT user_id FROM users WHERE university_id='PFYDP005'),
   'JOIN_REQUEST','Can I contribute my security expertise to your AI project?','PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),
   (SELECT user_id FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST','Full-stack developer here, excited about micro-services!','ACCEPTED'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),
   (SELECT user_id FROM users WHERE university_id='PFYDP006'),
   'JOIN_REQUEST','IoT background — interested in health monitoring hardware.','REJECTED');

INSERT INTO group_chat_messages (group_id, sender_id, message_text, chat_type) VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU001'),
   'Team, let us sync on the literature review today at 3 PM.','STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU002'),
   'Sounds good! I will prepare the UI wireframe slides.','STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='STU001'),
   'Dr. Tanvir, we have completed the initial dataset survey. Awaiting your feedback.','WITH_SUPERVISOR'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='SUP001'),
   'Great progress! Please make sure the citation format follows IEEE.','WITH_SUPERVISOR'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
   (SELECT user_id FROM users WHERE university_id='STU005'),
   'Team, our Week 1 reports are ready. Please submit before Friday.','STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
   (SELECT user_id FROM users WHERE university_id='STU006'),
   'Done! I have also uploaded the network topology diagram.','STUDENT_ONLY');

INSERT INTO direct_messages (sender_id, receiver_id, message_text) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),
   (SELECT user_id FROM users WHERE university_id='STU003'),
   'Cyrus, can you share the dataset links you found?'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),
   (SELECT user_id FROM users WHERE university_id='STU001'),
   'Sure! Check the shared drive folder I created.'),
  ((SELECT user_id FROM users WHERE university_id='STU002'),
   (SELECT user_id FROM users WHERE university_id='SUP001'),
   'Sir, is there any feedback on our Week 1 frontend wireframes?'),
  ((SELECT user_id FROM users WHERE university_id='SUP001'),
   (SELECT user_id FROM users WHERE university_id='STU002'),
   'Looks clean! Please add mobile breakpoints to the design.'),
  ((SELECT user_id FROM users WHERE university_id='STU005'),
   (SELECT user_id FROM users WHERE university_id='CT001'),
   'Mr. Shafiq, our group report has been submitted for Week 1.');

-- ── 4.26 UPLOADED FILES & GROUP TASKS ────────────────────────────────────────
INSERT INTO uploaded_files
  (uploader_id, file_path, original_name, mime_type, file_size_bytes, entity_type) VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),
   '/uploads/reports/UIU-G001_W1_STU001.pdf',
   'Week1_LiteratureSurvey.pdf','application/pdf',204800,'REPORT'),
  ((SELECT user_id FROM users WHERE university_id='SUP001'),
   '/uploads/tasks/UIU-G001_W2_task.pdf',
   'Week2_Task_Requirements.pdf','application/pdf',102400,'TASK');

INSERT INTO group_tasks (group_id, supervisor_id, week_no, title, description, task_file_id, due_date)
VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id FROM users WHERE university_id='SUP001'),
   2,'Finalize Dataset & Model Architecture',
   'Each member to document their module: dataset pipeline, model choice, and API contract.',
   (SELECT file_id FROM uploaded_files WHERE original_name='Week2_Task_Requirements.pdf'),
   DATE_ADD(CURDATE(), INTERVAL 7 DAY));

-- ── 4.27 ANNOUNCEMENTS ──────────────────────────────────────────────────────
INSERT INTO announcements (author_id, title, content, target_role, section_id)
VALUES
  ((SELECT user_id FROM users WHERE university_id='CT001'),
   'Week 2 Report Submission Reminder',
   'All FYDP-1 students must submit their Week 2 progress reports by Friday 11:59 PM.',
   'STUDENT',
   (SELECT section_id FROM sections WHERE section_code='CSE-A')),
  ((SELECT user_id FROM users WHERE university_id='ADMIN001'),
   'System Maintenance Notice',
   'The FYDP portal will be under maintenance on Sunday 2–4 AM. Please plan accordingly.',
   'ALL', NULL),
  ((SELECT user_id FROM users WHERE university_id='SUP001'),
   'Supervisor Office Hours Update',
   'Office hours shifted to Wednesday 2–4 PM starting next week.',
   'STUDENT', NULL);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 — TRIGGERS  (15 triggers total for v6.0)
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER $$

-- ============================================================================
-- TRIGGER 1: ESCALATION ENGINE
-- ============================================================================
CREATE TRIGGER trg_after_wpr_approve_escalate
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    DECLARE v_total_members  INT DEFAULT 0;
    DECLARE v_approved_count INT DEFAULT 0;
    DECLARE v_is_fully       TINYINT(1) DEFAULT 0;

    IF NEW.supervisor_status = 'APPROVED' AND OLD.supervisor_status != 'APPROVED' THEN

        SELECT COUNT(*) INTO v_total_members
          FROM group_members WHERE group_id = NEW.group_id;

        SELECT COUNT(*) INTO v_approved_count
          FROM weekly_progress_reports
         WHERE group_id = NEW.group_id AND week_no = NEW.week_no
           AND supervisor_status = 'APPROVED' AND is_active = 1;

        SET v_is_fully = IF(v_approved_count = v_total_members AND v_total_members > 0, 1, 0);

        -- [v7.0] Insert/update inbox row WITHOUT derived columns (3NF compliance)
        INSERT INTO course_teacher_inbox
            (group_id, week_no, escalated_at, escalation_status)
        VALUES
            (NEW.group_id, NEW.week_no, NOW(),
             IF(v_is_fully = 1, 'PENDING_REVIEW', 'IN_PROGRESS'))
        ON DUPLICATE KEY UPDATE
            escalation_status = IF(v_is_fully = 1, 'PENDING_REVIEW', 'IN_PROGRESS');

        IF v_is_fully = 1 THEN
            INSERT INTO notifications
                (user_id, notification_type, title, message,
                 reference_entity_id, reference_entity_type)
            SELECT gm.student_id, 'ESCALATION_COMPLETE',
                   CONCAT('Week ', NEW.week_no, ' Fully Approved'),
                   CONCAT('All Week ', NEW.week_no,
                          ' reports approved! Escalated to Course Teacher.'),
                   NEW.group_id, 'course_teacher_inbox'
              FROM group_members gm WHERE gm.group_id = NEW.group_id;
        END IF;
    END IF;
END$$

-- ============================================================================
-- TRIGGER 2: SUPERVISOR CAPACITY LIMIT — ON INSERT
-- ============================================================================
CREATE TRIGGER trg_before_group_insert_supervisor_limit
BEFORE INSERT ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_count INT DEFAULT 0;
    SELECT COUNT(*) INTO v_count FROM project_groups
     WHERE supervisor_id = NEW.supervisor_id AND current_stage_id = NEW.current_stage_id
       AND is_active = 1 AND project_status != 'DROPPED';
    IF v_count >= 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SUPERVISOR CAPACITY EXCEEDED: Max 3 active groups per stage.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 3: SUPERVISOR CAPACITY LIMIT — ON UPDATE
-- ============================================================================
CREATE TRIGGER trg_before_group_update_supervisor_limit
BEFORE UPDATE ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_count INT DEFAULT 0;
    IF NEW.supervisor_id != OLD.supervisor_id OR NEW.current_stage_id != OLD.current_stage_id THEN
        SELECT COUNT(*) INTO v_count FROM project_groups
         WHERE supervisor_id = NEW.supervisor_id AND current_stage_id = NEW.current_stage_id
           AND is_active = 1 AND project_status != 'DROPPED' AND group_id != NEW.group_id;
        IF v_count >= 3 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SUPERVISOR CAPACITY EXCEEDED: Max 3 active groups per stage.';
        END IF;
    END IF;
END$$

-- ============================================================================
-- TRIGGER 4: PREVENT DUPLICATE PENDING INVITATIONS + SELF-INVITE
-- ============================================================================
CREATE TRIGGER trg_before_invitation_insert_dedup
BEFORE INSERT ON matchmaking_team_invitations
FOR EACH ROW
BEGIN
    DECLARE v_pending INT DEFAULT 0;
    IF NEW.sender_student_id = NEW.receiver_student_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SELF INVITATION ERROR: A student cannot invite themselves.';
    END IF;
    SELECT COUNT(*) INTO v_pending FROM matchmaking_team_invitations
     WHERE invitation_status = 'PENDING'
       AND ((sender_student_id = NEW.sender_student_id   AND receiver_student_id = NEW.receiver_student_id)
         OR (sender_student_id = NEW.receiver_student_id AND receiver_student_id = NEW.sender_student_id));
    IF v_pending > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'DUPLICATE INVITATION: A pending invitation already exists between these students.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 5: AUDIT LOG ON SUPERVISOR REPORT DECISION
-- [v5.0 FIX 1] Reads NEW.last_changed_by — pool-safe, no session variable.
-- ============================================================================
CREATE TRIGGER trg_after_wpr_audit_log
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    IF NEW.supervisor_status != OLD.supervisor_status THEN
        INSERT INTO audit_log
            (table_name, operation, record_id, changed_by, old_data, new_data)
        VALUES (
            'weekly_progress_reports', 'UPDATE', NEW.report_id,
            NEW.last_changed_by,
            JSON_OBJECT('supervisor_status', OLD.supervisor_status,
                        'supervisor_feedback', OLD.supervisor_feedback,
                        'supervisor_signed_at', OLD.supervisor_signed_at),
            JSON_OBJECT('supervisor_status', NEW.supervisor_status,
                        'supervisor_feedback', NEW.supervisor_feedback,
                        'supervisor_signed_at', NEW.supervisor_signed_at)
        );
    END IF;
END$$

-- ============================================================================
-- TRIGGER 6: AUTO-UPDATE AVAILABILITY ON FYDP INVITATION ACCEPT/REJECT
-- [v6.0] Updated to reference user_profiles instead of student_profiles
-- ============================================================================
CREATE TRIGGER trg_after_invitation_response
AFTER UPDATE ON matchmaking_team_invitations
FOR EACH ROW
BEGIN
    IF NEW.invitation_status = 'ACCEPTED' AND OLD.invitation_status = 'PENDING' THEN
        -- [v6.0 FIX] Both sender AND receiver are now committed to a team
        UPDATE user_profiles
           SET availability_status = 'IN_TEAM', updated_at = NOW()
         WHERE user_id IN (NEW.receiver_student_id, NEW.sender_student_id)
           AND profile_type = 'FYDP';
        INSERT INTO notifications
            (user_id, notification_type, title, message,
             reference_entity_id, reference_entity_type)
        VALUES (NEW.sender_student_id, 'INVITATION_ACCEPTED',
                'Team Invitation Accepted',
                'Your team invitation has been accepted! You can now finalise your FYDP group.',
                NEW.invitation_id, 'matchmaking_team_invitations');

    ELSEIF NEW.invitation_status = 'REJECTED' AND OLD.invitation_status = 'PENDING' THEN
        INSERT INTO notifications
            (user_id, notification_type, title, message,
             reference_entity_id, reference_entity_type)
        VALUES (NEW.sender_student_id, 'INVITATION_REJECTED',
                'Team Invitation Declined',
                'Your team invitation was declined. Consider reaching out to other students.',
                NEW.invitation_id, 'matchmaking_team_invitations');
    END IF;
END$$

-- ============================================================================
-- TRIGGER 7: USER STATUS AUDIT LOG
--  Reads NEW.last_changed_by — pool-safe.
-- ============================================================================
CREATE TRIGGER trg_after_users_status_log
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    IF NEW.account_status != OLD.account_status THEN
        INSERT INTO user_status_log
            (user_id, old_status, new_status, changed_by, changed_at)
        VALUES (NEW.user_id, OLD.account_status, NEW.account_status,
                NEW.last_changed_by, NOW());
    END IF;
END$$

-- ============================================================================
-- TRIGGER 8: CT INBOX REVIEWER ROLE GUARD
-- ============================================================================
CREATE TRIGGER trg_before_cti_update_reviewer_guard
BEFORE UPDATE ON course_teacher_inbox
FOR EACH ROW
BEGIN
    IF NEW.reviewed_by IS NOT NULL
       AND (OLD.reviewed_by IS NULL OR NEW.reviewed_by != OLD.reviewed_by) THEN
        IF NOT EXISTS (
            SELECT 1 FROM users
             WHERE user_id = NEW.reviewed_by
               AND role = 'COURSE_TEACHER'
               AND account_status = 'ACTIVE'
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'VALIDATION ERROR: reviewed_by must be an active COURSE_TEACHER.';
        END IF;
    END IF;
END$$

-- ============================================================================
-- TRIGGER 9: PRE-FYDP JOIN REQUEST DEDUP
-- ============================================================================
CREATE TRIGGER trg_before_pfjr_insert_dedup
BEFORE INSERT ON pre_fydp_join_requests
FOR EACH ROW
BEGIN
    DECLARE v_pending INT DEFAULT 0;
    SELECT COUNT(*) INTO v_pending FROM pre_fydp_join_requests
     WHERE group_id = NEW.group_id AND sender_id = NEW.sender_id
       AND request_status = 'PENDING';
    IF v_pending > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'DUPLICATE REQUEST: A pending request already exists for this student and group.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 10: PRE-FYDP GROUP JOIN → AVAILABILITY AUTO-UPDATE
-- [v6.0] Updated to reference user_profiles instead of pre_fydp_profiles
-- ============================================================================
CREATE TRIGGER trg_after_pfgm_insert_availability
AFTER INSERT ON pre_fydp_group_members
FOR EACH ROW
BEGIN
    UPDATE user_profiles
       SET availability_status = 'IN_TEAM', updated_at = NOW()
     WHERE user_id = NEW.user_id
       AND profile_type = 'PRE_FYDP'
       AND availability_status = 'LOOKING';
END$$

-- ============================================================================
-- TRIGGER 11: PRE-FYDP GROUP LEAVE → AVAILABILITY ROLLBACK
-- [v6.0] Updated to reference user_profiles instead of pre_fydp_profiles
-- ============================================================================
CREATE TRIGGER trg_after_pfgm_delete_availability
AFTER DELETE ON pre_fydp_group_members
FOR EACH ROW
BEGIN
    DECLARE v_remaining INT DEFAULT 0;
    SELECT COUNT(*) INTO v_remaining FROM pre_fydp_group_members
     WHERE user_id = OLD.user_id;
    IF v_remaining = 0 THEN
        UPDATE user_profiles
           SET availability_status = 'LOOKING', updated_at = NOW()
         WHERE user_id = OLD.user_id
           AND profile_type = 'PRE_FYDP'
           AND availability_status = 'IN_TEAM';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 12: TASK ASSIGNMENT NOTIFICATION
-- ============================================================================
CREATE TRIGGER trg_after_task_insert_notify
AFTER INSERT ON group_tasks
FOR EACH ROW
BEGIN
    INSERT INTO notifications
        (user_id, notification_type, title, message,
         reference_entity_id, reference_entity_type)
    SELECT gm.student_id, 'TASK_ASSIGNED',
           CONCAT('New Task: ', NEW.title),
           CONCAT('A new task has been assigned for Week ', NEW.week_no, ': ', NEW.title,
                  IF(NEW.due_date IS NOT NULL, CONCAT(' (Due: ', NEW.due_date, ')'), '')),
           NEW.task_id, 'group_tasks'
      FROM group_members gm WHERE gm.group_id = NEW.group_id;
END$$

-- ============================================================================
-- TRIGGER 13: [v5.0 FIX 5] COPY WEIGHT_PCT FROM CONFIG ON EVALUATION INSERT
-- ============================================================================
CREATE TRIGGER trg_before_eval_insert_weight
BEFORE INSERT ON group_evaluations
FOR EACH ROW
BEGIN
    DECLARE v_stage_id  INT UNSIGNED;
    DECLARE v_weight    DECIMAL(5,2) DEFAULT 0.00;

    SELECT current_stage_id INTO v_stage_id
      FROM project_groups WHERE group_id = NEW.group_id LIMIT 1;

    SELECT weight_pct INTO v_weight
      FROM evaluation_weight_config
     WHERE stage_id = v_stage_id AND evaluation_type = NEW.evaluation_type
       AND is_active = 1 LIMIT 1;

    SET NEW.weight_pct = COALESCE(v_weight, 0.00);
END$$

-- ============================================================================
-- TRIGGER 14: [v6.0 NEW] PREVENT WEIGHT SUM > 100 ON INSERT
-- ============================================================================
CREATE TRIGGER trg_before_ewc_insert_weight_sum
BEFORE INSERT ON evaluation_weight_config
FOR EACH ROW
BEGIN
    DECLARE v_current_sum DECIMAL(7,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(weight_pct), 0.00) INTO v_current_sum
      FROM evaluation_weight_config
     WHERE stage_id  = NEW.stage_id
       AND is_active = 1;

    IF (v_current_sum + NEW.weight_pct) > 100.00 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'WEIGHT CONFIG ERROR: Total weight for this stage would exceed 100%. Insert rejected.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 15: [v6.0 NEW] PREVENT WEIGHT SUM > 100 ON UPDATE
-- ============================================================================
CREATE TRIGGER trg_before_ewc_update_weight_sum
BEFORE UPDATE ON evaluation_weight_config
FOR EACH ROW
BEGIN
    DECLARE v_current_sum DECIMAL(7,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(weight_pct), 0.00) INTO v_current_sum
      FROM evaluation_weight_config
     WHERE stage_id  = NEW.stage_id
       AND is_active = 1
       AND config_id != NEW.config_id;

    IF (v_current_sum + NEW.weight_pct) > 100.00 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'WEIGHT CONFIG ERROR: Total weight for this stage would exceed 100%. Update rejected.';
    END IF;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6 — STORED PROCEDURES & FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER $$

-- ============================================================================
-- PROCEDURE 1: BULK CSV IMPORT ENGINE
-- ============================================================================
CREATE PROCEDURE sp_bulk_import_ucam_groups(IN p_import_batch_id VARCHAR(50))
BEGIN
    DECLARE v_raw_student_uid       VARCHAR(50);
    DECLARE v_raw_group_code        VARCHAR(50);
    DECLARE v_raw_supervisor_uid    VARCHAR(50);
    DECLARE v_raw_stage_name        VARCHAR(50);
    DECLARE v_raw_project_title     VARCHAR(300);
    DECLARE v_raw_domain_name       VARCHAR(100);
    DECLARE v_staging_id            INT;
    DECLARE v_student_id            INT UNSIGNED DEFAULT NULL;
    DECLARE v_supervisor_id         INT UNSIGNED DEFAULT NULL;
    DECLARE v_stage_id              INT UNSIGNED DEFAULT NULL;
    DECLARE v_domain_id             INT UNSIGNED DEFAULT NULL;
    DECLARE v_group_id              INT UNSIGNED DEFAULT NULL;
    DECLARE v_default_section_id    INT UNSIGNED DEFAULT NULL;
    DECLARE v_row_count             INT DEFAULT 0;
    DECLARE v_success_count         INT DEFAULT 0;
    DECLARE v_error_count           INT DEFAULT 0;
    DECLARE v_done                  INT DEFAULT 0;
    DECLARE v_error_msg             VARCHAR(500);

    DECLARE cur_staging CURSOR FOR
        SELECT staging_id, raw_student_university_id, raw_group_code,
               raw_supervisor_university_id, raw_stage_name,
               raw_project_title, raw_domain_name
          FROM ucam_import_staging
         WHERE import_batch_id = p_import_batch_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;
        INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
        VALUES (v_row_count, v_error_msg,
                CONCAT('Group:', v_raw_group_code, '|Student:', v_raw_student_uid), NOW());
        SET v_error_count = v_error_count + 1;
        ROLLBACK;
    END;

    SELECT section_id INTO v_default_section_id
      FROM sections WHERE section_code = 'CSE-A' LIMIT 1;

    OPEN cur_staging;
    import_loop: LOOP
        FETCH cur_staging INTO
            v_staging_id, v_raw_student_uid, v_raw_group_code,
            v_raw_supervisor_uid, v_raw_stage_name, v_raw_project_title, v_raw_domain_name;
        IF v_done THEN LEAVE import_loop; END IF;

        SET v_row_count = v_row_count + 1;
        SET v_student_id = NULL; SET v_supervisor_id = NULL;
        SET v_stage_id   = NULL; SET v_domain_id     = NULL;
        SET v_group_id   = NULL;

        START TRANSACTION;

        SELECT user_id INTO v_student_id FROM users
         WHERE university_id = v_raw_student_uid AND role='STUDENT'
           AND account_status='ACTIVE' LIMIT 1;
        SET v_done = 0;
        IF v_student_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Student not found/inactive: ', v_raw_student_uid),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT user_id INTO v_supervisor_id FROM users
         WHERE university_id = v_raw_supervisor_uid AND role='SUPERVISOR'
           AND account_status='ACTIVE' LIMIT 1;
        SET v_done = 0;
        IF v_supervisor_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Supervisor not found/inactive: ', v_raw_supervisor_uid),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT stage_id INTO v_stage_id FROM fydp_stages
         WHERE stage_name = v_raw_stage_name LIMIT 1;
        SET v_done = 0;
        IF v_stage_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Invalid FYDP stage: ', v_raw_stage_name),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT domain_id INTO v_domain_id FROM project_domains
         WHERE domain_name = v_raw_domain_name LIMIT 1;
        SET v_done = 0;
        IF v_domain_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Domain not found: ', v_raw_domain_name),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        IF EXISTS (SELECT 1 FROM project_groups WHERE group_code = v_raw_group_code) THEN
            SELECT group_id INTO v_group_id FROM project_groups
             WHERE group_code = v_raw_group_code LIMIT 1;
            IF NOT EXISTS (SELECT 1 FROM group_members
                            WHERE group_id = v_group_id AND student_id = v_student_id) THEN
                INSERT INTO group_members (group_id, student_id, member_role)
                VALUES (v_group_id, v_student_id, 'DEVELOPER');
            END IF;
        ELSE
            INSERT INTO project_groups
                (group_code, project_title, project_domain_id,
                 supervisor_id, current_stage_id, section_id)
            VALUES (v_raw_group_code, v_raw_project_title, v_domain_id,
                    v_supervisor_id, v_stage_id, v_default_section_id);
            SET v_group_id = LAST_INSERT_ID();
            INSERT INTO group_members (group_id, student_id, member_role)
            VALUES (v_group_id, v_student_id, 'DEVELOPER');
        END IF;

        COMMIT;
        SET v_success_count = v_success_count + 1;
    END LOOP import_loop;
    CLOSE cur_staging;

    SELECT v_row_count    AS total_rows_processed,
           v_success_count AS successful_imports,
           v_error_count   AS failed_imports,
           p_import_batch_id AS batch_id;
END$$

-- ============================================================================
-- PROCEDURE 2: FYDP STAGE PROMOTION ENGINE
-- [v5.0 FIX 1] Sets project_groups.last_changed_by = p_admin_id BEFORE UPDATE
-- ============================================================================
CREATE PROCEDURE sp_promote_fydp_stage(
    IN p_group_id          INT UNSIGNED,
    IN p_new_stage_id      INT UNSIGNED,
    IN p_new_domain_id     INT UNSIGNED,
    IN p_new_project_title VARCHAR(300),
    IN p_admin_id          INT UNSIGNED,
    IN p_change_reason     TEXT
)
BEGIN
    DECLARE v_current_stage_id    INT UNSIGNED;
    DECLARE v_current_domain_id   INT UNSIGNED;
    DECLARE v_current_title       VARCHAR(300);
    DECLARE v_current_stage_order TINYINT;
    DECLARE v_new_stage_order     TINYINT;
    DECLARE v_title_changed       TINYINT(1) DEFAULT 0;
    DECLARE v_domain_changed      TINYINT(1) DEFAULT 0;
    DECLARE v_error_msg           VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
    END;

    START TRANSACTION;

    SELECT current_stage_id, project_domain_id, project_title
      INTO v_current_stage_id, v_current_domain_id, v_current_title
      FROM project_groups WHERE group_id = p_group_id AND is_active = 1
                             AND deleted_at IS NULL LIMIT 1;

    IF v_current_stage_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROMOTION ERROR: Group not found or inactive.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_admin_id AND role = 'ADMIN') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROMOTION ERROR: Only ADMIN role can promote groups.';
    END IF;

    SELECT stage_order INTO v_current_stage_order FROM fydp_stages WHERE stage_id = v_current_stage_id;
    SELECT stage_order INTO v_new_stage_order     FROM fydp_stages WHERE stage_id = p_new_stage_id;

    IF v_new_stage_order IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROMOTION ERROR: Target stage does not exist.';
    END IF;
    IF v_new_stage_order <= v_current_stage_order THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROMOTION ERROR: Groups can only be promoted forward.';
    END IF;

    SET v_title_changed  = IF(p_new_project_title IS NOT NULL AND p_new_project_title != v_current_title, 1, 0);
    SET v_domain_changed = IF(p_new_domain_id IS NOT NULL AND p_new_domain_id != v_current_domain_id, 1, 0);

    IF v_title_changed = 1 OR v_domain_changed = 1 THEN
        INSERT INTO topic_change_history
            (group_id, old_domain_id, new_domain_id, old_project_title,
             new_project_title, changed_by_admin, change_reason, changed_at)
        VALUES (p_group_id, v_current_domain_id,
                IF(v_domain_changed=1, p_new_domain_id, v_current_domain_id),
                v_current_title,
                IF(v_title_changed=1, p_new_project_title, v_current_title),
                p_admin_id, p_change_reason, NOW());
    END IF;

    UPDATE project_groups SET last_changed_by = p_admin_id WHERE group_id = p_group_id;

    UPDATE project_groups
       SET current_stage_id  = p_new_stage_id,
           project_domain_id = IF(p_new_domain_id IS NOT NULL, p_new_domain_id, project_domain_id),
           project_title     = IF(p_new_project_title IS NOT NULL AND p_new_project_title != '',
                                  p_new_project_title, project_title),
           updated_at        = NOW()
     WHERE group_id = p_group_id;

    INSERT INTO notifications
        (user_id, notification_type, title, message,
         reference_entity_id, reference_entity_type)
    SELECT gm.student_id, 'STAGE_PROMOTED',
           CONCAT('Promoted to ', (SELECT stage_name FROM fydp_stages WHERE stage_id=p_new_stage_id)),
           CONCAT('Your project group has been promoted to ',
                  (SELECT stage_name FROM fydp_stages WHERE stage_id=p_new_stage_id), '!'),
           p_group_id, 'project_groups'
      FROM group_members gm WHERE gm.group_id = p_group_id;

    COMMIT;

    SELECT p_group_id AS group_id,
           (SELECT group_code FROM project_groups WHERE group_id=p_group_id)     AS group_code,
           (SELECT stage_name FROM fydp_stages WHERE stage_id=v_current_stage_id) AS promoted_from,
           (SELECT stage_name FROM fydp_stages WHERE stage_id=p_new_stage_id)     AS promoted_to,
           v_title_changed  AS title_changed,
           v_domain_changed AS domain_changed,
           NOW() AS promoted_at;
END$$

-- ============================================================================
-- PROCEDURE 3: SUPERVISOR WEEKLY REPORT APPROVAL
-- ============================================================================
CREATE PROCEDURE sp_approve_weekly_report(
    IN p_report_id     INT UNSIGNED,
    IN p_supervisor_id INT UNSIGNED,
    IN p_new_status    ENUM('APPROVED','REJECTED'),
    IN p_feedback      TEXT
)
BEGIN
    DECLARE v_group_supervisor_id INT UNSIGNED;
    DECLARE v_report_group_id     INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT pg.supervisor_id, wpr.group_id
      INTO v_group_supervisor_id, v_report_group_id
      FROM weekly_progress_reports wpr
      JOIN project_groups pg ON pg.group_id = wpr.group_id
     WHERE wpr.report_id = p_report_id
       AND wpr.is_active = 1 AND wpr.deleted_at IS NULL LIMIT 1;

    IF v_group_supervisor_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'APPROVAL ERROR: Report or group not found.';
    END IF;
    IF v_group_supervisor_id != p_supervisor_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AUTHORIZATION ERROR: You are not the assigned supervisor.';
    END IF;

    UPDATE weekly_progress_reports
       SET last_changed_by = p_supervisor_id
     WHERE report_id = p_report_id;

    UPDATE weekly_progress_reports
       SET supervisor_status    = p_new_status,
           supervisor_feedback  = p_feedback,
           supervisor_signed_at = IF(p_new_status='APPROVED', NOW(), NULL),
           updated_at           = NOW()
     WHERE report_id = p_report_id;

    COMMIT;
    SELECT p_report_id AS report_id, p_new_status AS new_status, 'SUCCESS' AS result;
END$$

-- ============================================================================
-- PROCEDURE 4: MATCHMAKING RECOMMENDATION ENGINE
-- [v6.0] Updated to reference user_domain_interests instead of pre_fydp_student_domain_interests
-- ============================================================================
CREATE PROCEDURE sp_recommend_groups_for_student(
    IN p_student_id INT UNSIGNED,
    IN p_limit      INT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id=p_student_id
                   AND role='PRE_FYDP_STUDENT' AND account_status='ACTIVE'
                   AND is_active=1 AND deleted_at IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid or inactive Pre-FYDP student ID.';
    END IF;
    IF p_limit IS NULL OR p_limit = 0 THEN SET p_limit = 5; END IF;

    SELECT pfg.group_id, pfg.group_name, pd.domain_name, pfg.description, pfg.max_members,
           (SELECT COUNT(*) FROM pre_fydp_group_members m WHERE m.group_id=pfg.group_id) AS current_members,
           pfg.max_members -
           (SELECT COUNT(*) FROM pre_fydp_group_members m WHERE m.group_id=pfg.group_id) AS open_slots,
           fn_skill_match_score(p_student_id, pfg.group_id)                               AS skill_match_pct,
           EXISTS (SELECT 1 FROM user_domain_interests udi
                    WHERE udi.user_id=p_student_id AND udi.domain_id=pfg.domain_id
                      AND udi.interest_level IN ('HIGH','MEDIUM'))                         AS domain_aligned,
           ROUND(fn_skill_match_score(p_student_id, pfg.group_id)*0.70
               + (EXISTS (SELECT 1 FROM user_domain_interests udi
                           WHERE udi.user_id=p_student_id AND udi.domain_id=pfg.domain_id
                             AND udi.interest_level IN ('HIGH','MEDIUM'))*30))             AS recommendation_score,
           EXISTS (SELECT 1 FROM pre_fydp_group_members m
                    WHERE m.group_id=pfg.group_id AND m.user_id=p_student_id)             AS is_already_member,
           EXISTS (SELECT 1 FROM pre_fydp_join_requests jr
                    WHERE jr.group_id=pfg.group_id AND jr.sender_id=p_student_id
                      AND jr.request_status='PENDING')                                    AS has_pending_request
      FROM pre_fydp_groups pfg
      JOIN project_domains pd ON pd.domain_id = pfg.domain_id
     WHERE pfg.group_status = 'OPEN' AND pfg.is_active = 1
       AND pfg.deleted_at IS NULL
     ORDER BY recommendation_score DESC, skill_match_pct DESC
     LIMIT p_limit;
END$$

-- ============================================================================
-- PROCEDURE 5: GROUP PERFORMANCE REPORT
-- ============================================================================
CREATE PROCEDURE sp_generate_group_performance_report(IN p_group_id INT UNSIGNED)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM project_groups
                    WHERE group_id=p_group_id AND is_active=1
                      AND deleted_at IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Group not found or deleted.';
    END IF;

    SELECT pg.group_code, pg.project_title, pd.domain_name,
           fs.stage_name AS current_stage, sec.section_code,
           u.full_name   AS supervisor_name, pg.project_status,
           COUNT(DISTINCT gm.student_id)         AS total_members,
           pg.created_at                          AS group_formed_at,
           DATEDIFF(NOW(), pg.created_at)         AS days_since_formation
      FROM project_groups pg
      JOIN project_domains pd ON pd.domain_id   = pg.project_domain_id
      JOIN fydp_stages fs     ON fs.stage_id    = pg.current_stage_id
      JOIN sections sec       ON sec.section_id = pg.section_id
      JOIN users u            ON u.user_id      = pg.supervisor_id
      LEFT JOIN group_members gm ON gm.group_id = pg.group_id
     WHERE pg.group_id = p_group_id
     GROUP BY pg.group_id;

    SELECT u.university_id AS student_uid, u.full_name AS student_name, gm.member_role,
           COUNT(wpr.report_id)                                                          AS reports_submitted,
           SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)             AS approved,
           SUM(CASE WHEN wpr.supervisor_status='REJECTED' THEN 1 ELSE 0 END)             AS rejected,
           SUM(CASE WHEN wpr.supervisor_status='PENDING'  THEN 1 ELSE 0 END)             AS pending,
           CASE WHEN COUNT(wpr.report_id) > 0
                THEN ROUND(SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)
                           / COUNT(wpr.report_id) * 100, 2) ELSE 0.00 END               AS individual_approval_rate
      FROM group_members gm
      JOIN users u ON u.user_id = gm.student_id
      LEFT JOIN weekly_progress_reports wpr
             ON wpr.student_id=gm.student_id AND wpr.group_id=p_group_id
            AND wpr.is_active=1 AND wpr.deleted_at IS NULL
     WHERE gm.group_id = p_group_id
     GROUP BY u.university_id, u.full_name, gm.member_role
     ORDER BY approved DESC, reports_submitted DESC;

    SELECT wpr.week_no,
           COUNT(wpr.report_id)                                                          AS reports_this_week,
           SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)             AS approved_this_week,
           fn_get_group_approval_pct(p_group_id, wpr.week_no)                            AS approval_pct,
           GROUP_CONCAT(CONCAT(u.full_name,': ',wpr.supervisor_status)
                        ORDER BY u.full_name SEPARATOR ' | ')                            AS member_statuses
      FROM weekly_progress_reports wpr
      JOIN users u ON u.user_id = wpr.student_id
     WHERE wpr.group_id = p_group_id
       AND wpr.is_active = 1 AND wpr.deleted_at IS NULL
     GROUP BY wpr.week_no
     ORDER BY wpr.week_no;
END$$

-- ============================================================================
-- PROCEDURE 6: MARK ALL NOTIFICATIONS READ
-- ============================================================================
CREATE PROCEDURE sp_mark_all_notifications_read(IN p_user_id INT UNSIGNED)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id=p_user_id
                   AND is_active=1 AND deleted_at IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User not found or inactive.';
    END IF;
    UPDATE notifications SET is_read=1 WHERE user_id=p_user_id AND is_read=0;
    SELECT ROW_COUNT() AS notifications_marked_read;
END$$

-- ============================================================================
-- PROCEDURE 7: MARK DM CONVERSATION READ
-- ============================================================================
CREATE PROCEDURE sp_mark_dm_conversation_read(
    IN p_receiver_id INT UNSIGNED,
    IN p_sender_id   INT UNSIGNED
)
BEGIN
    UPDATE direct_messages
       SET is_read=1
     WHERE receiver_id=p_receiver_id AND sender_id=p_sender_id AND is_read=0;
    SELECT ROW_COUNT() AS messages_marked_read;
END$$

-- ============================================================================
-- PROCEDURE 8: CLEANUP EXPIRED SESSIONS
-- ============================================================================
CREATE PROCEDURE sp_cleanup_expired_sessions()
BEGIN
    DELETE FROM user_sessions
     WHERE expires_at < NOW() OR revoked_at IS NOT NULL;
    SELECT ROW_COUNT() AS sessions_cleaned;

    DELETE FROM password_reset_tokens
     WHERE expires_at < NOW() OR used_at IS NOT NULL;
    SELECT ROW_COUNT() AS reset_tokens_cleaned;
END$$

-- ============================================================================
-- PROCEDURE 9: AUTO-PROVISION NEXT MONTH'S PARTITIONS
-- ============================================================================
CREATE PROCEDURE sp_create_next_month_partitions()
BEGIN
    DECLARE v_next_month_start  DATE;
    DECLARE v_month_after_start DATE;
    DECLARE v_partition_name    VARCHAR(30);
    DECLARE v_sql               TEXT;
    DECLARE v_exists            INT DEFAULT 0;

    SET v_next_month_start  = DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 1 MONTH), '%Y-%m-01');
    SET v_month_after_start = DATE_ADD(v_next_month_start, INTERVAL 1 MONTH);
    SET v_partition_name    = CONCAT('p_', DATE_FORMAT(v_next_month_start, '%Y_%m'));

    SELECT COUNT(*) INTO v_exists
      FROM information_schema.partitions
     WHERE table_schema = DATABASE()
       AND table_name = 'audit_log'
       AND partition_name = v_partition_name;

    IF v_exists = 0 THEN
        SET v_sql = CONCAT(
            'ALTER TABLE audit_log REORGANIZE PARTITION p_future INTO (',
            'PARTITION ', v_partition_name, ' VALUES LESS THAN (',
            UNIX_TIMESTAMP(v_month_after_start), '),',
            'PARTITION p_future VALUES LESS THAN MAXVALUE)'
        );
        SET @ddl = v_sql;
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET v_sql = CONCAT(
            'ALTER TABLE login_attempts REORGANIZE PARTITION p_future INTO (',
            'PARTITION ', v_partition_name, ' VALUES LESS THAN (',
            UNIX_TIMESTAMP(v_month_after_start), '),',
            'PARTITION p_future VALUES LESS THAN MAXVALUE)'
        );
        SET @ddl = v_sql;
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        -- Silent: no result grid opened in Workbench
        INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
        VALUES (0, CONCAT('Partition provisioned: ', v_partition_name), 'sp_create_next_month_partitions', NOW());
    ELSE
        -- Silent: no result grid opened in Workbench
        INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
        VALUES (0, CONCAT('Partition already exists: ', v_partition_name), 'sp_create_next_month_partitions', NOW());
    END IF;
END$$

-- ============================================================================
-- FUNCTION 1: GROUP APPROVAL PERCENTAGE FOR A WEEK
-- ============================================================================
CREATE FUNCTION fn_get_group_approval_pct(
    p_group_id INT UNSIGNED,
    p_week_no  TINYINT UNSIGNED
)
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_approved INT DEFAULT 0;
    SELECT COUNT(*) INTO v_total   FROM group_members WHERE group_id=p_group_id;
    SELECT COUNT(*) INTO v_approved FROM weekly_progress_reports
     WHERE group_id=p_group_id AND week_no=p_week_no AND supervisor_status='APPROVED'
       AND is_active=1 AND deleted_at IS NULL;
    IF v_total = 0 THEN RETURN 0.00; END IF;
    RETURN ROUND((v_approved / v_total) * 100, 2);
END$$

-- ============================================================================
-- FUNCTION 2: CHECK IF STUDENT IS IN AN ACTIVE FYDP GROUP
-- ============================================================================
CREATE FUNCTION fn_is_student_in_active_group(p_student_id INT UNSIGNED)
RETURNS TINYINT(1)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;
    SELECT COUNT(*) INTO v_count
      FROM group_members gm
      JOIN project_groups pg ON pg.group_id=gm.group_id
     WHERE gm.student_id=p_student_id AND pg.is_active=1
       AND pg.project_status='ACTIVE' AND pg.deleted_at IS NULL;
    RETURN IF(v_count > 0, 1, 0);
END$$

-- ============================================================================
-- FUNCTION 3: SKILL MATCH SCORE
-- [v6.0] Updated to reference user_skills instead of pre_fydp_student_skills
-- ============================================================================
CREATE FUNCTION fn_skill_match_score(
    p_student_id INT UNSIGNED,
    p_group_id   INT UNSIGNED
)
RETURNS TINYINT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_required INT DEFAULT 0;
    DECLARE v_matched  INT DEFAULT 0;
    SELECT COUNT(*) INTO v_required FROM pre_fydp_group_required_skills WHERE group_id=p_group_id;
    IF v_required = 0 THEN RETURN 0; END IF;
    SELECT COUNT(*) INTO v_matched
      FROM pre_fydp_group_required_skills r
      JOIN user_skills us ON us.skill_id=r.skill_id AND us.user_id=p_student_id
     WHERE r.group_id = p_group_id;
    RETURN ROUND((v_matched / v_required) * 100);
END$$

-- ============================================================================
-- FUNCTION 4: UNREAD DM COUNT FOR A USER
-- ============================================================================
CREATE FUNCTION fn_unread_dm_count(p_receiver_id INT UNSIGNED)
RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_count INT UNSIGNED DEFAULT 0;
    SELECT COUNT(*) INTO v_count FROM direct_messages
     WHERE receiver_id=p_receiver_id AND is_read=0;
    RETURN v_count;
END$$

-- ============================================================================
-- FUNCTION 5: WEIGHTED FINAL GRADE FOR A GROUP
-- ============================================================================
CREATE FUNCTION fn_group_weighted_grade(p_group_id INT UNSIGNED)
RETURNS VARCHAR(2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_weighted_avg DECIMAL(7,4) DEFAULT 0;
    DECLARE v_total_weight DECIMAL(5,2) DEFAULT 0;

    SELECT SUM(weighted_score), SUM(weight_pct)
      INTO v_weighted_avg, v_total_weight
      FROM group_evaluations WHERE group_id = p_group_id;

    IF v_total_weight = 0 OR v_total_weight IS NULL THEN RETURN 'N/A'; END IF;

    SET v_weighted_avg = v_weighted_avg / (v_total_weight / 100);

    RETURN CASE
        WHEN v_weighted_avg >= 90 THEN 'A'
        WHEN v_weighted_avg >= 75 THEN 'B'
        WHEN v_weighted_avg >= 60 THEN 'C'
        WHEN v_weighted_avg >= 50 THEN 'D'
        ELSE 'F'
    END;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 — VIEWS  (17 total)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── VIEW 1: Full group progress summary ──────────────────────────────────────
CREATE OR REPLACE VIEW vw_group_progress_summary AS
SELECT
    pg.group_id, pg.group_code, pg.project_title,
    pd.domain_name,
    u.full_name                                                           AS supervisor_name,
    d.short_code                                                          AS supervisor_dept,
    fs.stage_name                                                         AS current_stage,
    sec.section_code, pg.project_status,
    COUNT(DISTINCT gm.student_id)                                         AS total_members,
    COUNT(DISTINCT wpr.report_id)                                         AS total_reports,
    SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)    AS approved_reports,
    SUM(CASE WHEN wpr.supervisor_status='PENDING'  THEN 1 ELSE 0 END)    AS pending_reports,
    SUM(CASE WHEN wpr.supervisor_status='REJECTED' THEN 1 ELSE 0 END)    AS rejected_reports
FROM project_groups pg
JOIN project_domains pd  ON pd.domain_id   = pg.project_domain_id
JOIN users u             ON u.user_id      = pg.supervisor_id
JOIN departments d       ON d.department_id= u.department_id
JOIN fydp_stages fs      ON fs.stage_id    = pg.current_stage_id
JOIN sections sec        ON sec.section_id = pg.section_id
LEFT JOIN group_members gm              ON gm.group_id  = pg.group_id
LEFT JOIN weekly_progress_reports wpr   ON wpr.group_id = pg.group_id
                                       AND wpr.is_active = 1 AND wpr.deleted_at IS NULL
WHERE pg.is_active = 1 AND pg.deleted_at IS NULL
GROUP BY pg.group_id, pg.group_code, pg.project_title, pd.domain_name,
         u.full_name, d.short_code, fs.stage_name, sec.section_code, pg.project_status;

-- ── VIEW 2: Supervisor workload ───────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_supervisor_workload AS
SELECT
    u.user_id AS supervisor_id, u.full_name AS supervisor_name,
    d.department_name, d.short_code AS dept_code, fs.stage_name,
    COUNT(pg.group_id)                    AS total_groups_in_stage,
    GREATEST(0, 3 - COUNT(pg.group_id))   AS remaining_capacity
FROM users u
JOIN departments d ON d.department_id = u.department_id
CROSS JOIN fydp_stages fs
LEFT JOIN project_groups pg
    ON  pg.supervisor_id    = u.user_id
    AND pg.current_stage_id = fs.stage_id
    AND pg.is_active        = 1
    AND pg.deleted_at       IS NULL
    AND pg.project_status  != 'DROPPED'
WHERE u.role='SUPERVISOR' AND u.account_status='ACTIVE'
  AND u.is_active=1 AND u.deleted_at IS NULL
GROUP BY u.user_id, u.full_name, d.department_name, d.short_code, fs.stage_name;

-- ── VIEW 3: Student matchmaking board [v6.0] ─────────────────────────────────
-- Updated to reference user_profiles, user_skills, user_domain_interests
CREATE OR REPLACE VIEW vw_student_matchmaking_board AS
SELECT
    u.user_id, u.full_name, d.department_name, d.short_code AS dept_code,
    up.batch, up.cgpa, up.preferred_role AS preferred_team_role,
    up.availability_status,
    up.github_url, up.linkedin_url,
    t.trimester_name                                         AS target_trimester,
    GROUP_CONCAT(DISTINCT s.skill_name   ORDER BY s.skill_name   SEPARATOR ', ') AS skills,
    GROUP_CONCAT(DISTINCT pd.domain_name ORDER BY pd.domain_name SEPARATOR ', ') AS domain_interests
FROM users u
JOIN departments d           ON d.department_id = u.department_id
JOIN user_profiles up        ON up.user_id      = u.user_id AND up.profile_type = 'FYDP'
LEFT JOIN trimesters t       ON t.trimester_id  = up.trimester_id
LEFT JOIN user_skills us     ON us.user_id      = u.user_id
LEFT JOIN skills s           ON s.skill_id      = us.skill_id
LEFT JOIN user_domain_interests udi ON udi.user_id = u.user_id
LEFT JOIN project_domains pd ON pd.domain_id    = udi.domain_id
WHERE u.role='STUDENT' AND u.account_status='ACTIVE'
  AND u.is_active=1 AND u.deleted_at IS NULL
  AND up.availability_status='LOOKING'
GROUP BY u.user_id, u.full_name, d.department_name, d.short_code, up.batch,
         up.cgpa, up.preferred_role, up.availability_status,
         up.github_url, up.linkedin_url, t.trimester_name;

-- ── VIEW 4: Course teacher pending inbox [v7.0 3NF fix] ─────────────────────
-- Counts now computed live from group_members and weekly_progress_reports
CREATE OR REPLACE VIEW vw_pending_course_teacher_inbox AS
SELECT
    ci.inbox_id, ci.group_id, pg.group_code, pg.project_title,
    sec.section_code, fs.stage_name, ci.week_no, ci.escalated_at,
    ci.escalation_status,
    (SELECT COUNT(*) FROM weekly_progress_reports wpr2
      WHERE wpr2.group_id=ci.group_id AND wpr2.week_no=ci.week_no
        AND wpr2.supervisor_status='APPROVED'
        AND wpr2.is_active=1 AND wpr2.deleted_at IS NULL)         AS approved_count,
    (SELECT COUNT(*) FROM group_members gm2
      WHERE gm2.group_id=ci.group_id)                             AS total_members,
    CONCAT(
        (SELECT COUNT(*) FROM weekly_progress_reports wpr3
          WHERE wpr3.group_id=ci.group_id AND wpr3.week_no=ci.week_no
            AND wpr3.supervisor_status='APPROVED'
            AND wpr3.is_active=1 AND wpr3.deleted_at IS NULL),
        ' / ',
        (SELECT COUNT(*) FROM group_members gm3
          WHERE gm3.group_id=ci.group_id)
    )                                                              AS approval_progress,
    DATEDIFF(NOW(), ci.escalated_at)                               AS days_waiting
FROM course_teacher_inbox ci
JOIN project_groups pg ON pg.group_id   = ci.group_id
                       AND pg.is_active=1 AND pg.deleted_at IS NULL
JOIN fydp_stages fs    ON fs.stage_id   = pg.current_stage_id
JOIN sections sec      ON sec.section_id= pg.section_id
WHERE ci.escalation_status IN ('PENDING_REVIEW','IN_PROGRESS')
ORDER BY ci.escalated_at ASC;

-- ── VIEW 5: CT Dashboard [v7.0 3NF fix] ─────────────────────────────────────
-- Counts now computed live from group_members and weekly_progress_reports
CREATE OR REPLACE VIEW vw_ct_dashboard AS
SELECT
    pg.group_id, pg.group_code, pg.project_title, sec.section_code, fs.stage_name,
    ci.week_no, ci.escalated_at,
    (SELECT COUNT(*) FROM weekly_progress_reports wpr2
      WHERE wpr2.group_id=ci.group_id AND wpr2.week_no=ci.week_no
        AND wpr2.supervisor_status='APPROVED'
        AND wpr2.is_active=1 AND wpr2.deleted_at IS NULL)         AS approved_count,
    (SELECT COUNT(*) FROM group_members gm2
      WHERE gm2.group_id=ci.group_id)                             AS total_members,
    IF(
        (SELECT COUNT(*) FROM weekly_progress_reports wpr4
          WHERE wpr4.group_id=ci.group_id AND wpr4.week_no=ci.week_no
            AND wpr4.supervisor_status='APPROVED'
            AND wpr4.is_active=1 AND wpr4.deleted_at IS NULL)
        = (SELECT COUNT(*) FROM group_members gm4
            WHERE gm4.group_id=ci.group_id)
        AND (SELECT COUNT(*) FROM group_members gm5
              WHERE gm5.group_id=ci.group_id) > 0,
        1, 0
    )                                                              AS is_fully_approved,
    CONCAT(
        (SELECT COUNT(*) FROM weekly_progress_reports wpr3
          WHERE wpr3.group_id=ci.group_id AND wpr3.week_no=ci.week_no
            AND wpr3.supervisor_status='APPROVED'
            AND wpr3.is_active=1 AND wpr3.deleted_at IS NULL),
        ' / ',
        (SELECT COUNT(*) FROM group_members gm3
          WHERE gm3.group_id=ci.group_id)
    )                                                              AS approval_progress,
    u.university_id                                   AS student_uid,
    u.full_name                                       AS student_name,
    COALESCE(wpr.supervisor_status,'NOT SUBMITTED')   AS report_status,
    wpr.report_title,
    uf.file_path                                      AS report_file_path,
    uf.original_name                                  AS report_file_name,
    wpr.supervisor_feedback, wpr.supervisor_signed_at, wpr.submitted_at
FROM course_teacher_inbox ci
JOIN project_groups pg   ON pg.group_id   = ci.group_id
                         AND pg.is_active=1 AND pg.deleted_at IS NULL
JOIN fydp_stages fs      ON fs.stage_id   = pg.current_stage_id
JOIN sections sec        ON sec.section_id= pg.section_id
JOIN group_members gm    ON gm.group_id   = ci.group_id
JOIN users u             ON u.user_id     = gm.student_id
LEFT JOIN weekly_progress_reports wpr
       ON wpr.group_id=ci.group_id AND wpr.student_id=gm.student_id
      AND wpr.week_no=ci.week_no
      AND wpr.is_active=1 AND wpr.deleted_at IS NULL
LEFT JOIN uploaded_files uf ON uf.file_id = wpr.report_file_id
ORDER BY pg.group_code, ci.week_no,
         FIELD(wpr.supervisor_status,'APPROVED','PENDING','REJECTED',NULL);

-- ── VIEW 6: CT Inbox Summary [v7.0 3NF fix] ─────────────────────────────────
-- Counts now computed live from group_members and weekly_progress_reports
CREATE OR REPLACE VIEW vw_ct_inbox_summary AS
SELECT
    ci.inbox_id, pg.group_code, pg.project_title,
    sec.section_code, fs.stage_name, ci.week_no, ci.escalated_at,
    (SELECT COUNT(*) FROM weekly_progress_reports wpr2
      WHERE wpr2.group_id=ci.group_id AND wpr2.week_no=ci.week_no
        AND wpr2.supervisor_status='APPROVED'
        AND wpr2.is_active=1 AND wpr2.deleted_at IS NULL)         AS approved_count,
    (SELECT COUNT(*) FROM group_members gm2
      WHERE gm2.group_id=ci.group_id)                             AS total_members,
    CONCAT(
        (SELECT COUNT(*) FROM weekly_progress_reports wpr3
          WHERE wpr3.group_id=ci.group_id AND wpr3.week_no=ci.week_no
            AND wpr3.supervisor_status='APPROVED'
            AND wpr3.is_active=1 AND wpr3.deleted_at IS NULL),
        ' / ',
        (SELECT COUNT(*) FROM group_members gm3
          WHERE gm3.group_id=ci.group_id)
    )                                                              AS approval_progress,
    IF(
        (SELECT COUNT(*) FROM weekly_progress_reports wpr4
          WHERE wpr4.group_id=ci.group_id AND wpr4.week_no=ci.week_no
            AND wpr4.supervisor_status='APPROVED'
            AND wpr4.is_active=1 AND wpr4.deleted_at IS NULL)
        = (SELECT COUNT(*) FROM group_members gm4
            WHERE gm4.group_id=ci.group_id)
        AND (SELECT COUNT(*) FROM group_members gm5
              WHERE gm5.group_id=ci.group_id) > 0,
        1, 0
    )                                                              AS is_fully_approved,
    ci.escalation_status,
    DATEDIFF(NOW(), ci.escalated_at) AS days_since_first_approval,
    CASE
        WHEN (SELECT COUNT(*) FROM weekly_progress_reports wpr5
               WHERE wpr5.group_id=ci.group_id AND wpr5.week_no=ci.week_no
                 AND wpr5.supervisor_status='APPROVED'
                 AND wpr5.is_active=1 AND wpr5.deleted_at IS NULL)
             = (SELECT COUNT(*) FROM group_members gm6
                 WHERE gm6.group_id=ci.group_id)
             AND (SELECT COUNT(*) FROM group_members gm7
                   WHERE gm7.group_id=ci.group_id) > 0
             THEN 'All Approved'
        WHEN (SELECT COUNT(*) FROM weekly_progress_reports wpr6
               WHERE wpr6.group_id=ci.group_id AND wpr6.week_no=ci.week_no
                 AND wpr6.supervisor_status='APPROVED'
                 AND wpr6.is_active=1 AND wpr6.deleted_at IS NULL) = 0
             THEN 'No Approvals Yet'
        ELSE CONCAT('In Progress (',
            (SELECT COUNT(*) FROM weekly_progress_reports wpr7
              WHERE wpr7.group_id=ci.group_id AND wpr7.week_no=ci.week_no
                AND wpr7.supervisor_status='APPROVED'
                AND wpr7.is_active=1 AND wpr7.deleted_at IS NULL),
            '/',
            (SELECT COUNT(*) FROM group_members gm8
              WHERE gm8.group_id=ci.group_id),
            ')')
    END AS readable_status
FROM course_teacher_inbox ci
JOIN project_groups pg ON pg.group_id   = ci.group_id
                       AND pg.is_active=1 AND pg.deleted_at IS NULL
JOIN fydp_stages fs    ON fs.stage_id   = pg.current_stage_id
JOIN sections sec      ON sec.section_id= pg.section_id
ORDER BY ci.escalated_at DESC;

-- ── VIEW 7: Pre-FYDP Skill Matchmaking Leaderboard [v6.0] ────────────────────
-- Updated to reference user_profiles and user_skills
CREATE OR REPLACE VIEW vw_pre_fydp_skill_match AS
SELECT
    u.university_id                              AS student_uid,
    u.full_name                                  AS student_name,
    up.preferred_role, up.cgpa, up.availability_status,
    pfg.group_id, pfg.group_name, pd.domain_name, pfg.group_status, pfg.max_members,
    COALESCE(mem.current_members, 0)             AS current_members,
    ROUND(COALESCE(
        COUNT(DISTINCT CASE WHEN us2.skill_id IS NOT NULL THEN rs.skill_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT rs.skill_id), 0)
    , 0))                                        AS skill_match_pct
FROM users u
JOIN user_profiles up        ON up.user_id    = u.user_id AND up.profile_type = 'PRE_FYDP'
JOIN pre_fydp_groups pfg     ON pfg.group_status = 'OPEN'
                             AND pfg.is_active = 1 AND pfg.deleted_at IS NULL
JOIN project_domains pd      ON pd.domain_id  = pfg.domain_id
LEFT JOIN pre_fydp_group_required_skills rs ON rs.group_id = pfg.group_id
LEFT JOIN user_skills us2
       ON us2.user_id=u.user_id AND us2.skill_id=rs.skill_id
LEFT JOIN (
    SELECT group_id, COUNT(*) AS current_members
      FROM pre_fydp_group_members GROUP BY group_id
) mem ON mem.group_id = pfg.group_id
WHERE u.role='PRE_FYDP_STUDENT' AND u.account_status='ACTIVE'
  AND u.is_active=1 AND u.deleted_at IS NULL
  AND up.availability_status='LOOKING'
GROUP BY u.university_id, u.full_name, up.preferred_role, up.cgpa,
         up.availability_status, pfg.group_id, pfg.group_name, pd.domain_name,
         pfg.group_status, pfg.max_members, mem.current_members
ORDER BY u.user_id, skill_match_pct DESC;

-- ── VIEW 8: Group Chat Feed ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_group_chat_feed AS
SELECT
    gcm.message_id, pg.group_code, pg.project_title, gcm.group_id,
    gcm.chat_type, gcm.sender_id,
    u.full_name                                  AS sender_name,
    u.role                                       AS sender_role,
    gcm.message_text,
    uf.file_path                                 AS attachment_path,
    uf.original_name                             AS attachment_name,
    gcm.created_at
FROM group_chat_messages gcm
JOIN project_groups pg   ON pg.group_id = gcm.group_id
                         AND pg.is_active=1 AND pg.deleted_at IS NULL
JOIN users u             ON u.user_id   = gcm.sender_id
LEFT JOIN uploaded_files uf ON uf.file_id = gcm.attachment_file_id
ORDER BY gcm.group_id, gcm.chat_type, gcm.created_at;

-- ── VIEW 9: DM Conversation Threads ──────────────────────────────────────────
CREATE OR REPLACE VIEW vw_dm_conversation_threads AS
SELECT
    dm.message_id, dm.sender_id,
    su.full_name                                 AS sender_name,
    su.university_id                             AS sender_uid,
    dm.receiver_id,
    ru.full_name                                 AS receiver_name,
    ru.university_id                             AS receiver_uid,
    dm.message_text,
    uf.file_path                                 AS attachment_path,
    uf.original_name                             AS attachment_name,
    dm.is_read, dm.created_at,
    LEAST(dm.sender_id, dm.receiver_id)          AS participant_a,
    GREATEST(dm.sender_id, dm.receiver_id)       AS participant_b
FROM direct_messages dm
JOIN users su        ON su.user_id = dm.sender_id
JOIN users ru        ON ru.user_id = dm.receiver_id
LEFT JOIN uploaded_files uf ON uf.file_id = dm.attachment_file_id
ORDER BY participant_a, participant_b, dm.created_at;

-- ── VIEW 10: Group Task Overview ─────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_group_task_overview AS
SELECT
    gt.task_id, pg.group_code, pg.project_title, u.full_name AS assigned_by,
    gt.week_no, gt.title AS task_title, gt.due_date,
    uf.original_name                                                    AS task_attachment,
    COUNT(DISTINCT gm.student_id)                                       AS total_members,
    COUNT(DISTINCT gts.submission_id)                                   AS submissions_received,
    SUM(CASE WHEN gts.status='ACKNOWLEDGED'   THEN 1 ELSE 0 END)        AS acknowledged,
    SUM(CASE WHEN gts.status='NEEDS_REVISION' THEN 1 ELSE 0 END)        AS needs_revision,
    ROUND(COUNT(DISTINCT gts.submission_id) * 100.0
          / NULLIF(COUNT(DISTINCT gm.student_id), 0), 2)                AS submission_rate_pct
FROM group_tasks gt
JOIN project_groups pg   ON pg.group_id = gt.group_id
                         AND pg.is_active=1 AND pg.deleted_at IS NULL
JOIN users u             ON u.user_id   = gt.supervisor_id
LEFT JOIN group_members gm         ON gm.group_id  = gt.group_id
LEFT JOIN group_task_submissions gts ON gts.task_id = gt.task_id
LEFT JOIN uploaded_files uf         ON uf.file_id   = gt.task_file_id
GROUP BY gt.task_id, pg.group_code, pg.project_title, u.full_name,
         gt.week_no, gt.title, gt.due_date, uf.original_name
ORDER BY gt.group_id, gt.week_no, gt.task_id;

-- ── VIEW 11: Active User Sessions ────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_active_user_sessions AS
SELECT
    us.session_id, u.user_id, u.university_id, u.full_name, u.role,
    us.ip_address, us.user_agent,
    us.created_at                                AS login_at,
    us.expires_at,
    TIMESTAMPDIFF(MINUTE, us.created_at, NOW()) AS session_age_minutes
FROM user_sessions us
JOIN users u ON u.user_id = us.user_id
WHERE us.expires_at > NOW()
  AND us.revoked_at  IS NULL
  AND u.account_status = 'ACTIVE'
  AND u.is_active = 1 AND u.deleted_at IS NULL
ORDER BY us.created_at DESC;

-- ── VIEW 12: Department-wide FYDP Analytics Dashboard ────────────────────────
CREATE OR REPLACE VIEW vw_department_fydp_analytics AS
SELECT
    d.department_id, d.department_name, d.short_code AS dept_code,
    COUNT(DISTINCT pg.group_id)                                           AS total_groups,
    COUNT(DISTINCT gm.student_id)                                         AS total_students_enrolled,
    COUNT(DISTINCT CASE WHEN pg.project_status='ACTIVE'    THEN pg.group_id END) AS active_groups,
    COUNT(DISTINCT CASE WHEN pg.project_status='COMPLETED' THEN pg.group_id END) AS completed_groups,
    COUNT(DISTINCT CASE WHEN pg.project_status='DROPPED'   THEN pg.group_id END) AS dropped_groups,
    COALESCE(SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END),0) AS approved_reports,
    COALESCE(SUM(CASE WHEN wpr.supervisor_status='PENDING'  THEN 1 ELSE 0 END),0) AS pending_reports,
    COALESCE(SUM(CASE WHEN wpr.supervisor_status='REJECTED' THEN 1 ELSE 0 END),0) AS rejected_reports,
    CASE WHEN COUNT(wpr.report_id) > 0
         THEN ROUND(SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)
                    / COUNT(wpr.report_id) * 100, 2)
         ELSE 0.00 END                                                    AS approval_rate_pct,
    RANK()  OVER (ORDER BY COUNT(DISTINCT CASE WHEN pg.project_status='ACTIVE' THEN pg.group_id END) DESC)
                                                                          AS dept_activity_rank,
    NTILE(4) OVER (ORDER BY COUNT(DISTINCT pg.group_id) DESC)             AS dept_quartile
FROM departments d
LEFT JOIN users u ON u.department_id=d.department_id AND u.role='SUPERVISOR'
                 AND u.is_active=1 AND u.deleted_at IS NULL
LEFT JOIN project_groups pg  ON pg.supervisor_id=u.user_id
                             AND pg.is_active=1 AND pg.deleted_at IS NULL
LEFT JOIN group_members gm   ON gm.group_id=pg.group_id
LEFT JOIN weekly_progress_reports wpr
       ON wpr.group_id=pg.group_id AND wpr.is_active=1 AND wpr.deleted_at IS NULL
WHERE d.short_code != 'ADMIN'
GROUP BY d.department_id, d.department_name, d.short_code;

-- ── VIEW 13: Pre-FYDP Student Readiness Scorecard [v6.0] ─────────────────────
-- Updated to reference user_profiles, user_skills, user_domain_interests
CREATE OR REPLACE VIEW vw_pre_fydp_readiness AS
WITH skill_agg AS (
    SELECT user_id,
           COUNT(*) AS total_skills,
           SUM(CASE proficiency_level
               WHEN 'EXPERT'       THEN 4
               WHEN 'ADVANCED'     THEN 3
               WHEN 'INTERMEDIATE' THEN 2
               WHEN 'BEGINNER'     THEN 1 END) AS skill_depth_score
      FROM user_skills GROUP BY user_id
),
domain_agg AS (
    SELECT user_id, COUNT(*) AS domain_count
      FROM user_domain_interests GROUP BY user_id
),
group_agg AS (
    SELECT user_id, COUNT(*) AS groups_joined
      FROM pre_fydp_group_members GROUP BY user_id
)
SELECT
    u.user_id, u.university_id, u.full_name, d.short_code AS dept_code,
    up.cgpa, up.preferred_role, up.availability_status, up.profile_strength,
    COALESCE(sa.total_skills, 0)       AS total_skills,
    COALESCE(sa.skill_depth_score, 0)  AS skill_depth_score,
    COALESCE(da.domain_count, 0)       AS domain_count,
    COALESCE(ga.groups_joined, 0)      AS groups_joined,
    LEAST(100, ROUND(
        (LEAST(COALESCE(up.profile_strength, 0), 100) * 0.30)
      + (LEAST(COALESCE(sa.skill_depth_score,0) * 5, 100) * 0.30)
      + (LEAST(COALESCE(da.domain_count,0)      * 25, 100) * 0.20)
      + (LEAST(COALESCE(ga.groups_joined,0)     * 33, 100) * 0.20)
    ))                                 AS readiness_score,
    RANK() OVER (ORDER BY up.profile_strength DESC) AS readiness_rank
FROM users u
JOIN departments d         ON d.department_id = u.department_id
JOIN user_profiles up      ON up.user_id      = u.user_id AND up.profile_type = 'PRE_FYDP'
LEFT JOIN skill_agg  sa    ON sa.user_id       = u.user_id
LEFT JOIN domain_agg da    ON da.user_id       = u.user_id
LEFT JOIN group_agg  ga    ON ga.user_id       = u.user_id
WHERE u.role='PRE_FYDP_STUDENT' AND u.account_status='ACTIVE'
  AND u.is_active=1 AND u.deleted_at IS NULL;

-- ── VIEW 14: System-wide KPI Health Dashboard [v6.0] ─────────────────────────
-- Updated students_looking_for_team to use user_profiles
CREATE OR REPLACE VIEW vw_system_health_kpi AS
SELECT
    (SELECT COUNT(*) FROM users WHERE is_active=1 AND deleted_at IS NULL)                              AS total_active_users,
    (SELECT COUNT(*) FROM users WHERE role='STUDENT'        AND account_status='ACTIVE' AND is_active=1 AND deleted_at IS NULL) AS active_students,
    (SELECT COUNT(*) FROM users WHERE role='SUPERVISOR'     AND account_status='ACTIVE' AND is_active=1 AND deleted_at IS NULL) AS active_supervisors,
    (SELECT COUNT(*) FROM users WHERE role='COURSE_TEACHER' AND account_status='ACTIVE' AND is_active=1 AND deleted_at IS NULL) AS active_course_teachers,
    (SELECT COUNT(*) FROM users WHERE role='PRE_FYDP_STUDENT' AND account_status='ACTIVE' AND is_active=1 AND deleted_at IS NULL) AS active_pre_fydp_students,
    (SELECT COUNT(*) FROM project_groups  WHERE project_status='ACTIVE' AND is_active=1 AND deleted_at IS NULL)  AS active_fydp_groups,
    (SELECT COUNT(*) FROM project_groups  WHERE project_status='COMPLETED' AND is_active=1)               AS completed_fydp_groups,
    (SELECT COUNT(*) FROM pre_fydp_groups WHERE group_status='OPEN' AND is_active=1 AND deleted_at IS NULL)      AS open_pre_fydp_groups,
    (SELECT COUNT(*) FROM weekly_progress_reports WHERE supervisor_status='PENDING' AND is_active=1 AND deleted_at IS NULL)      AS reports_pending_review,
    (SELECT COUNT(*) FROM course_teacher_inbox
      WHERE escalation_status IN ('PENDING_REVIEW','IN_PROGRESS'))                        AS ct_inbox_pending,
    (SELECT COUNT(*) FROM matchmaking_team_invitations WHERE invitation_status='PENDING') AS pending_invitations,
    (SELECT COUNT(*) FROM user_profiles WHERE availability_status='LOOKING')              AS students_looking_for_team,
    (SELECT COUNT(*) FROM group_chat_messages WHERE created_at >= NOW() - INTERVAL 1 DAY) AS group_msgs_last_24h,
    (SELECT COUNT(*) FROM direct_messages    WHERE created_at >= NOW() - INTERVAL 1 DAY)  AS dm_msgs_last_24h,
    (SELECT COUNT(*) FROM direct_messages    WHERE is_read=0)                              AS total_unread_dms,
    (SELECT COUNT(*) FROM user_sessions
      WHERE expires_at > NOW() AND revoked_at IS NULL)                                    AS active_sessions,
    (SELECT COUNT(*) FROM login_attempts
      WHERE was_success=0 AND attempted_at >= NOW() - INTERVAL 1 HOUR)                   AS failed_logins_last_hour,
    (SELECT COUNT(*) FROM group_task_submissions WHERE status='SUBMITTED')                AS pending_task_reviews;

-- ── VIEW 15: Supervisor Response Analytics ────────────────────────────────────
CREATE OR REPLACE VIEW vw_supervisor_response_analytics AS
SELECT
    u.user_id AS supervisor_id, u.full_name AS supervisor_name,
    d.short_code AS dept_code,
    COUNT(DISTINCT pg.group_id)                                             AS groups_supervised,
    COUNT(wpr.report_id)                                                    AS total_reports_received,
    SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)      AS reports_approved,
    SUM(CASE WHEN wpr.supervisor_status='REJECTED' THEN 1 ELSE 0 END)      AS reports_rejected,
    SUM(CASE WHEN wpr.supervisor_status='PENDING'  THEN 1 ELSE 0 END)      AS reports_pending,
    CASE WHEN COUNT(wpr.report_id) > 0
         THEN ROUND(SUM(CASE WHEN wpr.supervisor_status='APPROVED' THEN 1 ELSE 0 END)
                    / COUNT(wpr.report_id) * 100, 2)
         ELSE 0.00 END                                                      AS approval_rate_pct,
    ROUND(AVG(
        CASE WHEN wpr.supervisor_signed_at IS NOT NULL AND wpr.submitted_at IS NOT NULL
        THEN TIMESTAMPDIFF(HOUR, wpr.submitted_at, wpr.supervisor_signed_at)
        ELSE NULL END
    ), 1)                                                                   AS avg_response_hours,
    RANK() OVER (
        ORDER BY
            CASE WHEN AVG(CASE WHEN wpr.supervisor_signed_at IS NOT NULL AND wpr.submitted_at IS NOT NULL
                               THEN TIMESTAMPDIFF(HOUR, wpr.submitted_at, wpr.supervisor_signed_at)
                               ELSE NULL END) IS NULL THEN 1 ELSE 0 END ASC,
            AVG(CASE WHEN wpr.supervisor_signed_at IS NOT NULL AND wpr.submitted_at IS NOT NULL
                     THEN TIMESTAMPDIFF(HOUR, wpr.submitted_at, wpr.supervisor_signed_at)
                     ELSE NULL END) ASC
    )                                                                       AS response_speed_rank
FROM users u
JOIN departments d          ON d.department_id = u.department_id
LEFT JOIN project_groups pg ON pg.supervisor_id=u.user_id
                           AND pg.is_active=1 AND pg.deleted_at IS NULL
LEFT JOIN weekly_progress_reports wpr
       ON wpr.group_id=pg.group_id
      AND wpr.is_active=1 AND wpr.deleted_at IS NULL
WHERE u.role='SUPERVISOR' AND u.account_status='ACTIVE'
  AND u.is_active=1 AND u.deleted_at IS NULL
GROUP BY u.user_id, u.full_name, d.short_code;

-- ── VIEW 16: Group Grade Summary ─────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_group_grade_summary AS
SELECT
    pg.group_id, pg.group_code, pg.project_title,
    fs.stage_name AS current_stage,
    ge.evaluation_type,
    ge.score,
    ge.weight_pct,
    ge.weighted_score,
    fn_group_weighted_grade(pg.group_id)       AS final_grade,
    ROUND(
        SUM(ge2.weighted_score) / NULLIF(SUM(ge2.weight_pct) / 100, 0), 2
    )                                          AS weighted_avg_score,
    u.full_name                                AS evaluated_by
FROM project_groups pg
JOIN fydp_stages fs     ON fs.stage_id   = pg.current_stage_id
JOIN group_evaluations ge  ON ge.group_id = pg.group_id
JOIN group_evaluations ge2 ON ge2.group_id = pg.group_id
JOIN users u            ON u.user_id     = ge.teacher_id
WHERE pg.is_active=1 AND pg.deleted_at IS NULL
GROUP BY pg.group_id, pg.group_code, pg.project_title, fs.stage_name,
         ge.evaluation_type, ge.score, ge.weight_pct, ge.weighted_score,
         u.full_name;

-- ── VIEW 17: Active Announcements ────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_active_announcements AS
SELECT
    a.announcement_id, a.title, a.content, a.target_role,
    sec.section_code,
    u.full_name   AS author_name,
    u.role        AS author_role,
    a.created_at
FROM announcements a
JOIN users u             ON u.user_id    = a.author_id
LEFT JOIN sections sec   ON sec.section_id = a.section_id
WHERE a.is_active=1 AND a.deleted_at IS NULL
ORDER BY a.created_at DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 — DATABASE-LEVEL RBAC  [v5.0 FIX 3]
-- ─────────────────────────────────────────────────────────────────────────────

CREATE USER IF NOT EXISTS 'fydp_readonly'@'%'
    IDENTIFIED WITH caching_sha2_password BY 'Ch4ngeMe_Readonly_V5!';
GRANT SELECT ON fydp.* TO 'fydp_readonly'@'%';

CREATE USER IF NOT EXISTS 'fydp_app'@'%'
    IDENTIFIED WITH caching_sha2_password BY 'Ch4ngeMe_AppWriter_V5!';
GRANT SELECT, INSERT, UPDATE, DELETE ON fydp.* TO 'fydp_app'@'%';
GRANT EXECUTE                        ON fydp.* TO 'fydp_app'@'%';

CREATE USER IF NOT EXISTS 'fydp_migrator'@'%'
    IDENTIFIED WITH caching_sha2_password BY 'Ch4ngeMe_Migrator_V5!';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER,
      INDEX, REFERENCES ON fydp.* TO 'fydp_migrator'@'%';
GRANT EXECUTE ON fydp.* TO 'fydp_migrator'@'%';

CREATE USER IF NOT EXISTS 'fydp_admin'@'localhost'
    IDENTIFIED WITH caching_sha2_password BY 'Ch4ngeMe_DbaAdmin_V5!';
GRANT ALL PRIVILEGES ON fydp.* TO 'fydp_admin'@'localhost' WITH GRANT OPTION;

FLUSH PRIVILEGES;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 9 — TEST EXECUTION SCENARIOS  (18 tests)
-- ─────────────────────────────────────────────────────────────────────────────

SET SQL_SAFE_UPDATES = 0;

-- ── TEST 1: ESCALATION ENGINE ─────────────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 1: inbox before any approval ──' AS checkpoint;
SELECT * FROM course_teacher_inbox
 WHERE group_id=(SELECT group_id FROM project_groups WHERE group_code='UIU-G001');

CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id=(SELECT user_id FROM users WHERE university_id='STU001') AND week_no=1),
    (SELECT user_id FROM users WHERE university_id='SUP001'),
    'APPROVED','Excellent literature survey.');

-- -- SELECT '── After STU001 approval: IN_PROGRESS ──' AS checkpoint;
-- [v7.0] approved_count, total_members, is_fully_approved now computed in view
SELECT group_code, week_no, approved_count, total_members,
       is_fully_approved, escalation_status
  FROM vw_ct_inbox_summary WHERE group_code='UIU-G001';

CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id=(SELECT user_id FROM users WHERE university_id='STU002') AND week_no=1),
    (SELECT user_id FROM users WHERE university_id='SUP001'), 'APPROVED','Great UI wireframes.');
CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id=(SELECT user_id FROM users WHERE university_id='STU003') AND week_no=1),
    (SELECT user_id FROM users WHERE university_id='SUP001'), 'APPROVED','Good datasets.');
CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id=(SELECT user_id FROM users WHERE university_id='STU004') AND week_no=1),
    (SELECT user_id FROM users WHERE university_id='SUP001'), 'APPROVED','Excellent schema.');

-- -- SELECT '── After ALL approved: PENDING_REVIEW ──' AS checkpoint;
SELECT * FROM vw_ct_inbox_summary;
SELECT * FROM vw_ct_dashboard WHERE group_code='UIU-G001' AND week_no=1;

-- ── TEST 2: AUDIT LOG — pool-safe changed_by  [v5.0 FIX 1] ───────────────────
-- -- -- -- -- SELECT '── TEST 2: changed_by from NEW.last_changed_by (not session var) ──' AS checkpoint;
SELECT al.audit_id, al.table_name, al.operation, al.record_id,
       u.university_id AS changed_by_uid, al.old_data, al.new_data, al.changed_at
  FROM audit_log al
  LEFT JOIN users u ON u.user_id = al.changed_by
 ORDER BY al.changed_at DESC LIMIT 5;

-- ── TEST 3: APPROVAL PERCENTAGE FUNCTION ──────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 3: fn_get_group_approval_pct UIU-G001 Week 1 ──' AS checkpoint;
SELECT fn_get_group_approval_pct(
    (SELECT group_id FROM project_groups WHERE group_code='UIU-G001'), 1
) AS g001_week1_pct;

-- ── TEST 4: SKILL MATCH VIEW ──────────────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 4: Skill match — PFYDP001 vs all open groups (now uses unified user_skills) ──' AS checkpoint;
SELECT student_uid, group_name, skill_match_pct, current_members, max_members
  FROM vw_pre_fydp_skill_match WHERE student_uid='PFYDP001'
 ORDER BY skill_match_pct DESC;

-- ── TEST 5: SUPERVISOR CAPACITY LIMIT ────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 5a: 3rd group — should succeed ──' AS checkpoint;
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
VALUES
  ('UIU-G004','FinTrack: Blockchain Payment Ledger',
   (SELECT domain_id FROM project_domains WHERE domain_name='FinTech'),
   (SELECT user_id   FROM users WHERE university_id='SUP001'),
   (SELECT stage_id  FROM fydp_stages WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code='CSE-C'));


-- ── TEST 8: STAGE PROMOTION ───────────────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 8: promotion UIU-G001 → FYDP-2 ──' AS checkpoint;
CALL sp_promote_fydp_stage(
    (SELECT group_id  FROM project_groups WHERE group_code='UIU-G001'),
    (SELECT stage_id  FROM fydp_stages WHERE stage_name='FYDP-2'),
    (SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),
    'BanglaBot 2.0: Advanced AI Dialogue System',
    (SELECT user_id   FROM users WHERE university_id='ADMIN001'),
    'Group refined scope during FYDP-1.');
SELECT group_code, project_title, current_stage_id FROM project_groups WHERE group_code='UIU-G001';
SELECT * FROM topic_change_history
 WHERE group_id=(SELECT group_id FROM project_groups WHERE group_code='UIU-G001');

-- ── TEST 9: CT INBOX REVIEWER ROLE GUARD ──────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 9a: non-teacher reviewer — fail (COMMENTED OUT FOR WORKBENCH) ──' AS checkpoint;
/*
UPDATE course_teacher_inbox
   SET reviewed_by=(SELECT user_id FROM users WHERE university_id='STU001'),
       reviewed_at=NOW(), escalation_status='REVIEWED'
 WHERE group_id=(SELECT group_id FROM project_groups WHERE group_code='UIU-G001') AND week_no=1;
*/

-- -- -- -- -- SELECT '── TEST 9b: valid teacher reviewer — succeed ──' AS checkpoint;
UPDATE course_teacher_inbox
   SET reviewed_by=(SELECT user_id FROM users WHERE university_id='CT001'),
       reviewed_at=NOW(), escalation_status='REVIEWED'
 WHERE group_id=(SELECT group_id FROM project_groups WHERE group_code='UIU-G001') AND week_no=1;

-- ── TEST 10: PRE-FYDP JOIN REQUEST DEDUP ─────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 10: duplicate pending request — fail (COMMENTED OUT FOR WORKBENCH) ──' AS checkpoint;
/*
INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message)
VALUES ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),
        (SELECT user_id  FROM users WHERE university_id='PFYDP001'),
        'JOIN_REQUEST','Duplicate — blocked by trigger.');
*/

-- ── TEST 11: AVAILABILITY AUTO-UPDATE ────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 11a: PFYDP005 before joining ──' AS checkpoint;
-- [v6.0] Updated to query user_profiles instead of pre_fydp_profiles
SELECT u.university_id, up.availability_status
  FROM user_profiles up JOIN users u ON u.user_id=up.user_id
 WHERE u.university_id='PFYDP005' AND up.profile_type='PRE_FYDP';

INSERT INTO pre_fydp_group_members (group_id, user_id, member_role)
VALUES ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),
        (SELECT user_id  FROM users WHERE university_id='PFYDP005'), 'Security');

-- -- -- -- -- SELECT '── TEST 11b: PFYDP005 should be IN_TEAM ──' AS checkpoint;
-- Updated to query user_profiles instead of pre_fydp_profiles
SELECT u.university_id, up.availability_status
  FROM user_profiles up JOIN users u ON u.user_id=up.user_id
 WHERE u.university_id='PFYDP005' AND up.profile_type='PRE_FYDP';

-- ── TEST 12: TASK SUBMISSION ──────────────────────────────────────────────────
INSERT INTO group_task_submissions (task_id, student_id, status, student_note)
VALUES ((SELECT task_id FROM group_tasks LIMIT 1),
        (SELECT user_id FROM users WHERE university_id='STU001'),
        'SUBMITTED','Completed dataset pipeline documentation.');

-- -- -- -- -- SELECT '── TEST 12: Group task overview ──' AS checkpoint;
SELECT * FROM vw_group_task_overview;

-- ── TEST 13: STATUS LOG + POOL-SAFE AUDIT  [v5.0 FIX 1] ─────────────────────
-- -- -- -- -- SELECT '── TEST 13: pool-safe audit via last_changed_by ──' AS checkpoint;
UPDATE users SET last_changed_by=(SELECT user_id FROM (SELECT user_id FROM users WHERE university_id='ADMIN001') AS tmp),
                 account_status='SUSPENDED'
 WHERE university_id='STU002';
UPDATE users SET last_changed_by=(SELECT user_id FROM (SELECT user_id FROM users WHERE university_id='ADMIN001') AS tmp),
                 account_status='ACTIVE'
 WHERE university_id='STU002';
SELECT usl.*, u.full_name, changer.university_id AS changed_by_uid
  FROM user_status_log usl
  JOIN users u       ON u.user_id      = usl.user_id
  LEFT JOIN users changer ON changer.user_id = usl.changed_by
 WHERE usl.user_id=(SELECT user_id FROM users WHERE university_id='STU002')
 ORDER BY changed_at;

-- ── TEST 14: SESSION MANAGEMENT ──────────────────────────────────────────────
-- -- -- -- -- SELECT '── TEST 14: password reset token + session ──' AS checkpoint;
INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
VALUES ((SELECT user_id FROM users WHERE university_id='STU003'),
        SHA2(CONCAT('reset-token-', NOW()), 256),
        DATE_ADD(NOW(), INTERVAL 1 HOUR));

INSERT INTO user_sessions (session_id, user_id, refresh_token, ip_address, expires_at)
VALUES (UUID(),
        (SELECT user_id FROM users WHERE university_id='STU001'),
        SHA2(CONCAT('refresh-',UUID()),256),'192.168.1.100',
        DATE_ADD(NOW(), INTERVAL 7 DAY));
SELECT session_id, university_id, full_name, role, ip_address, session_age_minutes
  FROM vw_active_user_sessions LIMIT 5;

-- ── TEST 15: BULK IMPORT ──────────────────────────────────────────────────────
INSERT INTO ucam_import_staging
  (raw_student_university_id, raw_group_code, raw_supervisor_university_id,
   raw_stage_name, raw_project_title, raw_domain_name, import_batch_id)
VALUES
  ('STU001','UIU-IMP-001','SUP003','FYDP-1','Smart IoT Health','IoT','BATCH-001'),
  ('STU002','UIU-IMP-001','SUP003','FYDP-1','Smart IoT Health','IoT','BATCH-001'),
  ('INVALID','UIU-IMP-001','SUP003','FYDP-1','Should Fail','IoT','BATCH-001'),
  ('STU003','UIU-IMP-001','BAD',   'FYDP-1','Smart IoT Health','IoT','BATCH-001');
CALL sp_bulk_import_ucam_groups('BATCH-001');
SELECT * FROM import_error_logs ORDER BY logged_at DESC;

-- ── TEST 16: EVALUATION WEIGHT + GRADE ENGINE  [v5.0 FIX 5] ─────────────────
-- -- -- -- -- SELECT '── TEST 16: Eval weight auto-copied from config table ──' AS checkpoint;
INSERT INTO group_evaluations (group_id, teacher_id, evaluation_type, score)
VALUES ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
        (SELECT user_id  FROM users WHERE university_id='CT001'),
        'MIDTERM', 82.00);

SELECT ge.evaluation_type, ge.score, ge.weight_pct, ge.weighted_score,
       fn_group_weighted_grade(ge.group_id) AS grade
  FROM group_evaluations ge
  JOIN project_groups pg ON pg.group_id = ge.group_id
 WHERE pg.group_code = 'UIU-G001';

-- -- SELECT '── Grade summary view ──' AS checkpoint;
SELECT * FROM vw_group_grade_summary WHERE group_code='UIU-G001';

-- ── TEST 17: SOFT-DELETE FILTER VERIFICATION  [v5.0 FIX 2] ──────────────────
-- -- -- -- -- SELECT '── TEST 17: soft-deleted group must vanish from all views ──' AS checkpoint;
UPDATE project_groups
   SET is_active=0, deleted_at=NOW()
 WHERE group_code='UIU-G003';

-- -- SELECT '── UIU-G003 must not appear in progress summary: ──' AS checkpoint;
SELECT group_code FROM vw_group_progress_summary WHERE group_code='UIU-G003';
-- Expected: 0 rows

-- -- SELECT '── UIU-G003 must not appear in supervisor workload count: ──' AS checkpoint;
SELECT supervisor_name, total_groups_in_stage FROM vw_supervisor_workload
 WHERE supervisor_name='Dr. Karim Hossain';

-- ── TEST 18: PARTITION PROVISIONING  [v5.0 FIX 4] ───────────────────────────
-- -- -- -- -- SELECT '── TEST 18: provision next month partition ──' AS checkpoint;
CALL sp_create_next_month_partitions();



SELECT fn_is_student_in_active_group(
    (SELECT user_id FROM users WHERE university_id='STU001')
) AS is_in_active_group;
SELECT fn_unread_dm_count(
    (SELECT user_id FROM users WHERE university_id='STU003')
) AS unread_dm_count;

CALL sp_mark_all_notifications_read(
    (SELECT user_id FROM users WHERE university_id='STU001'));
CALL sp_mark_dm_conversation_read(
    (SELECT user_id FROM users WHERE university_id='STU003'),
    (SELECT user_id FROM users WHERE university_id='STU001'));
CALL sp_cleanup_expired_sessions();

SELECT MATCH(project_title) AGAINST('AI Bangla' IN BOOLEAN MODE) AS relevance,
       group_code, project_title
  FROM project_groups
 WHERE MATCH(project_title) AGAINST('AI Bangla' IN BOOLEAN MODE)
 ORDER BY relevance DESC;

SELECT audit_id, table_name, operation, record_id, changed_by, changed_at
  FROM audit_log ORDER BY changed_at DESC LIMIT 20;

 -- END OF COMMENTED TEST SECTION

SET SQL_SAFE_UPDATES = 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEMA VERSION — v6.0 + v7.0
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO schema_version (version, description, script) VALUES
  ('6.0',
   'Integrity CHECKs on soft-delete columns; weight sum trigger; user_profiles merged; user_skills/user_domain_interests merged; announcements.target_role ENUM (3NF fix); invitation trigger sender+receiver availability fix; sample announcements; test 6c collision fix',
   'V6__normalization_integrity.sql');

INSERT INTO schema_version (version, description, script) VALUES
  ('7.0',
   'Strict 3NF/BCNF compliance: removed derived columns (total_members, approved_count, is_fully_approved) from course_teacher_inbox; added preferred_role CHECK constraint to user_profiles; rewritten escalation trigger and 3 views to compute counts from source tables',
   'V7__strict_3nf_bcnf_compliance.sql');

INSERT INTO schema_version (version, description, script) VALUES
  ('8.0',
   'Backend compatibility: otp_code/otp_expires_at on users; batch on users; is_group_report+report_file_path on wpr; file_path/file_name/assigned_to on group_tasks; group_id/grade/feedback/rejection_reason on group_task_submissions; LEAVE_REQUEST ENUM; compatibility views for renamed tables',
   'V8__backend_compatibility.sql');

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPATIBILITY VIEWS — map old table names to new unified tables [v8.0]
-- ─────────────────────────────────────────────────────────────────────────────

-- Backward-compat view: pre_fydp_profiles → user_profiles (PRE_FYDP rows only)
CREATE OR REPLACE VIEW pre_fydp_profiles AS
  SELECT profile_id, user_id, batch, bio, cgpa, github_url, linkedin_url,
         portfolio_url, preferred_role, trimester_id, availability_status,
         profile_strength, created_at, updated_at
  FROM user_profiles
  WHERE profile_type = 'PRE_FYDP';

-- Backward-compat view: pre_fydp_student_skills → user_skills
CREATE OR REPLACE VIEW pre_fydp_student_skills AS
  SELECT user_id, skill_id, proficiency_level, years_experience, created_at
  FROM user_skills;

-- Backward-compat view: pre_fydp_student_domain_interests → user_domain_interests
CREATE OR REPLACE VIEW pre_fydp_student_domain_interests AS
  SELECT user_id, domain_id, interest_level, created_at
  FROM user_domain_interests;

-- Backward-compat view: task_submissions → group_task_submissions
CREATE OR REPLACE VIEW task_submissions AS
  SELECT submission_id, task_id, student_id, group_id, status, student_note AS notes,
         notes AS student_note_alias, attachment_file_id, file_path, file_name,
         grade, feedback, rejection_reason, submitted_at, reviewed_at, reviewed_by
  FROM group_task_submissions;

-- END
