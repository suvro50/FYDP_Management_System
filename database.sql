
-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1 — DATABASE CREATION
-- ─────────────────────────────────────────────────────────────────────────────

DROP DATABASE IF EXISTS fydp;

CREATE DATABASE fydp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE fydp;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2 — TABLE DEFINITIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE departments (
    department_id       INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    department_name     VARCHAR(150)     NOT NULL  COMMENT 'Full official name',
    short_code          VARCHAR(20)      NOT NULL  COMMENT 'e.g. CSE, EEE, BBA',
    faculty             VARCHAR(150)     NULL      COMMENT 'Parent faculty name',
    is_active           TINYINT(1)       NOT NULL  DEFAULT 1,
    created_at          DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                   ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (department_id),
    UNIQUE KEY uq_dept_name  (department_name),
    UNIQUE KEY uq_dept_code  (short_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Reference table — replaces raw VARCHAR department in users';

-- ----------------------------------------------------------------------------
-- TABLE: sections                                                [NEW v3.0]
CREATE TABLE sections (
    section_id      INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    section_code    VARCHAR(20)     NOT NULL  COMMENT 'e.g. CSE-A, EEE-B',
    department_id   INT UNSIGNED    NOT NULL,
    is_active       TINYINT(1)      NOT NULL  DEFAULT 1,
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (section_id),
    UNIQUE KEY uq_section_code (section_code),
    CONSTRAINT fk_sec_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Reference table — replaces raw section_code VARCHAR in multiple tables';

-- ----------------------------------------------------------------------------
-- TABLE: trimesters                                              [NEW v3.0]

CREATE TABLE trimesters (
    trimester_id    INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    trimester_name  VARCHAR(30)     NOT NULL  COMMENT 'e.g. Spring 2026',
    start_date      DATE            NOT NULL,
    end_date        DATE            NOT NULL,
    is_active       TINYINT(1)      NOT NULL  DEFAULT 1,
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (trimester_id),
    UNIQUE KEY uq_trim_name (trimester_name),
    CONSTRAINT chk_trim_dates CHECK (end_date > start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Reference table — replaces raw target_trimester VARCHAR';

-- ----------------------------------------------------------------------------
-- TABLE: skills
-- BCNF: skill_id and skill_name are both candidate keys.
-- ----------------------------------------------------------------------------
CREATE TABLE skills (
    skill_id        INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    skill_name      VARCHAR(100)    NOT NULL,
    skill_category  VARCHAR(100)    NULL      COMMENT 'e.g. Programming, AI/ML, DevOps',
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (skill_id),
    UNIQUE KEY uq_skill_name (skill_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master skill catalogue — shared across all modules';

-- ----------------------------------------------------------------------------
-- TABLE: project_domains
-- BCNF: domain_id and domain_name are both candidate keys.
-- ----------------------------------------------------------------------------
CREATE TABLE project_domains (
    domain_id       INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    domain_name     VARCHAR(100)    NOT NULL,
    description     TEXT            NULL,
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (domain_id),
    UNIQUE KEY uq_domain_name (domain_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master domain catalogue — shared across FYDP and Pre-FYDP modules';

-- ----------------------------------------------------------------------------
-- TABLE: fydp_stages
-- stage_order enforces forward-only promotion in sp_promote_fydp_stage.
-- BCNF: stage_id, stage_name, stage_order are all candidate keys.
-- ----------------------------------------------------------------------------
CREATE TABLE fydp_stages (
    stage_id        INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    stage_name      ENUM('FYDP-1','FYDP-2','FYDP-3')  NOT NULL,
    stage_order     TINYINT         NOT NULL  COMMENT 'Ordering: 1, 2, 3',
    description     TEXT            NULL,
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (stage_id),
    UNIQUE KEY uq_stage_name  (stage_name),
    UNIQUE KEY uq_stage_order (stage_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FYDP lifecycle stages — stage_order enforces forward-only promotion';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 1: USER MANAGEMENT
-- ══════════════════════════════════════════════════════════════════════════════

-- ----------------------------------------------------------------------------
-- TABLE: users
-- department_id FK eliminates transitive dependency (3NF).
-- Soft-delete: is_active + deleted_at preserve referential integrity.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id             INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    university_id       VARCHAR(20)     NOT NULL,
    full_name           VARCHAR(120)    NOT NULL,
    email               VARCHAR(150)    NOT NULL,
    password_hash       VARCHAR(255)    NOT NULL,
    role                ENUM('STUDENT','SUPERVISOR','COURSE_TEACHER',
                             'ADMIN','PRE_FYDP_STUDENT')
                                        NOT NULL  DEFAULT 'STUDENT',
    department_id       INT UNSIGNED    NOT NULL,
    batch               VARCHAR(20)     NULL,
    phone               VARCHAR(20)     NULL,
    profile_photo       VARCHAR(500)    NULL,
    account_status      ENUM('ACTIVE','SUSPENDED','DEACTIVATED')
                                        NOT NULL  DEFAULT 'ACTIVE',
    is_active           TINYINT(1)      NOT NULL  DEFAULT 1,
    deleted_at          DATETIME        NULL,
    created_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                  ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email         (email),
    UNIQUE KEY uq_users_university_id (university_id),
    CONSTRAINT fk_users_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master auth table — department FK eliminates update anomalies';

-- ----------------------------------------------------------------------------
-- TABLE: user_status_log
CREATE TABLE user_status_log (
    log_id          BIGINT UNSIGNED     NOT NULL  AUTO_INCREMENT,
    user_id         INT UNSIGNED        NOT NULL,
    old_status      ENUM('ACTIVE','SUSPENDED','DEACTIVATED')
                                        NULL      COMMENT 'NULL on first log',
    new_status      ENUM('ACTIVE','SUSPENDED','DEACTIVATED')
                                        NOT NULL,
    changed_by      INT UNSIGNED        NULL      COMMENT 'Admin user_id',
    reason          TEXT                NULL,
    changed_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id),
    CONSTRAINT fk_usl_user
        FOREIGN KEY (user_id)    REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_usl_changed_by
        FOREIGN KEY (changed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable status history — auto-populated by trigger on account_status change';

-- ----------------------------------------------------------------------------
-- TABLE: student_profiles
-- [v3.0] target_trimester VARCHAR → trimester_id FK
-- [v3.0] CGPA CHECK constraint: 0.00–4.00
-- Separated from users to avoid role-based null anomalies.
-- ----------------------------------------------------------------------------
CREATE TABLE student_profiles (
    student_profile_id      INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    student_id              INT UNSIGNED    NOT NULL,
    cgpa                    DECIMAL(4,2)    NULL,
    bio                     TEXT            NULL,
    github_url              VARCHAR(500)    NULL,
    linkedin_url            VARCHAR(500)    NULL,
    portfolio_url           VARCHAR(500)    NULL,
    preferred_team_role     ENUM('TEAM_LEAD','DEVELOPER','DESIGNER',
                                 'RESEARCHER','TESTER','DATA_ENGINEER')
                                            NULL,
    trimester_id            INT UNSIGNED    NULL      COMMENT '[v3.0] FK → trimesters (was VARCHAR)',
    availability_status     ENUM('LOOKING','IN_TEAM','NOT_AVAILABLE')
                                            NOT NULL  DEFAULT 'LOOKING',
    created_at              DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                      ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (student_profile_id),
    UNIQUE KEY uq_sp_student_id (student_id),
    CONSTRAINT chk_sp_cgpa CHECK (cgpa IS NULL OR cgpa BETWEEN 0.00 AND 4.00),
    CONSTRAINT fk_sp_student
        FOREIGN KEY (student_id)   REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_sp_trimester
        FOREIGN KEY (trimester_id) REFERENCES trimesters(trimester_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Extended profile — trimester FK + CGPA CHECK(0-4)';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 2: FYDP-TRACK MATCHMAKING
-- ══════════════════════════════════════════════════════════════════════════════

-- ----------------------------------------------------------------------------
-- TABLE: student_skills
-- BCNF: (student_id, skill_id) is the only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE student_skills (
    student_id          INT UNSIGNED    NOT NULL,
    skill_id            INT UNSIGNED    NOT NULL,
    proficiency_level   ENUM('BEGINNER','INTERMEDIATE','ADVANCED','EXPERT')
                                        NOT NULL  DEFAULT 'BEGINNER',
    years_experience    DECIMAL(4,1)    NULL      DEFAULT 0.0,
    created_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (student_id, skill_id),
    CONSTRAINT fk_ss_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ss_skill
        FOREIGN KEY (skill_id)   REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: FYDP Student ↔ Skill with proficiency metadata';

-- ----------------------------------------------------------------------------
-- TABLE: student_domain_interests
-- BCNF: (student_id, domain_id) → interest_level. Only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE student_domain_interests (
    student_id      INT UNSIGNED    NOT NULL,
    domain_id       INT UNSIGNED    NOT NULL,
    interest_level  ENUM('LOW','MEDIUM','HIGH')  NOT NULL  DEFAULT 'MEDIUM',
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (student_id, domain_id),
    CONSTRAINT fk_sdi_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_sdi_domain
        FOREIGN KEY (domain_id)  REFERENCES project_domains(domain_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: FYDP Student ↔ Domain interest preference';

-- ----------------------------------------------------------------------------
-- TABLE: matchmaking_team_invitations
-- Trigger enforces: (a) no self-invite (b) no duplicate PENDING.
-- ----------------------------------------------------------------------------
CREATE TABLE matchmaking_team_invitations (
    invitation_id           INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    sender_student_id       INT UNSIGNED    NOT NULL,
    receiver_student_id     INT UNSIGNED    NOT NULL,
    invitation_message      TEXT            NULL,
    invitation_status       ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED')
                                            NOT NULL  DEFAULT 'PENDING',
    responded_at            DATETIME        NULL,
    created_at              DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                      ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (invitation_id),
    CONSTRAINT fk_inv_sender
        FOREIGN KEY (sender_student_id)   REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_inv_receiver
        FOREIGN KEY (receiver_student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Team invitations — self-invite & duplicate-PENDING enforced by trigger';

-- ----------------------------------------------------------------------------
-- TABLE: notifications
-- [v3.0] reference_entity_type VARCHAR → ENUM (prevents garbage table names)
-- [v3.1] ENUM expanded with 'group_chat_messages','direct_messages'
-- 3NF: notification_id → all attributes. No transitive dependencies.
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
    notification_id         INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    user_id                 INT UNSIGNED    NOT NULL,
    notification_type       ENUM('INVITATION_RECEIVED','INVITATION_ACCEPTED',
                                 'INVITATION_REJECTED','REPORT_APPROVED',
                                 'REPORT_REJECTED','ESCALATION_COMPLETE',
                                 'STAGE_PROMOTED','SYSTEM_ALERT',
                                 'NEW_GROUP_MESSAGE','NEW_DIRECT_MESSAGE')
                                            NOT NULL,
    title                   VARCHAR(255)    NULL      COMMENT 'Short notification heading (added v3.2)',
    message                 TEXT            NOT NULL,
    reference_entity_id     INT UNSIGNED    NULL  COMMENT 'PK of the related record',
    reference_entity_type   ENUM('matchmaking_team_invitations',
                                 'project_groups',
                                 'course_teacher_inbox',
                                 'weekly_progress_reports',
                                 'pre_fydp_join_requests',
                                 'group_chat_messages',
                                 'direct_messages')
                                            NULL  COMMENT '[v3.1] ENUM expanded for messaging',
    is_read                 TINYINT(1)      NOT NULL  DEFAULT 0,
    created_at              DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id),
    CONSTRAINT fk_notif_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.1] System notification inbox — reference_entity_type ENUM extended for messaging';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 3: FYDP GROUP MANAGEMENT & ESCALATION ENGINE
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE announcements (
    announcement_id INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    author_id       INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users (teacher)',
    title           VARCHAR(255)        NOT NULL,
    content         TEXT                NOT NULL,
    target_role     VARCHAR(50)         NOT NULL  DEFAULT 'ALL'
                                        COMMENT 'ALL | STUDENT | SUPERVISOR | TEACHER',
    target_section  VARCHAR(100)        NULL
                                        COMMENT 'Optional section filter',
    created_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (announcement_id),
    CONSTRAINT fk_ann_author
        FOREIGN KEY (author_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_ann_author (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Teacher-broadcast announcements with optional role/section targeting';

-- ----------------------------------------------------------------------------
-- TABLE: group_evaluations
-- Purpose : Course-teacher grading of a project group per evaluation type.
--           Uses UNIQUE(group_id, evaluation_type) for ON DUPLICATE KEY UPDATE.
-- 3NF/BCNF : evaluation_id is the sole determinant.
-- ----------------------------------------------------------------------------
CREATE TABLE group_evaluations (
    evaluation_id   INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    group_id        INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → project_groups',
    teacher_id      INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users (course teacher)',
    evaluation_type VARCHAR(100)        NOT NULL
                                        COMMENT 'e.g. MIDTERM | FINAL | PRESENTATION',
    score           DECIMAL(5,2)        NOT NULL,
    feedback        TEXT                NULL,
    evaluated_at    DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (evaluation_id),
    UNIQUE KEY uk_eval_group_type (group_id, evaluation_type),
    CONSTRAINT fk_eval_group
        FOREIGN KEY (group_id)    REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_eval_teacher
        FOREIGN KEY (teacher_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_eval_group (group_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Per-group evaluation scores entered by course teacher';

-- ----------------------------------------------------------------------------
-- TABLE: project_groups
-- [v3.0] section_id FK (was raw section_code VARCHAR) — 3NF fix.
-- Supervisor capacity (max 3 active groups per stage) enforced by trigger.
-- ----------------------------------------------------------------------------
CREATE TABLE project_groups (
    group_id            INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    group_code          VARCHAR(30)     NOT NULL,
    project_title       VARCHAR(300)    NOT NULL,
    project_domain_id   INT UNSIGNED    NOT NULL,
    supervisor_id       INT UNSIGNED    NOT NULL,
    current_stage_id    INT UNSIGNED    NOT NULL,
    section_id          INT UNSIGNED    NOT NULL  COMMENT '[v3.0] FK → sections (was VARCHAR)',
    project_status      ENUM('ACTIVE','COMPLETED','DROPPED','ON_HOLD')
                                        NOT NULL  DEFAULT 'ACTIVE',
    is_active           TINYINT(1)      NOT NULL  DEFAULT 1,
    deleted_at          DATETIME        NULL,
    created_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                  ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    UNIQUE KEY uq_group_code (group_code),
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
  COMMENT='[v3.0] FYDP project groups — section_id FK + supervisor capacity trigger';

-- ----------------------------------------------------------------------------
-- TABLE: group_members
-- BCNF: (group_id, student_id) is the only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE group_members (
    group_member_id     INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    group_id            INT UNSIGNED    NOT NULL,
    student_id          INT UNSIGNED    NOT NULL,
    member_role         ENUM('TEAM_LEAD','DEVELOPER','DESIGNER',
                             'RESEARCHER','TESTER','DATA_ENGINEER')
                                        NOT NULL  DEFAULT 'DEVELOPER',
    joined_at           DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
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

-- ----------------------------------------------------------------------------
-- TABLE: course_teacher_sections
-- [v3.0] section_id FK (was section_code VARCHAR) — 3NF fix.
-- BCNF: (course_teacher_id, section_id, assigned_stage_id) is the only key.
-- ----------------------------------------------------------------------------
CREATE TABLE course_teacher_sections (
    mapping_id          INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    course_teacher_id   INT UNSIGNED    NOT NULL,
    section_id          INT UNSIGNED    NOT NULL  COMMENT '[v3.0] FK → sections (was VARCHAR)',
    assigned_stage_id   INT UNSIGNED    NOT NULL,
    created_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
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
  COMMENT='[v3.0] Maps course teachers to sections — section_id FK replaces VARCHAR';

-- ----------------------------------------------------------------------------
-- TABLE: weekly_progress_reports
-- [v3.1] report_file_path column added for PDF upload support.
-- CHECK constraint enforces valid week numbers (1–52).
-- UNIQUE KEY prevents duplicate weekly submissions.
-- ----------------------------------------------------------------------------
CREATE TABLE weekly_progress_reports (
    report_id               INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    group_id                INT UNSIGNED        NOT NULL,
    student_id              INT UNSIGNED        NOT NULL,
    week_no                 TINYINT UNSIGNED    NOT NULL,
    report_title            VARCHAR(300)        NOT NULL,
    report_content          LONGTEXT            NOT NULL,
    report_file_path        VARCHAR(500)        NULL
                                                COMMENT '[v3.1] Relative path to uploaded PDF e.g. /uploads/reports/report_7_xxx.pdf',
    submitted_at            DATETIME            NULL,
    supervisor_status       ENUM('PENDING','APPROVED','REJECTED')
                                                NOT NULL  DEFAULT 'PENDING',
    supervisor_feedback     TEXT                NULL,
    supervisor_signed_at    DATETIME            NULL,
    is_active               TINYINT(1)          NOT NULL  DEFAULT 1,
    created_at              DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                          ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (report_id),
    UNIQUE KEY uq_report_weekly (group_id, student_id, week_no),
    CONSTRAINT chk_week_range CHECK (week_no BETWEEN 1 AND 52),
    CONSTRAINT fk_wpr_group
        FOREIGN KEY (group_id)   REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_wpr_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.1] Weekly progress journal — report_file_path added for PDF uploads';

-- ----------------------------------------------------------------------------
-- TABLE: course_teacher_inbox
-- [v3.0 / v2.1 INTEGRATED] total_members, approved_count, is_fully_approved added.
-- [v3.0] escalation_status ENUM expanded — added 'IN_PROGRESS'.
-- Auto-populated ONLY by the escalation trigger. UNIQUE KEY = idempotency.
-- ----------------------------------------------------------------------------
CREATE TABLE course_teacher_inbox (
    inbox_id            INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    group_id            INT UNSIGNED        NOT NULL,
    week_no             TINYINT UNSIGNED    NOT NULL,
    escalated_at        DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    escalation_status   ENUM('IN_PROGRESS','PENDING_REVIEW','REVIEWED','FLAGGED')
                                            NOT NULL  DEFAULT 'IN_PROGRESS'
                                            COMMENT '[v3.0] IN_PROGRESS added for partial approval',
    total_members       TINYINT UNSIGNED    NOT NULL  DEFAULT 0
                                            COMMENT 'Total members in the group',
    approved_count      TINYINT UNSIGNED    NOT NULL  DEFAULT 0
                                            COMMENT 'How many members approved so far',
    is_fully_approved   TINYINT(1)          NOT NULL  DEFAULT 0
                                            COMMENT '1 = all members approved',
    reviewed_at         DATETIME            NULL,
    reviewed_by         INT UNSIGNED        NULL  COMMENT 'course_teacher user_id',
    notes               TEXT                NULL,
    PRIMARY KEY (inbox_id),
    UNIQUE KEY uq_inbox_group_week (group_id, week_no),
    CONSTRAINT fk_inbox_group
        FOREIGN KEY (group_id)    REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_inbox_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] CT inbox — partial + full approval tracking, idempotent via UNIQUE KEY';

-- ----------------------------------------------------------------------------
-- TABLE: topic_change_history
-- Immutable append-only audit log for project title and domain changes.
-- 3NF: history_id → all attributes. No transitive dependencies.
-- ----------------------------------------------------------------------------
CREATE TABLE topic_change_history (
    history_id          INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    group_id            INT UNSIGNED    NOT NULL,
    old_domain_id       INT UNSIGNED    NULL,
    new_domain_id       INT UNSIGNED    NULL,
    old_project_title   VARCHAR(300)    NULL,
    new_project_title   VARCHAR(300)    NULL,
    changed_by_admin    INT UNSIGNED    NOT NULL,
    change_reason       TEXT            NOT NULL,
    changed_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
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

-- ----------------------------------------------------------------------------
-- TABLE: import_error_logs
-- Row-level error log for bulk UCAM CSV import.
-- ----------------------------------------------------------------------------
CREATE TABLE import_error_logs (
    error_id        INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    error_row       INT             NOT NULL,
    error_message   VARCHAR(500)    NOT NULL,
    raw_data        TEXT            NULL,
    logged_at       DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (error_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Row-level error log for bulk UCAM CSV import failures';

-- ----------------------------------------------------------------------------
-- TABLE: ucam_import_staging
-- Raw staging — intentionally FK-free (raw data, validated in procedure).
-- ----------------------------------------------------------------------------
CREATE TABLE ucam_import_staging (
    staging_id                      INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    raw_student_university_id       VARCHAR(50)     NULL,
    raw_group_code                  VARCHAR(50)     NULL,
    raw_supervisor_university_id    VARCHAR(50)     NULL,
    raw_stage_name                  VARCHAR(50)     NULL,
    raw_project_title               VARCHAR(300)    NULL,
    raw_domain_name                 VARCHAR(100)    NULL,
    import_batch_id                 VARCHAR(50)     NULL  COMMENT 'UUID or batch label',
    imported_at                     DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (staging_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Staging table — intentionally FK-free (raw data)';

-- ----------------------------------------------------------------------------
-- TABLE: audit_log
-- Enterprise-grade immutable audit trail. JSON diff stores before/after state.
-- ----------------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id        BIGINT UNSIGNED     NOT NULL  AUTO_INCREMENT,
    table_name      VARCHAR(100)        NOT NULL,
    operation       ENUM('INSERT','UPDATE','DELETE')  NOT NULL,
    record_id       INT UNSIGNED        NOT NULL,
    changed_by      INT UNSIGNED        NULL  COMMENT 'user_id — NULL if system-triggered',
    old_data        JSON                NULL,
    new_data        JSON                NULL,
    changed_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Enterprise audit trail — JSON before/after diff';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 5: PRE-FYDP TEAM BUILDING PLATFORM
-- ══════════════════════════════════════════════════════════════════════════════

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_profiles
-- [v3.0] trimester_id FK (was VARCHAR) + CGPA CHECK(0-4)
-- [v2.0] JSON columns fully removed (1NF fix).
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_profiles (
    profile_id          INT UNSIGNED     NOT NULL  AUTO_INCREMENT,
    user_id             INT UNSIGNED     NOT NULL,
    bio                 TEXT             NULL,
    cgpa                DECIMAL(4,2)     NULL,
    preferred_role      ENUM('FULL_STACK_DEVELOPER','FRONTEND_DEVELOPER',
                             'BACKEND_DEVELOPER','ML_ENGINEER','DATA_SCIENTIST',
                             'SECURITY_ANALYST','EMBEDDED_DEVELOPER',
                             'UI_UX_DESIGNER','DEVOPS_ENGINEER','OTHER')
                                         NULL,
    github_url          VARCHAR(500)     NULL,
    linkedin_url        VARCHAR(500)     NULL,
    portfolio_url       VARCHAR(500)     NULL,
    trimester_id        INT UNSIGNED     NULL      COMMENT '[v3.0] FK → trimesters (was VARCHAR)',
    availability_status ENUM('LOOKING','IN_TEAM','NOT_AVAILABLE')
                                         NOT NULL  DEFAULT 'LOOKING',
    profile_strength    TINYINT UNSIGNED NOT NULL  DEFAULT 0
                                         COMMENT '0-100 completeness score',
    created_at          DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                                   ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (profile_id),
    UNIQUE KEY uq_pfp_user_id (user_id),
    CONSTRAINT chk_pfp_cgpa CHECK (cgpa IS NULL OR cgpa BETWEEN 0.00 AND 4.00),
    CONSTRAINT fk_pfp_user
        FOREIGN KEY (user_id)      REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfp_trimester
        FOREIGN KEY (trimester_id) REFERENCES trimesters(trimester_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Pre-FYDP profile — trimester FK + CGPA CHECK(0-4)';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_student_skills
-- [v2.0] Replaces JSON skills array in pre_fydp_profiles (1NF fix).
-- BCNF: (user_id, skill_id) is the only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_student_skills (
    user_id             INT UNSIGNED    NOT NULL,
    skill_id            INT UNSIGNED    NOT NULL,
    proficiency_level   ENUM('BEGINNER','INTERMEDIATE','ADVANCED','EXPERT')
                                        NOT NULL  DEFAULT 'BEGINNER',
    created_at          DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, skill_id),
    CONSTRAINT fk_pfss_user
        FOREIGN KEY (user_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfss_skill
        FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Pre-FYDP student ↔ skill (1NF fix — was JSON)';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_student_domain_interests
-- [v2.0] Replaces JSON domain_interests in pre_fydp_profiles (1NF fix).
-- BCNF: (user_id, domain_id) is the only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_student_domain_interests (
    user_id         INT UNSIGNED    NOT NULL,
    domain_id       INT UNSIGNED    NOT NULL,
    interest_level  ENUM('LOW','MEDIUM','HIGH')  NOT NULL  DEFAULT 'MEDIUM',
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, domain_id),
    CONSTRAINT fk_pfsdi_user
        FOREIGN KEY (user_id)   REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfsdi_domain
        FOREIGN KEY (domain_id) REFERENCES project_domains(domain_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Pre-FYDP student ↔ domain interest (1NF fix — was JSON)';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_groups
-- [v2.0] required_skills JSON removed, domain VARCHAR → FK.
-- 3NF: group_id → all attributes. No multi-valued attributes remain.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_groups (
    group_id        INT UNSIGNED     NOT NULL  AUTO_INCREMENT,
    group_name      VARCHAR(200)     NOT NULL,
    domain_id       INT UNSIGNED     NOT NULL  COMMENT 'FK → project_domains',
    description     TEXT             NULL,
    max_members     TINYINT UNSIGNED NOT NULL  DEFAULT 5,
    github_url      VARCHAR(500)     NULL,
    created_by      INT UNSIGNED     NOT NULL,
    group_status    ENUM('OPEN','FULL','CLOSED')  NOT NULL  DEFAULT 'OPEN',
    created_at      DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME         NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                               ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    CONSTRAINT fk_pfg_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_pfg_domain
        FOREIGN KEY (domain_id)  REFERENCES project_domains(domain_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Pre-FYDP team listings — domain FK, no JSON columns';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_group_required_skills
-- [v2.0] Replaces JSON required_skills in pre_fydp_groups (1NF fix).
-- BCNF: (group_id, skill_id) is the only candidate key.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_group_required_skills (
    group_id    INT UNSIGNED    NOT NULL,
    skill_id    INT UNSIGNED    NOT NULL,
    created_at  DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id, skill_id),
    CONSTRAINT fk_pfgrs_group
        FOREIGN KEY (group_id)  REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfgrs_skill
        FOREIGN KEY (skill_id)  REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Pre-FYDP group ↔ required skill (1NF fix — was JSON)';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_group_members
-- [v3.0] member_role VARCHAR → ENUM (consistency with group_members table)
-- UNIQUE KEY prevents duplicate membership.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_group_members (
    member_id       INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    group_id        INT UNSIGNED    NOT NULL,
    user_id         INT UNSIGNED    NOT NULL,
    member_role     ENUM('Lead','Frontend','Backend','ML Engineer',
                         'DevOps','Security','Tester','Data Engineer','Other')
                                    NULL      COMMENT '[v3.0] ENUM — was unsafe VARCHAR',
    joined_at       DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),
    UNIQUE KEY uq_pfgm (group_id, user_id),
    CONSTRAINT fk_pfgm_group
        FOREIGN KEY (group_id) REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfgm_user
        FOREIGN KEY (user_id)  REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.0] Bridge: Pre-FYDP group ↔ student — member_role is now type-safe ENUM';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_join_requests
-- UNIQUE KEY scoped to PENDING status — CANCELLED requests don't block reapply.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_join_requests (
    request_id      INT UNSIGNED    NOT NULL  AUTO_INCREMENT,
    group_id        INT UNSIGNED    NOT NULL,
    sender_id       INT UNSIGNED    NOT NULL  COMMENT 'Student requesting to join',
    request_type    ENUM('JOIN_REQUEST','INVITATION')  NOT NULL  DEFAULT 'JOIN_REQUEST',
    message         TEXT            NULL,
    request_status  ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED')
                                    NOT NULL  DEFAULT 'PENDING',
    responded_at    DATETIME        NULL,
    created_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL  DEFAULT CURRENT_TIMESTAMP
                                             ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (request_id),
    CONSTRAINT fk_pfjr_group
        FOREIGN KEY (group_id)  REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pfjr_sender
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Join requests and invitations for Pre-FYDP team building';

-- ══════════════════════════════════════════════════════════════════════════════
-- MODULE 6: MESSAGING & COMMUNICATION                           [NEW v3.1]
--
-- NORMALIZATION PROOF
-- ══════════════════════════════════════════════════════════════════════════════
--
--  group_chat_messages — 3NF / BCNF
--  ─────────────────────────────────────────────────────────────────────────
--  Candidate key : {message_id}   (single-column surrogate — BCNF trivially)
--
--  Functional dependencies:
--    message_id → group_id, sender_id, message_text,
--                 attachment_path, attachment_name, chat_type, created_at
--
--  1NF: All attributes are atomic. No arrays, no JSON, no repeating groups.
--       attachment_path and attachment_name are separate atomic columns.
--  2NF: Single-column PK → partial dependency impossible by definition.
--  3NF: No non-key attribute determines another non-key attribute:
--       • group_id does NOT determine sender_id (same group, many senders).
--       • chat_type does NOT determine group_id (many groups per type).
--       • created_at is a timestamp — no derived column depends on it.
--  BCNF: The only determinant is {message_id}, which is the candidate key. ✓
--
--  design note — why chat_type is IN this table, not a separate table:
--    chat_type is an immutable property of the message at write time
--    (STUDENT_ONLY / WITH_SUPERVISOR / WITH_TEACHER). It is NOT a lookup
--    value that changes, so a separate FK table would add joins with zero
--    normalization benefit. ENUM is the correct choice per 1NF.
--
--  design note — attachments (path + name) as separate VARCHAR columns:
--    Extracting to an attachment table would be correct if a single message
--    could have MULTIPLE attachments (1NF violation otherwise). Current
--    business rule = one optional attachment per message → two atomic
--    scalar columns is fully 1NF compliant. If multi-attachment is needed
--    later, create a group_chat_message_attachments bridge table.
--
-- ─────────────────────────────────────────────────────────────────────────────
--
--  direct_messages — 3NF / BCNF
--  ─────────────────────────────────────────────────────────────────────────
--  Candidate key : {message_id}
--
--  Functional dependencies:
--    message_id → sender_id, receiver_id, message_text,
--                 attachment_path, attachment_name, is_read, created_at
--
--  1NF: All attributes atomic. No multi-valued or composite columns.
--  2NF: Single-column PK → partial dependency impossible.
--  3NF: No transitive dependency:
--       • sender_id does NOT determine receiver_id (same sender, many DMs).
--       • is_read does NOT derive from any other non-key attribute.
--       • created_at is a write-once timestamp, not derived.
--  BCNF: Only determinant is {message_id}. ✓
--
--  design note — no conversation / thread table:
--    A conversation_id could be added as a FK to group (sender,receiver)
--    pairs into a conversations table. That is denormalised here because
--    conversation membership is fully derivable from (sender_id, receiver_id)
--    without data loss. Adding a conversations table would be for performance
--    (pagination) not normalisation. Can be added as a future optimisation.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- ----------------------------------------------------------------------------
-- TABLE: group_tasks
-- Purpose : Supervisor-assigned tasks for a project group, per week.
--           Supports optional PDF/DOC file attachment and a due date.
-- 3NF/BCNF : task_id is the sole determinant of all non-key attributes.
-- ----------------------------------------------------------------------------
CREATE TABLE group_tasks (
    task_id         INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    group_id        INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → project_groups',
    supervisor_id   INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users — task author',
    week_no         TINYINT UNSIGNED    NOT NULL
                                        COMMENT 'Target week (1–52)',
    title           VARCHAR(255)        NOT NULL
                                        COMMENT 'Short task title',
    description     TEXT                NULL
                                        COMMENT 'Full task details',
    file_path       VARCHAR(500)        NULL
                                        COMMENT 'Relative server path e.g. /uploads/tasks/file.pdf',
    file_name       VARCHAR(255)        NULL
                                        COMMENT 'Original filename shown in UI',
    due_date        DATE                NULL
                                        COMMENT 'Optional deadline',
    created_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_id),
    CONSTRAINT fk_gtask_group
        FOREIGN KEY (group_id)      REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gtask_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    INDEX idx_gtask_group (group_id),
    INDEX idx_gtask_week  (group_id, week_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Supervisor-assigned tasks per group per week, with optional attachment';

-- ----------------------------------------------------------------------------
-- TABLE: group_chat_messages                                    [NEW v3.1]

CREATE TABLE group_chat_messages (
    message_id      INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    group_id        INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → project_groups — which FYDP group this message belongs to',
    sender_id       INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users — the author of the message',
    message_text    TEXT                NULL
                                        COMMENT 'Body of the chat message (NULL allowed when attachment present)',
    attachment_path VARCHAR(500)        NULL
                                        COMMENT 'Relative server path to file e.g. /uploads/chat/grp3_week2_slide.pdf',
    attachment_name VARCHAR(255)        NULL
                                        COMMENT 'Original filename shown in UI e.g. week2_slide.pdf',
    chat_type       ENUM('STUDENT_ONLY',
                         'WITH_SUPERVISOR',
                         'WITH_TEACHER')
                                        NOT NULL  DEFAULT 'STUDENT_ONLY'
                                        COMMENT 'Controls message visibility scope within the group',
    created_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id),
    CONSTRAINT fk_gcm_group
        FOREIGN KEY (group_id)  REFERENCES project_groups(group_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_gcm_sender
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.1] Group chat messages — 3NF/BCNF, three visibility channels, optional attachment';

-- ----------------------------------------------------------------------------
-- TABLE: direct_messages                                        [NEW v3.1]
-- Purpose : 1-to-1 private messaging between any two active users
--           (student↔student, student↔supervisor, student↔teacher, etc.)
-- 3NF/BCNF : message_id is the sole determinant (proved above).
-- ----------------------------------------------------------------------------
CREATE TABLE direct_messages (
    message_id      INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    sender_id       INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users — message author',
    receiver_id     INT UNSIGNED        NOT NULL
                                        COMMENT 'FK → users — message recipient',
    message_text    TEXT                NULL
                                        COMMENT 'Message body (NULL allowed when attachment present)',
    attachment_path VARCHAR(500)        NULL
                                        COMMENT 'Relative server path e.g. /uploads/dm/file.pdf',
    attachment_name VARCHAR(255)        NULL
                                        COMMENT 'Original filename shown in UI',
    is_read         TINYINT(1)          NOT NULL  DEFAULT 0
                                        COMMENT '0 = unread, 1 = read by receiver',
    created_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id),
    CONSTRAINT fk_dm_sender
        FOREIGN KEY (sender_id)   REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_dm_receiver
        FOREIGN KEY (receiver_id) REFERENCES users(user_id)
        ON DELETE CASCADE  ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='[v3.1] 1-to-1 direct messages — 3NF/BCNF, any two users, optional attachment';

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — HIGH-PERFORMANCE INDEXING STRATEGY
-- ─────────────────────────────────────────────────────────────────────────────

-- departments
CREATE INDEX idx_dept_active            ON departments(is_active);

-- sections
CREATE INDEX idx_sec_dept               ON sections(department_id);
CREATE INDEX idx_sec_active             ON sections(is_active);

-- trimesters
CREATE INDEX idx_trim_active            ON trimesters(is_active);

-- users
CREATE INDEX idx_users_role             ON users(role);
CREATE INDEX idx_users_dept             ON users(department_id);
-- idx_users_email omitted: uq_users_email UNIQUE KEY already provides an index on email
CREATE INDEX idx_users_acct_status      ON users(account_status);
CREATE INDEX idx_users_is_active        ON users(is_active);

-- user_status_log
CREATE INDEX idx_usl_user               ON user_status_log(user_id);
CREATE INDEX idx_usl_changed_at         ON user_status_log(changed_at);

-- student_profiles
CREATE INDEX idx_sp_availability        ON student_profiles(availability_status);
CREATE INDEX idx_sp_trimester           ON student_profiles(trimester_id);

-- student_skills
CREATE INDEX idx_ss_skill_id            ON student_skills(skill_id);

-- student_domain_interests
CREATE INDEX idx_sdi_domain_id          ON student_domain_interests(domain_id);

-- matchmaking_team_invitations
CREATE INDEX idx_inv_receiver           ON matchmaking_team_invitations(receiver_student_id);
CREATE INDEX idx_inv_sender             ON matchmaking_team_invitations(sender_student_id);
CREATE INDEX idx_inv_status             ON matchmaking_team_invitations(invitation_status);

-- notifications
CREATE INDEX idx_notif_user_unread      ON notifications(user_id, is_read);
CREATE INDEX idx_notif_type             ON notifications(notification_type);

-- project_groups
CREATE INDEX idx_pg_supervisor          ON project_groups(supervisor_id);
CREATE INDEX idx_pg_stage               ON project_groups(current_stage_id);
CREATE INDEX idx_pg_section             ON project_groups(section_id);
CREATE INDEX idx_pg_domain              ON project_groups(project_domain_id);
CREATE INDEX idx_pg_status              ON project_groups(project_status);

-- [v3.0] FULLTEXT — enables fast keyword search on project titles
CREATE FULLTEXT INDEX ft_project_title  ON project_groups(project_title);

-- group_members
CREATE INDEX idx_gm_student             ON group_members(student_id);

-- course_teacher_sections
CREATE INDEX idx_cts_stage              ON course_teacher_sections(assigned_stage_id);
CREATE INDEX idx_cts_section            ON course_teacher_sections(section_id);

-- weekly_progress_reports
CREATE INDEX idx_wpr_supervisor_status  ON weekly_progress_reports(supervisor_status);
CREATE INDEX idx_wpr_week_no            ON weekly_progress_reports(week_no);
CREATE INDEX idx_wpr_group              ON weekly_progress_reports(group_id);
CREATE INDEX idx_wpr_student            ON weekly_progress_reports(student_id);
CREATE INDEX idx_wpr_escalation         ON weekly_progress_reports(group_id, week_no, supervisor_status);

-- course_teacher_inbox
CREATE INDEX idx_inbox_status           ON course_teacher_inbox(escalation_status);
CREATE INDEX idx_inbox_group            ON course_teacher_inbox(group_id);

-- topic_change_history
CREATE INDEX idx_tch_group              ON topic_change_history(group_id);
CREATE INDEX idx_tch_changed_at         ON topic_change_history(changed_at);

-- audit_log
CREATE INDEX idx_audit_table            ON audit_log(table_name, operation);
CREATE INDEX idx_audit_user             ON audit_log(changed_by);

-- pre_fydp_student_skills / domain_interests
CREATE INDEX idx_pfss_skill_id          ON pre_fydp_student_skills(skill_id);
CREATE INDEX idx_pfsdi_domain_id        ON pre_fydp_student_domain_interests(domain_id);

-- pre_fydp_groups
CREATE INDEX idx_pfg_domain             ON pre_fydp_groups(domain_id);
CREATE INDEX idx_pfg_creator            ON pre_fydp_groups(created_by);
CREATE INDEX idx_pfg_status             ON pre_fydp_groups(group_status);

-- [v3.0] FULLTEXT — enables fast search on Pre-FYDP group names and descriptions
CREATE FULLTEXT INDEX ft_pfg_name_desc  ON pre_fydp_groups(group_name, description);

-- pre_fydp_group_required_skills
CREATE INDEX idx_pfgrs_skill            ON pre_fydp_group_required_skills(skill_id);

-- pre_fydp_join_requests
CREATE INDEX idx_pfjr_sender            ON pre_fydp_join_requests(sender_id);
CREATE INDEX idx_pfjr_status            ON pre_fydp_join_requests(request_status);

-- ── [NEW v3.1] group_chat_messages indexes ───────────────────────────────────
-- Composite (group_id, chat_type): loads the chat feed for a group+channel
--   in one range scan — most frequent query pattern.
CREATE INDEX idx_gcm_group_type         ON group_chat_messages(group_id, chat_type);

-- (group_id, created_at): timeline/pagination queries within a group.
CREATE INDEX idx_gcm_group_created      ON group_chat_messages(group_id, created_at);

-- sender_id: "all messages sent by this user" (admin / audit queries).
CREATE INDEX idx_gcm_sender             ON group_chat_messages(sender_id);

-- ── [NEW v3.1] direct_messages indexes ───────────────────────────────────────
-- (receiver_id, is_read): unread badge count — fired on every inbox load.
--   Covering index so the COUNT(*) WHERE is_read=0 never touches the row.
CREATE INDEX idx_dm_receiver_read       ON direct_messages(receiver_id, is_read);

-- sender_id: "all DMs sent by this user" — needed for conversation history.
CREATE INDEX idx_dm_sender              ON direct_messages(sender_id);

-- Composite conversation index: loads the thread between two specific users
--   efficiently without a full table scan.
--   Query pattern: WHERE (sender_id=A AND receiver_id=B)
--                     OR (sender_id=B AND receiver_id=A) ORDER BY created_at
CREATE INDEX idx_dm_conversation        ON direct_messages(sender_id, receiver_id, created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 — SAMPLE DATA
-- All cross-references use subqueries (no hardcoded IDs).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 4.1: DEPARTMENTS ──────────────────────────────────────────────────────
INSERT INTO departments (department_name, short_code, faculty) VALUES
  ('Administration',                        'ADMIN', 'Central Administration'),
  ('Computer Science and Engineering',      'CSE',   'Faculty of Science and Engineering'),
  ('Electrical and Electronic Engineering', 'EEE',   'Faculty of Science and Engineering'),
  ('Business Administration',               'BBA',   'Faculty of Business and Economics'),
  ('Civil Engineering',                     'CE',    'Faculty of Science and Engineering');

-- ── 4.2: SECTIONS ─────────────────────────────────────────────────────────
INSERT INTO sections (section_code, department_id) VALUES
  ('CSE-A', (SELECT department_id FROM departments WHERE short_code = 'CSE')),
  ('CSE-B', (SELECT department_id FROM departments WHERE short_code = 'CSE')),
  ('CSE-C', (SELECT department_id FROM departments WHERE short_code = 'CSE')),
  ('CSE-D', (SELECT department_id FROM departments WHERE short_code = 'CSE')),
  ('EEE-A', (SELECT department_id FROM departments WHERE short_code = 'EEE'));

-- ── 4.3: TRIMESTERS ───────────────────────────────────────────────────────
INSERT INTO trimesters (trimester_name, start_date, end_date) VALUES
  ('Spring 2025', '2025-01-10', '2025-05-15'),
  ('Summer 2025', '2025-06-01', '2025-08-31'),
  ('Fall 2025',   '2025-09-10', '2025-12-31'),
  ('Spring 2026', '2026-01-10', '2026-05-15');

-- ── 4.4: SKILLS ───────────────────────────────────────────────────────────
INSERT INTO skills (skill_name, skill_category) VALUES
  ('Python',               'Programming'),
  ('Java',                 'Programming'),
  ('C++',                  'Programming'),
  ('JavaScript',           'Programming'),
  ('Spring Boot',          'Backend'),
  ('Node.js',              'Backend'),
  ('Backend Development',  'Backend'),
  ('React',                'Frontend'),
  ('Vue.js',               'Frontend'),
  ('CSS',                  'Frontend'),
  ('Frontend Development', 'Frontend'),
  ('Figma',                'Design'),
  ('UI/UX Design',         'Design'),
  ('MySQL',                'Database'),
  ('PostgreSQL',           'Database'),
  ('MongoDB',              'Database'),
  ('Machine Learning',     'AI/ML'),
  ('Deep Learning',        'AI/ML'),
  ('NLP',                  'AI/ML'),
  ('TensorFlow',           'AI/ML'),
  ('PyTorch',              'AI/ML'),
  ('OpenCV',               'AI/ML'),
  ('Data Science',         'Analytics'),
  ('D3.js',                'Analytics'),
  ('Cybersecurity',        'Security'),
  ('Kali Linux',           'Security'),
  ('Wireshark',            'Security'),
  ('Networking',           'Networking'),
  ('IoT',                  'Hardware'),
  ('Arduino',              'Hardware'),
  ('Raspberry Pi',         'Hardware'),
  ('MQTT',                 'Hardware'),
  ('Docker',               'DevOps'),
  ('AWS',                  'Cloud'),
  ('Flutter',              'Mobile'),
  ('React Native',         'Mobile'),
  ('Blockchain',           'Emerging Tech');

-- ── 4.5: PROJECT DOMAINS ──────────────────────────────────────────────────
INSERT INTO project_domains (domain_name, description) VALUES
  ('Artificial Intelligence',  'AI and intelligent systems'),
  ('NLP',                      'Natural Language Processing applications'),
  ('FinTech',                  'Financial technology and digital payments'),
  ('Health Informatics',       'Healthcare data management and analytics'),
  ('IoT',                      'Internet of Things and embedded systems'),
  ('Cybersecurity',            'Network and application security'),
  ('Data Analytics',           'Big data and business intelligence'),
  ('Mobile Application',       'Cross-platform mobile app development'),
  ('Machine Learning',         'ML model development and deployment'),
  ('Software Engineering',     'Large-scale software systems'),
  ('Cloud Computing',          'Cloud-native and containerized applications'),
  ('Embedded Systems',         'Low-level hardware and firmware development');

-- ── 4.6: FYDP STAGES ──────────────────────────────────────────────────────
INSERT INTO fydp_stages (stage_name, stage_order, description) VALUES
  ('FYDP-1', 1, 'Proposal, literature review, and initial planning'),
  ('FYDP-2', 2, 'Implementation, development, and testing'),
  ('FYDP-3', 3, 'Final presentation, thesis submission, and viva');

-- ── 4.7: USERS ────────────────────────────────────────────────────────────
SET @d_admin = (SELECT department_id FROM departments WHERE short_code = 'ADMIN');
SET @d_cse   = (SELECT department_id FROM departments WHERE short_code = 'CSE');
SET @d_eee   = (SELECT department_id FROM departments WHERE short_code = 'EEE');

INSERT INTO users
  (university_id, full_name, email, password_hash, role, department_id, batch, phone, account_status)
VALUES
  ('ADMIN001', 'Dr. Rafiqul Islam',   'admin@uiu.ac.bd',            SHA2('admin123',256), 'ADMIN',            @d_admin, NULL,      '01711000001', 'ACTIVE'),
  ('SUP001',   'Dr. Tanvir Ahmed',    'tanvir@uiu.ac.bd',           SHA2('sup123',256),   'SUPERVISOR',       @d_cse,   NULL,      '01711000002', 'ACTIVE'),
  ('SUP002',   'Dr. Nadia Rahman',    'nadia@uiu.ac.bd',            SHA2('sup123',256),   'SUPERVISOR',       @d_cse,   NULL,      '01711000003', 'ACTIVE'),
  ('SUP003',   'Dr. Karim Hossain',   'karim@uiu.ac.bd',            SHA2('sup123',256),   'SUPERVISOR',       @d_eee,   NULL,      '01711000004', 'ACTIVE'),
  ('CT001',    'Mr. Shafiq Alam',     'shafiq@uiu.ac.bd',           SHA2('ct123',256),    'COURSE_TEACHER',   @d_cse,   NULL,      '01711000005', 'ACTIVE'),
  ('CT002',    'Ms. Farhana Begum',   'farhana@uiu.ac.bd',          SHA2('ct123',256),    'COURSE_TEACHER',   @d_cse,   NULL,      '01711000006', 'ACTIVE'),
  ('STU001',   'Arif Hasan',          'arif@student.uiu.ac.bd',     SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000001', 'ACTIVE'),
  ('STU002',   'Bristy Akter',        'bristy@student.uiu.ac.bd',   SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000002', 'ACTIVE'),
  ('STU003',   'Cyrus Khan',          'cyrus@student.uiu.ac.bd',    SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000003', 'ACTIVE'),
  ('STU004',   'Dina Sultana',        'dina@student.uiu.ac.bd',     SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000004', 'ACTIVE'),
  ('STU005',   'Emon Chowdhury',      'emon@student.uiu.ac.bd',     SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000005', 'ACTIVE'),
  ('STU006',   'Farhan Islam',        'farhan@student.uiu.ac.bd',   SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000006', 'ACTIVE'),
  ('STU007',   'Gita Roy',            'gita@student.uiu.ac.bd',     SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000007', 'ACTIVE'),
  ('STU008',   'Hasan Ali',           'hasan@student.uiu.ac.bd',    SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000008', 'ACTIVE'),
  ('STU009',   'Israt Jahan',         'israt@student.uiu.ac.bd',    SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000009', 'ACTIVE'),
  ('STU010',   'Jahir Uddin',         'jahir@student.uiu.ac.bd',    SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000010', 'ACTIVE'),
  ('STU011',   'Kamrul Bashar',       'kamrul@student.uiu.ac.bd',   SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000011', 'ACTIVE'),
  ('STU012',   'Lima Khanam',         'lima@student.uiu.ac.bd',     SHA2('stu123',256),   'STUDENT',          @d_cse,   'B.Sc 57', '01811000012', 'ACTIVE'),
  ('PFYDP001', 'Suvrojit Bose',       'suvrojit@student.uiu.ac.bd', SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_cse,   'B.Sc 59', '01911000001', 'ACTIVE'),
  ('PFYDP002', 'Zainab Ali',          'zainab@student.uiu.ac.bd',   SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_cse,   'B.Sc 59', '01911000002', 'ACTIVE'),
  ('PFYDP003', 'Hamza Iqbal',         'hamza@student.uiu.ac.bd',    SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_cse,   'B.Sc 59', '01911000003', 'ACTIVE'),
  ('PFYDP004', 'Nusrat Jahan',        'nusrat@student.uiu.ac.bd',   SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_cse,   'B.Sc 59', '01911000004', 'ACTIVE'),
  ('PFYDP005', 'Rafiq Ahmed',         'rafiq@student.uiu.ac.bd',    SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_cse,   'B.Sc 59', '01911000005', 'ACTIVE'),
  ('PFYDP006', 'Samira Begum',        'samira@student.uiu.ac.bd',   SHA2('pre123',256),   'PRE_FYDP_STUDENT', @d_eee,   'B.Sc 58', '01911000006', 'ACTIVE');

-- ── 4.8: STUDENT PROFILES ─────────────────────────────────────────────────
SET @trim_sp25 = (SELECT trimester_id FROM trimesters WHERE trimester_name = 'Spring 2025');

INSERT INTO student_profiles
  (student_id, cgpa, bio, github_url, linkedin_url, preferred_team_role, trimester_id, availability_status)
SELECT
  u.user_id,
  ROUND(2.80 + (RAND() * 1.20), 2),
  'Passionate CSE student with interest in AI and software development.',
  CONCAT('https://github.com/', LOWER(REPLACE(u.full_name, ' ', '_'))),
  CONCAT('https://linkedin.com/in/', LOWER(REPLACE(u.full_name, ' ', '-'))),
  ELT(FLOOR(1 + RAND() * 6), 'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER'),
  @trim_sp25,
  'LOOKING'
FROM users u
WHERE u.role = 'STUDENT';

-- ── 4.9: STUDENT SKILLS ───────────────────────────────────────────────────
INSERT INTO student_skills (student_id, skill_id, proficiency_level, years_experience)
VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT skill_id FROM skills WHERE skill_name='Python'),           'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT skill_id FROM skills WHERE skill_name='Machine Learning'), 'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT skill_id FROM skills WHERE skill_name='React'),            'ADVANCED',     1.5),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT skill_id FROM skills WHERE skill_name='Node.js'),          'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT skill_id FROM skills WHERE skill_name='NLP'),              'EXPERT',       2.5),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT skill_id FROM skills WHERE skill_name='Deep Learning'),    'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT skill_id FROM skills WHERE skill_name='MySQL'),            'ADVANCED',     2.0),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT skill_id FROM skills WHERE skill_name='Data Science'),     'INTERMEDIATE', 1.0),
  ((SELECT user_id FROM users WHERE university_id='STU005'),(SELECT skill_id FROM skills WHERE skill_name='Cybersecurity'),    'ADVANCED',     1.5),
  ((SELECT user_id FROM users WHERE university_id='STU006'),(SELECT skill_id FROM skills WHERE skill_name='IoT'),              'INTERMEDIATE', 1.0);

-- ── 4.10: STUDENT DOMAIN INTERESTS ────────────────────────────────────────
INSERT INTO student_domain_interests (student_id, domain_id, interest_level)
VALUES
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU001'),(SELECT domain_id FROM project_domains WHERE domain_name='NLP'),                    'MEDIUM'),
  ((SELECT user_id FROM users WHERE university_id='STU002'),(SELECT domain_id FROM project_domains WHERE domain_name='Mobile Application'),     'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT domain_id FROM project_domains WHERE domain_name='NLP'),                    'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU003'),(SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU004'),(SELECT domain_id FROM project_domains WHERE domain_name='Data Analytics'),         'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU005'),(SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),          'HIGH'),
  ((SELECT user_id FROM users WHERE university_id='STU006'),(SELECT domain_id FROM project_domains WHERE domain_name='IoT'),                    'HIGH');

-- ── 4.11: COURSE TEACHER SECTIONS ─────────────────────────────────────────
INSERT INTO course_teacher_sections (course_teacher_id, section_id, assigned_stage_id)
VALUES
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

-- ── 4.12: PROJECT GROUPS ──────────────────────────────────────────────────
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
VALUES
  ('UIU-G001',
   'BanglaBot: Conversational AI for Bangla Language',
   (SELECT domain_id  FROM project_domains WHERE domain_name='NLP'),
   (SELECT user_id    FROM users           WHERE university_id='SUP001'),
   (SELECT stage_id   FROM fydp_stages     WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections        WHERE section_code='CSE-A')),
  ('UIU-G002',
   'SecureNet: AI-Powered Intrusion Detection System',
   (SELECT domain_id  FROM project_domains WHERE domain_name='Cybersecurity'),
   (SELECT user_id    FROM users           WHERE university_id='SUP001'),
   (SELECT stage_id   FROM fydp_stages     WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections        WHERE section_code='CSE-B')),
  ('UIU-G003',
   'HealthSync: Smart Patient Monitoring via IoT',
   (SELECT domain_id  FROM project_domains WHERE domain_name='Health Informatics'),
   (SELECT user_id    FROM users           WHERE university_id='SUP003'),
   (SELECT stage_id   FROM fydp_stages     WHERE stage_name='FYDP-1'),
   (SELECT section_id FROM sections        WHERE section_code='CSE-A'));

-- ── 4.13: GROUP MEMBERS ───────────────────────────────────────────────────
INSERT INTO group_members (group_id, student_id, member_role)
VALUES
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

-- ── 4.14: MATCHMAKING INVITATIONS ────────────────────────────────────────
INSERT INTO matchmaking_team_invitations
  (sender_student_id, receiver_student_id, invitation_message)
VALUES
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
   SET invitation_status = 'ACCEPTED', responded_at = NOW()
 WHERE sender_student_id   = (SELECT user_id FROM users WHERE university_id='STU001')
   AND receiver_student_id = (SELECT user_id FROM users WHERE university_id='STU002');

UPDATE matchmaking_team_invitations
   SET invitation_status = 'ACCEPTED', responded_at = NOW()
 WHERE sender_student_id   = (SELECT user_id FROM users WHERE university_id='STU003')
   AND receiver_student_id = (SELECT user_id FROM users WHERE university_id='STU004');

-- ── 4.15: NOTIFICATIONS ───────────────────────────────────────────────────
INSERT INTO notifications
  (user_id, notification_type, message, reference_entity_id, reference_entity_type, is_read)
VALUES
  ((SELECT user_id FROM users WHERE university_id='STU005'),
   'INVITATION_RECEIVED',
   'Emon Chowdhury has invited you to join a security FYDP project.',
   3, 'matchmaking_team_invitations', 0),
  ((SELECT user_id FROM users WHERE university_id='STU007'),
   'INVITATION_RECEIVED',
   'Gita Roy has invited you to join an AI FYDP project.',
   4, 'matchmaking_team_invitations', 0);

-- ── 4.16: WEEKLY PROGRESS REPORTS ────────────────────────────────────────
INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content, submitted_at, supervisor_status)
VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU001'),
   1, 'Week 1 - Literature Survey',
   'Completed initial literature review on Bangla NLP transformer models.', NOW(), 'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU002'),
   1, 'Week 1 - Frontend Planning',
   'Designed UI wireframes and component hierarchy for the chatbot interface.', NOW(), 'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU003'),
   1, 'Week 1 - Dataset Collection',
   'Identified 3 publicly available Bangla text datasets for model training.', NOW(), 'APPROVED'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU004'),
   1, 'Week 1 - DB Schema Draft',
   'Drafted initial normalized database schema for conversation storage.', NOW(), 'PENDING');

-- ── 4.17: PRE-FYDP PROFILES ──────────────────────────────────────────────
SET @trim_sp26 = (SELECT trimester_id FROM trimesters WHERE trimester_name = 'Spring 2026');

INSERT INTO pre_fydp_profiles
  (user_id, bio, cgpa, preferred_role, github_url, linkedin_url, trimester_id, availability_status, profile_strength)
VALUES
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),
   'Full-stack developer passionate about AI and ML.', 3.65,
   'FULL_STACK_DEVELOPER', 'https://github.com/suvrojit', 'https://linkedin.com/in/suvrojit-bose',
   @trim_sp26, 'LOOKING', 71),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),
   'Frontend specialist with strong design skills.', 3.52,
   'FRONTEND_DEVELOPER', 'https://github.com/zainabali', 'https://linkedin.com/in/zainab-ali',
   @trim_sp26, 'IN_TEAM', 85),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),
   'Backend developer with cloud and DevOps experience.', 3.78,
   'BACKEND_DEVELOPER', 'https://github.com/hamzaiqbal', 'https://linkedin.com/in/hamza-iqbal',
   @trim_sp26, 'IN_TEAM', 90),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),
   'ML researcher interested in NLP and computer vision.', 3.88,
   'ML_ENGINEER', 'https://github.com/nusratjahan', NULL,
   @trim_sp26, 'LOOKING', 60),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),
   'Cybersecurity enthusiast with CTF competition experience.', 3.45,
   'SECURITY_ANALYST', NULL, NULL,
   @trim_sp26, 'LOOKING', 40),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),
   'IoT and embedded systems developer with hardware experience.', 3.30,
   'EMBEDDED_DEVELOPER', NULL, NULL,
   @trim_sp26, 'LOOKING', 35);

-- ── 4.18: PRE-FYDP STUDENT SKILLS ────────────────────────────────────────
INSERT INTO pre_fydp_student_skills (user_id, skill_id, proficiency_level)
VALUES
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='Python'),          'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='React'),           'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='Node.js'),         'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='MySQL'),           'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow'),      'BEGINNER'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='React'),           'EXPERT'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='Vue.js'),          'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='Figma'),           'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='UI/UX Design'),    'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'),(SELECT skill_id FROM skills WHERE skill_name='CSS'),             'EXPERT'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Java'),            'EXPERT'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Spring Boot'),     'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='Docker'),          'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='AWS'),             'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'),(SELECT skill_id FROM skills WHERE skill_name='PostgreSQL'),      'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='Python'),          'EXPERT'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='TensorFlow'),      'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='PyTorch'),         'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='NLP'),             'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'),(SELECT skill_id FROM skills WHERE skill_name='OpenCV'),          'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Python'),          'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Kali Linux'),      'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Wireshark'),       'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'),(SELECT skill_id FROM skills WHERE skill_name='Networking'),      'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='C++'),             'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Arduino'),         'EXPERT'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Raspberry Pi'),    'ADVANCED'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='MQTT'),            'INTERMEDIATE'),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'),(SELECT skill_id FROM skills WHERE skill_name='Python'),          'INTERMEDIATE');

-- ── 4.19: PRE-FYDP STUDENT DOMAIN INTERESTS ──────────────────────────────
INSERT INTO pre_fydp_student_domain_interests (user_id, domain_id, interest_level)
VALUES
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

-- ── 4.20: PRE-FYDP GROUPS ────────────────────────────────────────────────
INSERT INTO pre_fydp_groups
  (group_name, domain_id, description, max_members, github_url, created_by, group_status)
VALUES
  ('NeuralVerse',
   (SELECT domain_id FROM project_domains WHERE domain_name='Artificial Intelligence'),
   'AI-powered virtual study assistant using GPT models and RAG pipeline.', 5,
   'https://github.com/neuralverse',
   (SELECT user_id FROM users WHERE university_id='PFYDP002'), 'OPEN'),
  ('CyberShield',
   (SELECT domain_id FROM project_domains WHERE domain_name='Cybersecurity'),
   'AI-driven intrusion detection system for university networks.', 5, NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP005'), 'OPEN'),
  ('MediCare AI',
   (SELECT domain_id FROM project_domains WHERE domain_name='Machine Learning'),
   'Predictive diagnostics using federated learning for health data privacy.', 4, NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP004'), 'OPEN'),
  ('CloudForge',
   (SELECT domain_id FROM project_domains WHERE domain_name='Cloud Computing'),
   'Containerized micro-services platform for student startups.', 5,
   'https://github.com/cloudforge',
   (SELECT user_id FROM users WHERE university_id='PFYDP003'), 'OPEN'),
  ('DataPulse',
   (SELECT domain_id FROM project_domains WHERE domain_name='Data Analytics'),
   'Real-time analytics dashboard for e-commerce platforms.', 4, NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'OPEN'),
  ('SmartCampus',
   (SELECT domain_id FROM project_domains WHERE domain_name='IoT'),
   'IoT-based smart campus management system with environmental sensors.', 5, NULL,
   (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'FULL');

-- ── 4.21: PRE-FYDP GROUP REQUIRED SKILLS ─────────────────────────────────
INSERT INTO pre_fydp_group_required_skills (group_id, skill_id)
VALUES
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
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT skill_id FROM skills WHERE skill_name='Backend Development')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT skill_id FROM skills WHERE skill_name='Node.js')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT skill_id FROM skills WHERE skill_name='MySQL')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT skill_id FROM skills WHERE skill_name='Docker')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),(SELECT skill_id FROM skills WHERE skill_name='Python')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),(SELECT skill_id FROM skills WHERE skill_name='React')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),(SELECT skill_id FROM skills WHERE skill_name='MongoDB')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),(SELECT skill_id FROM skills WHERE skill_name='D3.js')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='C++')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='Arduino')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='React')),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT skill_id FROM skills WHERE skill_name='MQTT'));

