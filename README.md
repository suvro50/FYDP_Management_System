# FYDP Management System

A full-stack web application for managing Final Year Design Projects (FYDP) at universities. Built to replace manual, paper-based workflows with a centralized platform for students, supervisors, and course teachers.

> Developed as part of the CSE curriculum at United International University (UIU), Bangladesh.

---

## The Problem It Solves

Managing FYDP projects across hundreds of students, multiple supervisors, and course teachers is chaotic without a proper system. This platform centralizes everything — team formation, weekly progress tracking, report escalation, real-time communication, and grading — in one place.

---

## Key Features

- **Role-based access control** — Students, Supervisors, Course Teachers, and Admins each have distinct dashboards and permissions
- **Team matchmaking** — Students browse profiles, filter by skills and domain interests, and send/receive team invitations
- **3-stage FYDP lifecycle** — Projects progress through FYDP-1 → FYDP-2 → FYDP-3 with stage promotion logic enforced at the database level
- **Weekly progress reports** — Students submit weekly reports; supervisors approve or reject with feedback; auto-escalation triggers notify course teachers when all group members are approved
- **Real-time group chat** — Three visibility channels: Student-only, With Supervisor, and With Teacher
- **Direct messaging** — 1-to-1 private messaging between any two users
- **Task assignment** — Supervisors assign weekly tasks with optional file attachments
- **Bulk import pipeline** — CSV-based UCAM student import with staging table and row-level error logging
- **Enterprise audit trail** — Immutable JSON diff audit log for all critical operations
- **OTP-based authentication** — Email OTP for account verification and password reset

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Node.js, Express.js |
| Database | MySQL (InnoDB, utf8mb4) |
| Frontend | EJS templating, HTML, CSS, JavaScript |
| Auth | JWT, bcrypt, OTP via email |
| File Uploads | Multer |

---

## Database Design Highlights

The schema (`database.sql`) is the core of this project — **2,581 lines** covering 6 modules:

- **Normalized to BCNF** — all transitive dependencies eliminated; JSON columns replaced with proper bridge tables (1NF fix in v2.0)
- **30+ tables** across User Management, Matchmaking, Group Management, Messaging, Pre-FYDP platform, and Import Pipeline
- **Strategic indexing** — composite indexes for common query patterns (e.g. `idx_wpr_escalation` on `(group_id, week_no, supervisor_status)`), FULLTEXT indexes on project titles and group descriptions
- **Referential integrity** — 50+ foreign key constraints with appropriate `ON DELETE` / `ON UPDATE` actions
- **Versioned schema** — schema evolved through v2.0 → v3.0 → v3.1 with documented migration scripts
- **Audit & compliance** — `audit_log` table stores before/after JSON diffs; `user_status_log` tracks account status changes via trigger

### Core Entity Relationships

```
departments → sections → users
                              ↓
                    student_profiles ←→ skills
                    student_profiles ←→ project_domains
                              ↓
                    project_groups → group_members
                              ↓
                    weekly_progress_reports
                              ↓
                    course_teacher_inbox (escalation engine)
```

---

## Project Structure

```
FYDP_Management_System/
├── config/          # Database connection and app configuration
├── middleware/      # Auth guards, role checks
├── routes/          # Express route handlers (modular by role)
├── views/           # EJS templates
├── public/          # Static assets (CSS, JS, images)
├── utils/           # Helper functions (email, OTP, file upload)
├── scripts/         # Migration scripts (versioned schema changes)
├── database.sql     # Full schema with indexes, triggers, and seed data
└── server.js        # Application entry point
```

---

## Getting Started

### Prerequisites
- Node.js v18+
- MySQL 8.0+

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/suvro50/FYDP_Management_System.git
cd FYDP_Management_System

# 2. Install dependencies
npm install

# 3. Set up environment variables
cp .env.example .env
# Edit .env with your DB credentials and email config

# 4. Create the database
mysql -u root -p < database.sql

# 5. Start the server
node server.js
```

### Environment Variables

Create a `.env` file based on `.env.example`:

```env
DB_HOST=localhost
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_NAME=fydp
JWT_SECRET=your_jwt_secret
EMAIL_USER=your_email@gmail.com
EMAIL_PASS=your_email_app_password
PORT=3000
```

---

## User Roles

| Role | Access |
|------|--------|
| `STUDENT` | Team matching, report submission, group chat, task viewing |
| `PRE_FYDP_STUDENT` | Pre-FYDP team building platform |
| `SUPERVISOR` | Group management, report approval, task assignment, escalation |
| `COURSE_TEACHER` | Inbox review, group evaluation, announcements |
| `ADMIN` | Full system access, bulk import, user management |

---

## Notable Technical Decisions

**Why BCNF over just 3NF?**
The matchmaking module has several multi-valued dependencies (skills, domain interests) that 3NF wouldn't catch. Decomposing into bridge tables (`student_skills`, `student_domain_interests`) ensures no update anomalies when a skill name changes.

**Why a staging table for imports?**
The `ucam_import_staging` table is intentionally FK-free. Raw CSV data is inserted first, then validated and promoted to production tables via a stored procedure. This separates ingestion from validation — failed rows are logged to `import_error_logs` without blocking successful rows.

**Why ENUM for `reference_entity_type` in notifications?**
Using a VARCHAR here would allow garbage table names to be inserted. The ENUM acts as a database-level constraint ensuring only valid entity types are referenced.

---

## Author

**Suvrojit** — CSE Student, United International University (UIU)  
GitHub: [@suvro50](https://github.com/suvro50)

---

## License

MIT License — feel free to use this as a reference for university management systems.
