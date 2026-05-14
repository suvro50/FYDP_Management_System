-- =============================================================================
--  FYDP MANAGEMENT & MATCHMAKING SYSTEM
--  Enterprise MySQL 8.0 Database Architecture
--  UIU — United International University
--  DBMS Lab Project | Competitive Showcase Edition
-- =============================================================================
--  Architecture: BCNF Normalized | InnoDB | utf8mb4
--  Features: Triggers | Stored Procedures | Transactions | Audit Logs
--            Views | Functions | Indexes | Soft-Delete | Escalation Engine
-- =============================================================================

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

-- ── MODULE 1: PRE-FYDP MATCHMAKING HUB ──────────────────────────────────────

-- ----------------------------------------------------------------------------
-- TABLE: users
-- Single authentication table for all roles in the system.
-- BCNF: Each non-key attribute (email, role, dept) depends solely on user_id.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id           INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    university_id     VARCHAR(20)      NOT NULL,
    full_name         VARCHAR(120)     NOT NULL,
    email             VARCHAR(150)     NOT NULL,
    password_hash     VARCHAR(255)     NOT NULL,
    role              ENUM('STUDENT','SUPERVISOR','COURSE_TEACHER','ADMIN','PRE_FYDP_STUDENT')
                                       NOT NULL DEFAULT 'STUDENT',
    department        VARCHAR(100)     NOT NULL,
    batch             VARCHAR(20)      NULL,
    phone             VARCHAR(20)      NULL,
    profile_photo     VARCHAR(500)     NULL,
    account_status    ENUM('ACTIVE','SUSPENDED','DEACTIVATED')
                                       NOT NULL DEFAULT 'ACTIVE',
    is_active         TINYINT(1)       NOT NULL DEFAULT 1,
    deleted_at        DATETIME         NULL,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email         (email),
    UNIQUE KEY uq_users_university_id (university_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master authentication table for all system roles';

-- ----------------------------------------------------------------------------
-- TABLE: student_profiles
-- Stores detailed academic/professional profile for students only.
-- BCNF: Separated from users to avoid partial dependency on role.
-- ----------------------------------------------------------------------------
CREATE TABLE student_profiles (
    student_profile_id    INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    student_id            INT UNSIGNED   NOT NULL,
    cgpa                  DECIMAL(4,2)   NULL,
    bio                   TEXT           NULL,
    github_url            VARCHAR(500)   NULL,
    linkedin_url          VARCHAR(500)   NULL,
    portfolio_url         VARCHAR(500)   NULL,
    preferred_team_role   ENUM('TEAM_LEAD','DEVELOPER','DESIGNER',
                               'RESEARCHER','TESTER','DATA_ENGINEER')
                                         NULL,
    target_trimester      VARCHAR(30)    NULL,
    availability_status   ENUM('LOOKING','IN_TEAM','NOT_AVAILABLE')
                                         NOT NULL DEFAULT 'LOOKING',
    created_at            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                  ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (student_profile_id),
    UNIQUE KEY uq_student_profiles_student_id (student_id),
    CONSTRAINT fk_student_profiles_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Extended academic profile for STUDENT role users';

-- ----------------------------------------------------------------------------
-- TABLE: skills
-- Master skill repository — normalized to avoid redundancy.
-- ----------------------------------------------------------------------------
CREATE TABLE skills (
    skill_id      INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    skill_name    VARCHAR(100)   NOT NULL,
    skill_category VARCHAR(100)  NULL COMMENT 'e.g. Programming, ML, Design',
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (skill_id),
    UNIQUE KEY uq_skills_name (skill_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master list of all recognized technical and soft skills';

-- ----------------------------------------------------------------------------
-- TABLE: project_domains
-- Master domain list — normalized, reused across matchmaking and groups.
-- ----------------------------------------------------------------------------
CREATE TABLE project_domains (
    domain_id     INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    domain_name   VARCHAR(100)   NOT NULL,
    description   TEXT           NULL,
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (domain_id),
    UNIQUE KEY uq_project_domains_name (domain_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master list of FYDP project domains';

-- ----------------------------------------------------------------------------
-- TABLE: student_skills
-- Bridge table: Many-to-many between students and skills.
-- ----------------------------------------------------------------------------
CREATE TABLE student_skills (
    student_id        INT UNSIGNED                            NOT NULL,
    skill_id          INT UNSIGNED                            NOT NULL,
    proficiency_level ENUM('BEGINNER','INTERMEDIATE','ADVANCED','EXPERT')
                                                              NOT NULL DEFAULT 'BEGINNER',
    years_experience  DECIMAL(4,1)                           NULL DEFAULT 0.0,
    created_at        DATETIME                               NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (student_id, skill_id),
    CONSTRAINT fk_student_skills_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_skills_skill
        FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Student-to-Skill with proficiency metadata';

-- ----------------------------------------------------------------------------
-- TABLE: student_domain_interests
-- Bridge table: Many-to-many between students and project domains.
-- ----------------------------------------------------------------------------
CREATE TABLE student_domain_interests (
    student_id    INT UNSIGNED   NOT NULL,
    domain_id     INT UNSIGNED   NOT NULL,
    interest_level ENUM('LOW','MEDIUM','HIGH') NOT NULL DEFAULT 'MEDIUM',
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (student_id, domain_id),
    CONSTRAINT fk_sdi_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_sdi_domain
        FOREIGN KEY (domain_id) REFERENCES project_domains(domain_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Student domain interest preferences';

-- ----------------------------------------------------------------------------
-- TABLE: matchmaking_team_invitations
-- Tracks pre-FYDP team formation invitations between students.
-- Business Rule: No duplicate PENDING invitations between the same pair.
-- ----------------------------------------------------------------------------
CREATE TABLE matchmaking_team_invitations (
    invitation_id       INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    sender_student_id   INT UNSIGNED   NOT NULL,
    receiver_student_id INT UNSIGNED   NOT NULL,
    invitation_message  TEXT           NULL,
    invitation_status   ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED')
                                       NOT NULL DEFAULT 'PENDING',
    responded_at        DATETIME       NULL,
    created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (invitation_id),
    -- Self-invitation prevention moved to trigger (MySQL 8.0 CHECK+CASCADE FK conflict)
    -- Prevent duplicate PENDING invitations (enforced via trigger below too)
    UNIQUE KEY uq_active_invitation (sender_student_id, receiver_student_id, invitation_status),
    CONSTRAINT fk_invitations_sender
        FOREIGN KEY (sender_student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_invitations_receiver
        FOREIGN KEY (receiver_student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Pre-registration team matchmaking invitation workflow';

-- ----------------------------------------------------------------------------
-- TABLE: notifications
-- Stores all system-generated notifications for users.
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
    notification_id       INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    user_id               INT UNSIGNED   NOT NULL,
    notification_type     ENUM('INVITATION_RECEIVED','INVITATION_ACCEPTED',
                               'INVITATION_REJECTED','REPORT_APPROVED',
                               'REPORT_REJECTED','ESCALATION_COMPLETE',
                               'STAGE_PROMOTED','SYSTEM_ALERT')
                                         NOT NULL,
    message               TEXT           NOT NULL,
    reference_entity_id   INT UNSIGNED   NULL COMMENT 'FK to relevant entity (report_id, invitation_id, etc.)',
    reference_entity_type VARCHAR(60)    NULL COMMENT 'e.g. weekly_progress_reports',
    is_read               TINYINT(1)     NOT NULL DEFAULT 0,
    created_at            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id),
    CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='System notification inbox for all users';

-- ── MODULE 2: POST-REGISTRATION ESCALATION & GRADING ENGINE ─────────────────

-- ----------------------------------------------------------------------------
-- TABLE: fydp_stages
-- Stores the 3 FYDP stages: FYDP-1, FYDP-2, FYDP-3
-- ----------------------------------------------------------------------------
CREATE TABLE fydp_stages (
    stage_id      INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    stage_name    ENUM('FYDP-1','FYDP-2','FYDP-3') NOT NULL,
    stage_order   TINYINT        NOT NULL COMMENT 'Ordering: 1,2,3',
    description   TEXT           NULL,
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (stage_id),
    UNIQUE KEY uq_fydp_stages_name (stage_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FYDP lifecycle stages: FYDP-1, FYDP-2, FYDP-3';

-- ----------------------------------------------------------------------------
-- TABLE: project_groups
-- Core group entity. Enforces 4-5 member rule via triggers.
-- BCNF: supervisor_id is a direct attribute — no transitive dependency.
-- ----------------------------------------------------------------------------
CREATE TABLE project_groups (
    group_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_code        VARCHAR(30)    NOT NULL,
    project_title     VARCHAR(300)   NOT NULL,
    project_domain_id INT UNSIGNED   NOT NULL,
    supervisor_id     INT UNSIGNED   NOT NULL,
    current_stage_id  INT UNSIGNED   NOT NULL,
    section_code      VARCHAR(20)    NOT NULL,
    project_status    ENUM('ACTIVE','COMPLETED','DROPPED','ON_HOLD')
                                     NOT NULL DEFAULT 'ACTIVE',
    is_active         TINYINT(1)     NOT NULL DEFAULT 1,
    deleted_at        DATETIME       NULL,
    created_at        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                              ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    UNIQUE KEY uq_group_code (group_code),
    CONSTRAINT fk_groups_domain
        FOREIGN KEY (project_domain_id) REFERENCES project_domains(domain_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_groups_supervisor
        FOREIGN KEY (supervisor_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_groups_stage
        FOREIGN KEY (current_stage_id) REFERENCES fydp_stages(stage_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='FYDP project groups — core entity for post-registration workflow';

-- ----------------------------------------------------------------------------
-- TABLE: group_members
-- Bridge: Students to Groups. Enforces single active membership.
-- ----------------------------------------------------------------------------
CREATE TABLE group_members (
    group_member_id   INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id          INT UNSIGNED   NOT NULL,
    student_id        INT UNSIGNED   NOT NULL,
    member_role       ENUM('TEAM_LEAD','DEVELOPER','DESIGNER',
                           'RESEARCHER','TESTER','DATA_ENGINEER')
                                     NOT NULL DEFAULT 'DEVELOPER',
    joined_at         DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_member_id),
    -- Prevent duplicate membership in the same group
    UNIQUE KEY uq_group_member (group_id, student_id),
    CONSTRAINT fk_gm_group
        FOREIGN KEY (group_id) REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_gm_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Group-to-Student membership with role assignment';

-- ----------------------------------------------------------------------------
-- TABLE: course_teacher_sections
-- Maps course teachers to sections and stages they oversee.
-- ----------------------------------------------------------------------------
CREATE TABLE course_teacher_sections (
    mapping_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    course_teacher_id   INT UNSIGNED   NOT NULL,
    section_code        VARCHAR(20)    NOT NULL,
    assigned_stage_id   INT UNSIGNED   NOT NULL,
    created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (mapping_id),
    UNIQUE KEY uq_cts_mapping (course_teacher_id, section_code, assigned_stage_id),
    CONSTRAINT fk_cts_teacher
        FOREIGN KEY (course_teacher_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_cts_stage
        FOREIGN KEY (assigned_stage_id) REFERENCES fydp_stages(stage_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Maps course teachers to sections and FYDP stages';

-- ----------------------------------------------------------------------------
-- TABLE: weekly_progress_reports
-- Digital journal workflow — one report per student per week per group.
-- This is the heartbeat of the escalation engine.
-- ----------------------------------------------------------------------------
CREATE TABLE weekly_progress_reports (
    report_id             INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id              INT UNSIGNED   NOT NULL,
    student_id            INT UNSIGNED   NOT NULL,
    week_no               TINYINT UNSIGNED NOT NULL,
    report_title          VARCHAR(300)   NOT NULL,
    report_content        LONGTEXT       NOT NULL,
    submitted_at          DATETIME       NULL,
    supervisor_status     ENUM('PENDING','APPROVED','REJECTED')
                                         NOT NULL DEFAULT 'PENDING',
    supervisor_feedback   TEXT           NULL,
    supervisor_signed_at  DATETIME       NULL,
    is_active             TINYINT(1)     NOT NULL DEFAULT 1,
    created_at            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                  ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (report_id),
    -- CRITICAL: One report per student per group per week
    UNIQUE KEY uq_report_weekly (group_id, student_id, week_no),
    -- Validate week number range
    CONSTRAINT chk_week_range CHECK (week_no BETWEEN 1 AND 52),
    CONSTRAINT fk_wpr_group
        FOREIGN KEY (group_id) REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_wpr_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Weekly digital journal — triggers escalation on full group approval';

-- ----------------------------------------------------------------------------
-- TABLE: course_teacher_inbox
-- Receives auto-escalated weekly packages when all group members are approved.
-- This table is populated ONLY by the escalation trigger.
-- ----------------------------------------------------------------------------
CREATE TABLE course_teacher_inbox (
    inbox_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id          INT UNSIGNED   NOT NULL,
    week_no           TINYINT UNSIGNED NOT NULL,
    escalated_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    escalation_status ENUM('PENDING_REVIEW','REVIEWED','FLAGGED')
                                     NOT NULL DEFAULT 'PENDING_REVIEW',
    reviewed_at       DATETIME       NULL,
    reviewed_by       INT UNSIGNED   NULL COMMENT 'course_teacher user_id',
    notes             TEXT           NULL,
    PRIMARY KEY (inbox_id),
    -- One escalation per group per week
    UNIQUE KEY uq_inbox_group_week (group_id, week_no),
    CONSTRAINT fk_inbox_group
        FOREIGN KEY (group_id) REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_inbox_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Auto-populated by escalation trigger when all group members are approved for a week';

-- ----------------------------------------------------------------------------
-- TABLE: topic_change_history
-- Immutable audit log for project title and domain changes during promotions.
-- BCNF: All attributes depend solely on history_id (no transitive deps).
-- ----------------------------------------------------------------------------
CREATE TABLE topic_change_history (
    history_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id            INT UNSIGNED   NOT NULL,
    old_domain_id       INT UNSIGNED   NULL,
    new_domain_id       INT UNSIGNED   NULL,
    old_project_title   VARCHAR(300)   NULL,
    new_project_title   VARCHAR(300)   NULL,
    changed_by_admin    INT UNSIGNED   NOT NULL,
    change_reason       TEXT           NOT NULL,
    changed_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    CONSTRAINT fk_tch_group
        FOREIGN KEY (group_id) REFERENCES project_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_tch_old_domain
        FOREIGN KEY (old_domain_id) REFERENCES project_domains(domain_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tch_new_domain
        FOREIGN KEY (new_domain_id) REFERENCES project_domains(domain_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tch_admin
        FOREIGN KEY (changed_by_admin) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit trail: FYDP stage promotion topic/domain changes';

-- ----------------------------------------------------------------------------
-- TABLE: import_error_logs
-- Logs failed rows from bulk UCAM CSV import procedure.
-- ----------------------------------------------------------------------------
CREATE TABLE import_error_logs (
    error_id      INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    error_row    INT            NOT NULL,
    error_message VARCHAR(500)   NOT NULL,
    raw_data      TEXT           NULL,
    logged_at     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (error_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Error log for bulk UCAM import failures';

-- ----------------------------------------------------------------------------
-- TABLE: ucam_import_staging
-- Temporary staging area for UCAM CSV bulk import simulation.
-- ----------------------------------------------------------------------------
CREATE TABLE ucam_import_staging (
    staging_id                  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    raw_student_university_id   VARCHAR(50)    NULL,
    raw_group_code              VARCHAR(50)    NULL,
    raw_supervisor_university_id VARCHAR(50)   NULL,
    raw_stage_name              VARCHAR(50)    NULL,
    raw_project_title           VARCHAR(300)   NULL,
    raw_domain_name             VARCHAR(100)   NULL,
    import_batch_id             VARCHAR(50)    NULL COMMENT 'UUID or batch label for tracking',
    imported_at                 DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (staging_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Staging table for UCAM CSV group import simulation';

-- ----------------------------------------------------------------------------
-- TABLE: audit_log (BONUS — Enterprise Audit Trail)
-- Logs all critical data modifications for full traceability.
-- ----------------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id        BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    table_name      VARCHAR(100)     NOT NULL,
    operation       ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id       INT UNSIGNED     NOT NULL,
    changed_by      INT UNSIGNED     NULL COMMENT 'user_id if available',
    old_data        JSON             NULL,
    new_data        JSON             NULL,
    changed_at      DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Enterprise audit trail for all critical table modifications';

-- ── MODULE 3: PRE-FYDP TEAM BUILDING PLATFORM ──────────────────────────────

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_profiles
-- Extended profile for PRE_FYDP_STUDENT users (skills, bio, availability).
-- Completely isolated from student_profiles used by FYDP students.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_profiles (
    profile_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    user_id             INT UNSIGNED   NOT NULL,
    bio                 TEXT           NULL,
    cgpa                DECIMAL(4,2)   NULL,
    skills              JSON           NULL COMMENT '["Python","React","ML"]',
    domain_interests    JSON           NULL COMMENT '["AI","Cybersecurity"]',
    preferred_role      VARCHAR(50)    NULL COMMENT 'Frontend/Backend/Full-stack/ML Engineer/etc.',
    github_url          VARCHAR(500)   NULL,
    linkedin_url        VARCHAR(500)   NULL,
    portfolio_url       VARCHAR(500)   NULL,
    target_trimester    VARCHAR(30)    NULL DEFAULT 'Spring 2026',
    availability_status ENUM('LOOKING','IN_TEAM','NOT_AVAILABLE')
                                       NOT NULL DEFAULT 'LOOKING',
    profile_strength    TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0-100 percentage',
    created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (profile_id),
    UNIQUE KEY uq_prefydp_profile_user (user_id),
    CONSTRAINT fk_prefydp_profile_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Extended profile for Pre-FYDP students in matchmaking platform';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_groups
-- Groups created by Pre-FYDP students looking for teammates.
-- Completely isolated from project_groups used by registered FYDP students.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_groups (
    group_id            INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_name          VARCHAR(200)   NOT NULL,
    domain              VARCHAR(100)   NOT NULL,
    description         TEXT           NULL,
    required_skills     JSON           NULL COMMENT '["Backend","Node.js","MySQL"]',
    max_members         TINYINT UNSIGNED NOT NULL DEFAULT 5,
    github_url          VARCHAR(500)   NULL,
    created_by          INT UNSIGNED   NOT NULL,
    group_status        ENUM('OPEN','FULL','CLOSED') NOT NULL DEFAULT 'OPEN',
    created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id),
    CONSTRAINT fk_prefydp_group_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Pre-FYDP team listings for matchmaking platform';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_group_members
-- Bridge table for Pre-FYDP group membership.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_group_members (
    member_id           INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id            INT UNSIGNED   NOT NULL,
    user_id             INT UNSIGNED   NOT NULL,
    member_role         VARCHAR(50)    NULL COMMENT 'Lead/Frontend/Backend/etc.',
    joined_at           DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),
    UNIQUE KEY uq_prefydp_gm (group_id, user_id),
    CONSTRAINT fk_prefydp_gm_group
        FOREIGN KEY (group_id) REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_prefydp_gm_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge: Pre-FYDP group membership';

-- ----------------------------------------------------------------------------
-- TABLE: pre_fydp_join_requests
-- Join/invite requests between Pre-FYDP students and groups.
-- ----------------------------------------------------------------------------
CREATE TABLE pre_fydp_join_requests (
    request_id          INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    group_id            INT UNSIGNED   NOT NULL,
    sender_id           INT UNSIGNED   NOT NULL COMMENT 'Student requesting to join',
    request_type        ENUM('JOIN_REQUEST','INVITATION') NOT NULL DEFAULT 'JOIN_REQUEST',
    message             TEXT           NULL,
    request_status      ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED')
                                       NOT NULL DEFAULT 'PENDING',
    responded_at        DATETIME       NULL,
    created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (request_id),
    UNIQUE KEY uq_prefydp_join_active (group_id, sender_id, request_status),
    CONSTRAINT fk_prefydp_join_group
        FOREIGN KEY (group_id) REFERENCES pre_fydp_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_prefydp_join_sender
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Join requests and invitations for Pre-FYDP team building';

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — HIGH-PERFORMANCE INDEXING STRATEGY
-- ─────────────────────────────────────────────────────────────────────────────

-- users table indexes
-- Reason: Role-based queries (e.g., "list all supervisors") are frequent
CREATE INDEX idx_users_role ON users(role);
-- Reason: Department filtering for matchmaking suggestions
CREATE INDEX idx_users_department ON users(department);
-- Reason: Searching users by email during login/lookup
CREATE INDEX idx_users_email ON users(email);
-- Reason: Filtering active/inactive accounts
CREATE INDEX idx_users_account_status ON users(account_status);

-- student_profiles indexes
-- Reason: Finding students by availability for matchmaking
CREATE INDEX idx_sp_availability ON student_profiles(availability_status);
-- Reason: Filtering by target trimester for team suggestions
CREATE INDEX idx_sp_trimester ON student_profiles(target_trimester);

-- student_skills indexes
-- Reason: FK column must be indexed for JOIN performance
CREATE INDEX idx_ss_skill_id ON student_skills(skill_id);

-- student_domain_interests indexes
-- Reason: FK indexing for domain-based filtering
CREATE INDEX idx_sdi_domain_id ON student_domain_interests(domain_id);

-- matchmaking_team_invitations indexes
-- Reason: Checking pending invitations for a receiver is a hot query
CREATE INDEX idx_invitations_receiver ON matchmaking_team_invitations(receiver_student_id);
-- Reason: Filtering by status (PENDING/ACCEPTED) is a core workflow query
CREATE INDEX idx_invitations_status ON matchmaking_team_invitations(invitation_status);
-- Reason: Sender lookup for outgoing invitation management
CREATE INDEX idx_invitations_sender ON matchmaking_team_invitations(sender_student_id);

-- notifications indexes
-- Reason: Fetching unread notifications is a frequent per-user operation
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, is_read);
-- Reason: Filtering by notification type for categorized inbox
CREATE INDEX idx_notifications_type ON notifications(notification_type);

-- project_groups indexes
-- Reason: Supervisor loads all their groups — high frequency query
CREATE INDEX idx_groups_supervisor ON project_groups(supervisor_id);
-- Reason: Stage-based group listing (e.g., all FYDP-2 groups)
CREATE INDEX idx_groups_stage ON project_groups(current_stage_id);
-- Reason: Section-based filtering for course teacher views
CREATE INDEX idx_groups_section ON project_groups(section_code);
-- Reason: Domain-based analytics and filtering
CREATE INDEX idx_groups_domain ON project_groups(project_domain_id);
-- Reason: Status filtering for active/completed groups
CREATE INDEX idx_groups_status ON project_groups(project_status);

-- group_members indexes
-- Reason: Finding all groups for a student (membership check)
CREATE INDEX idx_gm_student ON group_members(student_id);

-- course_teacher_sections indexes
-- Reason: FK indexing for stage-teacher lookup
CREATE INDEX idx_cts_stage ON course_teacher_sections(assigned_stage_id);
-- Reason: Section code lookup for teacher assignment
CREATE INDEX idx_cts_section ON course_teacher_sections(section_code);

-- weekly_progress_reports indexes
-- Reason: Supervisor approval dashboard — filters by status
CREATE INDEX idx_wpr_supervisor_status ON weekly_progress_reports(supervisor_status);
-- Reason: Week-based reporting queries
CREATE INDEX idx_wpr_week_no ON weekly_progress_reports(week_no);
-- Reason: FK indexing for group-level queries
CREATE INDEX idx_wpr_group ON weekly_progress_reports(group_id);
-- Reason: FK indexing for student-level queries
CREATE INDEX idx_wpr_student ON weekly_progress_reports(student_id);
-- Reason: Composite index — the escalation trigger joins on these two columns
CREATE INDEX idx_wpr_group_week_status ON weekly_progress_reports(group_id, week_no, supervisor_status);

-- course_teacher_inbox indexes
-- Reason: Teacher inbox filtered by review status
CREATE INDEX idx_inbox_status ON course_teacher_inbox(escalation_status);
-- Reason: FK indexing for group-based inbox queries
CREATE INDEX idx_inbox_group ON course_teacher_inbox(group_id);

-- topic_change_history indexes
-- Reason: Audit trail lookup by group is the primary access pattern
CREATE INDEX idx_tch_group ON topic_change_history(group_id);
-- Reason: Time-based audit queries
CREATE INDEX idx_tch_changed_at ON topic_change_history(changed_at);

-- audit_log indexes
-- Reason: Table-specific audit queries are the primary access pattern
CREATE INDEX idx_audit_table ON audit_log(table_name, operation);
-- Reason: User activity tracing
CREATE INDEX idx_audit_user ON audit_log(changed_by);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 — SAMPLE DATA
-- ─────────────────────────────────────────────────────────────────────────────

-- Users (Admin, Supervisors, Course Teachers, Students)
INSERT INTO users
  (university_id, full_name, email, password_hash, role, department, batch, phone, account_status)
VALUES
  -- Admin
  ('ADMIN001',    'Dr. Rafiqul Islam',     'admin@uiu.ac.bd',         SHA2('admin123',256),   'ADMIN',          'Administration', NULL,     '01711000001', 'ACTIVE'),
  -- Supervisors
  ('SUP001',      'Dr. Tanvir Ahmed',      'tanvir@uiu.ac.bd',        SHA2('sup123',256),     'SUPERVISOR',     'CSE',            NULL,     '01711000002', 'ACTIVE'),
  ('SUP002',      'Dr. Nadia Rahman',      'nadia@uiu.ac.bd',         SHA2('sup123',256),     'SUPERVISOR',     'CSE',            NULL,     '01711000003', 'ACTIVE'),
  ('SUP003',      'Dr. Karim Hossain',     'karim@uiu.ac.bd',         SHA2('sup123',256),     'SUPERVISOR',     'EEE',            NULL,     '01711000004', 'ACTIVE'),
  -- Course Teachers
  ('CT001',       'Mr. Shafiq Alam',       'shafiq@uiu.ac.bd',        SHA2('ct123',256),      'COURSE_TEACHER', 'CSE',            NULL,     '01711000005', 'ACTIVE'),
  ('CT002',       'Ms. Farhana Begum',     'farhana@uiu.ac.bd',       SHA2('ct123',256),      'COURSE_TEACHER', 'CSE',            NULL,     '01711000006', 'ACTIVE'),
  -- Students (12 students for 2-3 groups)
  ('STU001',      'Arif Hasan',            'arif@student.uiu.ac.bd',  SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000001', 'ACTIVE'),
  ('STU002',      'Bristy Akter',          'bristy@student.uiu.ac.bd',SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000002', 'ACTIVE'),
  ('STU003',      'Cyrus Khan',            'cyrus@student.uiu.ac.bd', SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000003', 'ACTIVE'),
  ('STU004',      'Dina Sultana',          'dina@student.uiu.ac.bd',  SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000004', 'ACTIVE'),
  ('STU005',      'Emon Chowdhury',        'emon@student.uiu.ac.bd',  SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000005', 'ACTIVE'),
  ('STU006',      'Farhan Islam',          'farhan@student.uiu.ac.bd',SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000006', 'ACTIVE'),
  ('STU007',      'Gita Roy',              'gita@student.uiu.ac.bd',  SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000007', 'ACTIVE'),
  ('STU008',      'Hasan Ali',             'hasan@student.uiu.ac.bd', SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000008', 'ACTIVE'),
  ('STU009',      'Israt Jahan',           'israt@student.uiu.ac.bd', SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000009', 'ACTIVE'),
  ('STU010',      'Jahir Uddin',           'jahir@student.uiu.ac.bd', SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000010', 'ACTIVE'),
  ('STU011',      'Kamrul Bashar',         'kamrul@student.uiu.ac.bd',SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000011', 'ACTIVE'),
  ('STU012',      'Lima Khanam',           'lima@student.uiu.ac.bd',  SHA2('stu123',256),     'STUDENT',        'CSE',            'B.Sc 57','01811000012', 'ACTIVE');

-- Student profiles
INSERT INTO student_profiles
  (student_id, cgpa, bio, github_url, linkedin_url, preferred_team_role, target_trimester, availability_status)
SELECT user_id,
  ROUND(2.80 + RAND() * 1.20, 2),
  CONCAT('Passionate CSE student with interest in ', department),
  CONCAT('https://github.com/', LOWER(REPLACE(full_name,' ','_'))),
  CONCAT('https://linkedin.com/in/', LOWER(REPLACE(full_name,' ','-'))),
  ELT(FLOOR(1 + RAND()*6), 'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER'),
  'Spring 2025',
  'LOOKING'
FROM users
WHERE role = 'STUDENT';

-- Skills master data
INSERT INTO skills (skill_name, skill_category) VALUES
  ('Python',           'Programming'),
  ('Java',             'Programming'),
  ('React',            'Frontend'),
  ('NodeJS',           'Backend'),
  ('MySQL',            'Database'),
  ('Machine Learning', 'AI/ML'),
  ('Deep Learning',    'AI/ML'),
  ('NLP',              'AI/ML'),
  ('Data Science',     'Analytics'),
  ('Cybersecurity',    'Security'),
  ('IoT',              'Hardware'),
  ('Docker',           'DevOps'),
  ('AWS',              'Cloud'),
  ('Flutter',          'Mobile'),
  ('Blockchain',       'Emerging Tech');

-- Project domains
INSERT INTO project_domains (domain_name, description) VALUES
  ('Artificial Intelligence',  'AI and machine learning based projects'),
  ('NLP',                      'Natural Language Processing applications'),
  ('FinTech',                  'Financial technology and digital payment systems'),
  ('Health Informatics',       'Healthcare data management and analytics'),
  ('IoT',                      'Internet of Things and embedded systems'),
  ('Cybersecurity',            'Network and application security'),
  ('Data Analytics',           'Big data and business intelligence'),
  ('Mobile Application',       'Cross-platform mobile app development');

-- Student skills (sample for first 6 students)
INSERT INTO student_skills (student_id, skill_id, proficiency_level, years_experience) VALUES
  (7,  1, 'ADVANCED',     2.0),  -- Arif: Python
  (7,  6, 'INTERMEDIATE', 1.0),  -- Arif: ML
  (8,  3, 'ADVANCED',     1.5),  -- Bristy: React
  (8,  4, 'INTERMEDIATE', 1.0),  -- Bristy: NodeJS
  (9,  8, 'EXPERT',       2.5),  -- Cyrus: NLP
  (9,  7, 'ADVANCED',     2.0),  -- Cyrus: Deep Learning
  (10, 5, 'ADVANCED',     2.0),  -- Dina: MySQL
  (10, 9, 'INTERMEDIATE', 1.0),  -- Dina: Data Science
  (11, 10,'ADVANCED',     1.5),  -- Emon: Cybersecurity
  (12, 11,'INTERMEDIATE', 1.0);  -- Farhan: IoT

-- Domain interests
INSERT INTO student_domain_interests (student_id, domain_id, interest_level) VALUES
  (7,  1, 'HIGH'),   -- Arif → AI
  (7,  2, 'MEDIUM'), -- Arif → NLP
  (8,  8, 'HIGH'),   -- Bristy → Mobile
  (9,  2, 'HIGH'),   -- Cyrus → NLP
  (9,  1, 'HIGH'),   -- Cyrus → AI
  (10, 7, 'HIGH'),   -- Dina → Data Analytics
  (11, 6, 'HIGH'),   -- Emon → Cybersecurity
  (12, 5, 'HIGH');   -- Farhan → IoT 

-- FYDP Stages
INSERT INTO fydp_stages (stage_name, stage_order, description) VALUES
  ('FYDP-1', 1, 'Initial proposal and literature review stage'),
  ('FYDP-2', 2, 'Implementation and development stage'),
  ('FYDP-3', 3, 'Final presentation and thesis submission stage');

-- Course teacher sections
INSERT INTO course_teacher_sections (course_teacher_id, section_code, assigned_stage_id) VALUES
  (5, 'CSE-A', 1),
  (5, 'CSE-B', 1),
  (6, 'CSE-A', 2),
  (6, 'CSE-C', 2);

-- Project groups (3 groups for testing)
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_code, project_status)
VALUES
  ('UIU-G001', 'BanglaBot: Conversational AI for Bangla Language',  2, 2, 1, 'CSE-A', 'ACTIVE'),
  ('UIU-G002', 'SecureNet: AI-Powered Intrusion Detection System',  6, 2, 1, 'CSE-B', 'ACTIVE'),
  ('UIU-G003', 'HealthSync: Smart Patient Monitoring via IoT',      4, 3, 1, 'CSE-A', 'ACTIVE');

-- Group members (4 members for G001, 4 for G002, 4 for G003)
INSERT INTO group_members (group_id, student_id, member_role) VALUES
  -- Group UIU-G001 (4 members)
  (1,  7, 'TEAM_LEAD'),
  (1,  8, 'DEVELOPER'),
  (1,  9, 'RESEARCHER'),
  (1, 10, 'DATA_ENGINEER'),
  -- Group UIU-G002 (4 members)
  (2, 11, 'TEAM_LEAD'),
  (2, 12, 'DEVELOPER'),
  (2, 13, 'RESEARCHER'),
  (2, 14, 'DEVELOPER'),
  -- Group UIU-G003 (4 members)
  (3, 15, 'TEAM_LEAD'),
  (3, 16, 'DEVELOPER'),
  (3, 17, 'RESEARCHER'),
  (3, 18, 'DATA_ENGINEER');

-- Matchmaking invitations
INSERT INTO matchmaking_team_invitations
  (sender_student_id, receiver_student_id, invitation_message, invitation_status)
VALUES
  (7,  8,  'Hey Bristy! I am working on an NLP project. Want to team up?', 'ACCEPTED'),
  (9,  10, 'Hi Dina! Your DB skills would complement my NLP work perfectly.', 'ACCEPTED'),
  (11, 12, 'Farhan, interested in a security-focused FYDP?', 'PENDING'),
  (13, 14, 'Let''s collaborate on an AI project this trimester!', 'PENDING');

-- Notifications
INSERT INTO notifications
  (user_id, notification_type, message, reference_entity_id, reference_entity_type, is_read)
VALUES
  (8,  'INVITATION_RECEIVED', 'Arif Hasan has invited you to join their FYDP team.',  1, 'matchmaking_team_invitations', 1),
  (10, 'INVITATION_RECEIVED', 'Cyrus Khan has invited you to join their FYDP team.',  2, 'matchmaking_team_invitations', 0),
  (12, 'INVITATION_RECEIVED', 'Emon Chowdhury has invited you to join a security FYDP project.', 3, 'matchmaking_team_invitations', 0);

-- Weekly progress reports (week 1 — partially approved, for trigger testing)
INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content, submitted_at, supervisor_status)
VALUES
  (1, 7,  1, 'Week 1 - Literature Survey', 'Completed initial literature review on Bangla NLP models.', NOW(), 'APPROVED'),
  (1, 8,  1, 'Week 1 - Frontend Planning', 'Designed UI wireframes and component hierarchy.',            NOW(), 'APPROVED'),
  (1, 9,  1, 'Week 1 - Dataset Collection','Identified 3 Bangla text datasets for training.',            NOW(), 'APPROVED'),
  (1, 10, 1, 'Week 1 - DB Schema Draft',   'Drafted initial database schema for the project.',           NOW(), 'PENDING');  -- NOT yet approved

-- ── PRE-FYDP SAMPLE DATA ────────────────────────────────────────────────────

-- Pre-FYDP Students (6 new users, completely separate from FYDP students)
INSERT INTO users
  (university_id, full_name, email, password_hash, role, department, batch, phone, account_status)
VALUES
  ('PFYDP001', 'Suvrojit Bose',     'suvrojit@student.uiu.ac.bd',  SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'CSE', 'B.Sc 59', '01911000001', 'ACTIVE'),
  ('PFYDP002', 'Zainab Ali',       'zainab@student.uiu.ac.bd',   SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'CSE', 'B.Sc 59', '01911000002', 'ACTIVE'),
  ('PFYDP003', 'Hamza Iqbal',      'hamza@student.uiu.ac.bd',    SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'CSE', 'B.Sc 59', '01911000003', 'ACTIVE'),
  ('PFYDP004', 'Nusrat Jahan',     'nusrat@student.uiu.ac.bd',   SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'CSE', 'B.Sc 59', '01911000004', 'ACTIVE'),
  ('PFYDP005', 'Rafiq Ahmed',      'rafiq@student.uiu.ac.bd',    SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'CSE', 'B.Sc 59', '01911000005', 'ACTIVE'),
  ('PFYDP006', 'Samira Begum',     'samira@student.uiu.ac.bd',   SHA2('pre123',256), 'PRE_FYDP_STUDENT', 'EEE', 'B.Sc 58', '01911000006', 'ACTIVE');

-- Pre-FYDP Profiles
INSERT INTO pre_fydp_profiles
  (user_id, bio, cgpa, skills, domain_interests, preferred_role, github_url, linkedin_url, target_trimester, availability_status, profile_strength)
VALUES
  ((SELECT user_id FROM users WHERE university_id='PFYDP001'), 'Full-stack developer passionate about AI and ML projects.', 3.65,
   '["Python","React","Node.js","MySQL","TensorFlow"]', '["AI","ML","Software Engineering"]', 'Full-stack Developer',
   'https://github.com/yusufkhan', 'https://linkedin.com/in/yusuf-khan', 'Spring 2026', 'LOOKING', 71),
  ((SELECT user_id FROM users WHERE university_id='PFYDP002'), 'Frontend specialist with design skills. Love building beautiful UIs.', 3.52,
   '["React","Vue.js","Figma","UI/UX","CSS"]', '["Software Engineering","Mobile Application"]', 'Frontend Developer',
   'https://github.com/zainabali', 'https://linkedin.com/in/zainab-ali', 'Spring 2026', 'IN_TEAM', 85),
  ((SELECT user_id FROM users WHERE university_id='PFYDP003'), 'Backend developer with cloud and DevOps experience.', 3.78,
   '["Java","Spring Boot","Docker","AWS","PostgreSQL"]', '["Software Engineering","Cloud Computing"]', 'Backend Developer',
   'https://github.com/hamzaiqbal', 'https://linkedin.com/in/hamza-iqbal', 'Spring 2026', 'IN_TEAM', 90),
  ((SELECT user_id FROM users WHERE university_id='PFYDP004'), 'ML researcher interested in NLP and computer vision.', 3.88,
   '["Python","TensorFlow","PyTorch","NLP","OpenCV"]', '["AI","NLP","Data Analytics"]', 'ML Engineer',
   'https://github.com/nusratjahan', NULL, 'Spring 2026', 'LOOKING', 60),
  ((SELECT user_id FROM users WHERE university_id='PFYDP005'), 'Cybersecurity enthusiast with CTF experience.', 3.45,
   '["Python","Kali Linux","Wireshark","Networking"]', '["Cybersecurity","IoT"]', 'Security Analyst',
   NULL, NULL, 'Spring 2026', 'LOOKING', 40),
  ((SELECT user_id FROM users WHERE university_id='PFYDP006'), 'IoT and embedded systems developer.', 3.30,
   '["C++","Arduino","Raspberry Pi","MQTT","Python"]', '["IoT","Hardware"]', 'Embedded Developer',
   NULL, NULL, 'Spring 2026', 'LOOKING', 35);

-- Pre-FYDP Groups (sample groups for dashboard)
INSERT INTO pre_fydp_groups
  (group_name, domain, description, required_skills, max_members, github_url, created_by, group_status)
VALUES
  ('NeuralVerse', 'AI', 'Building an AI-powered virtual study assistant using GPT models and RAG.',
   '["Python","TensorFlow","React","NLP"]', 5,
   'https://github.com/neuralverse', (SELECT user_id FROM users WHERE university_id='PFYDP002'), 'OPEN'),
  ('CyberShield', 'Cybersecurity', 'AI-driven intrusion detection system for university networks.',
   '["Python","MySQL","Backend","Networking"]', 5,
   NULL, (SELECT user_id FROM users WHERE university_id='PFYDP005'), 'OPEN'),
  ('MediCare AI', 'ML', 'Predictive diagnostics using federated learning.',
   '["Python","TensorFlow","Frontend"]', 4,
   NULL, (SELECT user_id FROM users WHERE university_id='PFYDP004'), 'OPEN'),
  ('CloudForge', 'Software Engineering', 'Containerized micro-services platform for student startups.',
   '["Backend","Node.js","MySQL","Docker"]', 5,
   'https://github.com/cloudforge', (SELECT user_id FROM users WHERE university_id='PFYDP003'), 'OPEN'),
  ('DataPulse', 'Data Analytics', 'Real-time analytics dashboard for e-commerce platforms.',
   '["Python","React","MongoDB","D3.js"]', 4,
   NULL, (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'OPEN'),
  ('SmartCampus', 'IoT', 'IoT-based smart campus management system with sensors.',
   '["C++","Arduino","React","MQTT"]', 5,
   NULL, (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'FULL');

-- Pre-FYDP Group Members
INSERT INTO pre_fydp_group_members (group_id, user_id, member_role)
VALUES
  -- NeuralVerse: Zainab (lead) + 3 others = 4/5
  (1, (SELECT user_id FROM users WHERE university_id='PFYDP002'), 'Lead'),
  (1, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'Backend'),
  (1, (SELECT user_id FROM users WHERE university_id='PFYDP004'), 'ML Engineer'),
  (1, (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'Hardware'),
  -- MediCare AI: Nusrat (lead) + 1 = 2/4
  (3, (SELECT user_id FROM users WHERE university_id='PFYDP004'), 'Lead'),
  (3, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'Frontend'),
  -- CloudForge: Hamza (lead) + 2 = 3/5
  (4, (SELECT user_id FROM users WHERE university_id='PFYDP003'), 'Lead'),
  (4, (SELECT user_id FROM users WHERE university_id='PFYDP002'), 'Frontend'),
  (4, (SELECT user_id FROM users WHERE university_id='PFYDP005'), 'Security'),
  -- SmartCampus: Full (5/5)
  (6, (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'Lead'),
  (6, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'Backend'),
  (6, (SELECT user_id FROM users WHERE university_id='PFYDP002'), 'Frontend'),
  (6, (SELECT user_id FROM users WHERE university_id='PFYDP003'), 'DevOps'),
  (6, (SELECT user_id FROM users WHERE university_id='PFYDP004'), 'Tester');

-- Pre-FYDP Join Requests (for "My Requests" page)
INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message, request_status)
VALUES
  (2, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'JOIN_REQUEST', 'I have experience with Python and networking. Would love to join!', 'PENDING'),
  (5, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'JOIN_REQUEST', 'Interested in data analytics!', 'PENDING'),
  (1, (SELECT user_id FROM users WHERE university_id='PFYDP005'), 'JOIN_REQUEST', 'Can I join your AI project?', 'PENDING'),
  (4, (SELECT user_id FROM users WHERE university_id='PFYDP001'), 'JOIN_REQUEST', 'Full-stack developer here!', 'ACCEPTED'),
  (3, (SELECT user_id FROM users WHERE university_id='PFYDP006'), 'JOIN_REQUEST', 'IoT background, interested in health tech', 'REJECTED');

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 — TRIGGERS
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER $$

-- ============================================================================
-- TRIGGER #1 — 100% APPROVAL ESCALATION ENGINE
-- Table: weekly_progress_reports (AFTER UPDATE)
-- Purpose: When ALL members of a group have APPROVED status for a given week,
--          automatically insert an escalation record into course_teacher_inbox.
-- This is the most critical trigger in the entire system.
-- ============================================================================
CREATE TRIGGER trg_after_wpr_approve_escalate
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    -- Variables to hold counts
    DECLARE v_total_members   INT DEFAULT 0;
    DECLARE v_approved_count  INT DEFAULT 0;

    -- Only execute escalation logic when supervisor_status changes TO 'APPROVED'
    -- This avoids unnecessary computation on unrelated updates
    IF NEW.supervisor_status = 'APPROVED' AND OLD.supervisor_status != 'APPROVED' THEN

        -- Step 1: Count total active members in this group
        SELECT COUNT(*)
          INTO v_total_members
          FROM group_members
         WHERE group_id = NEW.group_id;

        -- Step 2: Count how many members have APPROVED reports this specific week
        SELECT COUNT(*)
          INTO v_approved_count
          FROM weekly_progress_reports
         WHERE group_id       = NEW.group_id
           AND week_no        = NEW.week_no
           AND supervisor_status = 'APPROVED'
           AND is_active      = 1;

        -- Step 3: CRITICAL CHECK — All members approved AND counts match
        -- v_total_members must be > 0 to avoid edge-case on empty groups
        IF v_total_members > 0 AND v_approved_count = v_total_members THEN

            -- Step 4: Prevent duplicate escalation using INSERT IGNORE
            -- The UNIQUE KEY uq_inbox_group_week ensures idempotency
            INSERT IGNORE INTO course_teacher_inbox
                (group_id, week_no, escalated_at, escalation_status)
            VALUES
                (NEW.group_id, NEW.week_no, NOW(), 'PENDING_REVIEW');

            -- Step 5: Notify all group members about successful escalation
            -- This notifies every member in the group for transparency
            INSERT INTO notifications
                (user_id, notification_type, message, reference_entity_id, reference_entity_type)
            SELECT
                gm.student_id,
                'ESCALATION_COMPLETE',
                CONCAT('Week ', NEW.week_no, ' reports for your group have been escalated to the Course Teacher for review.'),
                NEW.group_id,
                'course_teacher_inbox'
            FROM group_members gm
            WHERE gm.group_id = NEW.group_id;

        END IF;
    END IF;
END$$


-- ============================================================================
-- TRIGGER #2 — SUPERVISOR CAPACITY LIMIT (BEFORE INSERT)
-- Table: project_groups (BEFORE INSERT)
-- Rule: A supervisor CANNOT supervise more than 3 groups in the SAME FYDP stage.
-- ============================================================================
CREATE TRIGGER trg_before_group_insert_supervisor_limit
BEFORE INSERT ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_existing_count INT DEFAULT 0;

    -- Count how many ACTIVE groups this supervisor already has in the same stage
    SELECT COUNT(*)
      INTO v_existing_count
      FROM project_groups
     WHERE supervisor_id     = NEW.supervisor_id
       AND current_stage_id  = NEW.current_stage_id
       AND is_active         = 1
       AND project_status    != 'DROPPED';

    -- Reject if limit exceeded
    IF v_existing_count >= 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SUPERVISOR CAPACITY EXCEEDED: Max 3 active groups per stage. Reassign to another supervisor.';
    END IF;
END$$


-- ============================================================================
-- TRIGGER #3 — SUPERVISOR CAPACITY LIMIT (BEFORE UPDATE)
-- Table: project_groups (BEFORE UPDATE)
-- Same rule as above but applied when supervisor or stage is changed.
-- ============================================================================
CREATE TRIGGER trg_before_group_update_supervisor_limit
BEFORE UPDATE ON project_groups
FOR EACH ROW
BEGIN
    DECLARE v_existing_count INT DEFAULT 0;

    -- Only run check if supervisor or stage is being changed
    IF NEW.supervisor_id != OLD.supervisor_id OR NEW.current_stage_id != OLD.current_stage_id THEN

        SELECT COUNT(*)
          INTO v_existing_count
          FROM project_groups
         WHERE supervisor_id     = NEW.supervisor_id
           AND current_stage_id  = NEW.current_stage_id
           AND is_active         = 1
           AND project_status    != 'DROPPED'
           -- Exclude the current row being updated to avoid self-counting
           AND group_id          != NEW.group_id;

        IF v_existing_count >= 3 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'SUPERVISOR CAPACITY EXCEEDED: Max 3 active groups per stage. Reassignment rejected.';
        END IF;
    END IF;
END$$


-- ============================================================================
-- TRIGGER #4 — PREVENT DUPLICATE PENDING INVITATIONS
-- Table: matchmaking_team_invitations (BEFORE INSERT)
-- Rule: No two PENDING invitations can exist between the same student pair
--       in either direction (A→B and B→A should also be prevented).
-- ============================================================================
CREATE TRIGGER trg_before_invitation_insert_dedup
BEFORE INSERT ON matchmaking_team_invitations
FOR EACH ROW
BEGIN
    DECLARE v_pending_count INT DEFAULT 0;

    -- RULE 1: Prevent self-invitation (moved here from CHECK constraint)
    IF NEW.sender_student_id = NEW.receiver_student_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SELF INVITATION ERROR: A student cannot send a team invitation to themselves.';
    END IF;

    -- RULE 2: Check both directions: A→B and B→A
    SELECT COUNT(*)
      INTO v_pending_count
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
-- TRIGGER #5 — AUDIT LOG ON REPORT UPDATES
-- Table: weekly_progress_reports (AFTER UPDATE)
-- Purpose: Preserve a full immutable audit trail of all supervisor decisions.
-- ============================================================================
CREATE TRIGGER trg_after_wpr_audit_log
AFTER UPDATE ON weekly_progress_reports
FOR EACH ROW
BEGIN
    -- Log only meaningful status changes to avoid audit log bloat
    IF NEW.supervisor_status != OLD.supervisor_status THEN
        INSERT INTO audit_log
            (table_name, operation, record_id, old_data, new_data)
        VALUES (
            'weekly_progress_reports',
            'UPDATE',
            NEW.report_id,
            JSON_OBJECT(
                'supervisor_status',   OLD.supervisor_status,
                'supervisor_feedback', OLD.supervisor_feedback,
                'supervisor_signed_at',OLD.supervisor_signed_at
            ),
            JSON_OBJECT(
                'supervisor_status',   NEW.supervisor_status,
                'supervisor_feedback', NEW.supervisor_feedback,
                'supervisor_signed_at',NEW.supervisor_signed_at
            )
        );
    END IF;
END$$


-- ============================================================================
-- TRIGGER #6 — AUTO SET STUDENT AVAILABILITY ON INVITATION ACCEPTANCE
-- Table: matchmaking_team_invitations (AFTER UPDATE)
-- Purpose: When an invitation is ACCEPTED, auto-update receiver's availability.
-- ============================================================================
CREATE TRIGGER trg_after_invitation_accept_availability
AFTER UPDATE ON matchmaking_team_invitations
FOR EACH ROW
BEGIN
    IF NEW.invitation_status = 'ACCEPTED' AND OLD.invitation_status = 'PENDING' THEN

        -- Mark receiver as IN_TEAM (they accepted and joined a team)
        UPDATE student_profiles
           SET availability_status = 'IN_TEAM',
               updated_at          = NOW()
         WHERE student_id = NEW.receiver_student_id;

        -- Notify the sender that the invitation was accepted
        INSERT INTO notifications
            (user_id, notification_type, message, reference_entity_id, reference_entity_type)
        VALUES (
            NEW.sender_student_id,
            'INVITATION_ACCEPTED',
            CONCAT('Your team invitation has been accepted! You can now finalize your group.'),
            NEW.invitation_id,
            'matchmaking_team_invitations'
        );

    ELSEIF NEW.invitation_status = 'REJECTED' AND OLD.invitation_status = 'PENDING' THEN

        -- Notify sender of rejection
        INSERT INTO notifications
            (user_id, notification_type, message, reference_entity_id, reference_entity_type)
        VALUES (
            NEW.sender_student_id,
            'INVITATION_REJECTED',
            'Your team invitation was declined. Consider inviting other students.',
            NEW.invitation_id,
            'matchmaking_team_invitations'
        );

    END IF;
END$$


DELIMITER ;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6 — STORED PROCEDURES
-- ─────────────────────────────────────────────────────────────────────────────

DELIMITER $$

-- ============================================================================
-- STORED PROCEDURE #1 — BULK CSV IMPORT ENGINE
-- Name: sp_bulk_import_ucam_groups
-- Purpose: Process all rows in ucam_import_staging, validate each row,
--          create groups and memberships, and log failures to import_error_logs.
-- ============================================================================
CREATE PROCEDURE sp_bulk_import_ucam_groups(
    IN p_import_batch_id VARCHAR(50)
)
BEGIN
    -- ── Cursor variables ──────────────────────────────────────────────────
    DECLARE v_raw_student_uid        VARCHAR(50);
    DECLARE v_raw_group_code         VARCHAR(50);
    DECLARE v_raw_supervisor_uid     VARCHAR(50);
    DECLARE v_raw_stage_name         VARCHAR(50);
    DECLARE v_raw_project_title      VARCHAR(300);
    DECLARE v_raw_domain_name        VARCHAR(100);
    DECLARE v_staging_id             INT;

    -- ── Resolved ID variables ──────────────────────────────────────────────
    DECLARE v_student_id             INT UNSIGNED DEFAULT NULL;
    DECLARE v_supervisor_id          INT UNSIGNED DEFAULT NULL;
    DECLARE v_stage_id               INT UNSIGNED DEFAULT NULL;
    DECLARE v_domain_id              INT UNSIGNED DEFAULT NULL;
    DECLARE v_group_id               INT UNSIGNED DEFAULT NULL;

    -- ── Control variables ─────────────────────────────────────────────────
    DECLARE v_row_count              INT DEFAULT 0;
    DECLARE v_success_count          INT DEFAULT 0;
    DECLARE v_error_count            INT DEFAULT 0;
    DECLARE v_done                   INT DEFAULT 0;
    DECLARE v_error_msg              VARCHAR(500);

    -- ── Cursor over staging table for current batch ───────────────────────
    DECLARE cur_staging CURSOR FOR
        SELECT staging_id, raw_student_university_id, raw_group_code,
               raw_supervisor_university_id, raw_stage_name,
               raw_project_title, raw_domain_name
          FROM ucam_import_staging
         WHERE import_batch_id = p_import_batch_id;

    -- ── Continue handler — logs error and moves to next row ───────────────
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;
        -- Log the failed row
        INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
        VALUES (
            v_row_count,
            v_error_msg,
            CONCAT('Group:', v_raw_group_code, '|Student:', v_raw_student_uid,
                   '|Supervisor:', v_raw_supervisor_uid),
            NOW()
        );
        SET v_error_count = v_error_count + 1;
        ROLLBACK;
    END;

    OPEN cur_staging;

    -- ── Row-by-row processing loop ─────────────────────────────────────────
    import_loop: LOOP
        FETCH cur_staging INTO
            v_staging_id, v_raw_student_uid, v_raw_group_code,
            v_raw_supervisor_uid, v_raw_stage_name,
            v_raw_project_title, v_raw_domain_name;

        IF v_done THEN
            LEAVE import_loop;
        END IF;

        SET v_row_count = v_row_count + 1;

        -- ── Reset resolved IDs for this iteration (prevents stale values) ──
        SET v_student_id = NULL;
        SET v_supervisor_id = NULL;
        SET v_stage_id = NULL;
        SET v_domain_id = NULL;
        SET v_group_id = NULL;

        -- ── Begin per-row transaction ──────────────────────────────────────
        START TRANSACTION;

        -- Validate: Student must exist and be ACTIVE
        SELECT user_id INTO v_student_id
          FROM users
         WHERE university_id = v_raw_student_uid
           AND role          = 'STUDENT'
           AND account_status = 'ACTIVE'
         LIMIT 1;

        SET v_done = 0;  -- Reset NOT FOUND flag (prevent cursor exit)

        IF v_student_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count,
                    CONCAT('VALIDATION ERROR: Student not found or inactive — UID: ', v_raw_student_uid),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1;
            ROLLBACK;
            ITERATE import_loop;
        END IF;

        -- Validate: Supervisor must exist and be ACTIVE
        SELECT user_id INTO v_supervisor_id
          FROM users
         WHERE university_id = v_raw_supervisor_uid
           AND role          = 'SUPERVISOR'
           AND account_status = 'ACTIVE'
         LIMIT 1;

        SET v_done = 0;  -- Reset NOT FOUND flag (prevent cursor exit)

        IF v_supervisor_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count,
                    CONCAT('VALIDATION ERROR: Supervisor not found or inactive — UID: ', v_raw_supervisor_uid),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1;
            ROLLBACK;
            ITERATE import_loop;
        END IF;

        -- Validate: Stage must exist
        SELECT stage_id INTO v_stage_id
          FROM fydp_stages
         WHERE stage_name = v_raw_stage_name
         LIMIT 1;

        SET v_done = 0;  -- Reset NOT FOUND flag (prevent cursor exit)

        IF v_stage_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count,
                    CONCAT('VALIDATION ERROR: Invalid FYDP stage name — ', v_raw_stage_name),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1;
            ROLLBACK;
            ITERATE import_loop;
        END IF;

        -- Validate: Domain must exist
        SELECT domain_id INTO v_domain_id
          FROM project_domains
         WHERE domain_name = v_raw_domain_name
         LIMIT 1;

        SET v_done = 0;  -- Reset NOT FOUND flag (prevent cursor exit)

        IF v_domain_id IS NULL THEN
            INSERT INTO import_error_logs (error_row, error_message, raw_data, logged_at)
            VALUES (v_row_count,
                    CONCAT('VALIDATION ERROR: Project domain not found — ', v_raw_domain_name),
                    v_raw_group_code, NOW());
            SET v_error_count = v_error_count + 1;
            ROLLBACK;
            ITERATE import_loop;
        END IF;

        -- Check for duplicate group code
        IF EXISTS (SELECT 1 FROM project_groups WHERE group_code = v_raw_group_code) THEN

            -- Group exists — only add member if not already added
            SELECT group_id INTO v_group_id
              FROM project_groups
             WHERE group_code = v_raw_group_code
             LIMIT 1;

            IF NOT EXISTS (
                SELECT 1 FROM group_members
                 WHERE group_id  = v_group_id
                   AND student_id = v_student_id
            ) THEN
                INSERT INTO group_members (group_id, student_id, member_role)
                VALUES (v_group_id, v_student_id, 'DEVELOPER');
            END IF;

        ELSE
            -- Create the group
            INSERT INTO project_groups
                (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_code)
            VALUES
                (v_raw_group_code, v_raw_project_title, v_domain_id, v_supervisor_id, v_stage_id, 'IMPORT');

            SET v_group_id = LAST_INSERT_ID();

            -- Add the member
            INSERT INTO group_members (group_id, student_id, member_role)
            VALUES (v_group_id, v_student_id, 'DEVELOPER');

        END IF;

        COMMIT;
        SET v_success_count = v_success_count + 1;

    END LOOP import_loop;

    CLOSE cur_staging;

    -- ── Final import summary ──────────────────────────────────────────────
    SELECT
        v_row_count    AS total_rows_processed,
        v_success_count AS successful_imports,
        v_error_count  AS failed_imports,
        p_import_batch_id AS batch_id;

END$$


-- ============================================================================
-- STORED PROCEDURE #2 — FYDP STAGE PROMOTION ENGINE
-- Name: sp_promote_fydp_stage
-- Purpose: Promote a group from one FYDP stage to the next.
--          Detects and records any title or domain changes in topic_change_history.
--          Full transactional safety with rollback on failure.
-- ============================================================================
CREATE PROCEDURE sp_promote_fydp_stage(
    IN p_group_id         INT UNSIGNED,
    IN p_new_stage_id     INT UNSIGNED,
    IN p_new_domain_id    INT UNSIGNED,
    IN p_new_project_title VARCHAR(300),
    IN p_admin_id         INT UNSIGNED,
    IN p_change_reason    TEXT
)
BEGIN
    -- Current group state
    DECLARE v_current_stage_id     INT UNSIGNED;
    DECLARE v_current_domain_id    INT UNSIGNED;
    DECLARE v_current_title        VARCHAR(300);
    DECLARE v_current_stage_order  TINYINT;
    DECLARE v_new_stage_order      TINYINT;
    DECLARE v_title_changed        TINYINT(1) DEFAULT 0;
    DECLARE v_domain_changed       TINYINT(1) DEFAULT 0;
    DECLARE v_error_msg            VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
    END;

    START TRANSACTION;

    -- ── Step 1: Validate group exists and is active ────────────────────────
    SELECT current_stage_id, project_domain_id, project_title
      INTO v_current_stage_id, v_current_domain_id, v_current_title
      FROM project_groups
     WHERE group_id  = p_group_id
       AND is_active = 1
     LIMIT 1;

    IF v_current_stage_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PROMOTION ERROR: Group not found or is inactive.';
    END IF;

    -- ── Step 2: Validate admin exists ─────────────────────────────────────
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_admin_id AND role = 'ADMIN') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PROMOTION ERROR: Invalid admin user. Only ADMIN role can promote groups.';
    END IF;

    -- ── Step 3: Validate stage ordering (must promote forward only) ────────
    SELECT stage_order INTO v_current_stage_order
      FROM fydp_stages WHERE stage_id = v_current_stage_id;

    SELECT stage_order INTO v_new_stage_order
      FROM fydp_stages WHERE stage_id = p_new_stage_id;

    IF v_new_stage_order IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PROMOTION ERROR: Target stage does not exist.';
    END IF;

    IF v_new_stage_order <= v_current_stage_order THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PROMOTION ERROR: A group can only be promoted to a higher FYDP stage. Downgrading is not permitted.';
    END IF;

    -- ── Step 4: Detect changes ─────────────────────────────────────────────
    IF p_new_project_title IS NOT NULL AND p_new_project_title != v_current_title THEN
        SET v_title_changed = 1;
    END IF;

    IF p_new_domain_id IS NOT NULL AND p_new_domain_id != v_current_domain_id THEN
        SET v_domain_changed = 1;
    END IF;

    -- ── Step 5: Audit log for title/domain changes ─────────────────────────
    IF v_title_changed = 1 OR v_domain_changed = 1 THEN
        INSERT INTO topic_change_history
            (group_id, old_domain_id, new_domain_id,
             old_project_title, new_project_title,
             changed_by_admin, change_reason, changed_at)
        VALUES (
            p_group_id,
            v_current_domain_id,
            IF(v_domain_changed = 1, p_new_domain_id, v_current_domain_id),
            v_current_title,
            IF(v_title_changed  = 1, p_new_project_title, v_current_title),
            p_admin_id,
            p_change_reason,
            NOW()
        );
    END IF;

    -- ── Step 6: Update project_groups ─────────────────────────────────────
    UPDATE project_groups
       SET current_stage_id  = p_new_stage_id,
           project_domain_id = IF(p_new_domain_id IS NOT NULL, p_new_domain_id, project_domain_id),
           project_title     = IF(p_new_project_title IS NOT NULL AND p_new_project_title != '', p_new_project_title, project_title),
           updated_at        = NOW()
     WHERE group_id = p_group_id;

    -- ── Step 7: Notify all group members of promotion ─────────────────────
    INSERT INTO notifications
        (user_id, notification_type, message, reference_entity_id, reference_entity_type)
    SELECT
        gm.student_id,
        'STAGE_PROMOTED',
        CONCAT('Congratulations! Your project group has been promoted to ',
               (SELECT stage_name FROM fydp_stages WHERE stage_id = p_new_stage_id),
               '.'),
        p_group_id,
        'project_groups'
    FROM group_members gm
    WHERE gm.group_id = p_group_id;

    COMMIT;

    -- ── Step 8: Return summary ─────────────────────────────────────────────
    SELECT
        p_group_id                                            AS group_id,
        (SELECT group_code FROM project_groups WHERE group_id = p_group_id) AS group_code,
        (SELECT stage_name FROM fydp_stages WHERE stage_id = v_current_stage_id) AS promoted_from,
        (SELECT stage_name FROM fydp_stages WHERE stage_id = p_new_stage_id)     AS promoted_to,
        v_title_changed                                       AS title_was_changed,
        v_domain_changed                                      AS domain_was_changed,
        NOW()                                                 AS promoted_at;

END$$


-- ============================================================================
-- STORED PROCEDURE #3 — SUPERVISOR APPROVAL WORKFLOW
-- Name: sp_approve_weekly_report
-- Purpose: Supervisor approves or rejects a report with feedback.
--          The AFTER UPDATE trigger then fires automatically if full approval.
-- ============================================================================
CREATE PROCEDURE sp_approve_weekly_report(
    IN p_report_id       INT UNSIGNED,
    IN p_supervisor_id   INT UNSIGNED,
    IN p_new_status      ENUM('APPROVED','REJECTED'),
    IN p_feedback        TEXT
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

    -- Fetch group supervisor to validate authorization
    SELECT pg.supervisor_id, wpr.group_id
      INTO v_group_supervisor_id, v_report_group_id
      FROM weekly_progress_reports wpr
      JOIN project_groups pg ON pg.group_id = wpr.group_id
     WHERE wpr.report_id = p_report_id
     LIMIT 1;

    -- Authorization check
    IF v_group_supervisor_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'APPROVAL ERROR: Report or associated group not found.';
    END IF;

    IF v_group_supervisor_id != p_supervisor_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'AUTHORIZATION ERROR: You are not the assigned supervisor for this group.';
    END IF;

    -- Update the report (this will fire trg_after_wpr_approve_escalate)
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
-- FUNCTION #1 — GET GROUP APPROVAL PERCENTAGE FOR A WEEK
-- Returns what percentage of members have approved reports for a given week.
-- ============================================================================
CREATE FUNCTION fn_get_group_approval_pct(
    p_group_id INT UNSIGNED,
    p_week_no  TINYINT UNSIGNED
)
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_approved INT DEFAULT 0;

    SELECT COUNT(*) INTO v_total
      FROM group_members WHERE group_id = p_group_id;

    SELECT COUNT(*) INTO v_approved
      FROM weekly_progress_reports
     WHERE group_id = p_group_id
       AND week_no  = p_week_no
       AND supervisor_status = 'APPROVED';

    IF v_total = 0 THEN
        RETURN 0.00;
    END IF;

    RETURN ROUND((v_approved / v_total) * 100, 2);
END$$


-- ============================================================================
-- FUNCTION #2 — CHECK IF STUDENT IS IN ACTIVE GROUP
-- Returns 1 if student is currently in an active group, 0 otherwise.
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
     WHERE gm.student_id  = p_student_id
       AND pg.is_active   = 1
       AND pg.project_status = 'ACTIVE';

    RETURN IF(v_count > 0, 1, 0);
END$$


DELIMITER ;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 — VIEWS (BONUS ENTERPRISE FEATURE)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── VIEW: Group progress summary
CREATE OR REPLACE VIEW vw_group_progress_summary AS
SELECT
    pg.group_id,
    pg.group_code,
    pg.project_title,
    pd.domain_name,
    u.full_name      AS supervisor_name,
    fs.stage_name    AS current_stage,
    pg.section_code,
    pg.project_status,
    COUNT(DISTINCT gm.student_id)        AS total_members,
    COUNT(DISTINCT wpr.report_id)        AS total_reports_submitted,
    SUM(CASE WHEN wpr.supervisor_status = 'APPROVED' THEN 1 ELSE 0 END) AS approved_reports,
    SUM(CASE WHEN wpr.supervisor_status = 'PENDING'  THEN 1 ELSE 0 END) AS pending_reports,
    SUM(CASE WHEN wpr.supervisor_status = 'REJECTED' THEN 1 ELSE 0 END) AS rejected_reports
FROM project_groups pg
JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
JOIN users u             ON u.user_id   = pg.supervisor_id
JOIN fydp_stages fs      ON fs.stage_id = pg.current_stage_id
LEFT JOIN group_members gm  ON gm.group_id = pg.group_id
LEFT JOIN weekly_progress_reports wpr ON wpr.group_id = pg.group_id
WHERE pg.is_active = 1
GROUP BY pg.group_id, pg.group_code, pg.project_title,
         pd.domain_name, u.full_name, fs.stage_name,
         pg.section_code, pg.project_status;

-- ── VIEW: Supervisor workload overview
CREATE OR REPLACE VIEW vw_supervisor_workload AS
SELECT
    u.user_id        AS supervisor_id,
    u.full_name      AS supervisor_name,
    u.department,
    fs.stage_name,
    COUNT(pg.group_id) AS total_groups_in_stage,
    3 - COUNT(pg.group_id) AS remaining_capacity
FROM users u
JOIN project_groups pg ON pg.supervisor_id = u.user_id AND pg.is_active = 1 AND pg.project_status != 'DROPPED'
JOIN fydp_stages fs    ON fs.stage_id = pg.current_stage_id
WHERE u.role = 'SUPERVISOR'
GROUP BY u.user_id, u.full_name, u.department, fs.stage_name;

-- ── VIEW: Student matchmaking board
CREATE OR REPLACE VIEW vw_student_matchmaking_board AS
SELECT
    u.user_id,
    u.full_name,
    u.department,
    u.batch,
    sp.cgpa,
    sp.preferred_team_role,
    sp.availability_status,
    sp.github_url,
    sp.linkedin_url,
    GROUP_CONCAT(DISTINCT s.skill_name ORDER BY s.skill_name SEPARATOR ', ')  AS skills,
    GROUP_CONCAT(DISTINCT pd.domain_name ORDER BY pd.domain_name SEPARATOR ', ') AS domain_interests
FROM users u
JOIN student_profiles sp     ON sp.student_id  = u.user_id
LEFT JOIN student_skills ss  ON ss.student_id  = u.user_id
LEFT JOIN skills s           ON s.skill_id     = ss.skill_id
LEFT JOIN student_domain_interests sdi ON sdi.student_id = u.user_id
LEFT JOIN project_domains pd ON pd.domain_id   = sdi.domain_id
WHERE u.role           = 'STUDENT'
  AND u.account_status = 'ACTIVE'
  AND sp.availability_status = 'LOOKING'
GROUP BY u.user_id, u.full_name, u.department, u.batch,
         sp.cgpa, sp.preferred_team_role, sp.availability_status,
         sp.github_url, sp.linkedin_url;

-- ── VIEW: Course teacher inbox — pending reviews
CREATE OR REPLACE VIEW vw_pending_course_teacher_inbox AS
SELECT
    ci.inbox_id,
    ci.group_id,
    pg.group_code,
    pg.project_title,
    pg.section_code,
    fs.stage_name,
    ci.week_no,
    ci.escalated_at,
    ci.escalation_status,
    DATEDIFF(NOW(), ci.escalated_at) AS days_waiting
FROM course_teacher_inbox ci
JOIN project_groups pg ON pg.group_id = ci.group_id
JOIN fydp_stages fs    ON fs.stage_id = pg.current_stage_id
WHERE ci.escalation_status = 'PENDING_REVIEW'
ORDER BY ci.escalated_at ASC;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 — TEST EXECUTION QUERIES & SCENARIOS
-- ─────────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 1: APPROVE FINAL MEMBER REPORT → TRIGGER ESCALATION
-- Goal: Approve the last PENDING report in group 1, week 1.
--       This should fire trg_after_wpr_approve_escalate and
--       auto-insert into course_teacher_inbox.
-- ══════════════════════════════════════════════════════════════════════════════

-- Before: Check current approval status for group 1, week 1
SELECT student_id, supervisor_status
  FROM weekly_progress_reports
 WHERE group_id = 1 AND week_no = 1;

-- Before: Confirm inbox is empty
SELECT * FROM course_teacher_inbox WHERE group_id = 1 AND week_no = 1;

-- ACTION: Supervisor (SUP001 = user_id 2) approves the last pending report
CALL sp_approve_weekly_report(4, 2, 'APPROVED', 'Excellent DB schema design. Well documented.');

-- After: Inbox should now have an escalation record
SELECT * FROM course_teacher_inbox WHERE group_id = 1 AND week_no = 1;

-- After: Group notifications
SELECT * FROM notifications WHERE reference_entity_id = 1 ORDER BY created_at DESC;

-- After: Verify approval percentage using function
SELECT fn_get_group_approval_pct(1, 1) AS approval_pct_group1_week1;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 2: SUPERVISOR CAPACITY LIMIT ENFORCEMENT
-- Goal: Attempt to add a 4th group to supervisor 2 in FYDP-1.
--       Should FAIL with SIGNAL error.
-- ══════════════════════════════════════════════════════════════════════════════

-- Before: Check current load of supervisor 2 in stage 1
SELECT supervisor_id, current_stage_id, COUNT(*) AS group_count
  FROM project_groups
 WHERE supervisor_id = 2 AND current_stage_id = 1 AND is_active = 1
 GROUP BY supervisor_id, current_stage_id;

-- ACTION: Try to add 4th group (should FAIL — supervisor 2 already has 2, add 1 more first)
INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_code)
VALUES
  ('UIU-G004', 'Test Group 4', 1, 2, 1, 'CSE-D');

INSERT INTO project_groups
  (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_code)
VALUES
  ('UIU-G005', 'Test Group 5 — Should Fail', 1, 2, 1, 'CSE-E');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 3: DUPLICATE WEEKLY REPORT ENFORCEMENT
-- Goal: Try to submit a second report for week 1 by student 7 in group 1.
--       Should FAIL due to UNIQUE KEY uq_report_weekly.
-- ══════════════════════════════════════════════════════════════════════════════

INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content, supervisor_status)
VALUES
  (1, 7, 1, 'Duplicate Week 1 Report', 'This should fail!', 'PENDING');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 4: FYDP PROMOTION WITH TOPIC CHANGE
-- Goal: Promote group 1 from FYDP-1 to FYDP-2 with a new domain and title.
--       Should insert into topic_change_history.
-- ══════════════════════════════════════════════════════════════════════════════

-- Before: Check current state
SELECT group_id, project_title, project_domain_id, current_stage_id
  FROM project_groups WHERE group_id = 1;

-- Before: Audit log should be empty for this group
SELECT * FROM topic_change_history WHERE group_id = 1;

-- ACTION: Admin promotes group 1 to FYDP-2 with new title and domain
CALL sp_promote_fydp_stage(
    1,          -- group_id
    2,          -- p_new_stage_id (FYDP-2)
    1,          -- p_new_domain_id (Artificial Intelligence)
    'BanglaBot 2.0: Advanced AI Dialogue System for Bangla',  -- new title
    1,          -- p_admin_id (admin user)
    'Group refined scope during FYDP-1. Shifting from pure NLP to AI Dialogue Systems.'
);

-- After: Confirm stage updated
SELECT group_id, project_title, project_domain_id, current_stage_id
  FROM project_groups WHERE group_id = 1;

-- After: Audit trail preserved
SELECT * FROM topic_change_history WHERE group_id = 1;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 5: BULK IMPORT ENGINE
-- Goal: Insert staging data and run the import procedure.
-- ══════════════════════════════════════════════════════════════════════════════

-- Insert sample staging rows
INSERT INTO ucam_import_staging
  (raw_student_university_id, raw_group_code, raw_supervisor_university_id,
   raw_stage_name, raw_project_title, raw_domain_name, import_batch_id)
VALUES
  ('STU001', 'UIU-IMPORT-001', 'SUP003', 'FYDP-1', 'Smart IoT Health System', 'IoT',                'BATCH-2025-01'),
  ('STU002', 'UIU-IMPORT-001', 'SUP003', 'FYDP-1', 'Smart IoT Health System', 'IoT',                'BATCH-2025-01'),
  ('INVALID_UID', 'UIU-IMPORT-001', 'SUP003', 'FYDP-1', 'Should fail', 'IoT',                       'BATCH-2025-01'), -- Invalid student
  ('STU003', 'UIU-IMPORT-001', 'BAD_SUP', 'FYDP-1', 'Smart IoT Health System', 'IoT',               'BATCH-2025-01'), -- Invalid supervisor
  ('STU004', 'UIU-IMPORT-002', 'SUP003', 'INVALID-STAGE', 'FinTech App', 'FinTech',                  'BATCH-2025-01'); -- Invalid stage

-- Run the import
CALL sp_bulk_import_ucam_groups('BATCH-2025-01');

-- Check results
SELECT * FROM import_error_logs ORDER BY logged_at DESC;
SELECT * FROM project_groups WHERE group_code LIKE 'UIU-IMPORT%';

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 6: DUPLICATE INVITATION PREVENTION
-- Goal: Try to send a reverse invitation while a PENDING one exists (11→12).
--       Should FAIL due to trigger trg_before_invitation_insert_dedup.
-- ══════════════════════════════════════════════════════════════════════════════

INSERT INTO matchmaking_team_invitations
  (sender_student_id, receiver_student_id, invitation_message)
VALUES
  (12, 11, 'This reverse PENDING invitation should be blocked by trigger!');

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 7: MATCHMAKING VIEWS & FUNCTION QUERIES
-- ══════════════════════════════════════════════════════════════════════════════

-- View all students looking for teams (matchmaking board)
SELECT * FROM vw_student_matchmaking_board;

-- View supervisor workload
SELECT * FROM vw_supervisor_workload;

-- View all group progress
SELECT * FROM vw_group_progress_summary;

-- Check pending course teacher inbox
SELECT * FROM vw_pending_course_teacher_inbox;

-- Is student 7 in an active group?
SELECT fn_is_student_in_active_group(7) AS is_in_group;

-- Get approval percentage for group 2, week 1
SELECT fn_get_group_approval_pct(2, 1) AS group2_week1_approval_pct;

-- Full audit log
SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT 20;

-- ══════════════════════════════════════════════════════════════════════════════
-- TEST SCENARIO 8: EDGE CASE — WEEK_NO CONSTRAINT
-- Goal: Try inserting a report with week_no = 0 or 53 (out of range).
-- ══════════════════════════════════════════════════════════════════════════════

INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content)
VALUES
  (2, 11, 0, 'Week 0 Report', 'This should violate CHECK constraint.');

INSERT INTO weekly_progress_reports
  (group_id, student_id, week_no, report_title, report_content)
VALUES
  (2, 11, 53, 'Week 53 Report', 'This should also violate CHECK constraint.');

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 9 — ARCHITECTURAL OPTIMIZATION NOTES
-- ─────────────────────────────────────────────────────────────────────────────

/*
═══════════════════════════════════════════════════════════════════════════════
 FYDP MANAGEMENT SYSTEM — ARCHITECTURE DECISION RECORD
 UIU DBMS Lab Project | Enterprise MySQL 8.0 Edition
═══════════════════════════════════════════════════════════════════════════════

── NORMALIZATION ──────────────────────────────────────────────────────────────

All tables satisfy BCNF (Boyce-Codd Normal Form):
  • users: PK=user_id; every attribute depends solely on user_id.
  • student_profiles: Separated from users to eliminate role-based partial dep.
  • skills, project_domains: Reference/lookup tables — fully atomic.
  • student_skills, student_domain_interests: Bridge tables using composite PKs.
  • project_groups: No transitive dependencies — supervisor_id, domain_id,
    stage_id are all direct attributes, not derived.
  • topic_change_history: Immutable append-only table — no update anomalies possible.

── ENGINE CHOICES ─────────────────────────────────────────────────────────────

  All tables use InnoDB for:
  • Full ACID transaction support
  • Row-level locking (better concurrency)
  • Foreign key enforcement
  • Crash recovery via redo log

── INDEXING RATIONALE ─────────────────────────────────────────────────────────

  1. All FK columns indexed → eliminates full table scans on JOINs.
  2. Composite index on (group_id, week_no, supervisor_status) in
     weekly_progress_reports → directly serves the escalation trigger's COUNT query.
  3. (user_id, is_read) composite index on notifications → sub-millisecond
     inbox fetch for any user.

── TRIGGER ARCHITECTURE ───────────────────────────────────────────────────────

  Triggers are designed to be:
  • IDEMPOTENT: INSERT IGNORE on course_teacher_inbox prevents duplicate escalations.
  • SURGICAL: Conditional guards (IF NEW.status != OLD.status) prevent unnecessary logic.
  • AUDITABLE: Every supervisor decision is captured in audit_log via JSON diff.
  • NON-BLOCKING: Triggers fire AFTER the main DML — no locking contention.

── SOFT DELETE STRATEGY ───────────────────────────────────────────────────────

  users and project_groups use:
  • is_active = 0 (soft flag)
  • deleted_at = TIMESTAMP
  This preserves referential integrity and audit trails while logically removing records.
  All active-data queries filter on is_active = 1.

── STORED PROCEDURE SAFETY ────────────────────────────────────────────────────

  All procedures use:
  • START TRANSACTION / COMMIT / ROLLBACK
  • EXIT HANDLER FOR SQLEXCEPTION → atomic rollback on any error
  • CONTINUE HANDLER in bulk import → row-level fault isolation
  • SIGNAL SQLSTATE '45000' for business rule violations

── SCALABILITY NOTES ──────────────────────────────────────────────────────────

  For production scale:
  • Partition weekly_progress_reports by week_no RANGE.
  • Archive audit_log to cold storage after 6 months.
  • Add READ REPLICA for supervisor dashboard queries.
  • Use connection pooling (ProxySQL) for concurrent access.
  • Add full-text index on project_title for search.

══════════════════════════════════════════════════════════════════════════════
 END OF FYDP MANAGEMENT SYSTEM SQL
 Designed to dominate the UIU DBMS Lab Showcase — Built for Full Marks
══════════════════════════════════════════════════════════════════════════════
*/