-- ── 4.22: PRE-FYDP GROUP MEMBERS ─────────────────────────────────────────
INSERT INTO pre_fydp_group_members (group_id, user_id, member_role)
VALUES
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP002'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Backend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'ML Engineer'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT user_id FROM users WHERE university_id='PFYDP003'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT user_id FROM users WHERE university_id='PFYDP002'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),(SELECT user_id FROM users WHERE university_id='PFYDP005'),'Security'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP006'),'Lead'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP001'),'Backend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP002'),'Frontend'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP003'),'DevOps'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='SmartCampus'),(SELECT user_id FROM users WHERE university_id='PFYDP004'),'Tester');

-- ── 4.23: PRE-FYDP JOIN REQUESTS ─────────────────────────────────────────
INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message, request_status)
VALUES
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CyberShield'),
   (SELECT user_id  FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST', 'I have experience with Python and networking. Would love to join!', 'PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='DataPulse'),
   (SELECT user_id  FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST', 'Interested in data analytics dashboards!', 'PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='NeuralVerse'),
   (SELECT user_id  FROM users WHERE university_id='PFYDP005'),
   'JOIN_REQUEST', 'Can I contribute my security expertise to your AI project?', 'PENDING'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='CloudForge'),
   (SELECT user_id  FROM users WHERE university_id='PFYDP001'),
   'JOIN_REQUEST', 'Full-stack developer here, excited about micro-services!', 'ACCEPTED'),
  ((SELECT group_id FROM pre_fydp_groups WHERE group_name='MediCare AI'),
   (SELECT user_id  FROM users WHERE university_id='PFYDP006'),
   'JOIN_REQUEST', 'IoT background — interested in health monitoring hardware.', 'REJECTED');

