const nodemailer = require("nodemailer");
const dns = require("dns");

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

/**
 * Verify that the email domain has valid MX records (i.e., the domain can receive emails).
 * This catches typos in the domain and non-existent subdomains before we even try to send.
 * Uses Google DNS (8.8.8.8) as a fallback if the system DNS resolver fails.
 * NOTE: UIU institutional emails (*.uiu.ac.bd) are always skipped — they don't have
 *       public MX records but are valid institutional addresses.
 * @param {string} email - The email address to verify
 * @returns {Promise<boolean>} - true if MX records exist or DNS is unavailable (fail-open)
 */
async function verifyEmailDomain(email) {
  const domain = email.split("@")[1];
  if (!domain) return false;

  // UIU institutional emails — skip MX check, always allow
  if (domain.toLowerCase().endsWith("uiu.ac.bd")) {
    console.log(`✅ UIU institutional email — skipping MX check for domain: ${domain}`);
    return true;
  }

  // Try system DNS first, then fallback to Google DNS
  const resolvers = [
    () => dns.promises.resolveMx(domain),
    () => {
      const resolver = new dns.promises.Resolver();
      resolver.setServers(["8.8.8.8", "8.8.4.4"]);
      return resolver.resolveMx(domain);
    },
  ];

  for (const resolve of resolvers) {
    try {
      const addresses = await resolve();
      if (!addresses || addresses.length === 0) {
        console.warn(`⚠️  No MX records found for domain: ${domain}`);
        return false;
      }
      console.log(`✅ MX records found for ${domain}:`, addresses.map(a => a.exchange).join(", "));
      return true;
    } catch (err) {
      // ENODATA / ENOTFOUND = domain definitively has no MX records
      if (err.code === "ENODATA" || err.code === "ENOTFOUND") {
        console.warn(`⚠️  No MX records for domain ${domain}: ${err.code}`);
        return false;
      }
      // ECONNREFUSED / ETIMEOUT = DNS resolver issue, try next resolver
      console.warn(`⚠️  DNS resolver issue for ${domain}: ${err.code || err.message}, trying fallback...`);
      continue;
    }
  }

  // If ALL DNS resolvers failed, allow the email through (fail-open)
  // The SMTP server will reject it if the address is truly invalid
  console.warn(`⚠️  All DNS resolvers failed for ${domain}, allowing send attempt (fail-open)`);
  return true;
}

/**
 * Send an email.
 * For UIU institutional emails (*.uiu.ac.bd), skips MX record validation and sends directly.
 * For all other domains, first validates MX records to catch typos.
 * @param {object} options - { to, subject, html }
 * @returns {Promise<boolean>}
 */
async function sendEmail({ to, subject, html }) {
  // Step 1: Validate email domain (UIU emails skip MX check automatically)
  const domainValid = await verifyEmailDomain(to);
  if (!domainValid) {
    const domain = to.split("@")[1];
    const errorMsg = `The email domain "${domain}" does not appear to accept emails. Please check the email address for typos.`;
    console.error(`❌ Email domain verification failed for: ${to}`);
    throw new Error(errorMsg);
  }

  // Step 2: Send the email
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

    // Provide user-friendly error messages for common SMTP failures
    if (error.responseCode === 550 || error.message.includes("not exist")) {
      throw new Error(`The email address "${to}" could not be reached. Please verify it is correct.`);
    }
    if (error.responseCode === 553 || error.message.includes("relay")) {
      throw new Error(`The email address "${to}" was rejected by the mail server. Please use a valid email.`);
    }

    throw error; // Let the caller handle other errors
  }
}

module.exports = { sendEmail, verifyEmailDomain };
