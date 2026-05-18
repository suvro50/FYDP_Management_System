const nodemailer = require("nodemailer");

let cachedTransporter = null;

function getTransporter() {
  if (cachedTransporter) return cachedTransporter;

  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    console.error("❌ SMTP_USER and SMTP_PASS are required in .env for email delivery!");
    console.error("   Set up Gmail App Password: https://myaccount.google.com/apppasswords");
    throw new Error("Email service not configured. Set SMTP_USER and SMTP_PASS in .env");
  }

  cachedTransporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });

  // Verify connection on first use
  cachedTransporter.verify()
    .then(() => console.log("✅ Gmail SMTP connected successfully"))
    .catch(err => {
      console.error("❌ Gmail SMTP connection failed:", err.message);
      cachedTransporter = null;
    });

  return cachedTransporter;
}

async function sendEmail({ to, subject, html }) {
  try {
    const transporter = getTransporter();
    const info = await transporter.sendMail({
      from: `"FYDP Management System" <${process.env.SMTP_USER}>`,
      to,
      subject,
      html,
    });

    console.log(`✉️  Email sent to ${to} (ID: ${info.messageId})`);
    return true;
  } catch (error) {
    console.error("❌ Failed to send email to", to);
    console.error("   Error:", error.message);
    throw error; // Let the caller handle it so user sees the error
  }
}

module.exports = { sendEmail };