-- ── 4.24: GROUP CHAT MESSAGES (sample)           [NEW v3.1] ──────────────
INSERT INTO group_chat_messages (group_id, sender_id, message_text, chat_type)
VALUES
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU001'),
   'Team, let us sync on the literature review today at 3 PM.', 'STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU002'),
   'Sounds good! I will prepare the UI wireframe slides.', 'STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='STU001'),
   'Dr. Tanvir, we have completed the initial dataset survey. Awaiting your feedback.', 'WITH_SUPERVISOR'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id='SUP001'),
   'Great progress! Please make sure the citation format follows IEEE.', 'WITH_SUPERVISOR'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
   (SELECT user_id  FROM users WHERE university_id='STU005'),
   'Team, our Week 1 reports are ready. Please submit before Friday.', 'STUDENT_ONLY'),
  ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
   (SELECT user_id  FROM users WHERE university_id='STU006'),
   'Done! I have also uploaded the network topology diagram.', 'STUDENT_ONLY');

-- ── 4.25: DIRECT MESSAGES (sample)               [NEW v3.1] ──────────────
INSERT INTO direct_messages (sender_id, receiver_id, message_text)
VALUES
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

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 — TRIGGERS
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER $$

-- ============================================================================
-- TRIGGER 1: ESCALATION ENGINE — INDIVIDUAL APPROVAL (v3.0 BUG FIXED)
-- Table  : weekly_progress_reports (AFTER UPDATE)
-- Change : First approval → creates inbox record with IN_PROGRESS status.
--          Each next approval → updates approved_count.
--          All approved → sets is_fully_approved = 1, status → PENDING_REVIEW.
-- ============================================================================
CREATE TRIGGER trg_after_wpr_approve_escalate
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    DECLARE v_total_members   INT DEFAULT 0;
    DECLARE v_approved_count  INT DEFAULT 0;
    DECLARE v_is_fully        TINYINT(1) DEFAULT 0;

    IF NEW.supervisor_status = 'APPROVED' AND OLD.supervisor_status != 'APPROVED' THEN

        SELECT COUNT(*) INTO v_total_members
          FROM group_members
         WHERE group_id = NEW.group_id;

        SELECT COUNT(*) INTO v_approved_count
          FROM weekly_progress_reports
         WHERE group_id          = NEW.group_id
           AND week_no           = NEW.week_no
           AND supervisor_status = 'APPROVED'
           AND is_active         = 1;

        SET v_is_fully = IF(v_approved_count = v_total_members AND v_total_members > 0, 1, 0);

        INSERT INTO course_teacher_inbox
            (group_id, week_no, escalated_at, escalation_status,
             total_members, approved_count, is_fully_approved)
        VALUES
            (NEW.group_id, NEW.week_no, NOW(),
             IF(v_is_fully = 1, 'PENDING_REVIEW', 'IN_PROGRESS'),
             v_total_members, v_approved_count, v_is_fully)
        ON DUPLICATE KEY UPDATE
            approved_count    = v_approved_count,
            is_fully_approved = v_is_fully,
            escalation_status = IF(v_is_fully = 1, 'PENDING_REVIEW', 'IN_PROGRESS');

        IF v_is_fully = 1 THEN
            INSERT INTO notifications
                (user_id, notification_type, message,
                 reference_entity_id, reference_entity_type)
            SELECT
                gm.student_id,
                'ESCALATION_COMPLETE',
                CONCAT('All Week ', NEW.week_no,
                       ' reports approved! Escalated to Course Teacher.'),
                NEW.group_id,
                'course_teacher_inbox'
            FROM group_members gm
            WHERE gm.group_id = NEW.group_id;
        END IF;

    END IF;
