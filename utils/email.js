const nodemailer = require("nodemailer");

async function createTransporter() {
  // If no real credentials, use Ethereal for demo
  if (!process.env.SMTP_HOST) {
    let testAccount = await nodemailer.createTestAccount();
    return nodemailer.createTransport({
      host: "smtp.ethereal.email",
      port: 587,
      secure: false, // true for 465, false for other ports
      auth: {
        user: testAccount.user, // generated ethereal user
        pass: testAccount.pass, // generated ethereal password
      },
    });
  }

  // Real credentials
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: process.env.SMTP_PORT || 587,
    secure: process.env.SMTP_PORT == 465,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
}

async function sendEmail({ to, subject, html }) {
  try {
    const transporter = await createTransporter();
    const info = await transporter.sendMail({
      from: '"FYDP Matchmaking System" <noreply@fydpsystem.local>',
      to,
      subject,
      html,
    });

    console.log(`✉️ Email sent to ${to}`);
    // If using ethereal, output the preview URL
    if (info.messageId && !process.env.SMTP_HOST) {
      console.log(`   Preview URL: ${nodemailer.getTestMessageUrl(info)}`);
    }
    return true;
  } catch (error) {
    console.error("Failed to send email:", error);
    return false;
  }
}
module.exports = { sendEmail };
