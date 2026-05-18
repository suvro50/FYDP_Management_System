const express = require("express");
const router = express.Router();
const db = require("../config/db");
const { sendEmail } = require("../utils/email");

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

// 1. Strict Faculty & Admin Check (Accepts admin.uiu.ac.bd and uiu.ac.bd)
const isFacultyOrAdminEmail =
  /^(?!.*[0-9]{6}@)[a-zA-Z0-9._%+-]+@((cse|eee|bba|ce|ece|admin|pharmacy|bge|english|economics|env)\.)?uiu\.ac\.bd$/i;

// 2. Strict Student Check (Requires exactly 6 digits before the @)
const isStudentEmail =
  /^[a-zA-Z._]+[0-9]{6}@(bscse|bseee|bsbba|bsce|bsece|bsseds|bssmsj|bsbge|bseco)\.uiu\.ac\.bd$/i;

// 3. Catch-All Validator (Best for the main login input)
const isAnyUiuEmail = /^[a-zA-Z0-9._%+-]+@([a-z]+\.)*uiu\.ac\.bd$/i;

function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function getDashboardUrl(role) {
  switch (role) {
    case "ADMIN":
      return "/admin/dashboard";
    case "SUPERVISOR":
      return "/supervisor/dashboard";
    case "COURSE_TEACHER":
      return "/teacher/dashboard";
    case "STUDENT":
      return "/student/dashboard";
    case "PRE_FYDP_STUDENT":
      return "/pre-fydp/dashboard";
    default:
      return "/login";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /login — serve login page
// ─────────────────────────────────────────────────────────────────────────────
router.get("/login", (req, res) => {
  if (req.session?.user) {
    return res.redirect(getDashboardUrl(req.session.user.role));
  }
  res.sendFile("login.html", { root: "./views" });
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/login — authenticate user
// ─────────────────────────────────────────────────────────────────────────────
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required" });
    }

    const [rows] = await db.query(
      `SELECT u.user_id, u.university_id, u.full_name, u.email, u.role,
              d.department_name AS department, u.batch,
              u.phone, u.profile_photo, u.account_status
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.email = ? AND u.password_hash = SHA2(?, 256) AND u.is_active = 1`,
      [email, password],
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: "Invalid email or password" });
    }

    const user = rows[0];

    if (user.account_status !== "ACTIVE") {
      return res
        .status(403)
        .json({ error: "Your account has been suspended or deactivated" });
    }

    req.session.user = {
      user_id: user.user_id,
      university_id: user.university_id,
      full_name: user.full_name,
      email: user.email,
      role: user.role,
      department: user.department,
      batch: user.batch,
      phone: user.phone,
      profile_photo: user.profile_photo,
    };

    res.json({
      success: true,
      redirect: getDashboardUrl(user.role),
      user: { full_name: user.full_name, role: user.role },
    });
  } catch (err) {
    console.error("Login error:", err);
    res.status(500).json({ error: "Server error. Please try again." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/signup — register a new user & send verification OTP
// ─────────────────────────────────────────────────────────────────────────────
router.post("/signup", async (req, res) => {
  try {
    const {
      full_name,
      university_id,
      email,
      role,
      department_id,
      batch,
      password,
    } = req.body;

    const isStudent = (role === "STUDENT" || role === "PRE_FYDP_STUDENT");
    const finalUniversityId = university_id ? university_id : null;

    if (
      !full_name ||
      (isStudent && !finalUniversityId) ||
      !email ||
      !role ||
      !department_id ||
      !password
    ) {
      return res
        .status(400)
        .json({ error: "All required fields must be filled." });
    }

    // Validate UIU email format based on selected role and department
    const deptMap = { 1: "cse", 2: "eee", 3: "bba", 4: "ece", 5: "ce" };
    const deptName = deptMap[department_id] || "cse";
    const expectedDomain = isStudent ? `bs${deptName}.uiu.ac.bd` : `${deptName}.uiu.ac.bd`;

    if (isStudent) {
      const studentRegex = new RegExp(`^[a-zA-Z._]+[0-9]{6,9}@${expectedDomain}$`, "i");
      if (!studentRegex.test(email)) {
        return res.status(400).json({ error: `Please use a valid UIU Student email matching your ID and department (e.g. 123456789@${expectedDomain}).` });
      }
    } else {
      const facultyRegex = new RegExp(`^(?!.*[0-9]{6,9}@)[a-zA-Z0-9._%+-]+@(${expectedDomain}|uiu\\.ac\\.bd)$`, "i");
      if (!facultyRegex.test(email)) {
        return res.status(400).json({ error: `Please use a valid UIU Faculty email matching your department (e.g. name@${expectedDomain}).` });
      }
    }

    // Check if email or university_id already exists
    let existing = [];
    if (finalUniversityId) {
      [existing] = await db.query(
        "SELECT user_id, is_active FROM users WHERE email = ? OR university_id = ?",
        [email, finalUniversityId],
      );
    } else {
      [existing] = await db.query(
        "SELECT user_id, is_active FROM users WHERE email = ?",
        [email],
      );
    }

    if (existing.length > 0) {
      const allInactive = existing.every(u => u.is_active === 0);
      if (allInactive) {
        // Delete the unverified ghost accounts and allow re-registration
        const idsToDelete = existing.map(u => u.user_id);
        await db.query(`DELETE FROM users WHERE user_id IN (${idsToDelete.map(() => '?').join(',')})`, idsToDelete);
      } else {
        return res
          .status(409)
          .json({
            error: "An account with this email or University ID already exists.",
          });
      }
    }

    const otp = generateOTP();
    const otpExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    // Insert user as inactive until OTP verified
    await db.query(
      `INSERT INTO users
        (full_name, university_id, email, password_hash, role, department_id, batch,
         account_status, is_active, otp_code, otp_expires_at)
       VALUES (?, ?, ?, SHA2(?, 256), ?, ?, ?, 'ACTIVE', 0, ?, ?)`,
      [
        full_name,
        finalUniversityId,
        email,
        password,
        role,
        department_id,
        batch || null,
        otp,
        otpExpires,
      ],
    );

    // Send OTP email
    await sendEmail({
      to: email,
      subject: "Verify Your FYDP Account — OTP Code",
      html: buildOtpEmail(full_name, otp, "signup"),
    });

    res.json({
      success: true,
      message: "Account created. Please verify your email with the OTP sent.",
    });
  } catch (err) {
    console.error("Signup error:", err);
    res.status(500).json({ error: "Registration failed. Please try again." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/forgot-password — send OTP for password reset
// ─────────────────────────────────────────────────────────────────────────────
router.post("/forgot-password", async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required." });

    // Validate UIU email format
    if (!isAnyUiuEmail.test(email)) {
      return res
        .status(400)
        .json({ error: "Please use a valid UIU email address." });
    }

    const [rows] = await db.query(
      "SELECT user_id, full_name FROM users WHERE email = ? AND is_active = 1",
      [email],
    );

    // Always respond success to prevent email enumeration
    if (rows.length === 0) {
      return res.json({
        success: true,
        message: "If that email exists, an OTP has been sent.",
      });
    }

    const user = rows[0];
    const otp = generateOTP();
    const otpExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await db.query(
      "UPDATE users SET otp_code = ?, otp_expires_at = ? WHERE user_id = ?",
      [otp, otpExpires, user.user_id],
    );

    await sendEmail({
      to: email,
      subject: "FYDP Password Reset — OTP Code",
      html: buildOtpEmail(user.full_name, otp, "reset"),
    });

    res.json({ success: true, message: "OTP sent to your email." });
  } catch (err) {
    console.error("Forgot password error:", err);
    res.status(500).json({ error: "Failed to send OTP. Please try again." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/verify-otp — verify the 6-digit code
// context: 'signup' | 'forgot'
// ─────────────────────────────────────────────────────────────────────────────
router.post("/verify-otp", async (req, res) => {
  try {
    const { email, otp, context } = req.body;
    if (!email || !otp)
      return res.status(400).json({ error: "Email and OTP are required." });

    const [rows] = await db.query(
      "SELECT user_id, otp_code, otp_expires_at FROM users WHERE email = ?",
      [email],
    );

    if (rows.length === 0)
      return res.status(404).json({ error: "Account not found." });

    const user = rows[0];

    if (!user.otp_code || user.otp_code !== otp) {
      return res
        .status(400)
        .json({ error: "Invalid OTP code. Please try again." });
    }

    if (new Date() > new Date(user.otp_expires_at)) {
      return res
        .status(400)
        .json({ error: "OTP has expired. Please request a new one." });
    }

    if (context === "signup") {
      // Activate the account
      await db.query(
        "UPDATE users SET is_active = 1, otp_code = NULL, otp_expires_at = NULL WHERE user_id = ?",
        [user.user_id],
      );
    } else {
      // Just clear OTP, reset-password will be called next
      await db.query(
        "UPDATE users SET otp_code = NULL, otp_expires_at = NULL WHERE user_id = ?",
        [user.user_id],
      );
      // Store verified reset email in session temporarily
      req.session.resetEmail = email;
    }

    res.json({ success: true, message: "OTP verified successfully." });
  } catch (err) {
    console.error("OTP verify error:", err);
    res.status(500).json({ error: "Verification failed. Please try again." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/resend-otp — resend OTP for signup verification
// ─────────────────────────────────────────────────────────────────────────────
router.post("/resend-otp", async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required." });

    const [rows] = await db.query(
      "SELECT user_id, full_name FROM users WHERE email = ?",
      [email],
    );
    if (rows.length === 0)
      return res.status(404).json({ error: "Account not found." });

    const user = rows[0];
    const otp = generateOTP();
    const otpExpires = new Date(Date.now() + 10 * 60 * 1000);

    await db.query(
      "UPDATE users SET otp_code = ?, otp_expires_at = ? WHERE user_id = ?",
      [otp, otpExpires, user.user_id],
    );

    await sendEmail({
      to: email,
      subject: "Your New OTP Code — FYDP System",
      html: buildOtpEmail(user.full_name, otp, "resend"),
    });

    res.json({ success: true, message: "New OTP sent." });
  } catch (err) {
    console.error("Resend OTP error:", err);
    res.status(500).json({ error: "Failed to resend OTP." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/reset-password — set a new password after OTP verified
// ─────────────────────────────────────────────────────────────────────────────
router.post("/reset-password", async (req, res) => {
  try {
    const { email, password } = req.body;

    // Use session-verified email for security
    const targetEmail = req.session.resetEmail || email;

    if (!targetEmail || !password) {
      return res
        .status(400)
        .json({ error: "Email and new password are required." });
    }
    if (password.length < 8) {
      return res
        .status(400)
        .json({ error: "Password must be at least 8 characters." });
    }

    const [result] = await db.query(
      "UPDATE users SET password_hash = SHA2(?, 256) WHERE email = ? AND is_active = 1",
      [password, targetEmail],
    );

    if (result.affectedRows === 0) {
      return res
        .status(404)
        .json({ error: "Account not found or not active." });
    }

    // Clear reset session
    delete req.session.resetEmail;

    res.json({ success: true, message: "Password reset successfully." });
  } catch (err) {
    console.error("Reset password error:", err);
    res.status(500).json({ error: "Password reset failed. Please try again." });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/logout
// ─────────────────────────────────────────────────────────────────────────────
router.post("/logout", (req, res) => {
  req.session.destroy((err) => {
    if (err) console.error("Logout error:", err);
    res.json({ success: true, redirect: "/login" });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /auth/me — get current session user
// ─────────────────────────────────────────────────────────────────────────────
router.get("/me", (req, res) => {
  if (!req.session?.user) {
    return res.status(401).json({ error: "Not authenticated" });
  }
  res.json({ user: req.session.user });
});

// ─────────────────────────────────────────────────────────────────────────────
// OTP EMAIL HTML BUILDER
// ─────────────────────────────────────────────────────────────────────────────
function buildOtpEmail(name, otp, type) {
  const titles = {
    signup: "Verify Your Email Address",
    reset: "Password Reset Request",
    resend: "Your New Verification Code",
  };
  const subtitles = {
    signup: "Enter this code to activate your FYDP account.",
    reset: "Enter this code to reset your password.",
    resend: "Here is your new OTP code.",
  };

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background:#f0f2ff;font-family:'Segoe UI',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2ff;padding:40px 20px;">
    <tr><td align="center">
      <table width="100%" style="max-width:480px;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(26,35,126,0.10);">

        <!-- Header -->
        <tr>
          <td style="background:linear-gradient(135deg,#1a237e,#1565c0);padding:30px 36px;text-align:center;">
            <div style="font-size:28px;margin-bottom:6px;">🎓</div>
            <div style="color:#fff;font-size:18px;font-weight:700;letter-spacing:-0.01em;">FYDP Management System</div>
            <div style="color:rgba(255,255,255,0.75);font-size:12px;margin-top:2px;">United International University</div>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:32px 36px;">
            <p style="color:#1a237e;font-size:18px;font-weight:700;margin:0 0 6px;">${titles[type] || "Verification Code"}</p>
            <p style="color:#616161;font-size:14px;margin:0 0 24px;">Hi <strong style="color:#212121;">${name}</strong>, ${subtitles[type] || ""}</p>

            <!-- OTP Box -->
            <div style="background:#f0f2ff;border-radius:12px;padding:24px;text-align:center;margin-bottom:24px;">
              <div style="letter-spacing:12px;font-size:36px;font-weight:800;color:#1a237e;font-family:'Courier New',monospace;">${otp}</div>
              <div style="color:#9e9e9e;font-size:12px;margin-top:8px;">Valid for <strong>10 minutes</strong></div>
            </div>

            <p style="color:#9e9e9e;font-size:12px;line-height:1.6;margin:0;">
              If you did not request this, please ignore this email. Your account remains secure.<br>
              Do not share this code with anyone.
            </p>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="background:#f5f6fa;padding:16px 36px;text-align:center;border-top:1px solid #eeeeee;">
            <div style="color:#bdbdbd;font-size:11px;">© ${new Date().getFullYear()} FYDP Management System — United International University</div>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

module.exports = router;