END$$

-- ============================================================================
-- TRIGGER 2: SUPERVISOR CAPACITY LIMIT — ON INSERT
-- Rule: Max 3 active groups per supervisor per stage.
-- ============================================================================
CREATE TRIGGER trg_before_group_insert_supervisor_limit
BEFORE INSERT ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_existing_count INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existing_count
      FROM project_groups
     WHERE supervisor_id    = NEW.supervisor_id
       AND current_stage_id = NEW.current_stage_id
       AND is_active        = 1
       AND project_status  != 'DROPPED';

    IF v_existing_count >= 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SUPERVISOR CAPACITY EXCEEDED: Max 3 active groups per stage.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 3: SUPERVISOR CAPACITY LIMIT — ON UPDATE
-- Same rule applied on supervisor/stage reassignment.
-- ============================================================================
CREATE TRIGGER trg_before_group_update_supervisor_limit
BEFORE UPDATE ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_existing_count INT DEFAULT 0;

    IF NEW.supervisor_id != OLD.supervisor_id OR NEW.current_stage_id != OLD.current_stage_id THEN

        SELECT COUNT(*) INTO v_existing_count
          FROM project_groups
         WHERE supervisor_id    = NEW.supervisor_id
           AND current_stage_id = NEW.current_stage_id
           AND is_active        = 1
           AND project_status  != 'DROPPED'
           AND group_id        != NEW.group_id;

        IF v_existing_count >= 3 THEN
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
    DECLARE v_pending_count INT DEFAULT 0;

    IF NEW.sender_student_id = NEW.receiver_student_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SELF INVITATION ERROR: A student cannot invite themselves.';
    END IF;

    SELECT COUNT(*) INTO v_pending_count
      FROM matchmaking_team_invitations
     WHERE invitation_status = 'PENDING'
       AND (
             (sender_student_id = NEW.sender_student_id   AND receiver_student_id = NEW.receiver_student_id)
          OR (sender_student_id = NEW.receiver_student_id AND receiver_student_id = NEW.sender_student_id)
           );

    IF v_pending_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'DUPLICATE INVITATION: A pending invitation already exists between these students.';
    END IF;
END$$

-- ============================================================================
-- TRIGGER 5: AUDIT LOG ON SUPERVISOR DECISION
-- ============================================================================
CREATE TRIGGER trg_after_wpr_audit_log
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    IF NEW.supervisor_status != OLD.supervisor_status THEN
        INSERT INTO audit_log
            (table_name, operation, record_id, old_data, new_data)
        VALUES (
            'weekly_progress_reports', 'UPDATE', NEW.report_id,
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
-- TRIGGER 6: AUTO-UPDATE AVAILABILITY ON INVITATION ACCEPT/REJECT
-- ============================================================================
CREATE TRIGGER trg_after_invitation_response
AFTER UPDATE ON matchmaking_team_invitations
FOR EACH ROW
BEGIN
    IF NEW.invitation_status = 'ACCEPTED' AND OLD.invitation_status = 'PENDING' THEN

        UPDATE student_profiles
           SET availability_status = 'IN_TEAM', updated_at = NOW()
         WHERE student_id = NEW.receiver_student_id;

        INSERT INTO notifications
            (user_id, notification_type, message, reference_entity_id, reference_entity_type)
        VALUES (
            NEW.sender_student_id, 'INVITATION_ACCEPTED',
            'Your team invitation has been accepted! You can now finalize your FYDP group.',
            NEW.invitation_id, 'matchmaking_team_invitations'
        );

    ELSEIF NEW.invitation_status = 'REJECTED' AND OLD.invitation_status = 'PENDING' THEN

        INSERT INTO notifications
            (user_id, notification_type, message, reference_entity_id, reference_entity_type)
        VALUES (
            NEW.sender_student_id, 'INVITATION_REJECTED',
            'Your team invitation was declined. Consider reaching out to other students.',
            NEW.invitation_id, 'matchmaking_team_invitations'
        );

    END IF;
END$$

-- ============================================================================
-- TRIGGER 7: USER STATUS AUDIT LOG
-- ============================================================================
CREATE TRIGGER trg_after_users_status_log
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    IF NEW.account_status != OLD.account_status THEN
        INSERT INTO user_status_log
            (user_id, old_status, new_status, changed_at)
        VALUES
            (NEW.user_id, OLD.account_status, NEW.account_status, NOW());
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
CREATE PROCEDURE sp_bulk_import_ucam_groups(
    IN p_import_batch_id VARCHAR(50)
)
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

    SELECT section_id INTO v_default_section_id FROM sections WHERE section_code = 'CSE-A' LIMIT 1;

    OPEN cur_staging;

    import_loop: LOOP
        FETCH cur_staging INTO
            v_staging_id, v_raw_student_uid, v_raw_group_code,
            v_raw_supervisor_uid, v_raw_stage_name,
            v_raw_project_title, v_raw_domain_name;

        IF v_done THEN LEAVE import_loop; END IF;

        SET v_row_count = v_row_count + 1;
        SET v_student_id = NULL; SET v_supervisor_id = NULL;
        SET v_stage_id = NULL; SET v_domain_id = NULL; SET v_group_id = NULL;

        START TRANSACTION;

        SELECT user_id INTO v_student_id FROM users
         WHERE university_id = v_raw_student_uid AND role = 'STUDENT' AND account_status = 'ACTIVE' LIMIT 1;
        SET v_done = 0;
        IF v_student_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Student not found/inactive: ', v_raw_student_uid), v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT user_id INTO v_supervisor_id FROM users
         WHERE university_id = v_raw_supervisor_uid AND role = 'SUPERVISOR' AND account_status = 'ACTIVE' LIMIT 1;
        SET v_done = 0;
        IF v_supervisor_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Supervisor not found/inactive: ', v_raw_supervisor_uid), v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT stage_id INTO v_stage_id FROM fydp_stages WHERE stage_name = v_raw_stage_name LIMIT 1;
        SET v_done = 0;
        IF v_stage_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Invalid FYDP stage: ', v_raw_stage_name), v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        SELECT domain_id INTO v_domain_id FROM project_domains WHERE domain_name = v_raw_domain_name LIMIT 1;
        SET v_done = 0;
        IF v_domain_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count, CONCAT('Domain not found: ', v_raw_domain_name), v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1; ROLLBACK; ITERATE import_loop;
        END IF;

        IF EXISTS (SELECT 1 FROM project_groups WHERE group_code = v_raw_group_code) THEN
            SELECT group_id INTO v_group_id FROM project_groups WHERE group_code = v_raw_group_code LIMIT 1;
            IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = v_group_id AND student_id = v_student_id) THEN
                INSERT INTO group_members (group_id, student_id, member_role) VALUES (v_group_id, v_student_id, 'DEVELOPER');
            END IF;
        ELSE
            INSERT INTO project_groups (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
            VALUES (v_raw_group_code, v_raw_project_title, v_domain_id, v_supervisor_id, v_stage_id, v_default_section_id);
            SET v_group_id = LAST_INSERT_ID();
            INSERT INTO group_members (group_id, student_id, member_role) VALUES (v_group_id, v_student_id, 'DEVELOPER');
        END IF;

        COMMIT;
        SET v_success_count = v_success_count + 1;

    END LOOP import_loop;

    CLOSE cur_staging;

    SELECT v_row_count AS total_rows_processed,
           v_success_count AS successful_imports,
           v_error_count   AS failed_imports,
           p_import_batch_id AS batch_id;
END$$

-- ============================================================================
-- PROCEDURE 2: FYDP STAGE PROMOTION ENGINE
-- ============================================================================
CREATE PROCEDURE sp_promote_fydp_stage(
    IN p_group_id           INT UNSIGNED,
    IN p_new_stage_id       INT UNSIGNED,
    IN p_new_domain_id      INT UNSIGNED,
    IN p_new_project_title  VARCHAR(300),
    IN p_admin_id           INT UNSIGNED,
    IN p_change_reason      TEXT
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
      FROM project_groups WHERE group_id = p_group_id AND is_active = 1 LIMIT 1;

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

    IF p_new_project_title IS NOT NULL AND p_new_project_title != v_current_title THEN
        SET v_title_changed = 1;
    END IF;
    IF p_new_domain_id IS NOT NULL AND p_new_domain_id != v_current_domain_id THEN
        SET v_domain_changed = 1;
    END IF;

    IF v_title_changed = 1 OR v_domain_changed = 1 THEN
        INSERT INTO topic_change_history
            (group_id, old_domain_id, new_domain_id, old_project_title,
             new_project_title, changed_by_admin, change_reason, changed_at)
        VALUES (
            p_group_id,
            v_current_domain_id,
            IF(v_domain_changed = 1, p_new_domain_id, v_current_domain_id),
            v_current_title,
            IF(v_title_changed  = 1, p_new_project_title, v_current_title),
            p_admin_id, p_change_reason, NOW()
        );
    END IF;

    UPDATE project_groups
       SET current_stage_id  = p_new_stage_id,
           project_domain_id = IF(p_new_domain_id IS NOT NULL, p_new_domain_id, project_domain_id),
           project_title     = IF(p_new_project_title IS NOT NULL AND p_new_project_title != '',
                                  p_new_project_title, project_title),
           updated_at        = NOW()
     WHERE group_id = p_group_id;

    INSERT INTO notifications
        (user_id, notification_type, message, reference_entity_id, reference_entity_type)
    SELECT
        gm.student_id, 'STAGE_PROMOTED',
        CONCAT('Your project group has been promoted to ',
               (SELECT stage_name FROM fydp_stages WHERE stage_id = p_new_stage_id), '!'),
        p_group_id, 'project_groups'
    FROM group_members gm WHERE gm.group_id = p_group_id;

    COMMIT;

    SELECT p_group_id AS group_id,
           (SELECT group_code  FROM project_groups WHERE group_id = p_group_id)       AS group_code,
           (SELECT stage_name  FROM fydp_stages WHERE stage_id = v_current_stage_id)  AS promoted_from,
           (SELECT stage_name  FROM fydp_stages WHERE stage_id = p_new_stage_id)      AS promoted_to,
           v_title_changed  AS title_changed,
           v_domain_changed AS domain_changed,
           NOW() AS promoted_at;
END$$

-- ============================================================================
-- PROCEDURE 3: SUPERVISOR WEEKLY REPORT APPROVAL
-- ============================================================================
CREATE PROCEDURE sp_approve_weekly_report(
    IN p_report_id      INT UNSIGNED,
    IN p_supervisor_id  INT UNSIGNED,
    IN p_new_status     ENUM('APPROVED','REJECTED'),
    IN p_feedback       TEXT
)
BEGIN
    DECLARE v_group_supervisor_id INT UNSIGNED;
    DECLARE v_report_group_id     INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT pg.supervisor_id, wpr.group_id
      INTO v_group_supervisor_id, v_report_group_id
      FROM weekly_progress_reports wpr
      JOIN project_groups pg ON pg.group_id = wpr.group_id
     WHERE wpr.report_id = p_report_id LIMIT 1;

    IF v_group_supervisor_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'APPROVAL ERROR: Report or group not found.';
    END IF;
    IF v_group_supervisor_id != p_supervisor_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AUTHORIZATION ERROR: You are not the assigned supervisor.';
    END IF;

    UPDATE weekly_progress_reports
       SET supervisor_status    = p_new_status,
           supervisor_feedback  = p_feedback,
           supervisor_signed_at = IF(p_new_status = 'APPROVED', NOW(), NULL),
           updated_at           = NOW()
     WHERE report_id = p_report_id;

    COMMIT;

    SELECT p_report_id AS report_id, p_new_status AS new_status, 'SUCCESS' AS result;
END$$

-- ============================================================================
-- FUNCTION 1: GROUP APPROVAL PERCENTAGE FOR A WEEK
-- ============================================================================
CREATE FUNCTION fn_get_group_approval_pct(
    p_group_id  INT UNSIGNED,
    p_week_no   TINYINT UNSIGNED
)
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_approved INT DEFAULT 0;

    SELECT COUNT(*) INTO v_total   FROM group_members WHERE group_id = p_group_id;
    SELECT COUNT(*) INTO v_approved FROM weekly_progress_reports
     WHERE group_id = p_group_id AND week_no = p_week_no AND supervisor_status = 'APPROVED';

    IF v_total = 0 THEN RETURN 0.00; END IF;
    RETURN ROUND((v_approved / v_total) * 100, 2);
END$$

-- ============================================================================
-- FUNCTION 2: CHECK IF STUDENT IS IN AN ACTIVE FYDP GROUP
-- ============================================================================
CREATE FUNCTION fn_is_student_in_active_group(
    p_student_id INT UNSIGNED
)
RETURNS TINYINT(1)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;

    SELECT COUNT(*) INTO v_count
      FROM group_members gm
      JOIN project_groups pg ON pg.group_id = gm.group_id
     WHERE gm.student_id    = p_student_id
       AND pg.is_active      = 1
       AND pg.project_status = 'ACTIVE';

    RETURN IF(v_count > 0, 1, 0);
END$$

-- ============================================================================
-- FUNCTION 3: SKILL MATCH SCORE — AI MATCHMAKING ENGINE
-- Returns 0–100: how many of a group's required skills a student has.
-- ============================================================================
CREATE FUNCTION fn_skill_match_score(
    p_student_id INT UNSIGNED,
    p_group_id   INT UNSIGNED
)
RETURNS TINYINT UNSIGNED
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_required_total INT DEFAULT 0;
    DECLARE v_matched_count  INT DEFAULT 0;

    SELECT COUNT(*) INTO v_required_total
      FROM pre_fydp_group_required_skills
     WHERE group_id = p_group_id;

    IF v_required_total = 0 THEN RETURN 0; END IF;

    SELECT COUNT(*) INTO v_matched_count
      FROM pre_fydp_group_required_skills  r
      JOIN pre_fydp_student_skills         s
        ON s.skill_id = r.skill_id
       AND s.user_id  = p_student_id
     WHERE r.group_id = p_group_id;

    RETURN ROUND((v_matched_count / v_required_total) * 100);
END$$

-- ============================================================================
-- FUNCTION 4: UNREAD DM COUNT FOR A USER               [NEW v3.1]
-- Returns the number of unread direct messages for a given receiver.
-- Used by the application badge counter on the inbox icon.
-- ============================================================================
CREATE FUNCTION fn_unread_dm_count(
    p_receiver_id INT UNSIGNED
)
RETURNS INT UNSIGNED
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT UNSIGNED DEFAULT 0;

    SELECT COUNT(*) INTO v_count
      FROM direct_messages
     WHERE receiver_id = p_receiver_id
       AND is_read     = 0;

    RETURN v_count;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 — VIEWS
-- ─────────────────────────────────────────────────────────────────────────────

-- ── VIEW 1: Full group progress summary ──────────────────────────────────────
CREATE OR REPLACE VIEW vw_group_progress_summary AS
SELECT
    pg.group_id,
    pg.group_code,
    pg.project_title,
    pd.domain_name,
    u.full_name                                                          AS supervisor_name,
    d.short_code                                                         AS supervisor_dept,
    fs.stage_name                                                        AS current_stage,
    sec.section_code,
    pg.project_status,
    COUNT(DISTINCT gm.student_id)                                        AS total_members,
    COUNT(DISTINCT wpr.report_id)                                        AS total_reports,
    SUM(CASE WHEN wpr.supervisor_status = 'APPROVED' THEN 1 ELSE 0 END) AS approved_reports,
    SUM(CASE WHEN wpr.supervisor_status = 'PENDING'  THEN 1 ELSE 0 END) AS pending_reports,
    SUM(CASE WHEN wpr.supervisor_status = 'REJECTED' THEN 1 ELSE 0 END) AS rejected_reports
FROM project_groups pg
JOIN project_domains pd       ON pd.domain_id   = pg.project_domain_id
JOIN users u                  ON u.user_id       = pg.supervisor_id
JOIN departments d            ON d.department_id = u.department_id
JOIN fydp_stages fs           ON fs.stage_id     = pg.current_stage_id
JOIN sections sec             ON sec.section_id  = pg.section_id
LEFT JOIN group_members gm    ON gm.group_id     = pg.group_id
LEFT JOIN weekly_progress_reports wpr ON wpr.group_id = pg.group_id
WHERE pg.is_active = 1
GROUP BY pg.group_id, pg.group_code, pg.project_title, pd.domain_name,
         u.full_name, d.short_code, fs.stage_name, sec.section_code, pg.project_status;

-- ── VIEW 2: Supervisor workload ───────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_supervisor_workload AS
SELECT
    u.user_id                                               AS supervisor_id,
    u.full_name                                             AS supervisor_name,
    d.department_name,
    d.short_code                                            AS dept_code,
    fs.stage_name,
    COUNT(pg.group_id)                                      AS total_groups_in_stage,
    GREATEST(0, 3 - COUNT(pg.group_id))                     AS remaining_capacity
FROM users u
JOIN departments d ON d.department_id = u.department_id
CROSS JOIN fydp_stages fs
LEFT JOIN project_groups pg
    ON  pg.supervisor_id    = u.user_id
    AND pg.current_stage_id = fs.stage_id
    AND pg.is_active        = 1
    AND pg.project_status  != 'DROPPED'
WHERE u.role = 'SUPERVISOR'
  AND u.account_status = 'ACTIVE'
GROUP BY u.user_id, u.full_name, d.department_name, d.short_code, fs.stage_name;

-- ── VIEW 3: Student matchmaking board ────────────────────────────────────────
CREATE OR REPLACE VIEW vw_student_matchmaking_board AS
SELECT
    u.user_id,
    u.full_name,
    d.department_name,
    d.short_code                                                                   AS dept_code,
    u.batch,
    sp.cgpa,
    sp.preferred_team_role,
    sp.availability_status,
    sp.github_url,
    sp.linkedin_url,
    t.trimester_name                                                               AS target_trimester,
    GROUP_CONCAT(DISTINCT s.skill_name   ORDER BY s.skill_name   SEPARATOR ', ')  AS skills,
    GROUP_CONCAT(DISTINCT pd.domain_name ORDER BY pd.domain_name SEPARATOR ', ')  AS domain_interests
FROM users u
JOIN departments d              ON d.department_id = u.department_id
JOIN student_profiles sp        ON sp.student_id   = u.user_id
LEFT JOIN trimesters t          ON t.trimester_id  = sp.trimester_id
LEFT JOIN student_skills ss     ON ss.student_id   = u.user_id
LEFT JOIN skills s              ON s.skill_id      = ss.skill_id
LEFT JOIN student_domain_interests sdi ON sdi.student_id = u.user_id
LEFT JOIN project_domains pd    ON pd.domain_id    = sdi.domain_id
WHERE u.role           = 'STUDENT'
  AND u.account_status = 'ACTIVE'
  AND sp.availability_status = 'LOOKING'
GROUP BY u.user_id, u.full_name, d.department_name, d.short_code, u.batch,
         sp.cgpa, sp.preferred_team_role, sp.availability_status,
         sp.github_url, sp.linkedin_url, t.trimester_name;

-- ── VIEW 4: Course teacher pending inbox ─────────────────────────────────────
CREATE OR REPLACE VIEW vw_pending_course_teacher_inbox AS
SELECT
    ci.inbox_id,
    ci.group_id,
    pg.group_code,
    pg.project_title,
    sec.section_code,
    fs.stage_name,
    ci.week_no,
    ci.escalated_at,
    ci.escalation_status,
    ci.approved_count,
    ci.total_members,
    CONCAT(ci.approved_count, ' / ', ci.total_members) AS approval_progress,
    DATEDIFF(NOW(), ci.escalated_at)                    AS days_waiting
FROM course_teacher_inbox ci
JOIN project_groups pg ON pg.group_id  = ci.group_id
JOIN fydp_stages fs    ON fs.stage_id  = pg.current_stage_id
JOIN sections sec      ON sec.section_id = pg.section_id
WHERE ci.escalation_status IN ('PENDING_REVIEW', 'IN_PROGRESS')
ORDER BY ci.escalated_at ASC;

-- ── VIEW 5: CT Dashboard ─────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_ct_dashboard AS
SELECT
    pg.group_id,
    pg.group_code,
    pg.project_title,
    sec.section_code,
    fs.stage_name,
    ci.week_no,
    ci.escalated_at,
    ci.approved_count,
    ci.total_members,
    ci.is_fully_approved,
    CONCAT(ci.approved_count, ' / ', ci.total_members) AS approval_progress,
    u.university_id   AS student_uid,
    u.full_name       AS student_name,
    COALESCE(wpr.supervisor_status, 'NOT SUBMITTED')    AS report_status,
    wpr.report_title,
    wpr.report_file_path,
    wpr.supervisor_feedback,
    wpr.supervisor_signed_at,
    wpr.submitted_at
FROM course_teacher_inbox ci
JOIN project_groups pg       ON pg.group_id  = ci.group_id
JOIN fydp_stages fs          ON fs.stage_id  = pg.current_stage_id
JOIN sections sec            ON sec.section_id = pg.section_id
JOIN group_members gm        ON gm.group_id  = ci.group_id
JOIN users u                 ON u.user_id    = gm.student_id
LEFT JOIN weekly_progress_reports wpr
    ON  wpr.group_id   = ci.group_id
    AND wpr.student_id = gm.student_id
    AND wpr.week_no    = ci.week_no
ORDER BY pg.group_code, ci.week_no,
         FIELD(wpr.supervisor_status, 'APPROVED', 'PENDING', 'REJECTED', NULL);

-- ── VIEW 6: CT Inbox Summary ─────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_ct_inbox_summary AS
SELECT
    ci.inbox_id,
    pg.group_code,
    pg.project_title,
    sec.section_code,
    fs.stage_name,
    ci.week_no,
    ci.escalated_at,
    ci.approved_count,
    ci.total_members,
    CONCAT(ci.approved_count, ' / ', ci.total_members) AS approval_progress,
    ci.is_fully_approved,
    ci.escalation_status,
    DATEDIFF(NOW(), ci.escalated_at)                    AS days_since_first_approval,
    CASE
        WHEN ci.is_fully_approved = 1 THEN 'All Approved'
        WHEN ci.approved_count = 0    THEN 'No Approvals Yet'
        ELSE CONCAT('In Progress (', ci.approved_count, '/', ci.total_members, ')')
    END AS readable_status
FROM course_teacher_inbox ci
JOIN project_groups pg ON pg.group_id   = ci.group_id
JOIN fydp_stages fs    ON fs.stage_id   = pg.current_stage_id
JOIN sections sec      ON sec.section_id = pg.section_id
ORDER BY ci.escalated_at DESC;

-- ── VIEW 7: Pre-FYDP Skill Matchmaking Leaderboard ────────────────
CREATE OR REPLACE VIEW vw_pre_fydp_skill_match AS
SELECT
    u.university_id                                       AS student_uid,
    u.full_name                                           AS student_name,
    pfp.preferred_role,
    pfp.cgpa,
    pfp.availability_status,
    pfg.group_id,
    pfg.group_name,
    pd.domain_name,
    pfg.group_status,
    pfg.max_members,
    (SELECT COUNT(*) FROM pre_fydp_group_members m WHERE m.group_id = pfg.group_id) AS current_members,
    fn_skill_match_score(u.user_id, pfg.group_id)         AS skill_match_pct
FROM users u
JOIN pre_fydp_profiles pfp  ON pfp.user_id  = u.user_id
CROSS JOIN pre_fydp_groups pfg
JOIN project_domains pd     ON pd.domain_id = pfg.domain_id
WHERE u.role             = 'PRE_FYDP_STUDENT'
  AND u.account_status   = 'ACTIVE'
  AND pfp.availability_status = 'LOOKING'
  AND pfg.group_status   = 'OPEN'
ORDER BY u.user_id, skill_match_pct DESC;

-- ── VIEW 8: Group Chat Feed                              [NEW v3.1] ──────────
CREATE OR REPLACE VIEW vw_group_chat_feed AS
SELECT
    gcm.message_id,
    pg.group_code,
    pg.project_title,
    gcm.group_id,
    gcm.chat_type,
    gcm.sender_id,
    u.full_name                                         AS sender_name,
    u.role                                              AS sender_role,
    gcm.message_text,
    gcm.attachment_path,
    gcm.attachment_name,
    gcm.created_at
FROM group_chat_messages gcm
JOIN project_groups pg ON pg.group_id = gcm.group_id
JOIN users u           ON u.user_id   = gcm.sender_id
ORDER BY gcm.group_id, gcm.chat_type, gcm.created_at;

-- ── VIEW 9: Direct Message Conversation Threads          [NEW v3.1] ──────────

CREATE OR REPLACE VIEW vw_dm_conversation_threads AS
SELECT
    dm.message_id,
    dm.sender_id,
    su.full_name                                        AS sender_name,
    su.university_id                                    AS sender_uid,
    dm.receiver_id,
    ru.full_name                                        AS receiver_name,
    ru.university_id                                    AS receiver_uid,
    dm.message_text,
    dm.attachment_path,
    dm.attachment_name,
    dm.is_read,
    dm.created_at,
    -- Canonical conversation key: always smallest_id → largest_id
    LEAST(dm.sender_id, dm.receiver_id)                 AS participant_a,
    GREATEST(dm.sender_id, dm.receiver_id)              AS participant_b
FROM direct_messages dm
JOIN users su ON su.user_id = dm.sender_id
JOIN users ru ON ru.user_id = dm.receiver_id
ORDER BY participant_a, participant_b, dm.created_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 — TEST EXECUTION SCENARIOS
-- ─────────────────────────────────────────────────────────────────────────────

SET SQL_SAFE_UPDATES = 0;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 1: ESCALATION ENGINE — PARTIAL THEN FULL APPROVAL
-- ══════════════════════════════════════════════════════════════════════════════
SELECT '── Before: inbox should be empty ──' AS checkpoint;
SELECT * FROM course_teacher_inbox
 WHERE group_id = (SELECT group_id FROM project_groups WHERE group_code = 'UIU-G001');

CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id = (SELECT user_id FROM users WHERE university_id = 'STU001') AND week_no = 1),
    (SELECT user_id FROM users WHERE university_id = 'SUP001'),
    'APPROVED', 'Excellent literature survey.');

SELECT '── After STU001 approved: status = IN_PROGRESS ──' AS checkpoint;
SELECT group_code, week_no, approved_count, total_members,
       is_fully_approved, escalation_status
  FROM vw_ct_inbox_summary WHERE group_code = 'UIU-G001';

CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id = (SELECT user_id FROM users WHERE university_id = 'STU002') AND week_no = 1),
    (SELECT user_id FROM users WHERE university_id = 'SUP001'),
    'APPROVED', 'Great UI wireframes.');
CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id = (SELECT user_id FROM users WHERE university_id = 'STU003') AND week_no = 1),
    (SELECT user_id FROM users WHERE university_id = 'SUP001'),
    'APPROVED', 'Good dataset collection.');

CALL sp_approve_weekly_report(
    (SELECT report_id FROM weekly_progress_reports
      WHERE student_id = (SELECT user_id FROM users WHERE university_id = 'STU004') AND week_no = 1),
    (SELECT user_id FROM users WHERE university_id = 'SUP001'),
    'APPROVED', 'Excellent DB schema design.');

SELECT '── After ALL approved: status = PENDING_REVIEW ──' AS checkpoint;
SELECT * FROM vw_ct_dashboard WHERE group_code = 'UIU-G001' AND week_no = 1;
SELECT * FROM vw_ct_inbox_summary;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 2: APPROVAL PERCENTAGE FUNCTION
-- ══════════════════════════════════════════════════════════════════════════════
SELECT fn_get_group_approval_pct(
    (SELECT group_id FROM project_groups WHERE group_code = 'UIU-G001'), 1
) AS g001_week1_approval_pct;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 3: SKILL MATCH FUNCTION — AI MATCHMAKING
-- ══════════════════════════════════════════════════════════════════════════════
SELECT '── Skill match: PFYDP001 vs all open groups ──' AS checkpoint;
SELECT group_name, domain_name, skill_match_pct,
       CONCAT(current_members, '/', max_members) AS slots
  FROM vw_pre_fydp_skill_match
 WHERE student_uid = 'PFYDP001'
 ORDER BY skill_match_pct DESC;

SELECT '── Full matchmaking leaderboard ──' AS checkpoint;
SELECT student_name, group_name, skill_match_pct
  FROM vw_pre_fydp_skill_match
 ORDER BY student_name, skill_match_pct DESC;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 4: SUPERVISOR CAPACITY LIMIT
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
VALUES
  ('UIU-G004', 'FinTrack: Blockchain-Based Payment Ledger',
   (SELECT domain_id  FROM project_domains WHERE domain_name = 'FinTech'),
   (SELECT user_id    FROM users WHERE university_id = 'SUP001'),
   (SELECT stage_id   FROM fydp_stages WHERE stage_name = 'FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code = 'CSE-C'));

-- 4th group → SIGNAL fires (SUPERVISOR CAPACITY EXCEEDED)
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
VALUES
  ('UIU-G005', 'This Insert Should Fail',
   (SELECT domain_id  FROM project_domains WHERE domain_name = 'FinTech'),
   (SELECT user_id    FROM users WHERE university_id = 'SUP001'),
   (SELECT stage_id   FROM fydp_stages WHERE stage_name = 'FYDP-1'),
   (SELECT section_id FROM sections WHERE section_code = 'CSE-D'));

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 5: CGPA CONSTRAINT
-- ══════════════════════════════════════════════════════════════════════════════
UPDATE student_profiles SET cgpa = 5.00
 WHERE student_id = (SELECT user_id FROM users WHERE university_id = 'STU001');

UPDATE pre_fydp_profiles SET cgpa = -1.00
 WHERE user_id = (SELECT user_id FROM users WHERE university_id = 'PFYDP001');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 6: DUPLICATE WEEKLY REPORT (UNIQUE KEY)
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content)
VALUES
  ((SELECT group_id FROM project_groups WHERE group_code = 'UIU-G001'),
   (SELECT user_id  FROM users WHERE university_id = 'STU001'),
   1, 'Duplicate Week 1 Report', 'Should fail — UNIQUE KEY constraint.');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 7: STAGE PROMOTION WITH TOPIC CHANGE
-- ══════════════════════════════════════════════════════════════════════════════
SELECT '── Before promotion ──' AS checkpoint;
SELECT group_code, project_title, current_stage_id FROM project_groups WHERE group_code = 'UIU-G001';

CALL sp_promote_fydp_stage(
    (SELECT group_id FROM project_groups WHERE group_code = 'UIU-G001'),
    (SELECT stage_id FROM fydp_stages WHERE stage_name = 'FYDP-2'),
    (SELECT domain_id FROM project_domains WHERE domain_name = 'Artificial Intelligence'),
    'BanglaBot 2.0: Advanced AI Dialogue System for Bangla',
    (SELECT user_id FROM users WHERE university_id = 'ADMIN001'),
    'Group refined scope to AI Dialogue Systems during FYDP-1.'
);

SELECT '── After promotion ──' AS checkpoint;
SELECT group_code, project_title, current_stage_id FROM project_groups WHERE group_code = 'UIU-G001';
SELECT * FROM topic_change_history WHERE group_id = (SELECT group_id FROM project_groups WHERE group_code = 'UIU-G001');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 8: BULK IMPORT ENGINE
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO ucam_import_staging
  (raw_student_university_id, raw_group_code, raw_supervisor_university_id,
   raw_stage_name, raw_project_title, raw_domain_name, import_batch_id)
VALUES
  ('STU001', 'UIU-IMP-001', 'SUP003', 'FYDP-1', 'Smart IoT Health',    'IoT',       'BATCH-001'),
  ('STU002', 'UIU-IMP-001', 'SUP003', 'FYDP-1', 'Smart IoT Health',    'IoT',       'BATCH-001'),
  ('INVALID', 'UIU-IMP-001','SUP003', 'FYDP-1', 'Should fail',         'IoT',       'BATCH-001'),
  ('STU003', 'UIU-IMP-001', 'BAD',    'FYDP-1', 'Smart IoT Health',    'IoT',       'BATCH-001'),
  ('STU004', 'UIU-IMP-002', 'SUP003', 'BADSTAGE','FinTech App',         'FinTech',   'BATCH-001');

CALL sp_bulk_import_ucam_groups('BATCH-001');
SELECT * FROM import_error_logs ORDER BY logged_at DESC;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 9: DUPLICATE INVITATION PREVENTION (REVERSE DIRECTION)
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO matchmaking_team_invitations
  (sender_student_id, receiver_student_id, invitation_message)
VALUES
  ((SELECT user_id FROM users WHERE university_id = 'STU006'),
   (SELECT user_id FROM users WHERE university_id = 'STU005'),
   'This reverse invitation should be blocked by trigger!');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 10: WEEK RANGE CHECK CONSTRAINT
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO weekly_progress_reports (group_id, student_id, week_no, report_title, report_content)
VALUES ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
        (SELECT user_id  FROM users WHERE university_id='STU005'),
        0, 'Week 0 invalid', 'Should fail CHECK constraint.');
INSERT INTO weekly_progress_reports (group_id, student_id, week_no, report_title, report_content)
VALUES ((SELECT group_id FROM project_groups WHERE group_code='UIU-G002'),
        (SELECT user_id  FROM users WHERE university_id='STU005'),
        53, 'Week 53 invalid', 'Should also fail CHECK constraint.');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 11: USER STATUS LOG TRIGGER
-- ══════════════════════════════════════════════════════════════════════════════
SELECT '── Before: no log entries ──' AS checkpoint;
SELECT * FROM user_status_log
 WHERE user_id = (SELECT user_id FROM users WHERE university_id = 'STU001');

UPDATE users SET account_status = 'SUSPENDED' WHERE university_id = 'STU001';
UPDATE users SET account_status = 'ACTIVE'    WHERE university_id = 'STU001';

SELECT '── After: 2 log entries ──' AS checkpoint;
SELECT usl.*, u.full_name
  FROM user_status_log usl
  JOIN users u ON u.user_id = usl.user_id
 WHERE usl.user_id = (SELECT user_id FROM users WHERE university_id = 'STU001')
 ORDER BY changed_at;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 12: FULLTEXT SEARCH
-- ══════════════════════════════════════════════════════════════════════════════
SELECT group_code, project_title
  FROM project_groups
 WHERE MATCH(project_title) AGAINST ('AI Bangla' IN BOOLEAN MODE);

SELECT group_name, description
  FROM pre_fydp_groups
 WHERE MATCH(group_name, description) AGAINST ('security intrusion' IN BOOLEAN MODE);

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 13: MESSAGING MODULE                              [NEW v3.1]
-- ══════════════════════════════════════════════════════════════════════════════
SELECT '── Group chat feed: UIU-G001 student-only channel ──' AS checkpoint;
SELECT sender_name, sender_role, chat_type, message_text, created_at
  FROM vw_group_chat_feed
 WHERE group_code = 'UIU-G001'
   AND chat_type  = 'STUDENT_ONLY'
 ORDER BY created_at;

SELECT '── Group chat feed: UIU-G001 supervisor channel ──' AS checkpoint;
SELECT sender_name, sender_role, chat_type, message_text, created_at
  FROM vw_group_chat_feed
 WHERE group_code = 'UIU-G001'
   AND chat_type  = 'WITH_SUPERVISOR'
 ORDER BY created_at;

SELECT '── DM conversation: STU001 ↔ STU003 ──' AS checkpoint;
SELECT sender_name, receiver_name, message_text, is_read, created_at
  FROM vw_dm_conversation_threads
 WHERE (participant_a = (SELECT user_id FROM users WHERE university_id='STU001')
    AND participant_b = (SELECT user_id FROM users WHERE university_id='STU003'))
    OR (participant_a = (SELECT user_id FROM users WHERE university_id='STU003')
    AND participant_b = (SELECT user_id FROM users WHERE university_id='STU001'))
 ORDER BY created_at;

SELECT '── Unread DM count for STU003 ──' AS checkpoint;
SELECT fn_unread_dm_count(
    (SELECT user_id FROM users WHERE university_id='STU003')
) AS unread_dm_count;

-- Mark a DM as read (simulating inbox open)
UPDATE direct_messages
   SET is_read = 1
 WHERE receiver_id = (SELECT user_id FROM users WHERE university_id='STU003')
   AND sender_id   = (SELECT user_id FROM users WHERE university_id='STU001');

SELECT '── Unread count after read (should be 0) ──' AS checkpoint;
SELECT fn_unread_dm_count(
    (SELECT user_id FROM users WHERE university_id='STU003')
) AS unread_dm_count_after_read;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST 14: ALL VIEWS
-- ══════════════════════════════════════════════════════════════════════════════
SELECT * FROM vw_student_matchmaking_board;
SELECT * FROM vw_supervisor_workload ORDER BY supervisor_name, stage_name;
SELECT * FROM vw_group_progress_summary;
SELECT * FROM vw_pending_course_teacher_inbox;
SELECT * FROM vw_group_chat_feed;
SELECT * FROM vw_dm_conversation_threads;

SELECT fn_is_student_in_active_group(
    (SELECT user_id FROM users WHERE university_id = 'STU001')) AS is_in_active_group;
SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT 20;

SET SQL_SAFE_UPDATES = 1;

 -- End